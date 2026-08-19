// ToolCallStreamingInferenceProvider.swift
// Swarm Framework
//
// Provider capability protocol for streaming tool call assembly (partial arguments + completed calls).

import Foundation

/// Provider-originated streaming updates used for live tool-call experiences.
public enum InferenceStreamUpdate: Sendable, Equatable {
    /// A chunk of assistant text produced during streaming.
    case outputChunk(String)

    /// A partial tool call update (arguments JSON fragment).
    case toolCallPartial(PartialToolCallUpdate)

    /// Completed tool calls ready for execution.
    case toolCallsCompleted([InferenceResponse.ParsedToolCall])

    /// Token usage statistics (typically available at the end of streaming).
    case usage(TokenUsage)

    /// A finished provider-owned turn, including the inner transcript.
    case finishedTurn(InferenceResponse)
}

/// An inference provider that can stream tool-call assembly.
///
/// This allows agents to surface partial tool arguments to clients before tool execution begins.
public protocol ToolCallStreamingInferenceProvider: InferenceProvider {
    /// Streams a response with potential tool calls, yielding partial tool-call updates as they arrive.
    func streamWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error>
}

