// HandoffHistoryApplication.swift
// Swarm Framework
//
// Pure projection of source-agent conversation history into a handoff.

import Foundation

/// Applies a ``HandoffHistory`` strategy to a source conversation.
///
/// `.none` drops the transcript. `.nested` and `.summarized` share the same
/// message projection (skip the triggering tool-call). `.summarized` additionally
/// annotates metadata with the existing mode / maxTokens keys. This does not
/// truncate or call a summarizer.
enum HandoffHistoryApplication: Sendable {
    /// Projected messages plus any history-strategy metadata.
    struct Projection: Sendable, Equatable {
        var messages: [AgentTurnTranscript.Message]
        var metadata: [String: SendableValue]
    }

    /// Projects `conversation` according to `history`.
    ///
    /// - Parameters:
    ///   - history: How prior turns are carried into the handoff.
    ///   - conversation: Source-agent transcript at the handoff site.
    ///   - skippingToolCallID: Tool-call id that triggered the handoff, omitted
    ///     from the nested assistant / tool-result projection.
    static func apply(
        _ history: HandoffHistory,
        conversation: [AgentTurnTranscript.Message],
        skippingToolCallID: String?
    ) -> Projection {
        let messages: [AgentTurnTranscript.Message]
        switch history {
        case .none:
            messages = []
        case .nested, .summarized:
            messages = nestedMessages(from: conversation, skippingToolCallID: skippingToolCallID)
        }

        return Projection(
            messages: messages,
            metadata: history.applyingSummaryMetadata(to: metadataSeed).metadata
        )
    }

    // MARK: Private

    private static let metadataSeed = HandoffInputData(
        sourceAgentName: "",
        targetAgentName: "",
        input: ""
    )

    private static func nestedMessages(
        from conversation: [AgentTurnTranscript.Message],
        skippingToolCallID: String?
    ) -> [AgentTurnTranscript.Message] {
        conversation.compactMap { message in
            switch message {
            case .system, .user:
                return message
            case let .assistant(content, toolCalls):
                let nestedToolCalls = toolCalls.filter { $0.id != skippingToolCallID }
                guard toolCalls.isEmpty || !nestedToolCalls.isEmpty else {
                    return nil
                }
                return .assistant(content, toolCalls: nestedToolCalls)
            case let .toolResult(_, _, toolCallID):
                guard toolCallID != skippingToolCallID else {
                    return nil
                }
                return message
            }
        }
    }
}
