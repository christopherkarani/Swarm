import Foundation

extension Workflow {
    /// Runs `operation`, racing it against `timeoutDuration` when configured.
    ///
    /// The race spawns detached tasks so a MainActor caller cannot deadlock
    /// the continuation (an unstructured inherited-context task would be
    /// scheduled on MainActor and never run). Detached tasks drop
    /// `@TaskLocal` values, so the ambient `AgentEnvironment` is snapshotted
    /// and re-applied inside the worker closure.
    func executeWithTimeout(
        _ operation: @escaping @Sendable () async throws -> AgentResult
    ) async throws -> AgentResult {
        guard let timeoutDuration else {
            return try await operation()
        }

        let capturedEnvironment = AgentEnvironmentValues.current
        return try await withTimeoutRace(
            timeout: timeoutDuration,
            priority: Task.currentPriority,
            timeoutError: AgentError.timeout(duration: timeoutDuration)
        ) {
            try await AgentEnvironmentValues.$current.withValue(capturedEnvironment) {
                try await operation()
            }
        }
    }
}
