// ResilienceTests+RateLimiter.swift
// Swarm Framework
//
// Tests for RateLimiter edge cases and safety constraints.
// Refill timing is driven entirely by VirtualClock (no real sleeping).

import Foundation
@_spi(ColonyInternal) @testable import Swarm
import Testing

// MARK: - RateLimiterTests

@Suite("RateLimiter Tests")
struct RateLimiterTests {
    /// Creates a limiter driven by a fresh virtual clock starting at nanosecond 0,
    /// so refill math can be asserted against exact injected instants.
    private func makeVirtualLimiter(
        maxTokens: Int,
        refillRatePerSecond: Double
    ) -> (limiter: RateLimiter, clock: VirtualClock) {
        let clock = VirtualClock()
        let limiter = RateLimiter(
            maxTokens: maxTokens,
            refillRatePerSecond: refillRatePerSecond,
            clock: clock
        )
        return (limiter, clock)
    }

    // MARK: - Sanitization Tests

    @Test("Invalid maxRequestsPerMinute is sanitized")
    func invalidMaxRequestsPerMinuteIsSanitized() async {
        let limiter = RateLimiter(maxRequestsPerMinute: 0)
        let available = await limiter.available
        #expect(available >= 1)
        #expect(await limiter.tryAcquire() == true)
    }

    @Test("Invalid token bucket parameters are sanitized")
    func invalidTokenBucketParametersAreSanitized() async throws {
        let limiter = RateLimiter(maxTokens: -10, refillRatePerSecond: 0)

        // First token should always be available after sanitization.
        #expect(await limiter.tryAcquire() == true)

        // Acquire wait uses the sanitized 1 token/s rate; drive it through the
        // virtual clock so the refill path is proven without a wall-clock sleep.
        let (virtualLimiter, clock) = makeVirtualLimiter(maxTokens: -10, refillRatePerSecond: 0)
        #expect(await virtualLimiter.tryAcquire() == true)
        try await virtualLimiter.acquire()
        #expect(clock.recordedSleeps == [1_000_000_000])
    }

    @Test("Nil clock falls back to the live clock")
    func nilClockFallsBackToLiveClock() async {
        let limiter = RateLimiter(maxTokens: 2, refillRatePerSecond: 1.0, clock: nil)
        #expect(await limiter.available == 2)
        #expect(await limiter.tryAcquire() == true)
    }

    // MARK: - Virtual Clock Refill Tests

    @Test("Bucket starts full and stays capped regardless of elapsed time")
    func bucketStartsFullAndStaysCapped() async {
        let (limiter, clock) = makeVirtualLimiter(maxTokens: 3, refillRatePerSecond: 1.0)

        clock.advance(by: 60_000_000_000)
        #expect(await limiter.available == 3)
        #expect(await limiter.tryAcquire() == true)
        #expect(await limiter.available == 2)
    }

    @Test("Refill grants tokens at exactly the configured virtual instants")
    func refillGrantsAtExactInstants() async {
        let (limiter, clock) = makeVirtualLimiter(maxTokens: 2, refillRatePerSecond: 1.0)

        // Drain the bucket completely.
        #expect(await limiter.tryAcquire() == true)
        #expect(await limiter.tryAcquire() == true)
        #expect(await limiter.available == 0)

        // Half a second at 1 token/s yields half a token: still blocked.
        clock.advance(by: 500_000_000)
        #expect(await limiter.available == 0)
        #expect(await limiter.tryAcquire() == false)

        // At exactly 1 s one full token has accumulated.
        clock.advance(to: 1_000_000_000)
        #expect(await limiter.tryAcquire() == true)

        // Immediately after, the remainder (0.5 s worth) is insufficient.
        #expect(await limiter.tryAcquire() == false)

        // At exactly 2 s total, the second token has accumulated.
        clock.advance(to: 2_000_000_000)
        #expect(await limiter.tryAcquire() == true)
        #expect(await limiter.available == 0)
    }

    @Test("Refill caps at maxTokens after long idle periods")
    func refillCapsAtMaxTokens() async {
        let (limiter, clock) = makeVirtualLimiter(maxTokens: 4, refillRatePerSecond: 2.0)

        #expect(await limiter.tryAcquire() == true)
        #expect(await limiter.tryAcquire() == true)
        #expect(await limiter.available == 2)

        // 100 s at 2 tokens/s far exceeds capacity; refill must clamp at 4.
        clock.advance(by: 100_000_000_000)
        #expect(await limiter.available == 4)

        // All four tokens are spendable after the capped refill.
        for _ in 1...4 {
            #expect(await limiter.tryAcquire() == true)
        }
        #expect(await limiter.tryAcquire() == false)
    }

    @Test("acquire() waits through the injected clock with zero real sleeping")
    func acquireWaitsThroughInjectedClock() async throws {
        let (limiter, clock) = makeVirtualLimiter(maxTokens: 1, refillRatePerSecond: 2.0)

        #expect(await limiter.tryAcquire() == true)

        let wallStart = ContinuousClock.now
        try await limiter.acquire()

        // Deficit 1.0 at 2 tokens/s requires exactly 0.5 s of virtual sleep;
        // VirtualClock completes it instantly and advances itself.
        #expect(clock.recordedSleeps == [500_000_000])
        let elapsed = ContinuousClock.now - wallStart
        // A real 0.5 s sleep would exceed this bound even on a loaded runner.
        #expect(elapsed < .milliseconds(250))

        // Bucket is empty again after consumption.
        #expect(await limiter.available == 0)
    }

    @Test("Consecutive acquires each record their exact virtual wait")
    func consecutiveAcquiresRecordExactWaits() async throws {
        let (limiter, clock) = makeVirtualLimiter(maxTokens: 1, refillRatePerSecond: 1.0)

        #expect(await limiter.tryAcquire() == true)
        try await limiter.acquire()
        try await limiter.acquire()

        // Each refill needs a full second at 1 token/s.
        #expect(clock.recordedSleeps == [1_000_000_000, 1_000_000_000])
        #expect(clock.now == 2_000_000_000)
    }

    @Test("reset() restores full capacity on the injected timeline")
    func resetRestoresFullCapacityOnInjectedTimeline() async {
        let (limiter, clock) = makeVirtualLimiter(maxTokens: 3, refillRatePerSecond: 1.0)

        clock.advance(by: 30_000_000_000)
        #expect(await limiter.tryAcquire() == true)
        #expect(await limiter.available == 2)

        await limiter.reset()
        #expect(await limiter.available == 3)
        #expect(await limiter.tryAcquire() == true)
        #expect(await limiter.available == 2)
    }

    @Test("acquire() stays cancellation-aware between injected waits")
    func acquireRemainsCancellationAwareBetweenWaits() async throws {
        // A clock whose sleeps never advance time keeps acquire() looping in
        // its wait branch, so cancellation must come from the loop itself.
        final class FrozenClock: SwarmClock, @unchecked Sendable {
            private let lock = NSLock()
            private var sleeps: [UInt64] = []

            var recordedSleeps: [UInt64] {
                lock.withLock { sleeps }
            }

            func nowNanoseconds() -> UInt64 { 0 }

            func sleep(nanoseconds duration: UInt64) async throws {
                lock.withLock { sleeps.append(duration) }
                try Task.checkCancellation()
            }
        }

        let frozen = FrozenClock()
        let limiter = RateLimiter(maxTokens: 1, refillRatePerSecond: 1.0, clock: frozen)

        #expect(await limiter.tryAcquire() == true)

        let task = Task {
            try await limiter.acquire()
        }
        // Yield until the waiter has entered (and slept inside) the loop.
        while await frozen.recordedSleeps.isEmpty {
            await Task.yield()
        }
        task.cancel()

        do {
            try await task.value
            Issue.record("Expected cancelled acquire to throw CancellationError")
        } catch is CancellationError {
            // Expected: propagated between injected waits.
        }
    }
}

// MARK: - TokenBucketMath Tests

@Suite("TokenBucketMath Tests")
private struct TokenBucketMathTests {
    // MARK: refilled

    @Test("Zero elapsed time leaves tokens unchanged")
    func zeroElapsedLeavesTokensUnchanged() {
        #expect(
            TokenBucketMath.refilled(tokens: 2.5, elapsedSeconds: 0, refillRate: 3.0, maxTokens: 10)
                == 2.5
        )
    }

    @Test("Elapsed time adds elapsed times rate tokens")
    func elapsedAddsRateScaledTokens() {
        #expect(
            TokenBucketMath.refilled(tokens: 1.0, elapsedSeconds: 2.5, refillRate: 4.0, maxTokens: 20)
                == 11.0
        )
    }

    @Test("Refill clamps at maxTokens")
    func refillClampsAtMaxTokens() {
        #expect(
            TokenBucketMath.refilled(tokens: 8.0, elapsedSeconds: 10, refillRate: 5.0, maxTokens: 9)
                == 9.0
        )
        #expect(
            TokenBucketMath.refilled(tokens: 9.0, elapsedSeconds: 60, refillRate: 1.0, maxTokens: 9)
                == 9.0
        )
    }

    @Test("Negative elapsed removes tokens at the refill rate")
    func negativeElapsedRemovesTokens() {
        #expect(
            TokenBucketMath.refilled(tokens: 5.0, elapsedSeconds: -2.0, refillRate: 1.5, maxTokens: 10)
                == 2.0
        )
    }

    // MARK: waitSeconds

    @Test("Wait time is deficit divided by rate")
    func waitTimeIsDeficitOverRate() {
        #expect(TokenBucketMath.waitSeconds(forDeficit: 0.5, refillRate: 2.0) == 0.25)
        #expect(TokenBucketMath.waitSeconds(forDeficit: 1.0, refillRate: 4.0) == 0.25)
    }

    @Test("Non-positive deficits yield zero wait")
    func nonPositiveDeficitsYieldZeroWait() {
        #expect(TokenBucketMath.waitSeconds(forDeficit: 0, refillRate: 2.0) == 0)
        #expect(TokenBucketMath.waitSeconds(forDeficit: -1.5, refillRate: 2.0) == 0)
    }

    @Test("Non-finite raw quotients yield zero wait")
    func nonFiniteQuotientsYieldZeroWait() {
        // Division by a non-finite deficit or rate must never produce an
        // invalid sleep duration.
        #expect(TokenBucketMath.waitSeconds(forDeficit: .infinity, refillRate: 2.0) == 0)
        #expect(TokenBucketMath.waitSeconds(forDeficit: .nan, refillRate: 2.0) == 0)
        #expect(TokenBucketMath.waitSeconds(forDeficit: 1.0, refillRate: .infinity) == 0)
        #expect(TokenBucketMath.waitSeconds(forDeficit: 1.0, refillRate: 0) == 0)
        #expect(TokenBucketMath.waitSeconds(forDeficit: 1.0, refillRate: .nan) == 0)
    }

    // MARK: elapsedSeconds

    @Test("Elapsed seconds converts nanosecond deltas forward and backward")
    func elapsedConvertsNanosecondDeltas() {
        #expect(
            TokenBucketMath.elapsedSeconds(from: 1_000_000_000, to: 2_500_000_000) == 1.5
        )
        #expect(TokenBucketMath.elapsedSeconds(from: 500, to: 500) == 0)
        #expect(
            TokenBucketMath.elapsedSeconds(from: 2_000_000_000, to: 1_500_000_000) == -0.5
        )
    }
}
