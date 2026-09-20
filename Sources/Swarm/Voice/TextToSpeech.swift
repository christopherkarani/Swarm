// TextToSpeech.swift
// Swarm Framework
//
// Host-injected speech synthesis.

import Foundation

/// Speaks one string and returns when that utterance finishes or is stopped.
public protocol TextToSpeech: Sendable {
    /// Speaks `text` and returns when playback finishes or is interrupted.
    func speak(_ text: String) async throws

    /// Interrupts current and pending audio in this adapter.
    func stop() async
}
