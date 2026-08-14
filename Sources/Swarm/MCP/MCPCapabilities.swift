// MCPCapabilities.swift
// Swarm Framework
//
// MCP server capability declarations.

import Foundation

// MARK: - MCPCapabilities

/// Capabilities supported by an MCP server.
///
/// MCPCapabilities describes what features an MCP server supports,
/// enabling clients to understand available functionality and
/// configure their behavior accordingly.
///
/// Example:
/// ```swift
/// let capabilities = MCPCapabilities(
///     tools: true,
///     resources: true,
///     prompts: false,
///     sampling: false
/// )
///
/// if capabilities.tools {
///     // Server supports tool discovery and execution
/// }
/// ```
public struct MCPCapabilities: Sendable, Codable, Equatable {
    /// Empty capabilities with all features disabled.
    ///
    /// Use this as a baseline or when no capabilities are available.
    public static let empty = MCPCapabilities()

    /// Whether the server supports tool discovery and execution.
    ///
    /// When `true`, the server can list available tools and execute
    /// tool calls requested by the client.
    public let tools: Bool

    /// Whether the server supports resource access.
    ///
    /// When `true`, the server can provide access to resources
    /// such as files, databases, or external data sources.
    public let resources: Bool

    /// Whether the remote server advertised prompt templates.
    ///
    /// Swarm's client does not implement `prompts/list` or `prompts/get`.
    /// Connection types always report `false` so this flag cannot be used
    /// as a feature-detection signal for Swarm APIs. The stored property
    /// remains for source compatibility.
    public let prompts: Bool

    /// Whether the remote server advertised sampling.
    ///
    /// Swarm's client does not implement sampling (a server-initiated
    /// request that needs an inference provider). Connection types always
    /// report `false`. The stored property remains for source compatibility.
    public let sampling: Bool

    // MARK: - Initialization

    /// Creates MCP capabilities with the specified features.
    ///
    /// - Parameters:
    ///   - tools: Whether tool discovery and execution is supported. Default: `false`
    ///   - resources: Whether resource access is supported. Default: `false`
    ///   - prompts: Unused by Swarm's client. Default: `false`. Prefer omitting
    ///     this argument; the value is retained for source compatibility.
    ///   - sampling: Unused by Swarm's client. Default: `false`. Prefer omitting
    ///     this argument; the value is retained for source compatibility.
    public init(
        tools: Bool = false,
        resources: Bool = false,
        prompts: Bool = false,
        sampling: Bool = false
    ) {
        self.tools = tools
        self.resources = resources
        self.prompts = prompts
        self.sampling = sampling
    }
}

// MARK: CustomStringConvertible

extension MCPCapabilities: CustomStringConvertible {
    public var description: String {
        """
        MCPCapabilities(
            tools: \(tools),
            resources: \(resources),
            prompts: \(prompts),
            sampling: \(sampling)
        )
        """
    }
}
