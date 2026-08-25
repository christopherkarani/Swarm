// ResilienceTests+Retry.swift
// Swarm Framework
//
// Tests for RetryPolicy resilience component using Swift Testing framework.

import Foundation
@_spi(ColonyInternal) @testable import Swarm
import Testing

// MARK: - RetryPolicy Tests

@Suite("RetryPolicy Tests")
struct RetryPolicyTests {
    // MARK: - Successful Execution Tests

    @Test("Successful execution without retry")
    func successfulExecutionWithoutRetry() async throws {
        let policy = RetryPolicy(maxAttempts: 3, backoff: .immediate)
        let counter = TestCounter()

        let result = try await policy.execute {
            _ = await counter.increment()
            return "success"
        }

        #expect(result == "success")
        #expect(await counter.get() == 1)
    }

    @Test("Immediate success with no retry attempts")
    func immediateSuccess() async throws {
        let policy = RetryPolicy.standard
        let counter = TestCounter()

        let result = try await policy.execute {
            _ = await counter.increment()
            return 42
        }

        #expect(result == 42)
        #expect(await counter.get() == 1)
    }

    // MARK: - Retry Until Success Tests

    @Test("Retry until success on transient errors")
    func retryUntilSuccess() async throws {
        let policy = RetryPolicy(maxAttempts: 3, backoff: .immediate)
        let counter = TestCounter()

        let result = try await policy.execute {
            let count = await counter.increment()
            if count < 3 {
                throw TestError.transient
            }
            return "success"
        }

        #expect(result == "success")
        #expect(await counter.get() == 3)
    }

    @Test("First retry succeeds after initial failure")
    func firstRetrySucceeds() async throws {
        let policy = RetryPolicy(maxAttempts: 2, backoff: .immediate)
        let counter = TestCounter()

        let result = try await policy.execute {
            let count = await counter.increment()
            if count == 1 {
                throw TestError.network
            }
            return "recovered"
        }

        #expect(result == "recovered")
        #expect(await counter.get() == 2)
    }

    // MARK: - Retry Exhaustion Tests

    @Test("Retry exhaustion throws ResilienceError.retriesExhausted")
    func retryExhaustion() async throws {
        let policy = RetryPolicy(maxAttempts: 2, backoff: .immediate)
        let counter = TestCounter()

        do {
            _ = try await policy.execute {
                _ = await counter.increment()
                throw TestError.permanent
            }
            Issue.record("Should have thrown ResilienceError.retriesExhausted")
        } catch let error as ResilienceError {
            if case let .retriesExhausted(attempts, lastError) = error {
                #expect(attempts == 3) // initial + 2 retries
                #expect(lastError.contains("Permanent"))
            } else {
                Issue.record("Expected retriesExhausted, got \(error)")
            }
        }

        #expect(await counter.get() == 3)
    }

	    @Test("All retries fail with consistent error")
	    func allRetriesFail() async throws {
	        let policy = RetryPolicy(maxAttempts: 3, backoff: .immediate)
	        let counter = TestCounter()

	        do {
	            _ = try await policy.execute {
	                _ = await counter.increment()
	                throw TestError.timeout
	            }
	            Issue.record("Expected error to be thrown")
	        } catch let error as ResilienceError {
	            #expect(error == .retriesExhausted(attempts: 4, lastError: TestError.timeout.localizedDescription))
	        }

	        #expect(await counter.get() == 4) // initial + 3 retries
	    }

    // MARK: - BackoffStrategy Tests

    @Test("BackoffStrategy.fixed returns constant delay")
    func fixedBackoff() {
        let strategy = BackoffStrategy.fixed(delay: 1.5)

        #expect(strategy.delay(forAttempt: 1) == 1.5)
        #expect(strategy.delay(forAttempt: 2) == 1.5)
        #expect(strategy.delay(forAttempt: 5) == 1.5)
    }

    @Test("BackoffStrategy.exponential calculates correct delays")
    func exponentialBackoff() {
        let strategy = BackoffStrategy.exponential(base: 1.0, multiplier: 2.0, maxDelay: 10.0)

        #expect(strategy.delay(forAttempt: 1) == 1.0) // 1.0 * 2^0
        #expect(strategy.delay(forAttempt: 2) == 2.0) // 1.0 * 2^1
        #expect(strategy.delay(forAttempt: 3) == 4.0) // 1.0 * 2^2
        #expect(strategy.delay(forAttempt: 4) == 8.0) // 1.0 * 2^3
        #expect(strategy.delay(forAttempt: 5) == 10.0) // capped at maxDelay
    }

    @Test("BackoffStrategy.linear calculates correct delays")
    func linearBackoff() {
        let strategy = BackoffStrategy.linear(initial: 1.0, increment: 0.5, maxDelay: 5.0)

        #expect(strategy.delay(forAttempt: 1) == 1.0) // 1.0 + 0.5 * 0
        #expect(strategy.delay(forAttempt: 2) == 1.5) // 1.0 + 0.5 * 1
        #expect(strategy.delay(forAttempt: 3) == 2.0) // 1.0 + 0.5 * 2
        #expect(strategy.delay(forAttempt: 10) == 5.0) // capped at maxDelay
    }

    @Test("BackoffStrategy.immediate returns zero delay")
    func immediateBackoff() {
        let strategy = BackoffStrategy.immediate

        #expect(strategy.delay(forAttempt: 1) == 0)
        #expect(strategy.delay(forAttempt: 100) == 0)
    }

    @Test("BackoffStrategy.custom uses provided calculator")
    func customBackoff() {
        let strategy = BackoffStrategy.custom { attempt in
            Double(attempt) * 10.0
        }

        #expect(strategy.delay(forAttempt: 1) == 10.0)
        #expect(strategy.delay(forAttempt: 2) == 20.0)
        #expect(strategy.delay(forAttempt: 5) == 50.0)
    }

    // MARK: - shouldRetry Predicate Tests

    @Test("shouldRetry predicate controls retry behavior")
    func shouldRetryPredicate() async throws {
        let policy = RetryPolicy(
            maxAttempts: 3,
            backoff: .immediate,
            shouldRetry: { error in
                // Only retry transient errors
                if let testError = error as? TestError {
                    testError == .transient
                } else {
                    false
                }
            }
        )
        let counter = TestCounter()

        do {
            _ = try await policy.execute {
                _ = await counter.increment()
                throw TestError.permanent
            }
            Issue.record("Should have thrown error")
        } catch let error as TestError {
            #expect(error == .permanent)
        }

        // Should not retry because shouldRetry returned false
        #expect(await counter.get() == 1)
    }

    @Test("shouldRetry allows selective error retry")
    func selectiveRetry() async throws {
        let transientCounter = TestCounter()
        let permanentCounter = TestCounter()

        let policy = RetryPolicy(
            maxAttempts: 3,
            backoff: .immediate,
            shouldRetry: { error in
                (error as? TestError) == .transient
            }
        )

        // Test with transient error - should retry
        do {
            _ = try await policy.execute {
                _ = await transientCounter.increment()
                throw TestError.transient
            }
        } catch {
            // Expected to exhaust retries
        }
        #expect(await transientCounter.get() == 4) // initial + 3 retries

        // Test with permanent error - should not retry
        do {
            _ = try await policy.execute {
                _ = await permanentCounter.increment()
                throw TestError.permanent
            }
        } catch {
            // Expected to fail immediately
        }
        #expect(await permanentCounter.get() == 1) // no retries
    }

    // MARK: - onRetry Callback Tests

    @Test("onRetry callback is invoked before each retry")
    func onRetryCallback() async throws {
        let recorder = TestRecorder<(Int, String)>()

        let policy = RetryPolicy(
            maxAttempts: 2,
            backoff: .immediate,
            onRetry: { attempt, error in
                await recorder.append((attempt, "\(error)"))
            }
        )
        let counter = TestCounter()

        do {
            _ = try await policy.execute {
                _ = await counter.increment()
                throw TestError.network
            }
        } catch {
            // Expected
        }

        let callbacks = await recorder.getAll()
        #expect(callbacks.count == 2)
        #expect(callbacks[0].0 == 1)
        #expect(callbacks[1].0 == 2)
    }

    @Test("Cancellation is propagated without retry")
    func cancellationIsPropagatedWithoutRetry() async throws {
        let counter = TestCounter()
        let retryRecorder = TestRecorder<Int>()
        let policy = RetryPolicy(
            maxAttempts: 3,
            backoff: .immediate,
            onRetry: { attempt, _ in
                await retryRecorder.append(attempt)
            }
        )

        do {
            _ = try await policy.execute {
                _ = await counter.increment()
                throw CancellationError()
            }
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }

        #expect(await counter.get() == 1)
        #expect(await retryRecorder.getAll().isEmpty)
    }

    @Test("Huge finite retry delays clamp instead of trapping")
    func hugeFiniteRetryDelaysClampInsteadOfTrapping() async throws {
        let counter = TestCounter()
        let policy = RetryPolicy(
            maxAttempts: 1,
            backoff: .exponential(base: 1.0e20, multiplier: 2.0, maxDelay: 1.0e20)
        )

        let task = Task<String, Error> {
            try await policy.execute {
                _ = await counter.increment()
                throw TestError.transient
            }
        }

        while await counter.get() == 0 {
            try await Task.sleep(for: .milliseconds(1))
        }
        try await Task.sleep(for: .milliseconds(5))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            // Expected after the oversized delay is clamped and sleep is cancelled.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }

        #expect(await counter.get() == 1)
    }

    @Test("Small finite retry delay still retries")
    func smallFiniteRetryDelayStillRetries() async throws {
        let counter = TestCounter()
        let policy = RetryPolicy(
            maxAttempts: 1,
            backoff: .immediate
        )

        let result = try await policy.execute {
            let attempt = await counter.increment()
            if attempt == 1 {
                throw TestError.transient
            }
            return "recovered"
        }

        #expect(result == "recovered")
        #expect(await counter.get() == 2)
    }

    // MARK: - Static Convenience Tests

    @Test("Static noRetry policy fails immediately")
    func noRetryPolicy() async throws {
        let counter = TestCounter()

        do {
            _ = try await RetryPolicy.noRetry.execute {
                _ = await counter.increment()
                throw TestError.transient
            }
            Issue.record("Should have thrown error")
        } catch {
            // Expected
        }

        #expect(await counter.get() == 1)
    }

    @Test("Static standard policy has correct configuration")
    func standardPolicy() {
        let policy = RetryPolicy.standard
        #expect(policy.maxAttempts == 3)
        #expect(policy.backoff == .exponential(base: 1.0, multiplier: 2.0, maxDelay: 60.0))
    }

    @Test("Static aggressive policy has correct configuration")
    func aggressivePolicy() {
        let policy = RetryPolicy.aggressive
        #expect(policy.maxAttempts == 5)
        #expect(policy.backoff == .exponentialWithJitter(base: 0.5, multiplier: 2.0, maxDelay: 30.0))
    }

    @Test("Invalid backoff delay values do not crash and retries exhaust")
    func invalidBackoffDelayValuesAreIgnored() async throws {
        let counter = TestCounter()
        let policy = RetryPolicy(
            maxAttempts: 2,
            backoff: .custom { attempt in
                switch attempt {
                case 1: return -.infinity
                case 2: return .nan
                default: return 0
                }
            }
        )

        do {
            _ = try await policy.execute {
                _ = await counter.increment()
                throw TestError.transient
            }
            Issue.record("Expected retriesExhausted")
        } catch let error as ResilienceError {
            if case let .retriesExhausted(attempts, _) = error {
                #expect(attempts == 3)
            } else {
                Issue.record("Expected retriesExhausted, got \(error)")
            }
        }

        #expect(await counter.get() == 3)
    }

    @Test("Infinite backoff delay is clamped to avoid overflow")
    func infiniteBackoffDelayIsSafe() async throws {
        let counter = TestCounter()
        let policy = RetryPolicy(
            maxAttempts: 1,
            backoff: .custom { _ in .infinity }
        )

        do {
            _ = try await policy.execute {
                _ = await counter.increment()
                throw TestError.transient
            }
            Issue.record("Expected retriesExhausted")
        } catch let error as ResilienceError {
            if case let .retriesExhausted(attempts, _) = error {
                #expect(attempts == 2)
            } else {
                Issue.record("Expected retriesExhausted, got \(error)")
            }
        }

        #expect(await counter.get() == 2)
    }
}

// MARK: - Deterministic Randomness & Sleep Seam Support

/// Lock-guarded wrapper exposing `SeededRandomGenerator` through the
/// `@Sendable` closure shape accepted by RetryPolicy and BackoffStrategy.
/// (The generator is a value type; `@Sendable` closures need shared state.)
private final class SharedSeededRandom: @unchecked Sendable {
    // MARK: Private

    private let lock = NSLock()
    private var generator: SeededRandomGenerator

    // MARK: Init

    init(seed: UInt64) {
        generator = SeededRandomGenerator(seed: seed)
    }

    // MARK: Internal

    func random(in range: ClosedRange<Double>) -> Double {
        lock.withLock { generator.random(in: range) }
    }
}

// MARK: - Jitter Determinism Tests

@Suite("RetryPolicy Determinism Tests")
private struct RetryPolicyDeterminismTests {
    @Test("Seeded randomness reproduces exponentialWithJitter sequences")
    func seededExponentialJitterReplaysExactly() {
        let strategy = BackoffStrategy.exponentialWithJitter(base: 1.0, multiplier: 2.0, maxDelay: 10.0)

        let firstRun = SharedSeededRandom(seed: 99)
        let firstSequence = (1...6).map { strategy.delay(forAttempt: $0, random: firstRun.random(in:)) }

        let replayRun = SharedSeededRandom(seed: 99)
        let replaySequence = (1...6).map { strategy.delay(forAttempt: $0, random: replayRun.random(in:)) }

        #expect(firstSequence == replaySequence)

        for (index, delay) in firstSequence.enumerated() {
            let capped = min(1.0 * pow(2.0, Double(index)), 10.0)
            #expect(delay >= 0)
            #expect(delay <= capped)
        }
        #expect(Set(firstSequence).count > 1) // jitter actually varies
    }

    @Test("Seeded randomness reproduces decorrelatedJitter sequences")
    func seededDecorrelatedJitterReplaysExactly() {
        let strategy = BackoffStrategy.decorrelatedJitter(base: 0.5, maxDelay: 20.0)

        let firstRun = SharedSeededRandom(seed: 7)
        let firstSequence = (1...5).map { strategy.delay(forAttempt: $0, random: firstRun.random(in:)) }

        let replayRun = SharedSeededRandom(seed: 7)
        let replaySequence = (1...5).map { strategy.delay(forAttempt: $0, random: replayRun.random(in:)) }

        #expect(firstSequence == replaySequence)

        for (index, delay) in firstSequence.enumerated() {
            // previousSleep formula preserved byte-identically:
            // attempt == 1 uses base; else base * pow(3, attempt - 2).
            let previousSleep = index == 0 ? 0.5 : 0.5 * pow(3.0, Double(index - 1))
            #expect(delay >= 0.5)
            #expect(delay <= min(previousSleep * 3.0, 20.0))
        }
    }

    @Test("Public delay(forAttempt:) keeps live randomness and unchanged math")
    func publicDelayKeepsLiveRandomness() {
        let strategy = BackoffStrategy.exponentialWithJitter(base: 1.0, multiplier: 2.0, maxDelay: 1_000_000.0)

        let delays = (0..<16).map { _ in strategy.delay(forAttempt: 1) }

        #expect(delays.allSatisfy { $0 >= 0 && $0 <= 1.0 })
        #expect(Set(delays).count > 1)

        // Non-jitter strategies are unaffected by the seam.
        #expect(BackoffStrategy.fixed(delay: 1.5).delay(forAttempt: 3) == 1.5)
        #expect(BackoffStrategy.immediate.delay(forAttempt: 9) == 0)
    }

    // MARK: Injected Sleep Seam Tests

    @Test("Injected clock records exact per-attempt delays without real sleeping")
    func executeRecordsExactDelaysViaVirtualClock() async throws {
        let clock = VirtualClock()
        let counter = TestCounter()
        let policy = RetryPolicy(
            maxAttempts: 3,
            backoff: .fixed(delay: 0.25),
            clock: clock
        )

        let wallStart = ContinuousClock.now

        let result = try await policy.execute {
            let count = await counter.increment()
            if count < 3 {
                throw TestError.transient
            }
            return "recovered"
        }

        #expect(result == "recovered")
        #expect(await counter.get() == 3)
        #expect(clock.recordedSleeps == [250_000_000, 250_000_000]) // attempts 1 and 2 only
        #expect(clock.now == 500_000_000) // virtual time advanced by the two sleeps

        let elapsed = ContinuousClock.now - wallStart
        // Two real 250 ms sleeps would take at least 0.5 s.
        #expect(elapsed < .milliseconds(250))
    }

    @Test("Seeded jitter retries replay identical sleep sequences end to end")
    func seededJitterEndToEndReplaysIdenticalSleeps() async throws {
        let strategy = BackoffStrategy.exponentialWithJitter(base: 1.0, multiplier: 2.0, maxDelay: 60.0)

        func runOnce() async throws -> [UInt64] {
            let clock = VirtualClock()
            let random = SharedSeededRandom(seed: 2_026)
            let counter = TestCounter()
            let policy = RetryPolicy(maxAttempts: 3, backoff: strategy, clock: clock, random: random.random(in:))

            _ = try await policy.execute {
                let count = await counter.increment()
                if count < 4 {
                    throw TestError.network
                }
                return true
            }

            #expect(await counter.get() == 4) // initial + 3 retries
            return clock.recordedSleeps
        }

        let firstRun = try await runOnce()
        let secondRun = try await runOnce()

        #expect(firstRun.count == 3)
        #expect(firstRun == secondRun)

        for (index, nanoseconds) in firstRun.enumerated() {
            let capped = min(1.0 * pow(2.0, Double(index)), 60.0)
            #expect(Double(nanoseconds) / 1_000_000_000 <= capped)
        }
    }

    @Test("Injected clock preserves immediate cancellation semantics")
    func injectedClockPreservesCancellationSemantics() async throws {
        let clock = VirtualClock()
        let counter = TestCounter()
        let retryRecorder = TestRecorder<Int>()
        let policy = RetryPolicy(
            maxAttempts: 3,
            backoff: .fixed(delay: 1.0),
            onRetry: { attempt, _ in
                await retryRecorder.append(attempt)
            },
            clock: clock
        )

        do {
            _ = try await policy.execute {
                _ = await counter.increment()
                throw CancellationError()
            }
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            // Expected: cancellation rethrown immediately, no retry, no sleep.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }

        #expect(await counter.get() == 1)
        #expect(await retryRecorder.getAll().isEmpty)
        #expect(clock.recordedSleeps.isEmpty)
    }
}
