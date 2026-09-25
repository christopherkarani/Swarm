// VoiceTurnResult.swift
// Swarm Framework
//
// Outcome of one listenAndRespond or respond(to:) turn.

import Foundation

/// Result of one voice turn.
///
/// Carries text only — no PCM, buffers, or recording URLs.
public struct VoiceTurnResult: Sendable {
    /// Transcript sent to the agent.
    public let transcript: String

    /// Agent result captured from `.lifecycle(.completed)`.
    public let agentResult: AgentResult

    /// Sentences actually passed to ``TextToSpeech``.
    public let spokenUtterances: [String]

    /// Creates a turn result.
    public init(transcript: String, agentResult: AgentResult, spokenUtterances: [String]) {
        self.transcript = transcript
        self.agentResult = agentResult
        self.spokenUtterances = spokenUtterances
    }
}
