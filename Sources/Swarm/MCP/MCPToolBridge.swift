// MCPToolBridge.swift
// Swarm Framework
//
// Bridges MCP tools to Swarm Tool protocol.

import Foundation

// MARK: - MCPToolBridge

/// An actor that bridges Model Context Protocol (MCP) tools to Swarm Tool protocol.
///
/// MCPToolBridge provides seamless integration between MCP servers and Swarm
/// by converting MCP tool schemas into native Tool implementations that can be
/// used with agents, registries, and orchestrators.
///
/// ## Usage
///
/// ```swift
/// // Create a bridge for an MCP server
/// let bridge = MCPToolBridge(server: mcpServer)
///
/// // Convert all MCP tools to Swarm tools
/// let tools = try await bridge.bridgeTools()
///
/// // Register with an agent
/// for tool in tools {
///     await agent.register(tool)
/// }
/// ```
///
/// ## Thread Safety
///
/// MCPToolBridge is an actor, providing thread-safe access to the underlying
/// MCP server. All operations are isolated and can be safely called from
/// multiple async contexts.
public actor MCPToolBridge {
    // MARK: Public

    // MARK: - Initialization

    /// Creates a new MCP tool bridge for the given server.
    ///
    /// - Parameter server: The MCP server to bridge tools from.
    public init(server: any MCPServerConnection) {
        self.server = server
    }

    // MARK: - Public Methods

    /// Converts all MCP tools to Swarm tools.
    ///
    /// This method retrieves all tool schemas from the MCP server and
    /// wraps each one in an `MCPBridgedTool` that delegates execution back
    /// to the server.
    ///
    /// - Returns: An array of Tool implementations that delegate to the MCP server.
    /// - Throws: `MCPError.methodNotFound` if the server does not support tools.
    ///           `MCPError.internalError` if listing tools fails.
    ///
    /// ## Example
    /// ```swift
    /// let bridge = MCPToolBridge(server: fileServer)
    /// let tools = try await bridge.bridgeTools()
    ///
    /// for tool in tools {
    ///     print("Bridged tool: \(tool.name)")
    /// }
    /// ```
    public func bridgeTools() async throws -> [any AnyJSONTool] {
        let schemas = try await server.listTools()
        return schemas.map { schema in
            MCPBridgedTool(schema: schema, server: server)
        }
    }

    // MARK: Private

    /// The MCP server providing the tools.
    private let server: any MCPServerConnection
}

// MARK: - MCPBridgedTool

/// A Tool implementation that delegates execution to an MCP server.
///
/// MCPBridgedTool wraps an MCP tool schema and routes all execution
/// calls to the underlying MCP server. This enables MCP tools to be used
/// seamlessly within the Swarm framework.
///
/// ## Thread Safety
///
/// MCPBridgedTool is `Sendable` and can be safely shared across async contexts.
/// The underlying MCP server must also be `Sendable` (as required by the
/// `MCPServerConnection` protocol).
///
/// ### Actor Isolation Contract
///
/// This struct stores an existential reference (`any MCPServerConnection`) to an actor-isolated
/// server. While Swift's type system allows this because `MCPServerConnection` requires `Sendable`
/// conformance, the following guarantees apply:
///
/// - **Execution Serialization**: All calls to `execute()` are automatically serialized
///   by the server's actor isolation, even when invoked concurrently from multiple contexts.
/// - **No Data Races**: The `schema` property is immutable and `Sendable`. The `server`
///   reference is safe because actor methods are inherently thread-safe.
/// - **Concurrent Safety**: Multiple `MCPBridgedTool` instances referencing the same server
///   can safely execute in parallel; the actor ensures request serialization.
///
/// Example of safe concurrent usage:
/// ```swift
/// let tools = try await bridge.bridgeTools()
/// await withTaskGroup(of: SendableValue.self) { group in
///     for tool in tools {
///         group.addTask {
///             try await tool.execute(arguments: ["query": .string("test")])
///         }
///     }
/// }
/// ```
struct MCPBridgedTool: AnyJSONTool, Sendable {
    /// The tool schema from the MCP server.
    let schema: ToolSchema

    /// The MCP server to delegate execution to.
    let server: any MCPServerConnection

    /// Optional display name used when this tool must be disambiguated.
    let displayNameOverride: String?

    /// Original server-side tool name used for execution calls.
    let serverToolName: String

    init(
        schema: ToolSchema,
        server: any MCPServerConnection,
        displayName: String? = nil,
        serverToolName: String? = nil
    ) {
        self.schema = schema
        self.server = server
        displayNameOverride = displayName
        self.serverToolName = serverToolName ?? schema.name
    }

    // MARK: - Tool Protocol

    /// The unique name of the tool.
    var name: String {
        displayNameOverride ?? schema.name
    }

    /// A description of what the tool does.
    var description: String {
        schema.description
    }

    /// The parameters this tool accepts.
    var parameters: [ToolParameter] {
        schema.parameters
    }

    /// Executes the tool by delegating to the MCP server.
    ///
    /// - Parameter arguments: The arguments passed to the tool.
    /// - Returns: The result of the tool execution from the MCP server.
    /// - Throws: `MCPError.methodNotFound` if the tool does not exist on the server.
    ///           `MCPError.invalidParams` if the arguments are invalid.
    ///           `MCPError.internalError` if execution fails.
    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        try await server.callTool(name: serverToolName, arguments: arguments)
    }
}
