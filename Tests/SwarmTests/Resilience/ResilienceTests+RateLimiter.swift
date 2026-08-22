// ResilienceTests+RateLimiter.swift
// Swarm Framework
//
// Tests for RateLimiter edge cases and safety constraints.

import Foundation
@testable import Swarm
import Testing

@Suite("RateLimiter Tests")
struct RateLimiterTests {
    @Test("Invalid maxRequestsPerMinute is sanitized")
    func invalidMaxRequestsPerMinuteIsSanitized() async {
        let limiter = RateLimiter(maxRequestsPerMinute: 0)
        let available = await limiter.available
        #expect(available >= 1)
        #expect(await limiter.tryAcquire() == true)
    }

    @Test("Invalid token bucket parameters are sanitized")
    func invalidTokenBucketParametersAreSanitized() async throws {
        let time = SteppedInstant()
        let limiter = RateLimiter(maxTokens: -10, refillRatePerSecond: 0, clock: time.limiterClock())

        // First token should always be available after sanitization.
        #expect(await limiter.tryAcquire() == true)

        // Refill path should remain safe and not produce invalid sleep math.
        // The injected clock advances during waits, so this returns instantly
        // instead of sleeping one real second.
        try await limiter.acquire()
    }

    // MARK: - Deterministic Time Tests

    @Test("Partial refills below one token do not permit acquisition")
    func partialRefillsBelowOneTokenDoNotPermitAcquisition() async {
        let time = SteppedInstant()
        let limiter = RateLimiter(
            maxTokens: 2,
            refillRatePerSecond: 1.0,
            clock: time.limiterClock()
        )

        // Drain the bucket
        #expect(await limiter.tryAcquire() == true)
        #expect(await limiter.tryAcquire() == true)
        #expect(await limiter.available == 0)

        // Quarter-second steps accumulate fractional tokens that stay below one
        for _ in 1...3 {
            time.advance(by: .seconds(0.25))
            #expect(await limiter.available == 0)
            #expect(await limiter.tryAcquire() == false)
        }

        // The fourth quarter second completes exactly one whole token
        time.advance(by: .seconds(0.25))
        #expect(await limiter.available == 1)
        #expect(await limiter.tryAcquire() == true)
    }

    @Test("Refill never exceeds bucket capacity")
    func refillCapsAtCapacity() async {
        let time = SteppedInstant()
        let limiter = RateLimiter(
            maxTokens: 3,
            refillRatePerSecond: 2.0,
            clock: time.limiterClock()
        )

        // Drain, then advance far beyond the time needed to refill to capacity
        #expect(await limiter.tryAcquire() == true)
        #expect(await limiter.tryAcquire() == true)
        #expect(await limiter.tryAcquire() == true)
        time.advance(by: .seconds(10_000))

        #expect(await limiter.available == 3)
    }

    @Test("acquire bridges empty bucket via injected sleeps with zero real delay")
    func acquireBridgesEmptyBucketViaInjectedSleeps() async throws {
        let time = SteppedInstant()
        let recorder = SleepRecorder()
        let clock = RateLimiterClock(
            now: { time.current },
            sleep: { duration in
                await recorder.record(UInt64(duration.timeInterval * 1_000_000_000))
                time.advance(by: duration)
            }
        )
        let limiter = RateLimiter(maxTokens: 2, refillRatePerSecond: 1.0, clock: clock)

        // Drain so acquisition must wait for a refill
        #expect(await limiter.tryAcquire() == true)
        #expect(await limiter.tryAcquire() == true)

        try await limiter.acquire()

        // Exactly one one-second wait bridged the gap to the next token
        let sleeps = await recorder.getAll()
        #expect(sleeps.count == 1)
        #expect(sleeps.first == 1_000_000_000)

        // The bridged token was consumed by the acquisition
        #expect(await limiter.available == 0)
    }

    @Test("acquire consumes instantly without sleeping when tokens exist")
    func acquireWithoutWaitDoesNotSleep() async throws {
        let time = SteppedInstant()
        let recorder = SleepRecorder()
        let clock = RateLimiterClock(
            now: { time.current },
            sleep: { duration in
                await recorder.record(UInt64(duration.timeInterval * 1_000_000_000))
                time.advance(by: duration)
            }
        )
        let limiter = RateLimiter(maxTokens: 2, refillRatePerSecond: 1.0, clock: clock)

        try await limiter.acquire()

        let sleeps = await recorder.getAll()
        #expect(sleeps.isEmpty)
        #expect(await limiter.available == 1)
    }
}
