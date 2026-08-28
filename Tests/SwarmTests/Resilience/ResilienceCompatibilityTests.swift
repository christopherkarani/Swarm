// ResilienceCompatibilityTests.swift
// Swarm Framework
//
// Source-compatibility coverage for deprecated resilience aliases.

import Swarm
import Testing

@Suite("Resilience Compatibility")
struct ResilienceCompatibilityTests {
    @Test("deprecated Retry remains an alias for RetryPolicy")
    func retryAliasRemainsAvailable() {
        let legacy: Retry = .noRetry
        let canonical: RetryPolicy = legacy

        #expect(canonical.maxAttempts == RetryPolicy.noRetry.maxAttempts)
    }

    @Test("deprecated Fallback remains an alias for FallbackChain")
    func fallbackAliasRemainsAvailable() async throws {
        let legacy: Fallback<String> = Fallback()
        let result = try await legacy
            .fallback(name: "Default", "fallback-value")
            .execute()

        #expect(result == "fallback-value")
    }
}
