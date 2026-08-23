// ResilienceTests+CircuitBreaker.swift
// Swarm Framework
//
// Tests for CircuitBreaker resilience component using Swift Testing framework.
// Transition timing is driven entirely by VirtualClock (no real sleeping).

import Foundation
@_spi(ColonyInternal) @testable import Swarm
import Testing

// MARK: - CircuitBreakerTests

@Suite("CircuitBreaker Tests")
struct CircuitBreakerTests {
    /// Creates a breaker driven by a fresh virtual clock starting at nanosecond 0.
    ///
    /// Construction anchors the breaker's Date timeline at the current wall
    /// clock paired with nanosecond 0, so every injected instant converts via
    /// `anchorDate.addingTimeInterval(nanoseconds / 1e9)`.
    private func makeVirtualBreaker(
        name: String = "test",
        failureThreshold: Int,
        successThreshold: Int = 2,
        resetTimeout: TimeInterval,
        halfOpenMaxRequests: Int = 1
    ) -> (breaker: CircuitBreaker, clock: VirtualClock) {
        let clock = VirtualClock()
        let breaker = CircuitBreaker(
            name: name,
            failureThreshold: failureThreshold,
            successThreshold: successThreshold,
            resetTimeout: resetTimeout,
            halfOpenMaxRequests: halfOpenMaxRequests,
            clock: clock
        )
        return (breaker, clock)
    }

    /// The `Date` the breaker assigns to the given virtual-clock reading.
    private func date(_ breaker: CircuitBreaker, atNanoseconds nanoseconds: UInt64) async -> Date {
        let bridge = await breaker.clockBridge
        return bridge.date(atNanoseconds: nanoseconds)
    }

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

    @Test("Circuit opens at the exact injected instant")
    func circuitOpensAtExactInjectedInstant() async throws {
        let (breaker, clock) = makeVirtualBreaker(
            name: "test",
            failureThreshold: 3,
            resetTimeout: 60.0
        )

        // All three failures stamp at virtual time 10 s.
        clock.advance(by: 10_000_000_000)

        for _ in 1...3 {
            do {
                _ = try await breaker.execute {
                    throw TestError.network
                }
            } catch {
                // Expected
            }
        }

        let expectedUntil = await date(breaker, atNanoseconds: 10_000_000_000).addingTimeInterval(60.0)
        let state = await breaker.currentState()
        #expect(state == .open(until: expectedUntil))
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

    @Test("Circuit transitions to halfOpen at the exact injected instant")
    func circuitTransitionsToHalfOpen() async throws {
        let (breaker, clock) = makeVirtualBreaker(
            name: "test",
            failureThreshold: 2,
            resetTimeout: 60.0
        )

        // Open the circuit at virtual time 0
        for _ in 1...2 {
            do {
                _ = try await breaker.execute {
                    throw TestError.network
                }
            } catch {
                // Expected
            }
        }

        let expectedUntil = await date(breaker, atNanoseconds: 0).addingTimeInterval(60.0)

        // Verify circuit is open with the exact window
        var state = await breaker.currentState()
        #expect(state == .open(until: expectedUntil))

        // Just before the window elapses: still open, requests blocked.
        // Margin is 1 ms because Date's Double storage resolves ~100 ns at
        // present-day epochs; finer probes round onto the boundary itself.
        clock.advance(to: 60_000_000_000 - 1_000_000)
        do {
            _ = try await breaker.execute {
                "too early"
            }
            Issue.record("Request before the deadline should have been blocked")
        } catch let error as ResilienceError {
            guard case .circuitBreakerOpen = error else {
                Issue.record("Expected circuitBreakerOpen, got \(error)")
                return
            }
        }

        state = await breaker.currentState()
        #expect(state == .open(until: expectedUntil))

        // Advance to exactly the injected deadline: transition fires
        clock.advance(to: 60_000_000_000)
        let result = try await breaker.execute {
            "recovered"
        }
        #expect(result == "recovered")

        state = await breaker.currentState()
        // Success streak (1 of 2) keeps the circuit half-open
        #expect(state == .halfOpen)
    }

    // MARK: - Circuit Closing Tests

    @Test("Circuit closes after successThreshold successes in halfOpen")
    func circuitClosesAfterSuccesses() async throws {
        let (breaker, clock) = makeVirtualBreaker(
            name: "test",
            failureThreshold: 2,
            successThreshold: 2,
            resetTimeout: 60.0,
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

        // Jump instantly to the exact half-open transition instant
        clock.advance(to: 60_000_000_000)

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
        let (breaker, clock) = makeVirtualBreaker(
            name: "test",
            failureThreshold: 2,
            successThreshold: 3,
            resetTimeout: 60.0
        )

        // Open circuit
        for _ in 1...2 {
            do {
                _ = try await breaker.execute { throw TestError.network }
            } catch {}
        }

        // Jump instantly past the open window into half-open
        clock.advance(to: 60_000_000_000)

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

    @Test("Second trip extends the window from the second call's instant")
    func secondTripExtendsWindowFromLatestInstant() async throws {
        let (breaker, clock) = makeVirtualBreaker(name: "test", failureThreshold: 2, resetTimeout: 60.0)

        // First trip at virtual time 10 s
        clock.advance(to: 10_000_000_000)
        await breaker.trip()
        var state = await breaker.currentState()
        #expect(state == .open(until: await date(breaker, atNanoseconds: 10_000_000_000).addingTimeInterval(60.0)))

        // Second trip at virtual time 20 s must re-anchor the window there
        clock.advance(to: 20_000_000_000)
        await breaker.trip()
        state = await breaker.currentState()
        #expect(state == .open(until: await date(breaker, atNanoseconds: 20_000_000_000).addingTimeInterval(60.0)))
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

    @Test("Statistics lastFailureTime stamps from the injected clock")
    func statisticsLastFailureTimeUsesInjectedClock() async throws {
        let (breaker, clock) = makeVirtualBreaker(
            name: "test",
            failureThreshold: 5,
            resetTimeout: 60.0
        )

        // Failure stamped at virtual time 42 s
        clock.advance(to: 42_000_000_000)
        do {
            _ = try await breaker.execute {
                throw TestError.network
            }
        } catch {
            // Expected
        }

        let stats = await breaker.statistics()
        let expectedFailureInstant = await date(breaker, atNanoseconds: 42_000_000_000)
        #expect(stats.lastFailureTime == expectedFailureInstant)
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
        let (breaker, clock) = makeVirtualBreaker(
            name: "test",
            failureThreshold: 2,
            resetTimeout: 60.0,
            halfOpenMaxRequests: 1
        )

        // Open circuit
        for _ in 1...2 {
            do {
                _ = try await breaker.execute { throw TestError.network }
            } catch {}
        }

        // Jump to the exact half-open transition instant
        clock.advance(to: 60_000_000_000)

        // Deterministic in-flight coordination: the first half-open operation
        // signals entry, then suspends until released by this test.
        let started = AsyncLatch()
        let release = AsyncLatch()

        let task = Task {
            try await breaker.execute {
                started.open()
                await release.wait()
                return "success"
            }
        }

        // Proceed only once the first request holds the half-open slot.
        await started.wait()

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
        release.open()
        _ = try await task.value
    }
}

// MARK: - Pure Transition Math Tests

@Suite("CircuitBreaker Transition Math Tests")
struct CircuitBreakerTransitionMathTests {
    /// Fixed reference instant for deterministic expectations.
    private let reference = Date(timeIntervalSince1970: 1_000_000)

    private func snapshot(
        state: CircuitBreaker.State = .closed,
        consecutiveFailures: Int = 0,
        consecutiveSuccesses: Int = 0
    ) -> CircuitBreakerTransitions.Snapshot {
        .init(
            state: state,
            consecutiveFailures: consecutiveFailures,
            consecutiveSuccesses: consecutiveSuccesses
        )
    }

    @Test("Failure below threshold keeps the circuit closed")
    func failureBelowThresholdKeepsClosed() {
        let after = CircuitBreakerTransitions.failure(
            snapshot(consecutiveFailures: 1),
            failureThreshold: 3,
            resetTimeout: 60.0,
            now: reference
        )

        #expect(after.state == .closed)
        #expect(after.consecutiveFailures == 2)
        #expect(after.consecutiveSuccesses == 0)
    }

    @Test("Failure at threshold opens with the exact deadline")
    func failureAtThresholdOpensWithExactDeadline() {
        let after = CircuitBreakerTransitions.failure(
            snapshot(consecutiveFailures: 2),
            failureThreshold: 3,
            resetTimeout: 90.0,
            now: reference
        )

        #expect(after.state == .open(until: reference.addingTimeInterval(90.0)))
        #expect(after.consecutiveFailures == 3)
    }

    @Test("Failure while open leaves the window untouched")
    func failureWhileOpenLeavesWindowUntouched() {
        let originalUntil = reference.addingTimeInterval(30.0)
        let after = CircuitBreakerTransitions.failure(
            snapshot(state: .open(until: originalUntil), consecutiveFailures: 4),
            failureThreshold: 3,
            resetTimeout: 90.0,
            now: reference.addingTimeInterval(40.0)
        )

        #expect(after.state == .open(until: originalUntil))
        #expect(after.consecutiveFailures == 5)
    }

    @Test("Any failure in halfOpen reopens from that failure's instant")
    func failureInHalfOpenReopensFromFailureInstant() {
        let failureInstant = reference.addingTimeInterval(75.0)
        let after = CircuitBreakerTransitions.failure(
            snapshot(state: .halfOpen),
            failureThreshold: 3,
            resetTimeout: 90.0,
            now: failureInstant
        )

        #expect(after.state == .open(until: failureInstant.addingTimeInterval(90.0)))
    }

    @Test("Success in halfOpen accumulates and closes at the threshold")
    func successInHalfOpenAccumulatesAndCloses() {
        let afterFirst = CircuitBreakerTransitions.success(snapshot(state: .halfOpen), successThreshold: 2)
        #expect(afterFirst.state == .halfOpen)
        #expect(afterFirst.consecutiveSuccesses == 1)

        let afterSecond = CircuitBreakerTransitions.success(afterFirst, successThreshold: 2)
        #expect(afterSecond.state == .closed)
        #expect(afterSecond.consecutiveSuccesses == 0)
        #expect(afterSecond.consecutiveFailures == 0)
    }

    @Test("Success outside halfOpen resets the success streak")
    func successOutsideHalfOpenResetsStreak() {
        let after = CircuitBreakerTransitions.success(
            snapshot(state: .open(until: reference), consecutiveSuccesses: 1),
            successThreshold: 2
        )
        #expect(after.state == .open(until: reference))
        #expect(after.consecutiveSuccesses == 0)
    }

    @Test("Manual trip opens the window from the given instant")
    func trippedOpensFromGivenInstant() {
        let after = CircuitBreakerTransitions.tripped(
            snapshot(consecutiveFailures: 7, consecutiveSuccesses: 1),
            resetTimeout: 45.0,
            now: reference
        )

        #expect(after.state == .open(until: reference.addingTimeInterval(45.0)))
        #expect(after.consecutiveSuccesses == 0)
        // Tripping does not erase the failure streak, matching legacy behavior.
        #expect(after.consecutiveFailures == 7)
    }

    @Test("Manual trip while open extends the window from the new instant")
    func trippedWhileOpenExtendsWindow() {
        let firstWindow = CircuitBreakerTransitions.tripped(
            snapshot(),
            resetTimeout: 60.0,
            now: reference
        )

        let secondInstant = reference.addingTimeInterval(25.0)
        let extended = CircuitBreakerTransitions.tripped(
            firstWindow,
            resetTimeout: 60.0,
            now: secondInstant
        )

        // Window extends from the second call's now, not stacked onto the old one.
        #expect(firstWindow.state == .open(until: reference.addingTimeInterval(60.0)))
        #expect(extended.state == .open(until: secondInstant.addingTimeInterval(60.0)))
    }

    @Test("Timeout check returns nil before the deadline")
    func timeoutCheckBeforeDeadlineReturnsNil() {
        let open = snapshot(state: .open(until: reference.addingTimeInterval(60.0)))
        let early = CircuitBreakerTransitions.timeoutCheck(open, now: reference.addingTimeInterval(59.999))

        #expect(early == nil)

        let closed = snapshot(state: .closed)
        #expect(CircuitBreakerTransitions.timeoutCheck(closed, now: reference.addingTimeInterval(999)) == nil)

        let halfOpen = snapshot(state: .halfOpen)
        #expect(CircuitBreakerTransitions.timeoutCheck(halfOpen, now: reference) == nil)
    }

    @Test("Timeout check at the deadline moves to halfOpen and resets the streak")
    func timeoutCheckAtDeadlineTransitionsToHalfOpen() {
        let open = snapshot(
            state: .open(until: reference.addingTimeInterval(60.0)),
            consecutiveFailures: 3,
            consecutiveSuccesses: 1
        )

        let transitioned = CircuitBreakerTransitions.timeoutCheck(open, now: reference.addingTimeInterval(60.0))

        #expect(transitioned != nil)
        #expect(transitioned?.state == .halfOpen)
        #expect(transitioned?.consecutiveSuccesses == 0)
        // Failure streak survives the half-open probe window.
        #expect(transitioned?.consecutiveFailures == 3)
    }
}

// MARK: - Clock Bridge Tests

@Suite("CircuitBreaker Clock Bridge Tests")
struct CircuitBreakerClockBridgeTests {
    @Test("Anchor instant maps to itself; deltas convert to seconds")
    func anchorAndDeltaMapping() {
        let anchorDate = Date(timeIntervalSince1970: 777_777)
        let bridge = CircuitBreakerClockBridge(anchorNanoseconds: 500, anchorDate: anchorDate)

        #expect(bridge.anchorNanoseconds == 500)
        #expect(bridge.date(atNanoseconds: 500) == anchorDate)
        #expect(bridge.date(atNanoseconds: 1_000_000_500) == anchorDate.addingTimeInterval(1.0))
        #expect(bridge.date(atNanoseconds: 0) == anchorDate.addingTimeInterval(-0.000_000_5))
    }
}

// MARK: - CircuitBreakerRegistry Tests

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

// MARK: - AsyncLatch

/// One-shot async gate for deterministic coordination of in-flight operations.
///
/// `wait()` suspends until `open()` is called (or resumes immediately when
/// already open), letting tests pin ordering without real sleeping.
private final class AsyncLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Opens the gate and resumes all suspended waiters.
    func open() {
        lock.lock()
        opened = true
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0.resume() }
    }

    /// Suspends until the gate is open.
    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if opened {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }
}
