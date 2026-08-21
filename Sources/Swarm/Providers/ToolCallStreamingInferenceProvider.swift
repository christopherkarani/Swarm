// ToolCallStreamingInferenceProvider.swift
// Swarm Framework
//
// Streaming tool-call updates on the InferenceProvider seam.

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
/// ``InferenceProvider`` now includes ``InferenceProvider/streamWithToolCalls(prompt:tools:options:)``.
/// This marker remains as a deprecated alias for source compatibility.
///
/// Agent dispatches live streaming from ``InferenceProviderCapabilities/streamingToolCalls``
/// and ``InferenceProvider/streamWithToolCalls(messages:tools:options:)``. Do not use this
/// protocol as the Agent seam.
@available(*, deprecated, message: "Declare InferenceProviderCapabilities.streamingToolCalls and override streamWithToolCalls on InferenceProvider")
public protocol ToolCallStreamingInferenceProvider: InferenceProvider {}
