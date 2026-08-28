// ClockSupport.swift
// Swarm Framework
//
// Clock seam support for Resilience: the live continuous-clock adapter and
// Duration <-> nanosecond conversions used by SwarmClock consumers.

import Foundation

// MARK: - LiveSwarmClock

/// Default `SwarmClock` backed by Swift's sleep-inclusive continuous clock and
/// task suspension.
///
/// `nowNanoseconds()` measures from a stored `ContinuousClock.Instant`, so
/// elapsed time includes system sleep and remains monotonic without being tied
/// to wall-clock calendar time.
/// `sleep(nanoseconds:)` suspends via `Task.sleep`, propagating cancellation
/// as `CancellationError`. Durations beyond `Int64.max` nanoseconds
/// (~292 years) saturate instead of trapping.
struct LiveSwarmClock: SwarmClock {
    /// Shared instance; `LiveSwarmClock` is stateless and value-semantic.
    static let live = LiveSwarmClock()
    private static let reference = ContinuousClock.now

    func nowNanoseconds() -> UInt64 {
        Self.reference.duration(to: ContinuousClock.now).swarmNanoseconds
    }

    func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: min(nanoseconds, UInt64(Int64.max)))
    }
}

// MARK: - Nanosecond Conversions

extension Duration {
    /// Total nanoseconds for `SwarmClock`-style APIs.
    ///
    /// Negative durations clamp to `0`; overflow saturates at `UInt64.max`.
    /// Exact integer math: every duration below the saturation point
    /// (~584 years) converts with zero precision loss.
    var swarmNanoseconds: UInt64 {
        let (seconds, attoseconds) = components
        guard seconds > 0 || attoseconds > 0 else { return 0 }
        let nanosecondsFromAttoseconds = UInt64(attoseconds / 1_000_000_000)
        let (secondsInNanoseconds, overflow) =
            UInt64(seconds).multipliedReportingOverflow(by: 1_000_000_000)
        if overflow || secondsInNanoseconds > UInt64.max - nanosecondsFromAttoseconds {
            return UInt64.max
        }
        return secondsInNanoseconds + nanosecondsFromAttoseconds
    }

    /// Creates a duration from nanoseconds; values beyond `Int64.max`
    /// saturate at that limit (~292 years).
    init(swarmNanoseconds value: UInt64) {
        self = value > UInt64(Int64.max)
            ? .nanoseconds(Int64.max)
            : .nanoseconds(Int64(value))
    }
}
