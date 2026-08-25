// InferenceStreamEvent.swift
// Swarm Framework
//
// Generic stream events for providers that support tool-call streaming.

import Foundation

// MARK: - InferenceStreamEvent

/// Stream events emitted by tool-call capable inference providers.
///
/// Providers can emit text deltas, tool call deltas, finish reasons, and usage
/// metadata. Errors should be surfaced by terminating the stream with a failure.
public enum InferenceStreamEvent: Sendable, Equatable {
    /// A text content delta.
    case textDelta(String)

    /// A tool call delta with streaming fragments.
    /// - Parameters:
    ///   - index: The index of the tool call in the array.
    ///   - id: The tool call ID (may be nil for subsequent deltas).
    ///   - name: The function name (may be nil for subsequent deltas).
    ///   - arguments: The partial arguments JSON string.
    case toolCallDelta(index: Int, id: String?, name: String?, arguments: String)

    /// The finish reason for the response.
    case finishReason(String)

    /// Token usage information.
    case usage(promptTokens: Int, completionTokens: Int)

    /// Stream completed (received terminal marker).
    case done
}
