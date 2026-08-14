// MCPProtocolVersion.swift
// Swarm Framework
//
// MCP protocol version identifiers and client-side negotiation.

import Foundation

// MARK: - MCPProtocolVersion

/// Protocol versions understood by Swarm's MCP client.
///
/// MCP versions are date strings (`YYYY-MM-DD`) naming the last
/// backwards-incompatible revision. Swarm speaks the current specification
/// and remains compatible with the original `2024-11-05` revision used by
/// many deployed servers.
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/
public enum MCPProtocolVersion: Sendable {
    /// The original MCP revision (`2024-11-05`).
    public static let legacy = "2024-11-05"

    /// The latest MCP revision Swarm's client requests during initialize.
    public static let current = "2025-11-25"

    /// Every protocol version this client will accept from a server.
    ///
    /// Unknown versions fail loudly — Swarm never silently assumes
    /// compatibility with an unsupported server.
    public static let supported: Set<String> = [
        "2024-11-05",
        "2025-03-26",
        "2025-06-18",
        "2025-11-25"
    ]

    /// Negotiates the session version from the server's initialize result.
    ///
    /// - Parameter serverReported: The `protocolVersion` string returned by
    ///   the server. `nil` or empty is treated as unsupported.
    /// - Returns: The server-reported version when it is in ``supported``.
    /// - Throws: ``MCPError/unsupportedProtocolVersion(_:)`` when the server
    ///   speaks a version Swarm does not implement.
    public static func negotiate(serverReported: String?) throws -> String {
        guard let serverReported, !serverReported.isEmpty else {
            throw MCPError.unsupportedProtocolVersion(serverReported ?? "")
        }
        guard supported.contains(serverReported) else {
            throw MCPError.unsupportedProtocolVersion(serverReported)
        }
        return serverReported
    }
}

// MARK: - MCPToolResultStyle

/// How ``MCPServerConnection/callTool(name:arguments:)`` presents a
/// successful `tools/call` result.
public enum MCPToolResultStyle: Sendable, Equatable {
    /// Unwrap MCP content blocks (the default).
    ///
    /// A single `text` content block becomes a `.string`. Multiple blocks
    /// become a `.array` of the original content objects. Results that are
    /// not MCP envelopes are returned unchanged.
    case unwrappedContent

    /// Return the raw `tools/call` result object (`content`, `isError`, …).
    case rawEnvelope
}
