// HandoffTool.swift
// Swarm Framework
//
// Handoff as a Tool — place handoffs alongside tools in @ToolBuilderV3.

import Foundation

/// A handoff to another agent, expressed as a Tool.
///
/// Place handoffs alongside tools in the @ToolBuilderV3 closure:
/// ```swift
/// AgentV3("Router") {
///     SearchTool()
///     HandoffV3(specialistAgent)
///     HandoffV3(summarizerAgent)
/// }
/// ```
public struct HandoffV3: ToolV3, Sendable {
    public let name: String
    public let description: String

    /// The target agent to hand off to.
    public let target: AgentV3

    /// History transfer mode.
    public let history: HandoffHistory

    /// Creates a handoff to the target agent.
    ///
    /// - Parameters:
    ///   - target: The agent to hand off to.
    ///   - history: How to transfer conversation history. Default: `.none`.
    public init(_ target: AgentV3, history: HandoffHistory = .none) {
        let snakeName = target.name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
        self.name = "handoff_to_\(snakeName)"
        self.description = "Transfer to \(target.name) agent"
        self.target = target
        self.history = history
    }

    public func call() async throws -> String {
        // The runtime intercepts handoff tool calls before call() is invoked.
        // This is a fallback that should not be reached in normal execution.
        "Handoff to \(target.name)"
    }
}

// MARK: - HandoffHistory

/// How conversation history is transferred during a handoff.
///
/// ```swift
/// HandoffV3(expert, history: .summarized(maxTokens: 500))
/// ```
public enum HandoffHistory: Sendable {
    /// No history transferred.
    case none

    /// Full nested conversation history.
    case nested

    /// LLM-summarized history with a token budget.
    case summarized(maxTokens: Int = 1000)
}
