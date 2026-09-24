// VoiceActivityDetector.swift
// Swarm Framework
//
// Opt-in barge-in detector. Does not open Agent.

import Foundation

/// Voice-activity updates used for barge-in while the session is speaking.
public enum VoiceActivityEvent: Sendable, Equatable {
    /// Speech was detected over the interrupt threshold.
    case speechStarted
    /// Speech is no longer detected.
    case speechEnded
}

/// Host-injected detector that may interrupt text-to-speech.
///
/// Linux and tests use a mock. Apple ships ``AppleVoiceActivityDetector``.
public protocol VoiceActivityDetector: Sendable {
    /// Starts observing. The stream finishes when ``stop()`` is called or the
    /// detector ends.
    func start() -> AsyncThrowingStream<VoiceActivityEvent, Error>

    /// Stops observation.
    func stop() async
}
