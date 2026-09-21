// VoiceEvent.swift
// Swarm Framework
//
// Long-lived events emitted by VoiceSession.

import Foundation

/// Phase of a turn-based ``VoiceSession``.
public enum VoicePhase: String, Sendable, Equatable {
    /// No turn is in flight.
    case idle
    /// Waiting for a final transcript from speech-to-text.
    case listening
    /// The agent stream is running.
    case running
    /// An utterance is being spoken.
    case speaking
}

/// Events a host can use to reconstruct voice UI.
///
/// `stop()` does not finish the stream. Deinit does.
public enum VoiceEvent: Sendable, Equatable {
    /// The session moved to a new phase.
    case phase(VoicePhase)

    /// A volatile speech-to-text update.
    case partialTranscript(String)

    /// The transcript that will be (or was) sent to the agent.
    case finalTranscript(String)

    /// A forwarded ``AgentEvent`` from `agent.stream`.
    case agent(AgentEvent)

    /// Speech synthesis of `text` started.
    case speaking(String)

    /// Speech synthesis of `text` finished or was interrupted.
    case speakingFinished(String)
}
