// ToolFailureCause.swift
// Swarm Framework
//
// Single factory for turn-path tool-failure errors.

import Foundation

/// Maps turn-path tool failures to `AgentError` with a preserved cause.
///
/// The turn loop, tool engine, tool registry, event stream, and result
/// mapping previously constructed ``AgentError/toolFailure(toolName:message:cause:)``
/// inline at each site. This factory is the single mapping point so message
/// derivation and cause preservation stay consistent.
///
/// The factory always wraps: an `AgentError` passed to
/// ``wrapped(toolName:error:)`` is preserved as `cause` inside a new
/// `toolFailure`. The engine seam relies on this nesting to keep both the
/// registry mapping and the original error reachable.
enum ToolFailureCause: Sendable {
    /// Wraps a caught error, keeping the instance reachable as `cause`.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool that failed.
    ///   - error: The caught error; its localized description becomes the message.
    static func wrapped(toolName: String, error: any Error) -> AgentError {
        .toolFailure(toolName: toolName, message: error.localizedDescription, cause: error)
    }

    /// Wraps a caught error under an explicit message, keeping the instance reachable as `cause`.
    ///
    /// Use this when the failure message is already fixed (for example, the
    /// transcript text derived from an Engine outcome) and must not be
    /// re-derived from the error.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool that failed.
    ///   - message: Human-readable summary of the failure.
    ///   - error: The caught error, preserved as `cause`.
    static func wrapped(toolName: String, message: String, error: any Error) -> AgentError {
        .toolFailure(toolName: toolName, message: message, cause: error)
    }

    /// Synthesizes a message-only failure when no error instance exists.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool that failed.
    ///   - message: Human-readable summary of the failure.
    static func messageOnly(toolName: String, message: String) -> AgentError {
        .toolFailure(toolName: toolName, message: message, cause: nil)
    }
}
