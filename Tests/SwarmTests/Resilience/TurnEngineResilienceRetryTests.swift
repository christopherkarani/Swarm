// TurnEngineResilienceRetryTests.swift
// Swarm Framework
//
// Deterministic tests for the canonical inference retry seam
// (`ResilienceRetry`, W3-T3). All backoff progression runs against a
// `VirtualClock` — no real sleeps. Also pins the documented divergence of the
// Hive graph path's local retry loop (`ChatGraph.withRetry`) at both sites.

import Foundation
@_spi(ColonyInternal) @testable import Swarm
import Testing

// MARK: - Fixtures

/// Unclassified error type: `InferenceRetryability` fails closed on it.
private struct UnclassifiedError: Error, Equatable {}

private actor CallCounter {
    private(set) var count = 0

    func increment() -> Int {
        count += 1
        return count
    }
}

private final class RetryEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []

    func record(_ item: String) {
        lock.withLock { items.append(item) }
    }

    var entries: [String] {
        lock.withLock { items }
    }
}

// MARK: - Canonical Retry Seam Tests

@Suite("TurnEngine Canonical ResilienceRetry Tests")
struct TurnEngineResilienceRetryTests {

    // MARK: Failing-then-succeeding progression

    @Test("Failing-then-succeeding retries exactly per exponential backoff curve")
    func failingThenSucceedingExactProgression() async throws {
        let clock = VirtualClock()
        let counter = CallCounter()
        let policy = RetryPolicy(
            maxAttempts: 3,
            backoff: .exponential(base: 1.0, multiplier: 2.0, maxDelay: 60.0)
        )

        let result = try await ResilienceRetry.run(policy: policy, clock: clock) {
            let attempt = await counter.increment()
            if attempt < 3 {
                throw AgentError.generationFailed(reason: "transient-\(attempt)")
            }
            return "recovered"
        }

        #expect(result == "recovered")
        let calls = await counter.count
        // Initial attempt + two retries; third call succeeds.
        #expect(calls == 3)
        // Exact curve: 1s, then 1s * 2.
        #expect(clock.recordedSleeps == [1_000_000_000, 2_000_000_000])
        #expect(clock.now == 3_000_000_000)
    }

    // MARK: Exhaustion

    @Test("Exhaustion throws retriesExhausted with exact attempt count")
    func exhaustionWrapsInRetriesExhausted() async throws {
        let clock = VirtualClock()
        let counter = CallCounter()
        let policy = RetryPolicy(maxAttempts: 2, backoff: .fixed(delay: 0.25))

        var caught: Error?
        do {
            _ = try await ResilienceRetry.run(policy: policy, clock: clock) { () -> String in
                _ = await counter.increment()
                throw AgentError.rateLimitExceeded(retryAfter: nil)
            }
        } catch {
            caught = error
        }

        let calls = await counter.count
        // Initial attempt + maxAttempts(2) retries, all failing.
        #expect(calls == 3)
        #expect(clock.recordedSleeps == [250_000_000, 250_000_000])

        guard case let .retriesExhausted(attempts, lastError) = caught as? ResilienceError else {
            Issue.record("Expected ResilienceError.retriesExhausted, got \(String(describing: caught))")
            return
        }
        #expect(attempts == 3)
        #expect(!lastError.isEmpty)
    }

    // MARK: Hard retryability gate

    @Test("Unclassified errors fail closed without consuming budget")
    func unclassifiedErrorsFailClosed() async throws {
        let clock = VirtualClock()
        let counter = CallCounter()
        let policy = RetryPolicy(maxAttempts: 3, backoff: .immediate)

        var caught: Error?
        do {
            _ = try await ResilienceRetry.run(policy: policy, clock: clock) { () -> String in
                _ = await counter.increment()
                throw UnclassifiedError()
            }
        } catch {
            caught = error
        }

        let calls = await counter.count
        // shouldRetry defaults to true, yet the hard gate fails closed:
        // single attempt, original error rethrown verbatim, no sleeps.
        #expect(calls == 1)
        #expect(clock.sleepCount == 0)
        #expect(caught as? UnclassifiedError == UnclassifiedError())
    }

    @Test("userShouldRetry false short-circuits even a retryable error")
    func userGateFalseShortCircuits() async throws {
        let clock = VirtualClock()
        let counter = CallCounter()
        let policy = RetryPolicy(
            maxAttempts: 3,
            backoff: .immediate,
            shouldRetry: { _ in false }
        )

        var caught: Error?
        do {
            _ = try await ResilienceRetry.run(policy: policy, clock: clock) { () -> String in
                _ = await counter.increment()
                throw AgentError.generationFailed(reason: "hard-gate passes, user gate blocks")
            }
        } catch {
            caught = error
        }

        let calls = await counter.count
        #expect(calls == 1)
        #expect(clock.sleepCount == 0)

        guard case let .generationFailed(reason) = caught as? AgentError else {
            Issue.record("Expected original AgentError.generationFailed, got \(String(describing: caught))")
            return
        }
        #expect(reason == "hard-gate passes, user gate blocks")
    }

    // MARK: Cancellation

    @Test("CancellationError is never retried")
    func cancellationErrorNeverRetried() async throws {
        let clock = VirtualClock()
        let counter = CallCounter()

        var caught: Error?
        do {
            _ = try await ResilienceRetry.run(
                policy: RetryPolicy.standard,
                clock: clock
            ) { () -> String in
                _ = await counter.increment()
                throw CancellationError()
            }
        } catch {
            caught = error
        }

        let calls = await counter.count
        #expect(calls == 1)
        #expect(clock.sleepCount == 0)
        #expect(caught is CancellationError)
    }

    @Test("Pre-cancelled task rethrows without retrying a retryable error")
    func preCancelledTaskSkipsRetry() async throws {
        let clock = VirtualClock()
        let counter = CallCounter()

        // URLError.timedOut IS hard-gate retryable, so this isolates the
        // Task.isCancelled branch. Whichever wins the benign race (cancel
        // landing before or after the body starts), the first catch must
        // rethrow verbatim without sleeping: either checkCancellation fires,
        // or Task.isCancelled is observed in the catch block.
        let task = Task {
            try await ResilienceRetry.run(policy: RetryPolicy.standard, clock: clock) { () -> String in
                _ = await counter.increment()
                try Task.checkCancellation()
                throw URLError(.timedOut)
            }
        }
        task.cancel()

        var caught: Error?
        do {
            _ = try await task.value
            Issue.record("Expected cancelled run to throw")
        } catch {
            caught = error
        }

        let calls = await counter.count
        #expect(calls == 1)
        #expect(clock.sleepCount == 0)
        #expect(!(caught is ResilienceError))
        #expect(caught is CancellationError || caught is URLError)
    }

    // MARK: No-retry fast path

    @Test("maxAttempts == 0 runs the operation exactly once on success")
    func zeroBudgetSuccessFastPath() async throws {
        let clock = VirtualClock()
        let counter = CallCounter()

        let result = try await ResilienceRetry.run(
            policy: .noRetry,
            clock: clock
        ) {
            _ = await counter.increment()
            return "done"
        }

        #expect(result == "done")
        let calls = await counter.count
        #expect(calls == 1)
        #expect(clock.sleepCount == 0)
    }

    @Test("maxAttempts == 0 rethrows the bare error instead of wrapping it")
    func zeroBudgetFailureRethrowsOriginal() async throws {
        let clock = VirtualClock()
        let counter = CallCounter()

        var caught: Error?
        do {
            _ = try await ResilienceRetry.run(policy: .noRetry, clock: clock) { () -> String in
                _ = await counter.increment()
                throw AgentError.embeddingFailed(reason: "no budget")
            }
        } catch {
            caught = error
        }

        let calls = await counter.count
        #expect(calls == 1)
        #expect(!(caught is ResilienceError))
        guard case let .embeddingFailed(reason) = caught as? AgentError else {
            Issue.record("Expected original AgentError.embeddingFailed, got \(String(describing: caught))")
            return
        }
        #expect(reason == "no budget")
    }

    // MARK: Backoff sanitization

    @Test("Backoff above the one-hour ceiling sanitizes to exactly one hour")
    func backoffSanitizesToOneHourCeiling() async throws {
        let clock = VirtualClock()
        let counter = CallCounter()
        let policy = RetryPolicy(maxAttempts: 2, backoff: .fixed(delay: 7200))

        _ = try await ResilienceRetry.run(policy: policy, clock: clock) { () -> String in
            let attempt = await counter.increment()
            if attempt == 1 {
                throw AgentError.inferenceProviderUnavailable(reason: "blip")
            }
            return "ok"
        }

        let calls = await counter.count
        #expect(calls == 2)
        #expect(clock.recordedSleeps == [3_600_000_000_000])
    }

    @Test("Non-finite backoff delays are dropped, not slept")
    func nonFiniteDelayIsDropped() async throws {
        let clock = VirtualClock()
        let counter = CallCounter()
        let policy = RetryPolicy(maxAttempts: 2, backoff: .custom { _ in .nan })

        _ = try await ResilienceRetry.run(policy: policy, clock: clock) { () -> String in
            let attempt = await counter.increment()
            if attempt == 1 {
                throw AgentError.generationFailed(reason: "retry me")
            }
            return "ok"
        }

        let calls = await counter.count
        #expect(calls == 2)
        #expect(clock.recordedSleeps.isEmpty)
    }

    // MARK: Side-effect ordering

    @Test("onRetry ordering: operation, user callback, injected hook, sleep")
    func retrySideEffectOrderingPreserved() async throws {
        let clock = VirtualClock()
        let counter = CallCounter()
        let log = RetryEventLog()
        let policy = RetryPolicy(
            maxAttempts: 2,
            backoff: .fixed(delay: 0.5),
            onRetry: { attempt, _ in log.record("user:\(attempt)") }
        )

        let result = try await ResilienceRetry.run(policy: policy, clock: clock, onRetryAttempt: { attempt, _ in
            log.record("hook:\(attempt)")
        }) { () -> String in
            let attempt = await counter.increment()
            log.record("op:\(attempt)")
            if attempt == 1 {
                throw AgentError.rateLimitExceeded(retryAfter: nil)
            }
            return "ok"
        }

        #expect(result == "ok")
        // Historical agent-path order: the composed callback ran the user
        // policy first, then logging/observer/tracing, before the backoff
        // sleep. Attempt numbering starts at 1 on the first RETRY.
        #expect(log.entries == ["op:1", "user:1", "hook:1", "op:2"])
        #expect(clock.recordedSleeps == [500_000_000])
    }

    @Test("Jittered backoff stays beneath the uncapped exponential curve")
    func jitterStaysBeneathCurve() async throws {
        let clock = VirtualClock()
        let counter = CallCounter()
        let policy = RetryPolicy(
            maxAttempts: 3,
            backoff: .exponentialWithJitter(base: 0.5, multiplier: 2.0, maxDelay: 30.0)
        )

        _ = try await ResilienceRetry.run(policy: policy, clock: clock) { () -> String in
            let attempt = await counter.increment()
            if attempt < 3 {
                throw AgentError.inferenceProviderUnavailable(reason: "flaky")
            }
            return "ok"
        }

        let calls = await counter.count
        let sleeps = clock.recordedSleeps
        #expect(calls == 3)
        #expect(sleeps.count == 2)
        // Jitter draws from [0, capped delay]: attempt 1 caps at 0.5s,
        // attempt 2 at 1.0s.
        #expect(sleeps[0] <= 500_000_000)
        #expect(sleeps[1] <= 1_000_000_000)
    }
}

// MARK: - Graph Path Divergence Contract

@Suite("TurnEngine Graph Retry Divergence Contract")
struct TurnEngineGraphRetryDivergenceTests {

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/SwarmTests/Resilience/
            .deletingLastPathComponent() // Tests/SwarmTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
    }

    /// The Hive graph path keeps its own loop because its semantics diverge
    /// beyond an injectable classifier (total-attempt counting, verbatim
    /// last-error rethrow, unconditional gating, different backoff math).
    /// This pins that BOTH sites carry the written rationale so the
    /// divergence stays deliberate rather than accidental drift.
    @Test("Documented divergence rationale exists at both retry sites")
    func divergenceRationalePresentAtBothSites() throws {
        let chatGraphSource = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/Swarm/Internal/GraphRuntime/ChatGraph.swift"),
            encoding: .utf8
        )
        let canonicalSource = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/Swarm/Internal/TurnEngine/ResilienceRetry.swift"),
            encoding: .utf8
        )

        // Graph site: rationale cites total-attempt counting and verbatim
        // last-error rethrow.
        #expect(chatGraphSource.contains("Deliberate divergence from the canonical agent-inference retry"))
        #expect(chatGraphSource.contains("for attempt in 0 ..< maxAttempts"))
        #expect(chatGraphSource.contains("ResilienceError.retriesExhausted(attempts:lastError:)"))

        // Canonical site: header cross-references the graph loop.
        #expect(canonicalSource.contains("ChatGraph.withRetry"))
        // And still expresses the agent-path hard gate conjunction.
        #expect(canonicalSource.contains("InferenceRetryability.isRetryable(error) && policy.shouldRetry(error)"))
    }
}
