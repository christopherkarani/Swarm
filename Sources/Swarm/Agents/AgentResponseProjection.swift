// AgentResponseProjection.swift
// Swarm Framework
//
// Pure AgentResult → AgentResponse join. Duplicate tool-call ids last-win.

import Foundation

/// Builds ``AgentResponse`` from a finished ``AgentResult``.
///
/// Tool results are joined to calls by ``ToolCall/id``. When two calls share
/// an id, the later call wins — the same last-wins `reduce(into:)` used by
/// ``AgentRuntime/runWithResponse(_:session:observer:)``. This never traps on
/// duplicate keys.
enum AgentResponseProjection: Sendable {
    /// Projects `result` into a response with the supplied identity.
    static func make(from result: AgentResult, responseID: String, agentName: String) -> AgentResponse {
        let toolCallsById = result.toolCalls.reduce(into: [UUID: ToolCall]()) { dict, call in
            dict[call.id] = call
        }

        let toolCallRecords: [ToolCallRecord] = result.toolResults.compactMap { toolResult in
            guard let toolCall = toolCallsById[toolResult.callId] else {
                Log.agents.warning("Tool result missing matching call: \(toolResult.callId)")
                return nil
            }

            return ToolCallRecord(
                callId: toolResult.callId,
                toolName: toolCall.toolName,
                arguments: toolCall.arguments,
                duration: toolResult.duration,
                timestamp: toolCall.timestamp,
                outcome: ToolCallRecord.Outcome(toolResult.outcome)
            )
        }

        return AgentResponse(
            responseId: responseID,
            output: result.output,
            agentName: agentName,
            metadata: result.metadata,
            toolCalls: toolCallRecords,
            usage: result.tokenUsage,
            iterationCount: result.iterationCount
        )
    }
}
