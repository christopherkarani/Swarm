// HandoffPreparation.swift
// Swarm Framework
//
// Pure handoff request construction. `when` / `onTransfer` stay in the shell.

import Foundation

/// Builds the values the tool-loop and ``HandoffCoordinator`` share before
/// executing a handoff: last-user lookup, request, filtered context, and
/// history projection.
///
/// Input-string policy remains ``AgentTurnKernel/handoffInput(lastUserText:reason:)``.
enum HandoffPreparation: Sendable {
    /// Prepared request plus the context / history projection the shell applies.
    struct Prepared: Sendable {
        var request: HandoffRequest
        var allowedContext: [String: SendableValue]
        var historyProjection: HandoffHistoryApplication.Projection
        var nestsSession: Bool
    }

    /// Last `.user` content in `conversation`, if any.
    static func lastUserText(from conversation: [AgentTurnTranscript.Message]) -> String? {
        guard let lastUser = conversation.last(where: {
            if case .user = $0 { return true }
            return false
        }) else {
            return nil
        }
        if case let .user(content) = lastUser {
            return content
        }
        return nil
    }

    /// Builds a ``HandoffRequest`` from already-transformed input data.
    ///
    /// Non-empty `transformed.input` is kept. An empty input falls back to
    /// ``AgentTurnKernel/handoffInput(lastUserText:reason:)``. Context is
    /// `transformed.context` merged with `transformed.metadata` (metadata wins).
    static func makeRequest(
        sourceAgentName: String,
        targetAgentName: String,
        lastUserText: String?,
        reason: String,
        transformed: HandoffInputData
    ) -> HandoffRequest {
        let input = transformed.input.isEmpty
            ? AgentTurnKernel.handoffInput(lastUserText: lastUserText, reason: reason)
            : transformed.input
        let context = transformed.context.merging(transformed.metadata) { _, new in new }
        return HandoffRequest(
            sourceAgentName: sourceAgentName,
            targetAgentName: targetAgentName,
            input: input,
            reason: reason.isEmpty ? nil : reason,
            context: context
        )
    }

    /// Applies history metadata, builds the request, and filters reserved keys.
    static func prepare(
        sourceAgentName: String,
        targetAgentName: String,
        lastUserText: String?,
        reason: String,
        transformed: HandoffInputData,
        history: HandoffHistory,
        conversation: [AgentTurnTranscript.Message],
        skippingToolCallID: String?
    ) -> Prepared {
        let historyProjection = HandoffHistoryApplication.apply(
            history,
            conversation: conversation,
            skippingToolCallID: skippingToolCallID
        )
        var annotated = transformed
        for (key, value) in historyProjection.metadata {
            annotated.metadata[key] = value
        }
        let request = makeRequest(
            sourceAgentName: sourceAgentName,
            targetAgentName: targetAgentName,
            lastUserText: lastUserText,
            reason: reason,
            transformed: annotated
        )
        return Prepared(
            request: request,
            allowedContext: HandoffContextFilter.allowedValues(request.context),
            historyProjection: historyProjection,
            nestsSession: history.nestsHistory
        )
    }
}
