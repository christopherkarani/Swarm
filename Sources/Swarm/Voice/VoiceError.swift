// VoiceError.swift
// Swarm Framework
//
// Pipeline errors for VoiceSession. Agent and guardrail failures are rethrown.

import Foundation

/// Errors raised by the voice coordinator and speech adapters.
///
/// `VoiceError` covers listen / speak pipeline failures only. `AgentError` and
/// `GuardrailError` from `agent.stream` are rethrown unchanged.
public enum VoiceError: Error, Sendable, Equatable {
    /// A turn is already in flight on this `VoiceSession`.
    case busy

    /// The transcript was empty or whitespace-only; the agent was not started.
    case emptyTranscript

    /// Microphone or speech-recognition permission was denied.
    case notAuthorized(reason: String)

    /// The requested locale is not supported by the speech adapter.
    case unsupportedLocale(String)

    /// Language assets are missing and were not installed.
    case assetUnavailable(reason: String)

    /// Speech-to-text failed after a listen started.
    case speechFailed(reason: String)

    /// Text-to-speech failed while speaking an utterance.
    case synthesisFailed(reason: String)

    /// The agent stream ended without a completed `AgentResult`.
    case agentFinishedWithoutResult

    /// The in-flight turn was stopped.
    case cancelled
}

extension VoiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .busy:
            "A voice turn is already in progress."
        case .emptyTranscript:
            "The transcript was empty."
        case let .notAuthorized(reason):
            "Speech is not authorized: \(reason)"
        case let .unsupportedLocale(locale):
            "Unsupported speech locale: \(locale)"
        case let .assetUnavailable(reason):
            "Speech assets are unavailable: \(reason)"
        case let .speechFailed(reason):
            "Speech recognition failed: \(reason)"
        case let .synthesisFailed(reason):
            "Speech synthesis failed: \(reason)"
        case .agentFinishedWithoutResult:
            "The agent stream finished without a result."
        case .cancelled:
            "The voice turn was cancelled."
        }
    }
}
