// StreamingTextToSpeech.swift
// Swarm Framework
//
// Chunked speech synthesis for low time-to-first-audio.

import Foundation

/// Text-to-speech that yields audio bytes while synthesis is still running.
///
/// `VoiceSession` prefers this path when the adapter conforms: each chunk
/// surfaces as ``VoiceEvent/audioChunk(utterance:data:)`` so the host can
/// play audio before the utterance finishes synthesizing. Adapters that do
/// not conform keep the whole-utterance ``TextToSpeech/speak(_:)`` path.
///
/// Chunks for one utterance concatenate byte-for-byte into the complete
/// audio payload. The stream finishes when synthesis completes; hosts use
/// the bracketing ``VoiceEvent/speaking(_:)`` /
/// ``VoiceEvent/speakingFinished(_:)`` events to frame playback.
public protocol StreamingTextToSpeech: TextToSpeech {
    /// Synthesizes `text`, yielding audio chunks as they arrive.
    ///
    /// Nonisolated like ``SpeechToText/start()`` so actors return the stream
    /// without hopping; hop inside for adapter state.
    ///
    /// - Parameter text: Utterance to synthesize. Must contain non-whitespace.
    /// - Returns: Audio chunks in playback order.
    nonisolated func streamAudio(_ text: String) -> AsyncThrowingStream<Data, Error>
}
