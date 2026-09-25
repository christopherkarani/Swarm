// SpeechTranscript.swift
// Swarm Framework
//
// Partial and final speech-to-text payloads.

import Foundation

/// A transcript fragment from ``SpeechToText``.
///
/// Partials never start an agent turn. `VoiceSession` uses the last non-empty
/// `isFinal == true` text, or the last non-empty partial if the stream ends
/// without a final.
public struct SpeechTranscript: Sendable, Equatable {
    /// Recognized text for this update.
    public let text: String

    /// Whether this update is a committed utterance.
    public let isFinal: Bool

    /// Creates a transcript fragment.
    /// - Parameters:
    ///   - text: Recognized text.
    ///   - isFinal: Whether recognition has committed this utterance.
    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}
