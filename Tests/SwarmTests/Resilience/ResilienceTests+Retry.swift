// ResilienceTests+Retry.swift
// Swarm Framework
//
// Tests for RetryPolicy resilience component using Swift Testing framework.

import Foundation
@testable import Swarm
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

    // MARK: - Deterministic Jitter Tests

    @Test("exponentialWithJitter upper-bound source returns capped exponential delays")
    func jitterUpperBoundReturnsCappedExponentialDelays() {
        let strategy = BackoffStrategy.exponentialWithJitter(base: 1.0, multiplier: 2.0, maxDelay: 8.0)
        let source = RetryRandomSource(randomIn: { $0.upperBound })

        #expect(strategy.delay(forAttempt: 1, randomSource: source) == 1.0)
        #expect(strategy.delay(forAttempt: 2, randomSource: source) == 2.0)
        #expect(strategy.delay(forAttempt: 3, randomSource: source) == 4.0)
        #expect(strategy.delay(forAttempt: 4, randomSource: source) == 8.0)
        // Past the cap the draw range tops out at maxDelay
        #expect(strategy.delay(forAttempt: 5, randomSource: source) == 8.0)
    }

    @Test("exponentialWithJitter lower-bound source collapses to zero delay")
    func jitterLowerBoundCollapsesToZeroDelay() {
        let strategy = BackoffStrategy.exponentialWithJitter(base: 1.0, multiplier: 2.0, maxDelay: 60.0)
        let source = RetryRandomSource(randomIn: { $0.lowerBound })

        for attempt in 1...5 {
            #expect(strategy.delay(forAttempt: attempt, randomSource: source) == 0.0)
        }
    }

    @Test("exponentialWithJitter midpoint source returns exact midpoints")
    func jitterMidpointReturnsExactMidpoints() {
        let strategy = BackoffStrategy.exponentialWithJitter(base: 1.0, multiplier: 2.0, maxDelay: 8.0)
        let source = RetryRandomSource(randomIn: { ($0.lowerBound + $0.upperBound) / 2 })

        #expect(strategy.delay(forAttempt: 1, randomSource: source) == 0.5)
        #expect(strategy.delay(forAttempt: 2, randomSource: source) == 1.0)
        #expect(strategy.delay(forAttempt: 3, randomSource: source) == 2.0)
        #expect(strategy.delay(forAttempt: 4, randomSource: source) == 4.0)
    }

    @Test("decorrelatedJitter draws from ranges derived from injected randomness")
    func decorrelatedJitterRangesFollowFormula() {
        let strategy = BackoffStrategy.decorrelatedJitter(base: 1.0, maxDelay: 100.0)
        let ranges = SyncRecorder<ClosedRange<Double>>()
        let source = RetryRandomSource(randomIn: { range in
            ranges.record(range)
            return range.upperBound
        })

        // previousSleep grows by a factor of 3 per attempt after the first
        #expect(strategy.delay(forAttempt: 1, randomSource: source) == 3.0)
        #expect(strategy.delay(forAttempt: 2, randomSource: source) == 3.0)
        #expect(strategy.delay(forAttempt: 3, randomSource: source) == 9.0)
        #expect(strategy.delay(forAttempt: 4, randomSource: source) == 27.0)
        #expect(strategy.delay(forAttempt: 5, randomSource: source) == 81.0)

        let recorded = ranges.all
        #expect(recorded.count == 5)
        #expect(recorded[0] == 1.0...3.0)
        #expect(recorded[1] == 1.0...3.0)
        #expect(recorded[2] == 1.0...9.0)
        #expect(recorded[3] == 1.0...27.0)
        #expect(recorded[4] == 1.0...81.0)
    }

    @Test("decorrelatedJitter lower-bound source returns base and respects maxDelay")
    func decorrelatedJitterLowerBoundAndCap() {
        let strategy = BackoffStrategy.decorrelatedJitter(base: 1.0, maxDelay: 10.0)
        let source = RetryRandomSource(randomIn: { $0.lowerBound })

        for attempt in 1...6 {
            #expect(strategy.delay(forAttempt: attempt, randomSource: source) == 1.0)
        }

        // Upper bound past maxDelay is clamped by min(delay, maxDelay)
        let cappedSource = RetryRandomSource(randomIn: { $0.upperBound })
        #expect(strategy.delay(forAttempt: 4, randomSource: cappedSource) == 10.0)
        #expect(strategy.delay(forAttempt: 5, randomSource: cappedSource) == 10.0)
    }

    @Test("Default random source draws within strategy bounds")
    func defaultRandomSourceStaysWithinBounds() {
        // GUD-001: the default source must keep drawing uniform samples from
        // exactly the pre-change ranges.
        let jitter = BackoffStrategy.exponentialWithJitter(base: 1.0, multiplier: 1.0, maxDelay: 1.0)
        var jitterSamples: Set<Double> = []
        for _ in 0..<500 {
            let value = jitter.delay(forAttempt: 1)
            #expect(value >= 0.0 && value <= 1.0)
            jitterSamples.insert(value)
        }

        let decorrelated = BackoffStrategy.decorrelatedJitter(base: 1.0, maxDelay: 100.0)
        var decorrelatedSamples: Set<Double> = []
        for _ in 0..<500 {
            let value = decorrelated.delay(forAttempt: 1)
            #expect(value >= 1.0 && value <= 3.0)
            decorrelatedSamples.insert(value)
        }

        // Continuous uniform sampling cannot realistically repeat one value
        #expect(jitterSamples.count > 1)
        #expect(decorrelatedSamples.count > 1)
    }

    @Test("Retry applies deterministic jittered backoff via injected sleep")
    func retryAppliesDeterministicJitteredBackoff() async throws {
        let counter = TestCounter()
        let recorder = SleepRecorder()
        let policy = RetryPolicy(
            maxAttempts: 2,
            backoff: .exponentialWithJitter(base: 1.0, multiplier: 2.0, maxDelay: 60.0)
        )

        let result = try await policy.execute(
            {
                let attempt = await counter.increment()
                if attempt < 3 {
                    throw TestError.transient
                }
                return "recovered"
            },
            sleep: { nanoseconds in
                await recorder.record(nanoseconds)
            },
            randomSource: RetryRandomSource(randomIn: { $0.upperBound })
        )

        #expect(result == "recovered")
        #expect(await counter.get() == 3)

        // Attempt 1 sleeps 1s (jittered cap), attempt 2 sleeps 2s; zero real time passes
        let sleeps = await recorder.getAll()
        #expect(sleeps == [1_000_000_000, 2_000_000_000])
    }

    @Test("Zero-delay backoff skips the sleep handler entirely")
    func zeroDelayBackoffSkipsSleep() async throws {
        let counter = TestCounter()
        let recorder = SleepRecorder()
        let policy = RetryPolicy(maxAttempts: 2, backoff: .immediate)

        do {
            _ = try await policy.execute(
                {
                    _ = await counter.increment()
                    throw TestError.transient
                },
                sleep: { nanoseconds in
                    await recorder.record(nanoseconds)
                }
            )
            Issue.record("Expected retriesExhausted")
        } catch {}

        #expect(await counter.get() == 3)
        #expect(await recorder.getAll().isEmpty)
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
