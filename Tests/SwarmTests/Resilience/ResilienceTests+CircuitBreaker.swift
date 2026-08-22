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
        let now = SteppedDate()
        let start = now.current
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 2,
            resetTimeout: 0.1,
            clock: BreakerClock(now: { now.current })
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

        // Verify circuit is open until exactly start + resetTimeout
        var state = await breaker.currentState()
        #expect(state == .open(until: start.addingTimeInterval(0.1)))

        // Before the window elapses, requests are rejected and the circuit stays open
        await #expect(throws: ResilienceError.self) {
            _ = try await breaker.execute {
                "too early"
            }
        }
        state = await breaker.currentState()
        #expect(state == .open(until: start.addingTimeInterval(0.1)))

        // Advance exactly to the boundary and trigger the state check via execution
        now.advance(by: 0.1)
        do {
            _ = try await breaker.execute {
                "test"
            }
        } catch {
            // May fail depending on timing
        }

        state = await breaker.currentState()
        // One success counts toward successThreshold (2), so the circuit stays halfOpen
        #expect(state == .halfOpen)
    }

    // MARK: - Circuit Closing Tests

    @Test("Circuit closes after successThreshold successes in halfOpen")
    func circuitClosesAfterSuccesses() async throws {
        let now = SteppedDate()
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 2,
            successThreshold: 2,
            resetTimeout: 0.1,
            halfOpenMaxRequests: 5,
            clock: BreakerClock(now: { now.current })
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

        // Advance past the timeout to transition to half-open
        now.advance(by: 0.15)

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
        let now = SteppedDate()
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 2,
            successThreshold: 3,
            resetTimeout: 0.1,
            clock: BreakerClock(now: { now.current })
        )

        // Open circuit
        for _ in 1...2 {
            do {
                _ = try await breaker.execute { throw TestError.network }
            } catch {}
        }

        // Advance past the timeout to transition to half-open
        now.advance(by: 0.15)

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
        let now = SteppedDate()
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 2,
            resetTimeout: 0.1,
            halfOpenMaxRequests: 1,
            clock: BreakerClock(now: { now.current })
        )

        // Open circuit
        for _ in 1...2 {
            do {
                _ = try await breaker.execute { throw TestError.network }
            } catch {}
        }

        // Advance past the timeout so the next request transitions to half-open
        now.advance(by: 0.15)

        let (enteredStream, enteredContinuation) = AsyncStream<Void>.makeStream()
        let (releaseStream, releaseContinuation) = AsyncStream<Void>.makeStream()

        // First request should be allowed; hold it in flight inside half-open
        let task = Task { @Sendable in
            try await breaker.execute {
                enteredContinuation.yield()
                await releaseStream.first { _ in true }
                return "success"
            }
        }

        // Deterministically wait until the first request is in flight
        await enteredStream.first { _ in true }

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

        // Release the held request and let it succeed
        releaseContinuation.yield()
        let result = try await task.value
        #expect(result == "success")

        // One success counts toward successThreshold (default 2): still halfOpen
        let state = await breaker.currentState()
        #expect(state == .halfOpen)
    }

    // MARK: - Deterministic Time Tests

    @Test("Manual trip computes open window from injected clock")
    func manualTripUsesInjectedClock() async throws {
        let now = SteppedDate(Date(timeIntervalSince1970: 5_000))
        let start = now.current
        let breaker = CircuitBreaker(
            name: "test",
            resetTimeout: 30.0,
            clock: BreakerClock(now: { now.current })
        )

        await breaker.trip()

        let state = await breaker.currentState()
        #expect(state == .open(until: start.addingTimeInterval(30.0)))
    }

    @Test("Half-open probe failure re-opens from injected instant")
    func halfOpenProbeFailureReopensFromInjectedNow() async throws {
        let now = SteppedDate(Date(timeIntervalSince1970: 6_000))
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 2,
            resetTimeout: 10.0,
            clock: BreakerClock(now: { now.current })
        )

        // Open the circuit
        for _ in 1...2 {
            do {
                _ = try await breaker.execute { throw TestError.network }
            } catch {}
        }

        // Advance past the window and fail the half-open probe
        now.advance(by: 11.0)
        let probedAt = now.current
        do {
            _ = try await breaker.execute { throw TestError.network }
            Issue.record("Failing probe should rethrow its error")
        } catch {}

        // Re-open deadline must come from the injected now, not the wall clock
        let state = await breaker.currentState()
        #expect(state == .open(until: probedAt.addingTimeInterval(10.0)))
    }

    @Test("Boundary exactly at open deadline transitions to halfOpen")
    func boundaryExactlyAtDeadlineTransitionsToHalfOpen() async throws {
        let now = SteppedDate(Date(timeIntervalSince1970: 7_000))
        let breaker = CircuitBreaker(
            name: "test",
            failureThreshold: 1,
            resetTimeout: 5.0,
            clock: BreakerClock(now: { now.current })
        )

        do {
            _ = try await breaker.execute { throw TestError.network }
        } catch {}
        guard case let .open(until: deadline) = await breaker.currentState() else {
            Issue.record("Expected open state after threshold failure")
            return
        }

        // One tick below the deadline: still open
        now.advance(by: 4.999)
        await #expect(throws: ResilienceError.self) {
            _ = try await breaker.execute { "rejected" }
        }
        let stillOpen = await breaker.currentState()
        #expect(stillOpen == .open(until: deadline))

        // Exactly at the deadline (`now >= until`): transition fires
        now.advance(by: 0.001)
        _ = try await breaker.execute { "probe" }
        let state = await breaker.currentState()
        // successThreshold defaults to 2, so a single success stays halfOpen
        #expect(state == .halfOpen)
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
