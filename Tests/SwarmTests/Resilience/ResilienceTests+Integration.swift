// ResilienceTests+Integration.swift
// Swarm Framework
//
// Integration tests for combining multiple resilience components.

import Foundation
@testable import Swarm
import Testing

// MARK: - Integration Tests

@Suite("Resilience Integration Tests")
struct ResilienceIntegrationTests {
    @Test("RetryPolicy with CircuitBreaker integration")
    func retryWithCircuitBreaker() async throws {
        let breaker = CircuitBreaker(
            name: "api",
            failureThreshold: 3,
            resetTimeout: 0.1
        )

        let policy = RetryPolicy(
            maxAttempts: 3,
            backoff: .immediate
        )

        let counter = TestCounter()

        // Execute with both retry and circuit breaker
        do {
            _ = try await policy.execute {
                try await breaker.execute {
                    _ = await counter.increment()
                    throw TestError.network
                }
            }
        } catch {
            // Expected to fail
        }

        // Should have attempted 3 total times
        // Circuit should be open now
        let state = await breaker.currentState()
        if case .open = state {
            // Success
        } else {
            Issue.record("Expected circuit to be open")
        }
    }

    @Test("FallbackChain with RetryPolicy per step")
    func fallbackWithRetryPerStep() async throws {
        let primaryCounter = TestCounter()
        let secondaryCounter = TestCounter()

        let policy = RetryPolicy(maxAttempts: 3, backoff: .immediate)

        let result = try await FallbackChain<String>()
            .attempt(name: "Primary") {
                try await policy.execute {
                    _ = await primaryCounter.increment()
                    throw TestError.transient
                }
            }
            .attempt(name: "Secondary") {
                try await policy.execute {
                    let count = await secondaryCounter.increment()
                    if count < 2 {
                        throw TestError.transient
                    }
                    return "secondary-success"
                }
            }
            .execute()

        #expect(result == "secondary-success")
        #expect(await primaryCounter.get() == 3) // 3 total attempts
        #expect(await secondaryCounter.get() == 2) // succeeds on the 2nd total attempt
    }
}
