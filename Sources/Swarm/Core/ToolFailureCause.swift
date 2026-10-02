// ToolFailureCause.swift
// Swarm Framework
//
// Single factory for turn-path tool-failure errors.

import Foundation

/// Maps turn-path tool failures to `AgentError` with a preserved cause.
///
/// Scope: the agent turn path only — the call sites that wrap a caught tool
/// error (or synthesize a message-only failure) while executing a turn:
/// `AgentTurnRunner` (single-call and batch throws), `ToolExecutionEngine`,
/// `ToolRegistry.execute`, `ToolExecutionResult.from`, and the event-stream
/// observer. These sites previously constructed
/// ``AgentError/toolFailure(toolName:message:cause:)`` inline; this factory
/// is their single mapping point so message derivation and cause preservation
/// stay consistent.
///
/// Out of scope — these origins construct `AgentError` directly and must not
/// route through this factory:
/// - Inference-path provider mapping (``AgentErrorCauseFactory`` plus the
///   Foundation Models / OpenAI-compatible cause tables).
/// - Individual tool implementations synthesizing their own failures
///   (for example web search and built-in tools).
/// - Typed tool bridging (`AnyJSONToolAdapter`) and legacy parallel-executor
///   composite errors (`ParallelToolExecutor`).
/// - Provider-owned tool loops (`FoundationModelsNativeSession`) and the
///   internal graph runtime (`GraphAgent`).
///
/// The factory always wraps: an `AgentError` passed to
/// ``wrapped(toolName:error:)`` is preserved as `cause` inside a new
/// `toolFailure`. The engine seam relies on this nesting to keep both the
/// registry mapping and the original error reachable.
///
/// Cancellation is deliberately not special-cased here: turn-path failures
/// identify the failing tool, so the cause is always preserved, and direct
/// `ToolRegistry` callers already see raw cancellation via its pre-wrap
/// rethrow. Cooperative cancellation on the inference path maps to
/// `.cancelled` in ``AgentErrorCauseFactory`` instead.
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
