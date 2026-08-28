// TimeoutRaceSettlementHookTests.swift
// Swarm Framework
//
// Deterministic tests for the `onSettle` hook: replayed pre-install outcomes
// run the hook, the hook observes the exact winning outcome exactly once, and
// the timeout path claims the timeout before cancelling the operation.

import Foundation
import Testing
@_spi(ColonyInternal) @testable import Swarm

private final class HookRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [Error?] = []

    var calls: [Error?] {
        lock.withLock { outcomes }
    }

    func record(_ error: Error?) {
        lock.withLock { outcomes.append(error) }
    }
}

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

private final class ParkableOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var parked: CheckedContinuation<String, Error>?
    private var pendingRelease: Result<String, Error>?

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
private struct MappedCancelled: Error {}

@Suite("TimeoutRace Settlement Hook")
private struct TimeoutRaceSettlementHookTests {
    @Test("onSettle fires once with nil when the operation succeeds")
    func hookFiresOnceWithNilOnSuccess() async throws {
        let recorder = HookRecorder()
        let clock = SettableTestClock()
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
        }

        #expect(recorder.calls.count == 1)
        #expect(recorder.calls.first is BoomError)
    }

    @Test("outcome recorded before install replays and still runs onSettle")
    func hookRunsForPreInstallSettlement() async throws {
        let recorder = HookRecorder()
        let race = TimeoutRace<Int>(onSettle: recorder.record)
        race.finish(returning: 7)

        let value = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            race.install(continuation: continuation)
        }

        #expect(value == 7)
        #expect(recorder.calls.count == 1)
        #expect(recorder.calls[0] == nil)
    }

    @Test("timeout wins on an instant-return fake clock with the timeout payload")
    func timeoutWinsOnInstantFakeClock() async throws {
        let recorder = HookRecorder()
        let clock = VirtualClock(startingAtNanoseconds: 0)
        let parkable = ParkableOperation()

        do {
            _ = try await withTimeoutRace(
                timeout: .milliseconds(5),
                clock: clock,
                timeoutError: AgentError.timeout(duration: .milliseconds(5)),
                onSettle: recorder.record
            ) {
                try await parkable.run()
            }
            Issue.record("Expected timeout")
        } catch let error as AgentError {
            guard case .timeout = error else {
                Issue.record("Expected AgentError.timeout, got \(error)")
                return
            }
        }

        #expect(recorder.calls.count == 1)
        #expect(recorder.calls.first is AgentError)
        if case .timeout = recorder.calls.first as? AgentError {
        } else {
            Issue.record("Expected timeout payload, got \(String(describing: recorder.calls.first))")
        }
        #expect(clock.sleepCount == 1)
        parkable.release(.success("drain"))
    }

    @Test("timeout claim beats a cancellation-mapped operation unwind")
    func timeoutClaimBeatsMappedCancellation() async throws {
        let recorder = HookRecorder()
        let clock = VirtualClock(startingAtNanoseconds: 0)

        do {
            _ = try await withTimeoutRace(
                timeout: .milliseconds(5),
                clock: clock,
                timeoutError: AgentError.timeout(duration: .milliseconds(5)),
                onSettle: recorder.record
            ) {
                try await Task.sleep(nanoseconds: .max)
                return "never"
            }
            Issue.record("Expected timeout")
        } catch let error as AgentError {
            guard case .timeout = error else {
                Issue.record("Expected AgentError.timeout, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected AgentError.timeout, got \(error)")
        }

        #expect(recorder.calls.count == 1)
        if case .timeout = recorder.calls.first as? AgentError {
        } else {
            Issue.record("Timeout must win the settle payload, got \(String(describing: recorder.calls.first))")
        }
    }

    @Test("tasks registered against a settled coordinator are cancelled synchronously")
    func lateRegistrationCancelledAfterSettlement() {
        let race = TimeoutRace<Int>(onSettle: nil)
        race.finish(returning: 1)

        let lateOperation = Task<Void, Never> {
            _ = try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        race.setOperationTask(lateOperation)
        let lateTimer = Task<Void, Never> {
            _ = try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        race.setTimeoutTask(lateTimer)

        #expect(lateOperation.isCancelled)
        #expect(lateTimer.isCancelled)
    }
}
