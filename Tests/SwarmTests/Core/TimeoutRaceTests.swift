import Foundation
import Testing
@testable import Swarm

@Suite("TimeoutRace")
struct TimeoutRaceTests {
    @Test("outcome recorded before install resumes the continuation with success")
    func recordedSuccessAppliesOnLateInstall() async throws {
        let race = TimeoutRace<Int>()
        race.finish(returning: 42)

        let value = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            race.install(continuation: continuation)
        }
        #expect(value == 42)
    }

    @Test("outcome recorded before install resumes the continuation with failure")
    func recordedFailureAppliesOnLateInstall() async throws {
        let race = TimeoutRace<Int>()
        race.finish(throwing: CancellationError())

        await #expect(throws: CancellationError.self) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
                race.install(continuation: continuation)
            }
        }
    }

    @Test("tasks registered after settlement are cancelled immediately")
    func lateRegisteredTasksAreCancelled() async {
        let race = TimeoutRace<Int>()
        race.finish(throwing: CancellationError())

        let operationTask = Task { _ = try? await Task.sleep(nanoseconds: 5_000_000_000) }
        race.setOperationTask(operationTask)
        #expect(operationTask.isCancelled)

        let timeoutTask = Task { _ = try? await Task.sleep(nanoseconds: 5_000_000_000) }
        race.setTimeoutTask(timeoutTask)
        #expect(timeoutTask.isCancelled)
    }

    @Test("first settlement wins under concurrent finish attempts")
    func firstOutcomeWins() async throws {
        let race = TimeoutRace<Int>()
        race.finish(returning: 7)
        race.finish(throwing: CancellationError())
        race.finish(returning: 99)

        let value = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            race.install(continuation: continuation)
        }
        #expect(value == 7)
    }

    @Test("withTimeoutRace settles immediately when the surrounding task is already cancelled")
    func alreadyCancelledParentSettlesImmediately() async throws {
        final class SettlementProbe: @unchecked Sendable {
            private let lock = NSLock()
            private var _isSettled = false
            private var _failure: (any Error)?

            var state: (settled: Bool, failure: (any Error)?) {
                lock.lock()
                defer { lock.unlock() }
                return (_isSettled, _failure)
            }

            func settle(failure: (any Error)?) {
                lock.lock()
                _isSettled = true
                _failure = failure
                lock.unlock()
            }
        }

        let probe = SettlementProbe()
        let work = Task<Void, Never> {
            do {
                _ = try await withTimeoutRace(
                    timeout: .seconds(30),
                    timeoutError: AgentError.timeout(duration: .seconds(30))
                ) {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                }
                probe.settle(failure: nil)
            } catch {
                probe.settle(failure: error)
            }
        }
        work.cancel()

        // Bounded wait so a regression in early-settlement cannot hang the suite;
        // without the fix only the 30s timer could settle this race.
        for _ in 0..<100 where !probe.state.settled {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let state = probe.state
        #expect(state.settled, "withTimeoutRace did not settle after parent cancellation")

        work.cancel()
        _ = await work.result

        guard case true = state.settled else { return }
        let failure = state.failure
        #expect(failure is CancellationError, "expected CancellationError, got \(String(describing: failure))")
    }
}
