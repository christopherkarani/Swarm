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
        let limiter = RateLimiter(maxTokens: -10, refillRatePerSecond: 0)

        // First token should always be available after sanitization.
        #expect(await limiter.tryAcquire() == true)

        // Refill path should remain safe and not produce invalid sleep math.
        try await limiter.acquire()
    }
}
