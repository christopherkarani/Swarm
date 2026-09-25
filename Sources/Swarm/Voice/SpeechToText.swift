// SpeechToText.swift
// Swarm Framework
//
// Host-injected speech recognition. Does not call Agent.

import Foundation

/// Converts spoken audio into ``SpeechTranscript`` values.
///
/// Implementations must not open a microphone from a protocol default. Hosts
/// inject Apple, Whisper, or test doubles.
public protocol SpeechToText: Sendable {
    /// Starts capture and yields partial then final transcripts.
    func start() -> AsyncThrowingStream<SpeechTranscript, Error>

    /// Ends capture. Outstanding `start()` streams should finish.
    func stop() async
}
