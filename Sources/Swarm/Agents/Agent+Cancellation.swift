// Agent+Cancellation.swift
// Swarm Framework
//
// Extracted from Agent.swift. Effects stay on Agent behind AgentTurnKernel;
// collaborators come from the once-per-turn AgentTurnDependencies snapshot.

import Foundation

extension Agent {
    actor ActiveRunCancellationState {
        private var activeRunID: UUID?
        private var activeTask: Task<InternalRunResult, Error>?

        func begin(runID: UUID, task: Task<InternalRunResult, Error>) {
            activeRunID = runID
            activeTask = task
        }

        func finish(runID: UUID) {
            guard activeRunID == runID else { return }
            activeRunID = nil
            activeTask = nil
        }

        func cancelCurrent() {
            activeTask?.cancel()
        }
    }

    final class TimedOperationCoordinator<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Error>?
        private var operationTask: Task<Void, Never>?
        private var timeoutTask: Task<Void, Never>?
        private var ownedLoopGate: ProviderOwnedLoopGate?
        private var completed = false

        func setOwnedLoopGate(_ gate: ProviderOwnedLoopGate?) {
            lock.lock()
            defer { lock.unlock() }
            ownedLoopGate = gate
        }

        func install(continuation: CheckedContinuation<T, Error>) {
            lock.lock()
            defer { lock.unlock() }
            self.continuation = continuation
        }

        func setOperationTask(_ task: Task<Void, Never>) {
            lock.lock()
            defer { lock.unlock() }
            operationTask = task
        }

        func setTimeoutTask(_ task: Task<Void, Never>) {
            lock.lock()
            defer { lock.unlock() }
            timeoutTask = task
        }

        func finish(returning value: T) {
            complete(deactivateOwnedLoop: false) { continuation in
                continuation.resume(returning: value)
            }
        }

        func finish(throwing error: Error) {
            complete(deactivateOwnedLoop: Self.shouldDeactivateOwnedLoop(for: error)) { continuation in
                continuation.resume(throwing: error)
            }
        }

        func cancelPending(with error: Error) {
            let pendingState = takePendingState()
            if Self.shouldDeactivateOwnedLoop(for: error) {
                pendingState.ownedLoopGate?.deactivate()
            }
            pendingState.operationTask?.cancel()
            pendingState.timeoutTask?.cancel()
            pendingState.continuation?.resume(throwing: error)
        }

        private func complete(
            deactivateOwnedLoop: Bool,
            _ resume: (CheckedContinuation<T, Error>) -> Void
        ) {
            let pendingState = takePendingState()
            if deactivateOwnedLoop {
                pendingState.ownedLoopGate?.deactivate()
            }
            pendingState.operationTask?.cancel()
            pendingState.timeoutTask?.cancel()
            guard let continuation = pendingState.continuation else { return }
            resume(continuation)
        }

        private static func shouldDeactivateOwnedLoop(for error: Error) -> Bool {
            if error is CancellationError {
                return true
            }
            if case .timeout = error as? AgentError {
                return true
            }
            return false
        }

        private func takePendingState() -> (
            continuation: CheckedContinuation<T, Error>?,
            operationTask: Task<Void, Never>?,
            timeoutTask: Task<Void, Never>?,
            ownedLoopGate: ProviderOwnedLoopGate?
        ) {
            lock.lock()
            defer { lock.unlock() }

            guard completed == false else {
                return (nil, nil, nil, nil)
            }

            completed = true
            let pendingContinuation = continuation
            let pendingOperationTask = operationTask
            let pendingTimeoutTask = timeoutTask
            let pendingGate = ownedLoopGate
            continuation = nil
            operationTask = nil
            timeoutTask = nil
            ownedLoopGate = nil
            return (pendingContinuation, pendingOperationTask, pendingTimeoutTask, pendingGate)
        }
    }

    /// Cancels any ongoing execution.
    ///
    public func cancel() async {
        await cancellationState.cancelCurrent()
    }

    /// Checks for cancellation and timeout conditions.
    func checkCancellationAndTimeout(startTime: ContinuousClock.Instant) throws {
        // Use Task.checkCancellation() for reliable cancellation detection
        // This is the standard Swift concurrency pattern
        try Task.checkCancellation()

        let elapsed = ContinuousClock.now - startTime
        if elapsed > configuration.timeout {
            throw AgentError.timeout(duration: configuration.timeout)
        }
    }

    func executeWithinRemainingTimeout<T: Sendable>(
        startTime: ContinuousClock.Instant,
        executionGate: ProviderOwnedLoopGate? = nil,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try Task.checkCancellation()

        let remaining = configuration.timeout - (ContinuousClock.now - startTime)
        if remaining <= .zero {
            throw AgentError.timeout(duration: configuration.timeout)
        }

        let coordinator = TimedOperationCoordinator<T>()
        coordinator.setOwnedLoopGate(executionGate)

        return try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                    coordinator.install(continuation: continuation)

                    let operationTask = Task {
                        do {
                            coordinator.finish(returning: try await operation())
                        } catch {
                            coordinator.finish(throwing: error)
                        }
                    }
                    coordinator.setOperationTask(operationTask)

                    let timeoutTask = Task { [timeout = configuration.timeout, remaining] in
                        do {
                            try await Task.sleep(for: remaining)
                            operationTask.cancel()
                            coordinator.finish(throwing: AgentError.timeout(duration: timeout))
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

    func normalizeCancellation(_ error: Error) -> Error {
        if error is CancellationError {
            return AgentError.cancelled
        }
        if let agentError = error as? AgentError, agentError == .cancelled {
            return agentError
        }
        return error
    }

    func fallbackDiagnosticMessage(for error: Error) -> String {
        let described = String(describing: error)
        if described != String(describing: type(of: error)) {
            return described
        }

        let localized = error.localizedDescription
        if !localized.isEmpty {
            return localized
        }

        return String(describing: type(of: error))
    }
}
