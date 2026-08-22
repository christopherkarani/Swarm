// ClockSupport.swift
// Swarm Framework
//
// Clock seam support for Resilience: the live wall-clock adapter and
// Duration <-> nanosecond conversions used by SwarmClock consumers.

import Foundation

// MARK: - LiveSwarmClock

/// Default `SwarmClock` backed by system uptime and task suspension.
///
/// `nowNanoseconds()` reads monotonic boot-relative uptime (`DispatchTime`),
/// so values are not comparable to `Date` or wall-clock epochs.
/// `sleep(nanoseconds:)` suspends via `Task.sleep`, propagating cancellation
/// as `CancellationError`.
struct LiveSwarmClock: SwarmClock {
    /// Shared instance; `LiveSwarmClock` is stateless and value-semantic.
    static let live = LiveSwarmClock()

    func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

// MARK: - Nanosecond Conversions

extension Duration {
    /// Total nanoseconds for `SwarmClock`-style APIs.
    ///
    /// Negative durations clamp to `0`; overflow saturates at `UInt64.max`.
    /// Sub-nanosecond precision may round.
    var swarmNanoseconds: UInt64 {
        let (seconds, attoseconds) = components
        let total = Double(seconds) * 1_000_000_000 + Double(attoseconds) / 1_000_000_000
        guard total > 0 else { return 0 }
        return total >= Double(UInt64.max) ? UInt64.max : UInt64(total)
    }

    /// Creates a duration from nanoseconds; values beyond `Int64.max`
    /// saturate at that limit (~292 years).
    init(swarmNanoseconds value: UInt64) {
        self = value > UInt64(Int64.max)
            ? .nanoseconds(Int64.max)
            : .nanoseconds(Int64(value))
    }
}
