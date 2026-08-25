// TimeoutRaceSettlementHookTests.swift
// Swarm Framework
//
// Deterministic tests for the `onSettle` hook added to the shared settlement
// primitive (W3-T1): replayed pre-install outcomes run the hook, the hook
// observes the exact winning outcome exactly once, and the timeout path runs
// through the SwarmClock seam. All timing is driven by fake clocks or
// explicit settlement — no assertion depends on real-sleep timing.

import Foundation
import Testing
@_spi(ColonyInternal) @testable import Swarm

// MARK: - Test Helpers

/// Records every `onSettle` invocation behind a lock.
private final class HookRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [Error?] = []

    var calls: [Error?] {
        lock.withLock { outcomes }
    }

    func record(_ error: Error?) {
        lock.withLock {
            outcomes.append(error)
        }
    }
}

/// Clock whose sleep parks until explicitly released, so tests decide which
/// race side settles. Resuming normally lets the timer branch proceed. A
/// worker already cancelled before sleeping refuses to park (it throws),
/// so cleanup cannot strand a late-arriving sleeper; workers parked first are
/// not woken by task cancellation and must be released via ``releaseAll()``.
private final class SettableTestClock: SwarmClock, @unchecked Sendable {
    private let lock = NSLock()
    private var sleepers: [CheckedContinuation<Void, Error>] = []

    func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    func sleep(nanoseconds _: UInt64) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            sleepers.append(continuation)
            lock.unlock()
        }
    }

    /// Wakes every parked sleep, returning normally from each.
    func releaseAll() {
        lock.lock()
        let parked = sleepers
        sleepers.removeAll()
        lock.unlock()
        for continuation in parked {
            continuation.resume()
        }
    }
}

/// Operation body that parks on a manually released continuation, giving
/// tests explicit control over whether the raced operation can settle. A
/// body whose task was already cancelled refuses to park, so draining a
/// losing operation after settlement can never strand a late-arriving parker.
private final class ParkableOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var parked: CheckedContinuation<String, Error>?
    private var pendingRelease: Result<String, Error>?

    /// Resumes the parked body (or arms the release if not yet parked).
    func release(_ result: Result<String, Error>) {
        lock.lock()
        if let continuation = parked {
            parked = nil
            lock.unlock()
            continuation.resume(with: result)
            return
        }
        pendingRelease = result
        lock.unlock()
    }

    func run() async throws -> String {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let release = pendingRelease {
                pendingRelease = nil
                lock.unlock()
                continuation.resume(with: release)
                return
            }
            parked = continuation
            lock.unlock()
        }
    }
}

private struct BoomError: Error {}

// MARK: - Settlement Hook Tests

@Suite("TimeoutRace Settlement Hook")
private struct TimeoutRaceSettlementHookTests {
    @Test("onSettle fires once with nil when the operation succeeds")
    func hookFiresOnceWithNilOnSuccess() async throws {
        let recorder = HookRecorder()
        let clock = SettableTestClock()
        // The timer stays parked until cleanup releases it, so the operation
        // deterministically wins the race.
        defer { clock.releaseAll() }

        let value = try await withTimeoutRace(
            timeout: .seconds(30),
            clock: clock,
            timeoutError: AgentError.timeout(duration: .seconds(30)),
            onSettle: recorder.record
        ) {
            42
        }

        #expect(value == 42)
        #expect(recorder.calls.count == 1)
        #expect(recorder.calls[0] == nil)
    }

    @Test("onSettle receives the exact operation failure")
    func hookReceivesOperationFailure() async throws {
        let recorder = HookRecorder()
        let clock = SettableTestClock()
        defer { clock.releaseAll() }

        do {
            _ = try await withTimeoutRace(
                timeout: .seconds(30),
                clock: clock,
                timeoutError: AgentError.timeout(duration: .seconds(30)),
                onSettle: recorder.record
            ) {
                throw BoomError()
            }
            Issue.record("Expected BoomError to propagate")
        } catch is BoomError {
            // Expected winner.
        }

        #expect(recorder.calls.count == 1)
        #expect(recorder.calls.first is BoomError)
    }

    @Test("onSettle receives CancellationError when the parent task is cancelled")
    func hookReceivesParentCancellation() async throws {
        let recorder = HookRecorder()
        let clock = SettableTestClock()
        let parkable = ParkableOperation()

        // The operation parks, so settlement can only come from the parent's
        // cancellation handler.
        let work = Task<String, Error> {
            try await withTimeoutRace(
                timeout: .seconds(30),
                clock: clock,
                timeoutError: AgentError.timeout(duration: .seconds(30)),
                onSettle: recorder.record
            ) {
                try await parkable.run()
            }
        }
        work.cancel()

        guard case let .failure(error)? = await boundedOutcome(of: work, timeout: .seconds(2)) else {
            work.cancel()
            parkable.release(.success("drain"))
            clock.releaseAll()
            Issue.record("Race did not settle promptly after parent cancellation")
            return
        }
        #expect(error is CancellationError)

        #expect(recorder.calls.count == 1)
        #expect(recorder.calls.first is CancellationError)

        parkable.release(.success("drain"))
        clock.releaseAll()
    }

    @Test("outcome recorded before install replays and still runs onSettle")
    func hookRunsForPreInstallSettlement() async throws {
        let recorder = HookRecorder()
        let race = TimeoutRace<Int>(onSettle: recorder.record)
        race.finish(returning: 7)

        let value = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            race.install(continuation: continuation)
        }

        // AC-101 companion: the replay path applies the hook exactly like a
        // live settlement, with no hang between record and install.
        #expect(value == 7)
        #expect(recorder.calls.count == 1)
        #expect(recorder.calls[0] == nil)
    }

    @Test("timeout wins deterministically on an instant-return fake clock")
    func timeoutWinsOnInstantFakeClock() async throws {
        let recorder = HookRecorder()
        let clock = VirtualClock(startingAtNanoseconds: 0)

        let work = Task<String, Error> {
            try await withTimeoutRace(
                timeout: .milliseconds(5),
                clock: clock,
                timeoutError: AgentError.timeout(duration: .milliseconds(5)),
                onSettle: recorder.record
            ) {
                try await Task.sleep(nanoseconds: 60_000_000_000)
                return "never"
            }
        }

        guard case let .failure(error)? = await boundedOutcome(of: work, timeout: .seconds(2)) else {
            work.cancel()
            Issue.record("Instant-clock timeout did not settle the race promptly")
            return
        }

        guard case .timeout = error as? AgentError else {
            Issue.record("Expected AgentError.timeout, got \(error)")
            return
        }
        #expect(recorder.calls.count == 1)
        #expect(recorder.calls.first is AgentError)
        // REQ-006 pin: the timer suspension went through the SwarmClock seam,
        // not a raw Task.sleep.
        #expect(clock.sleepCount == 1)

        work.cancel()
    }

    @Test("tasks registered against a settled coordinator are cancelled synchronously")
    func lateRegistrationCancelledAfterSettlement() {
        // AC-102 through the class seam, where registration order is fully
        // controlled: both worker slots registered after settlement must be
        // cancelled immediately instead of being stored for a replay that can
        // never happen.
        let race = TimeoutRace<Int>(onSettle: nil)
        race.finish(returning: 1)

        let lateOperation = Task { _ = try? await Task.sleep(nanoseconds: 5_000_000_000) }
        race.setOperationTask(lateOperation)
        let lateTimer = Task { _ = try? await Task.sleep(nanoseconds: 5_000_000_000) }
        race.setTimeoutTask(lateTimer)

        #expect(lateOperation.isCancelled)
        #expect(lateTimer.isCancelled)
    }
}

/// Awaits a task result with a watchdog bound so regressions surface as fast
/// failures instead of hangs; the bound never decides a passing outcome.
private func boundedOutcome<T: Sendable>(
    of task: Task<T, Error>,
    timeout: Duration
) async -> Result<T, Error>? {
    await withTaskGroup(of: Result<T, Error>?.self) { group in
        group.addTask {
            do {
                return .success(try await task.value)
            } catch {
                return .failure(error)
            }
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
