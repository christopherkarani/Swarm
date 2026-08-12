import Foundation

extension Workflow {
    /// Runs `operation`, racing it against `timeoutDuration` when configured.
    ///
    /// Uses `Task.detached` so a MainActor caller cannot deadlock the
    /// continuation (an unstructured `Task {}` would be scheduled on MainActor
    /// and never run). Detached tasks drop `@TaskLocal` values, so the ambient
    /// `AgentEnvironment` is snapshotted and re-applied inside the worker.
    func executeWithTimeout(
        _ operation: @escaping @Sendable () async throws -> AgentResult
    ) async throws -> AgentResult {
        guard let timeoutDuration else {
            return try await operation()
        }

        let coordinator = WorkflowTimedOperationCoordinator<AgentResult>()
        let priority = Task.currentPriority
        let capturedEnvironment = AgentEnvironmentValues.current
        return try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { continuation in
                    coordinator.install(continuation: continuation)

                    let operationTask = Task.detached(priority: priority) {
                        do {
                            let result = try await AgentEnvironmentValues.$current.withValue(
                                capturedEnvironment
                            ) {
                                try await operation()
                            }
                            coordinator.finish(returning: result)
                        } catch {
                            coordinator.finish(throwing: error)
                        }
                    }
                    coordinator.setOperationTask(operationTask)

                    let timeoutTask = Task.detached(priority: priority) {
                        do {
                            try await Task.sleep(for: timeoutDuration)
                            operationTask.cancel()
                            coordinator.finish(throwing: AgentError.timeout(duration: timeoutDuration))
                        } catch is CancellationError {
                            return
                        } catch {
                            coordinator.finish(throwing: error)
                        }
                    }
                    coordinator.setTimeoutTask(timeoutTask)
                }
            },
            onCancel: {
                coordinator.cancelPending(with: CancellationError())
            }
        )
    }
}

private final class WorkflowTimedOperationCoordinator<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var completed = false

    func install(continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func setOperationTask(_ task: Task<Void, Never>) {
        lock.lock()
        operationTask = task
        lock.unlock()
    }

    func setTimeoutTask(_ task: Task<Void, Never>) {
        lock.lock()
        timeoutTask = task
        lock.unlock()
    }

    func finish(returning value: T) {
        complete { continuation in
            continuation.resume(returning: value)
        }
    }

    func finish(throwing error: Error) {
        complete { continuation in
            continuation.resume(throwing: error)
        }
    }

    func cancelPending(with error: Error) {
        let pendingState = takePendingState()
        pendingState.operationTask?.cancel()
        pendingState.timeoutTask?.cancel()
        pendingState.continuation?.resume(throwing: error)
    }

    private func complete(_ resume: (CheckedContinuation<T, Error>) -> Void) {
        let pendingState = takePendingState()
        pendingState.operationTask?.cancel()
        pendingState.timeoutTask?.cancel()
        guard let continuation = pendingState.continuation else { return }
        resume(continuation)
    }

    private func takePendingState() -> (
        continuation: CheckedContinuation<T, Error>?,
        operationTask: Task<Void, Never>?,
        timeoutTask: Task<Void, Never>?
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard completed == false else {
            return (nil, nil, nil)
        }

        completed = true
        let pendingContinuation = continuation
        let pendingOperationTask = operationTask
        let pendingTimeoutTask = timeoutTask
        continuation = nil
        operationTask = nil
        timeoutTask = nil
        return (pendingContinuation, pendingOperationTask, pendingTimeoutTask)
    }
}
