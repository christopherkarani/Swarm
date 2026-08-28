#if SWARM_MCP
import Foundation
import Swarm

/// Tool catalog boundary for exposing Swarm tools over MCP.
public protocol SwarmMCPToolCatalog: Sendable {
    /// Returns the current set of MCP-exposed tool schemas.
    func listTools() async throws -> [ToolSchema]
}

/// Tool execution boundary for serving MCP `tools/call` requests.
public protocol SwarmMCPToolExecutor: Sendable {
    /// Executes a tool call using Swarm as the backend.
    func executeTool(named toolName: String, arguments: [String: SendableValue]) async throws -> SendableValue
}

/// Swarm-native execution outcomes that need deterministic MCP mapping.
public enum SwarmMCPToolExecutionError: Error, Sendable, Equatable {
    /// Execution is paused pending human approval.
    case approvalRequired(
        prompt: String,
        reason: String?,
        metadata: [String: SendableValue]
    )

    /// Execution was rejected by policy or authorization constraints.
    case permissionDenied(
        reason: String,
        metadata: [String: SendableValue]
    )
}

/// Default adapter backed by Swarm's `ToolRegistry`.
public actor SwarmMCPToolRegistryAdapter: SwarmMCPToolCatalog, SwarmMCPToolExecutor {
    private let registry: ToolRegistry

    public init(registry: ToolRegistry) {
        self.registry = registry
    }

    public func listTools() async throws -> [ToolSchema] {
        await registry.schemas
    }

    public func executeTool(named toolName: String, arguments: [String: SendableValue]) async throws -> SendableValue {
        try await registry.execute(toolNamed: toolName, arguments: arguments)
    }
}
#endif
