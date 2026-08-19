import Foundation

/// Executes one Swarm tool by name during a provider-owned tool loop.
///
/// Agent supplies this at the ``InferenceProvider`` tool-calling call.
/// Capture adapters ignore it. An adapter constructed to own the loop
/// requires it and throws ``AgentError/providerOwnedToolLoopRequiresExecutor``
/// when it is missing.
public struct ToolCallExecutor: Sendable {
    private let body: @Sendable (String, [String: SendableValue]) async throws -> SendableValue

    /// Creates an executor that runs `execute` for each tool the adapter invokes.
    ///
    /// - Parameter execute: Tool name and arguments in; tool output out.
    public init(
        _ execute: @escaping @Sendable (
            _ name: String,
            _ arguments: [String: SendableValue]
        ) async throws -> SendableValue
    ) {
        self.body = execute
    }

    /// Runs the named tool and returns its output.
    ///
    /// - Parameters:
    ///   - name: The tool name advertised on the call's schema list.
    ///   - arguments: Parsed tool arguments.
    /// - Returns: The tool output.
    /// - Throws: Cancellation when the run has timed out or been cancelled,
    ///   or the underlying tool error.
    public func executeTool(
        named name: String,
        arguments: [String: SendableValue]
    ) async throws -> SendableValue {
        try await body(name, arguments)
    }
}
