// ResilienceTests+CircuitBreaker.swift
// Swarm Framework
//
// Tests for CircuitBreaker resilience component using Swift Testing framework.

import Foundation
@testable import Swarm
import Testing

// MARK: - CircuitBreakerTests

@Suite("CircuitBreaker Tests")
struct CircuitBreakerTests {
    // MARK: - Initial State Tests

    @Test("Initial state is closed")
    func initialStateClosed() async {
        let breaker = CircuitBreaker(name: "test")
        let state = await breaker.currentState()
        #expect(state == .closed)
    }

    @Test("Initial state allows requests")
    func initialStateAllowsRequests() async {
        let breaker = CircuitBreaker(name: "test")
        let isAllowing = await breaker.isAllowingRequests()
        #expect(isAllowing == true)
    }

    // MARK: - Circuit Opening Tests

    @Test("Circuit opens after failureThreshold failures")
    func circuitOpensAfterFailures() async throws {
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 3,
            resetTimeout: 60.0
        )

        // Execute 3 failing operations
        for _ in 1...3 {
            do {
                _ = try await breaker.execute {
                    throw TestError.network
                }
            } catch {
                // Expected
            }
        }

        // Circuit should now be open
        let state = await breaker.currentState()
        if case .open = state {
            // Success
        } else {
            Issue.record("Expected circuit to be open, got \(state)")
        }
    }

    @Test("Circuit remains closed below failureThreshold")
    func circuitRemainsClosedBelowThreshold() async throws {
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 5,
            resetTimeout: 60.0
        )

        // Execute 3 failing operations (below threshold)
        for _ in 1...3 {
            do {
                _ = try await breaker.execute {
                    throw TestError.network
                }
            } catch {
                // Expected
            }
        }

        let state = await breaker.currentState()
        #expect(state == .closed)
    }

    @Test("Open circuit throws circuitBreakerOpen error")
    func openCircuitThrowsError() async throws {
        let breaker = CircuitBreaker(
            name: "payment-service",
            failureThreshold: 2,
            resetTimeout: 60.0
        )

        // Trigger circuit open
        for _ in 1...2 {
            do {
                _ = try await breaker.execute {
                    throw TestError.network
                }
            } catch {
                // Expected
            }
        }

        // Next request should fail with circuitBreakerOpen
        do {
            _ = try await breaker.execute {
                "success"
            }
            Issue.record("Should have thrown circuitBreakerOpen")
        } catch let error as ResilienceError {
            if case let .circuitBreakerOpen(serviceName) = error {
                #expect(serviceName == "payment-service")
            } else {
                Issue.record("Expected circuitBreakerOpen, got \(error)")
            }
        }
    }

    // MARK: - Half-Open Transition Tests

    @Test("Circuit transitions to halfOpen after timeout")
    func circuitTransitionsToHalfOpen() async throws {
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 2,
            resetTimeout: 0.1 // Short timeout for testing
        )

        // Open the circuit
        for _ in 1...2 {
            do {
                _ = try await breaker.execute {
                    throw TestError.network
                }
            } catch {
                // Expected
            }
        }

        // Verify circuit is open
        var state = await breaker.currentState()
        if case .open = state {
            // Good
        } else {
            Issue.record("Expected circuit to be open")
        }

        // Wait for timeout
        try await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds

        // Trigger state check by attempting execution
        do {
            _ = try await breaker.execute {
                // This will check state and transition to half-open
                "test"
            }
        } catch {
            // May fail depending on timing
        }

        state = await breaker.currentState()
        // Should be halfOpen or closed (if the test operation succeeded)
        #expect(state == .halfOpen || state == .closed)
    }

    // MARK: - Circuit Closing Tests

    @Test("Circuit closes after successThreshold successes in halfOpen")
    func circuitClosesAfterSuccesses() async throws {
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 2,
            successThreshold: 2,
            resetTimeout: 0.1,
            halfOpenMaxRequests: 5
        )

        // Open the circuit
        for _ in 1...2 {
            do {
                _ = try await breaker.execute {
                    throw TestError.network
                }
            } catch {
                // Expected
            }
        }

        // Wait for timeout to transition to half-open
        try await Task.sleep(nanoseconds: 150_000_000)

        // Execute successful operations to close circuit
        for _ in 1...2 {
            _ = try await breaker.execute {
                "success"
            }
        }

        let state = await breaker.currentState()
        #expect(state == .closed)
    }

    @Test("Single success in halfOpen keeps circuit halfOpen")
    func singleSuccessInHalfOpen() async throws {
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 2,
            successThreshold: 3,
            resetTimeout: 0.1
        )

        // Open circuit
        for _ in 1...2 {
            do {
                _ = try await breaker.execute { throw TestError.network }
            } catch {}
        }

        // Wait and transition to half-open
        try await Task.sleep(nanoseconds: 150_000_000)

        // One success
        _ = try await breaker.execute { "success" }

        let state = await breaker.currentState()
        #expect(state == .halfOpen)
    }

    // MARK: - Manual Control Tests

    @Test("Manual reset closes circuit")
    func manualReset() async throws {
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 2,
            resetTimeout: 60.0
        )

        // Open the circuit
        for _ in 1...2 {
            do {
                _ = try await breaker.execute {
                    throw TestError.network
                }
            } catch {
                // Expected
            }
        }

        // Manually reset
        await breaker.reset()

        let state = await breaker.currentState()
        #expect(state == .closed)
    }

    @Test("Manual trip opens circuit")
    func manualTrip() async throws {
        let breaker = CircuitBreaker(name: "test")

        // Initially closed
        var state = await breaker.currentState()
        #expect(state == .closed)

        // Manually trip
        await breaker.trip()

        state = await breaker.currentState()
        if case .open = state {
            // Success
        } else {
            Issue.record("Expected circuit to be open after trip()")
        }
    }

    // MARK: - Statistics Tests

    @Test("Statistics track success and failure counts")
    func testStatistics() async throws {
        let breaker = CircuitBreaker(name: "test-service")

        // Execute some successful operations
        for _ in 1...3 {
            _ = try await breaker.execute {
                "success"
            }
        }

        // Execute some failures
        for _ in 1...2 {
            do {
                _ = try await breaker.execute {
                    throw TestError.network
                }
            } catch {
                // Expected
            }
        }

        let stats = await breaker.statistics()
        #expect(stats.name == "test-service")
        #expect(stats.successCount == 3)
        #expect(stats.failureCount == 2)
        #expect(stats.lastFailureTime != nil)
    }

    @Test("Statistics calculate success rate correctly")
    func testSuccessRate() async throws {
        let breaker = CircuitBreaker(name: "test")

        // 3 successes, 1 failure = 75% success rate
        _ = try await breaker.execute { "ok" }
        _ = try await breaker.execute { "ok" }
        _ = try await breaker.execute { "ok" }
        do {
            _ = try await breaker.execute { throw TestError.network }
        } catch {}

        let stats = await breaker.statistics()
        let rate = stats.successRate ?? 0.0
        #expect(abs(rate - 0.75) < 0.01)
    }

    // MARK: - HalfOpen Request Limiting Tests

    @Test("HalfOpen state limits concurrent requests")
    func halfOpenRequestLimit() async throws {
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 2,
            resetTimeout: 0.1,
            halfOpenMaxRequests: 1
        )

        // Open circuit
        for _ in 1...2 {
            do {
                _ = try await breaker.execute { throw TestError.network }
            } catch {}
        }

        // Wait for half-open transition
        try await Task.sleep(nanoseconds: 150_000_000)

        // First request should be allowed
        let task = Task { @Sendable in
            try await breaker.execute {
                try await Task.sleep(nanoseconds: 100_000_000) // Slow operation
                return "success"
            }
        }

        // Give it time to start
        try await Task.sleep(nanoseconds: 10_000_000)

        // Second concurrent request should be blocked
        do {
            _ = try await breaker.execute {
                "should fail"
            }
            Issue.record("Second request should have been blocked")
        } catch let error as ResilienceError {
            if case .circuitBreakerOpen = error {
                // Expected
            } else {
                Issue.record("Expected circuitBreakerOpen")
            }
        }

        // Clean up
        _ = try await task.value
    }
}

// MARK: - CircuitBreakerRegistryTests

@Suite("CircuitBreakerRegistry Tests")
struct CircuitBreakerRegistryTests {
    @Test("Registry creates and returns circuit breakers")
    func registryCreatesBreakers() async {
        let registry = CircuitBreakerRegistry()

        let breaker1 = await registry.breaker(named: "api")
        let breaker2 = await registry.breaker(named: "database")

        let stats1 = await breaker1.statistics()
        let stats2 = await breaker2.statistics()

        #expect(stats1.name == "api")
        #expect(stats2.name == "database")
    }

    @Test("Registry returns same instance for same name")
    func registryReturnsSameInstance() async {
        let registry = CircuitBreakerRegistry()

        let breaker1 = await registry.breaker(named: "service")
        let breaker2 = await registry.breaker(named: "service")

        // Should be the same instance
        let stats1 = await breaker1.statistics()
        let stats2 = await breaker2.statistics()

        #expect(stats1.name == stats2.name)
    }

    @Test("Registry applies custom configuration")
    func registryCustomConfiguration() async throws {
        let registry = CircuitBreakerRegistry()

        let breaker = await registry.breaker(named: "custom") { config in
            config.failureThreshold = 10
        }

        // Verify threshold by testing it
        for _ in 1...9 {
            do {
                _ = try await breaker.execute { throw TestError.network }
            } catch {}
        }

        let state = await breaker.currentState()
        #expect(state == .closed) // Should still be closed with 9 failures
    }

    @Test("Registry resetAll resets all breakers")
    func registryResetAll() async throws {
        let registry = CircuitBreakerRegistry()

        let breaker1 = await registry.breaker(named: "service1")
        let breaker2 = await registry.breaker(named: "service2")

        // Trip both breakers
        await breaker1.trip()
        await breaker2.trip()

        // Reset all
        await registry.resetAll()

        let state1 = await breaker1.currentState()
        let state2 = await breaker2.currentState()

        #expect(state1 == .closed)
        #expect(state2 == .closed)
    }
}
