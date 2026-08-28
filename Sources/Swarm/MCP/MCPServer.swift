// MCPServer.swift
// Swarm Framework
//
// Protocol defining the interface for Model Context Protocol (MCP) server connections.

import Foundation

// MARK: - MCPServerConnection

/// A client-side connection to a Model Context Protocol (MCP) server.
///
/// `MCPServerConnection` is the interface Swarm uses to talk to a remote MCP
/// process or HTTP endpoint. Implementations include ``HTTPMCPServer`` and
/// ``StdioMCPServer``. The historical name `MCPServer` was easy to confuse
/// with an actual server; it remains available as a deprecated typealias.
///
/// The protocol follows a lifecycle pattern where connections must be
/// initialized before use and properly closed when no longer needed.
///
/// ## Server Lifecycle
///
/// MCP servers follow a strict lifecycle:
///
/// 1. **Create**: Instantiate the server with connection configuration
/// 2. **Initialize**: Call `initialize()` to establish the connection and negotiate capabilities
/// 3. **Use**: Call `listTools()`, `callTool()`, `listResources()`, `readResource()` as needed
/// 4. **Close**: Call `close()` to gracefully shut down the connection
///
/// ```
/// Create -> Initialize -> Use (Tools/Resources) -> Close
/// ```
///
/// ## Example Usage
///
/// The following example demonstrates connecting to an HTTP-based MCP server,
/// discovering available tools, and executing a tool:
///
/// ```swift
/// // Create an HTTP MCP server connection
/// let server = try HTTPMCPServer(
///     url: URL(string: "http://localhost:8080")!,
///     name: "filesystem-server"
/// )
///
/// do {
///     // Initialize the connection and get capabilities
///     let capabilities = try await server.initialize()
///     print("Server capabilities: \(capabilities)")
///
///     // Discover available tools
///     if capabilities.tools {
///         let tools = try await server.listTools()
///         print("Available tools:")
///         for tool in tools {
///             print("  - \(tool.name): \(tool.description)")
///         }
///
///         // Call a tool
///         let result = try await server.callTool(
///             name: "read_file",
///             arguments: ["path": .string("/path/to/file.txt")]
///         )
///         print("Tool result: \(result)")
///     }
///
///     // Access resources if supported
///     if capabilities.resources {
///         let resources = try await server.listResources()
///         for resource in resources {
///             let content = try await server.readResource(uri: resource.uri)
///             print("Resource \(resource.name): \(content)")
///         }
///     }
///     try await server.close()
/// } catch {
///     print("MCP error: \(error)")
///     try? await server.close()
/// }
/// ```
///
/// ## Thread Safety
///
/// Implementations of `MCPServerConnection` must be `Sendable` to support concurrent access
/// from multiple async contexts. Use actors or other synchronization primitives
/// to protect mutable state.
///
/// ## Error Handling
///
/// All methods throw `MCPError` for protocol-level errors. Implementations should
/// map transport-specific errors to appropriate `MCPError` instances using the
/// standard JSON-RPC 2.0 error codes.
public protocol MCPServerConnection: Sendable {
    /// The name of this MCP server.
    ///
    /// This name is used for identification and logging purposes.
    /// It should be unique within an agent's set of connected servers.
    var name: String { get }

    /// The capabilities of this MCP server.
    ///
    /// This property reflects the server's capabilities as determined during
    /// initialization. Before `initialize()` is called, this may return
    /// `.empty` or throw an error depending on the implementation.
    ///
    /// Use this property to check what features the server supports before
    /// calling related methods:
    ///
    /// ```swift
    /// let caps = await server.capabilities
    /// if caps.tools {
    ///     let tools = try await server.listTools()
    /// }
    /// ```
    var capabilities: MCPCapabilities { get async }

    // MARK: - Lifecycle Methods

    /// Initializes the connection to the MCP server and negotiates capabilities.
    ///
    /// This method must be called before using any other methods on the server.
    /// It establishes the connection, performs protocol negotiation, and returns
    /// the server's capabilities.
    ///
    /// - Returns: The capabilities supported by this server.
    /// - Throws: `MCPError.internalError` if the connection cannot be established.
    ///           `MCPError.invalidRequest` if the protocol negotiation fails.
    ///
    /// ## Important
    /// - This method should only be called once per server instance.
    /// - Calling other methods before `initialize()` may result in undefined behavior.
    /// - After calling `close()`, you must create a new server instance rather than
    ///   re-initializing the existing one.
    ///
    /// ## Example
    /// ```swift
    /// let server = try HTTPMCPServer(url: url, name: "my-server")
    /// let capabilities = try await server.initialize()
    /// print("Tools supported: \(capabilities.tools)")
    /// ```
    func initialize() async throws -> MCPCapabilities

    /// Closes the connection to the MCP server.
    ///
    /// Call this method when you are finished using the server to release
    /// resources and gracefully terminate the connection.
    ///
    /// - Throws: `MCPError.internalError` if an error occurs during shutdown.
    ///
    /// ## Important
    /// - After calling `close()`, no other methods should be called on this server.
    /// - It is safe to call `close()` multiple times; subsequent calls should be no-ops.
    /// - Failing to call `close()` may leak resources or leave connections open.
    ///
    /// ## Example
    /// ```swift
    /// defer {
    ///     try? await server.close()
    /// }
    /// // Use server...
    /// ```
    func close() async throws

    // MARK: - Tool Methods

    /// Lists all tools available from this MCP server.
    ///
    /// Returns the definitions of all tools that can be called via `callTool()`.
    /// Check `capabilities.tools` before calling this method.
    ///
    /// - Returns: An array of tool schemas describing available tools.
    /// - Throws: `MCPError.methodNotFound` if the server does not support tools.
    ///           `MCPError.internalError` if an error occurs while listing tools.
    ///
    /// ## Example
    /// ```swift
    /// let tools = try await server.listTools()
    /// for tool in tools {
    ///     print("\(tool.name): \(tool.description)")
    ///     for param in tool.parameters {
    ///         print("  - \(param.name) (\(param.type)): \(param.description)")
    ///     }
    /// }
    /// ```
    func listTools() async throws -> [ToolSchema]

    /// Calls a tool on the MCP server with the specified arguments.
    ///
    /// Executes the named tool with the provided arguments and returns the result.
    /// The tool must exist in the list returned by `listTools()`.
    ///
    /// Built-in transports unwrap MCP `content` blocks by default (a single
    /// text block becomes a `.string`). Use ``HTTPMCPServer/callToolRaw(name:arguments:)``
    /// or ``StdioMCPServer/callToolRaw(name:arguments:)`` for the raw envelope.
    /// An empty tool name throws ``MCPError/invalidParams(_:)`` instead of
    /// trapping.
    ///
    /// - Parameters:
    ///   - name: The name of the tool to call, as returned by `listTools()`.
    ///   - arguments: A dictionary of argument names to values. The arguments must
    ///                match the tool's parameter definitions.
    ///
    /// - Returns: The unwrapped tool result as a `SendableValue`.
    ///
    /// - Throws: `MCPError.methodNotFound` if the tool does not exist.
    ///           `MCPError.invalidParams` if the arguments are invalid or missing.
    ///           `MCPError.internalError` if the tool execution fails.
    ///
    /// ## Example
    /// ```swift
    /// let result = try await server.callTool(
    ///     name: "search",
    ///     arguments: [
    ///         "query": .string("swift concurrency"),
    ///         "limit": .int(10)
    ///     ]
    /// )
    ///
    /// if let items = result.arrayValue {
    ///     for item in items {
    ///         print(item)
    ///     }
    /// }
    /// ```
    func callTool(name: String, arguments: [String: SendableValue]) async throws -> SendableValue

    // MARK: - Resource Methods

    /// Lists all resources available from this MCP server.
    ///
    /// Returns metadata about all resources that can be read via `readResource()`.
    /// Check `capabilities.resources` before calling this method.
    ///
    /// - Returns: An array of resource metadata objects.
    /// - Throws: `MCPError.methodNotFound` if the server does not support resources.
    ///           `MCPError.internalError` if an error occurs while listing resources.
    ///
    /// ## Example
    /// ```swift
    /// let resources = try await server.listResources()
    /// for resource in resources {
    ///     print("\(resource.name) (\(resource.uri))")
    ///     if let description = resource.description {
    ///         print("  \(description)")
    ///     }
    /// }
    /// ```
    func listResources() async throws -> [MCPResource]

    /// Reads the content of a resource from the MCP server.
    ///
    /// Retrieves the content of the specified resource. The resource must exist
    /// in the list returned by `listResources()`.
    ///
    /// - Parameter uri: The URI of the resource to read, as returned by `listResources()`.
    ///
    /// - Returns: The content of the resource, which may be text or binary data.
    ///
    /// - Throws: `MCPError.methodNotFound` if the resource does not exist.
    ///           `MCPError.invalidParams` if the URI is malformed.
    ///           `MCPError.internalError` if reading the resource fails.
    ///
    /// ## Example
    /// ```swift
    /// let content = try await server.readResource(uri: "file:///config.json")
    ///
    /// if let text = content.text {
    ///     print("Config contents: \(text)")
    /// } else if let blob = content.blob {
    ///     // Decode Base64 binary data
    ///     let data = Data(base64Encoded: blob)
    /// }
    /// ```
    func readResource(uri: String) async throws -> MCPResourceContent
}

// MARK: - MCPServerConnection Default Implementations

public extension MCPServerConnection {
    /// Checks whether tools are supported and throws if not.
    ///
    /// Helper method to validate tool capability before operations.
    ///
    /// - Throws: `MCPError.methodNotFound` if tools are not supported.
    func requireToolsCapability() async throws {
        let caps = await capabilities
        guard caps.tools else {
            throw MCPError.methodNotFound("tools/list - server does not support tools")
        }
    }

    /// Checks whether resources are supported and throws if not.
    ///
    /// Helper method to validate resource capability before operations.
    ///
    /// - Throws: `MCPError.methodNotFound` if resources are not supported.
    func requireResourcesCapability() async throws {
        let caps = await capabilities
        guard caps.resources else {
            throw MCPError.methodNotFound("resources/list - server does not support resources")
        }
    }
}

/// Deprecated name for ``MCPServerConnection``.
///
/// The historical `MCPServer` name described a *client* connection and was
/// easy to confuse with an MCP server process. New code should conform to
/// and refer to ``MCPServerConnection``.
@available(*, deprecated, renamed: "MCPServerConnection")
public typealias MCPServer = MCPServerConnection
