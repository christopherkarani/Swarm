// TimeoutRace.swift
// Swarm Framework
//
// Shared completion machinery for async operations raced against a timeout,
// consolidating the per-site coordinator/race classes that previously lived
// in GuardrailRunner and Workflow+Timeout and in Agent's
// TimedOperationCoordinator (whose owned-loop-gate deactivation now rides on
// the `onSettle` hook). One timeout site deliberately keeps its own
// machinery: StreamOperations.timeout(after:) is a stream-lifetime operator
// rather than a one-shot race.

import Foundation

/// One-shot completion coordinator for an asynchronous operation racing a
/// timeout timer.
///
/// The wrapped checked continuation is resumed exactly once: whichever side
/// finishes first records the outcome, both worker tasks are cancelled, and
/// any task registered after settlement is cancelled immediately. An outcome
/// recorded before `install(continuation:)` runs (e.g. a cancellation handler
/// firing in that window) is applied as soon as the continuation arrives, so
/// no registration order can leak or strand it.
///
/// `onSettle` fires exactly once per race — at settlement time, before the
/// worker tasks are cancelled and the continuation is resumed — with `nil`
/// for success or the settled error. It runs even when settlement precedes
/// continuation installation.
final class TimeoutRace<T: Sendable>: @unchecked Sendable {
    private enum Outcome {
        case success(T)
        case failure(Error)
    }

    private let lock = NSLock()
    private let onSettle: (@Sendable (Error?) -> Void)?
    private var continuation: CheckedContinuation<T, Error>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var outcome: Outcome?

    init(onSettle: (@Sendable (Error?) -> Void)? = nil) {
        self.onSettle = onSettle
    }

    func install(continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
        resumeRecordedOutcomeIfReady()
    }

    func setOperationTask(_ task: Task<Void, Never>) {
        lock.lock()
        let settledAlready = outcome != nil
        if !settledAlready {
            operationTask = task
        }
        lock.unlock()

        if settledAlready {
            task.cancel()
        }
    }

    func setTimeoutTask(_ task: Task<Void, Never>) {
        lock.lock()
        let settledAlready = outcome != nil
        if !settledAlready {
            timeoutTask = task
        }
        lock.unlock()

        if settledAlready {
            task.cancel()
        }
    }

    func finish(returning value: T) {
        record(.success(value))
    }

    func finish(throwing error: Error) {
        record(.failure(error))
    }

    private func record(_ newOutcome: Outcome) {
        lock.lock()
        guard outcome == nil else {
            lock.unlock()
            return
        }
        outcome = newOutcome
        let pendingContinuation = continuation
        let pendingOperationTask = operationTask
        let pendingTimeoutTask = timeoutTask
        continuation = nil
        operationTask = nil
        timeoutTask = nil
        lock.unlock()

        switch newOutcome {
        case .success:
            onSettle?(nil)
        case let .failure(error):
            onSettle?(error)
        }
        pendingOperationTask?.cancel()
        pendingTimeoutTask?.cancel()
        if let pendingContinuation {
            resume(newOutcome, onto: pendingContinuation)
        }
    }

    private func resumeRecordedOutcomeIfReady() {
        lock.lock()
        let recorded = outcome
        let pendingContinuation = continuation
        if recorded != nil {
            continuation = nil
        }
        lock.unlock()

        if let recorded, let pendingContinuation {
            resume(recorded, onto: pendingContinuation)
        }
    }

    private func resume(_ outcome: Outcome, onto continuation: CheckedContinuation<T, Error>) {
        switch outcome {
        case let .success(value):
            continuation.resume(returning: value)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}

/// Runs `operation`, racing it against `timeout` measured on `clock`.
///
/// Whichever finishes first wins; the loser task is cancelled and the result
/// resumes exactly once. When `cancelsOnParentCancellation` is set (the
/// default), cancelling the surrounding task settles the race immediately
/// with `CancellationError`; when cleared, parent cancellation does not
/// interrupt the park, matching sites whose callers own cancellation
/// handling. A non-nil `priority` spawns both worker tasks detached at that
/// priority so actor-context work cannot deadlock the race; `nil` keeps the
/// inherited-context `Task {}` flavor.
///
/// Sleep failures other than cancellation surface through the continuation;
/// `LiveSwarmClock` suspension only ever throws `CancellationError`.
///
/// `onSettle`, when provided, fires exactly once with the settled outcome —
/// `nil` for success or the winning error — before the losing task is
/// cancelled and the continuation resumes.
func withTimeoutRace<T: Sendable>(
    timeout: Duration,
    clock: any SwarmClock = LiveSwarmClock.live,
    cancelsOnParentCancellation: Bool = true,
    priority: TaskPriority? = nil,
    timeoutError: @autoclosure @escaping @Sendable () -> Error,
    onSettle: (@Sendable (_ error: Error?) -> Void)? = nil,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let race = TimeoutRace<T>(onSettle: onSettle)

    func run() async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            race.install(continuation: continuation)

            func spawn(_ work: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
                if let priority {
                    return Task.detached(priority: priority, operation: work)
                }
                return Task(operation: work)
            }

            let operationTask = spawn {
                do {
                    race.finish(returning: try await operation())
                } catch {
                    race.finish(throwing: error)
                }
            }
            race.setOperationTask(operationTask)

            let timeoutTask = spawn {
                do {
                    try await clock.sleep(nanoseconds: timeout.swarmNanoseconds)
                } catch is CancellationError {
                    return
                } catch {
                    race.finish(throwing: error)
                    return
                }
                // Claim the timeout outcome first so a concurrently unwinding
                // operation cannot win with CancellationError and skip gate
                // deactivation. record() cancels the losing operation task.
                race.finish(throwing: timeoutError())
            }
            race.setTimeoutTask(timeoutTask)
        }
    }

    guard cancelsOnParentCancellation else {
        return try await run()
    }

    return try await withTaskCancellationHandler(
        operation: {
            try await run()
        },
        onCancel: {
            race.finish(throwing: CancellationError())
        }
    )
}
