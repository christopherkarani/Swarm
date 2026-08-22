// ResilienceTests.swift
// Swarm Framework
//
// Common test utilities and helpers for resilience component tests.
// Individual test suites are in extension files for better organization.

import Foundation
@testable import Swarm
import Synchronization
import Testing

// MARK: - SteppedDate

/// Mutex-guarded mutable date for driving injected breaker clocks.
final class SteppedDate: Sendable {
    // MARK: Private

    private let value: Mutex<Date>

    // MARK: - Initialization

    init(_ start: Date = Date(timeIntervalSince1970: 1_000)) {
        value = Mutex(start)
    }

    // MARK: Internal

    var current: Date { value.withLock { $0 } }

    func advance(by interval: TimeInterval) {
        value.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}

// MARK: - SteppedInstant

/// Mutex-guarded mutable instant for driving injected rate limiter clocks.
///
/// The sleep handler advances the instant instead of suspending, so refill
/// math across acquisition waits runs deterministically with zero real delay.
final class SteppedInstant: Sendable {
    // MARK: Private

    private let value: Mutex<ContinuousClock.Instant>

    // MARK: - Initialization

    /// Starts at the current continuous-clock instant; only `advance(by:)`
    /// moves it, keeping every step deterministic.
    init() {
        value = Mutex(ContinuousClock.now)
    }

    init(_ start: ContinuousClock.Instant) {
        value = Mutex(start)
    }

    // MARK: Internal

    var current: ContinuousClock.Instant { value.withLock { $0 } }

    func advance(by duration: Duration) {
        value.withLock { $0 = $0.advanced(by: duration) }
    }

    /// A rate limiter clock whose sleeps advance this instant instantly.
    func limiterClock() -> RateLimiterClock {
        RateLimiterClock(
            now: { [self] in current },
            sleep: { [self] duration in
                advance(by: duration)
            }
        )
    }

    /// A rate limiter clock whose sleeps neither suspend nor advance time.
    func frozenLimiterClock() -> RateLimiterClock {
        RateLimiterClock(now: { [self] in current }, sleep: { _ in })
    }
}

// MARK: - SyncRecorder

/// Mutex-guarded value recorder usable from synchronous closures.
final class SyncRecorder<T: Sendable>: Sendable {
    // MARK: Private

    private let items: Mutex<[T]> = Mutex([])

    // MARK: Internal

    func record(_ item: T) {
        items.withLock { $0.append(item) }
    }

    var all: [T] { items.withLock { $0 } }
}

// MARK: - SleepRecorder

/// Records sanitized backoff delays handed to an injected retry sleep handler.
actor SleepRecorder {
    // MARK: Internal

    func record(_ nanoseconds: UInt64) {
        durations.append(nanoseconds)
    }

    func getAll() -> [UInt64] { durations }

    // MARK: Private

    private var durations: [UInt64] = []
}

// MARK: - TestError

enum TestError: Error, Equatable, LocalizedError {
    case transient
    case permanent
    case network
    case timeout

    var errorDescription: String? {
        switch self {
        case .transient: "Transient error occurred"
        case .permanent: "Permanent error occurred"
        case .network: "Network error occurred"
        case .timeout: "Timeout error occurred"
        }
    }
}

// MARK: - TestCounter

/// Thread-safe counter for testing async code
actor TestCounter {
    // MARK: Internal

    func increment() -> Int {
        value += 1
        return value
    }

    func get() -> Int { value }

    func reset() { value = 0 }

    // MARK: Private

    private var value: Int = 0
}

// MARK: - TestRecorder

/// Thread-safe array for tracking values
actor TestRecorder<T: Sendable> {
    // MARK: Internal

    func append(_ item: T) {
        items.append(item)
    }

    func getAll() -> [T] { items }

    func count() -> Int { items.count }

    // MARK: Private

    private var items: [T] = []
}

// MARK: - TestFlag

/// Thread-safe boolean flag
actor TestFlag {
    // MARK: Internal

    func set(_ newValue: Bool) {
        value = newValue
    }

    func get() -> Bool { value }

    // MARK: Private

    private var value: Bool = false
}
