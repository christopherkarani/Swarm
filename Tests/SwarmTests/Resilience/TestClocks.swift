// TestClocks.swift
// Swarm Framework
//
// Virtual clock and seeded randomness for deterministic Resilience tests.
// Consumed by clock/backoff/limiter suites (T2-T4).

import Foundation
@_spi(ColonyInternal) @testable import Swarm
import Testing

// MARK: - VirtualClock

/// Manually advanced `SwarmClock` for deterministic time control in tests.
///
/// All mutable state is guarded by a single `NSLock`, so the class is safely
/// usable across concurrency domains (`@unchecked Sendable`).
///
/// Sleep semantics: `sleep(nanoseconds:)` completes instantly — it records the
/// requested duration and advances its own clock by that amount instead of
/// waiting, so suites can exercise arbitrarily long delays with zero real time.
final class VirtualClock: SwarmClock, @unchecked Sendable {
    private let lock = NSLock()
    private var currentNanoseconds: UInt64
    private var sleeps: [UInt64] = []

    init(startingAtNanoseconds start: UInt64 = 0) {
        currentNanoseconds = start
    }

    /// Current virtual instant in nanoseconds.
    var now: UInt64 {
        lock.withLock { currentNanoseconds }
    }

    /// Every sleep request in order, as nanosecond durations.
    var recordedSleeps: [UInt64] {
        lock.withLock { sleeps }
    }

    var sleepCount: Int {
        lock.withLock { sleeps.count }
    }

    /// Jumps to an absolute instant (may move backwards).
    func advance(to target: UInt64) {
        lock.withLock { currentNanoseconds = target }
    }

    /// Moves the clock forward by a nanosecond delta.
    func advance(by delta: UInt64) {
        lock.withLock { currentNanoseconds += delta }
    }

    /// Moves the clock forward by a duration delta.
    func advance(by delta: Duration) {
        advance(by: delta.swarmNanoseconds)
    }

    // MARK: SwarmClock

    func nowNanoseconds() -> UInt64 {
        now
    }

    func sleep(nanoseconds duration: UInt64) async throws {
        lock.withLock {
            sleeps.append(duration)
            currentNanoseconds += duration
        }
    }
}

// MARK: - SeededRandomGenerator

/// Deterministic SplitMix64 random source producing reproducible sequences.
///
/// Seedable stand-in for `Double.random` so jitter/backoff tests can assert
/// exact delay values. Each instance owns its own stream; copies replay it.
struct SeededRandomGenerator: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// Next raw 64-bit value in the sequence.
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform Double in `range`, drawn from 53 bits of entropy.
    mutating func random(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) * 0x1.0p-53
        let width = range.upperBound - range.lowerBound
        return min(range.lowerBound + unit * width, range.upperBound)
    }
}

// MARK: - Virtual Clock Tests

@Suite("VirtualClock Tests")
private struct VirtualClockTests {
    @Test("Starts at its configured instant")
    func startsAtConfiguredInstant() {
        let clock = VirtualClock(startingAtNanoseconds: 1_000)
        #expect(clock.now == 1_000)
        #expect(clock.nowNanoseconds() == 1_000)
    }

    @Test("advance(by:) moves forward, advance(to:) sets absolute instants")
    func advancingMovesAndSetsTime() {
        let clock = VirtualClock()
        clock.advance(by: 500)
        #expect(clock.now == 500)

        clock.advance(to: 250)
        #expect(clock.now == 250)

        clock.advance(to: 100)
        #expect(clock.now == 100)
    }

    @Test("Duration-based advance converts to nanoseconds")
    func durationAdvanceConvertsUnits() {
        let clock = VirtualClock()
        clock.advance(by: .seconds(2) + .milliseconds(500))
        #expect(clock.now == 2_500_000_000)
    }

    @Test("Sleeps are recorded, not awaited; virtual time advances instantly")
    func sleepsAreRecordedNotAwaited() async throws {
        let clock = VirtualClock()

        try await clock.sleep(nanoseconds: 1_000_000_000) // 1 s virtual
        try await clock.sleep(nanoseconds: 60_000_000_000) // 60 s virtual

        #expect(clock.sleepCount == 2)
        #expect(clock.recordedSleeps == [1_000_000_000, 60_000_000_000])
        #expect(clock.now == 61_000_000_000)
    }
}

// MARK: - Seeded Random Generator Tests

@Suite("SeededRandomGenerator Tests")
private struct SeededRandomGeneratorTests {
    @Test("Same seed reproduces identical sequences")
    func sameSeedReproducesSequence() {
        var first = SeededRandomGenerator(seed: 42)
        var second = SeededRandomGenerator(seed: 42)

        let left = (0..<64).map { _ in first.next() }
        let right = (0..<64).map { _ in second.next() }

        #expect(left == right)
    }

    @Test("Matches published SplitMix64 reference vectors")
    func matchesPublishedSplitMix64Vectors() {
        var seedZero = SeededRandomGenerator(seed: 0)
        #expect([
            seedZero.next(), seedZero.next(), seedZero.next(),
        ] == [
            0xE220_A839_7B1D_CDAF,
            0x6E78_9E6A_A1B9_65F4,
            0x06C4_5D18_8009_454F,
        ])

        var seed42 = SeededRandomGenerator(seed: 42)
        #expect([
            seed42.next(), seed42.next(), seed42.next(),
        ] == [
            13_679_457_532_755_275_413,
            2_949_826_092_126_892_291,
            5_139_283_748_462_763_858,
        ])
    }

    @Test("Different seeds diverge")
    func differentSeedsDiverge() {
        var one = SeededRandomGenerator(seed: 1)
        var two = SeededRandomGenerator(seed: 2)

        let left = (0..<16).map { _ in one.next() }
        let right = (0..<16).map { _ in two.next() }

        #expect(left != right)
    }

    @Test("Ranged doubles stay in bounds and replay exactly")
    func rangedDoublesStayInBoundsAndReplay() {
        var generator = SeededRandomGenerator(seed: 7)
        let range: ClosedRange<Double> = 0.25...4.75

        let draws = (0..<1_000).map { _ in generator.random(in: range) }

        #expect(draws.allSatisfy { range.contains($0) })

        var replay = SeededRandomGenerator(seed: 7)
        #expect((0..<1_000).map { _ in replay.random(in: range) } == draws)
    }
}

// MARK: - Duration Nanosecond Conversion Tests

@Suite("Duration Nanosecond Conversion Tests")
private struct DurationNanosecondConversionTests {
    @Test("Positive durations convert exactly within Double precision")
    func positiveConversionIsExact() {
        #expect((.seconds(1) + .nanoseconds(1)).swarmNanoseconds == 1_000_000_001)
        #expect(Duration.milliseconds(250).swarmNanoseconds == 250_000_000)
    }

    @Test("Exact integer math survives the 2^53 nanosecond Double cliff")
    func conversionIsExactPastDoublePrecision() {
        // 2^53 ns + 1: the previous Double-based conversion truncated to 2^53.
        #expect(
            Duration.nanoseconds(9_007_199_254_740_993).swarmNanoseconds
                == 9_007_199_254_740_993
        )
        // Exact just below saturation: exercises the addition-overflow guard.
        #expect(
            Duration.seconds(18_446_744_073).swarmNanoseconds == 18_446_744_073_000_000_000
        )
        // Seconds product beyond UInt64.max: exercises the multiply-overflow branch.
        #expect(Duration.seconds(Int64.max - 123).swarmNanoseconds == UInt64.max)
    }

    @Test("Negative and zero durations clamp to zero nanoseconds")
    func negativeDurationsClampToZero() {
        #expect(Duration.seconds(0).swarmNanoseconds == 0)
        #expect(Duration.seconds(-1).swarmNanoseconds == 0)
        #expect(Duration.milliseconds(-500).swarmNanoseconds == 0)
    }

    @Test("Overflowing durations saturate at UInt64.max")
    func overflowingDurationsSaturate() {
        #expect(Duration.seconds(Int64.max).swarmNanoseconds == UInt64.max)
    }

    @Test("Init saturates values beyond Int64.max nanoseconds")
    func initSaturatesBeyondInt64MaxNanoseconds() {
        #expect(
            Duration(swarmNanoseconds: UInt64(Int64.max) + 1)
                == .nanoseconds(Int64.max)
        )
        #expect(Duration(swarmNanoseconds: 1_500_000_000) == .milliseconds(1500))
    }
}

// MARK: - Live Clock Tests

@Suite("LiveSwarmClock Tests")
private struct LiveSwarmClockTests {
    @Test("Reads nonnegative monotonic time across suspension")
    func readsNonnegativeMonotonicTimeAcrossSuspension() async throws {
        let clock = LiveSwarmClock()
        let first = clock.nowNanoseconds()

        try await Task.sleep(nanoseconds: 1_000_000)

        let second = clock.nowNanoseconds()
        #expect(first >= 0)
        #expect(second >= first)
    }

    @Test("Sleep propagates task cancellation")
    func sleepPropagatesCancellation() async throws {
        let clock = LiveSwarmClock.live

        let task = Task {
            try await clock.sleep(nanoseconds: 60_000_000_000)
        }
        task.cancel()

        do {
            try await task.value
            Issue.record("Expected cancelled sleep to throw CancellationError")
        } catch is CancellationError {
            // Expected: cancellation propagated out of Task.sleep.
        }
    }
}
