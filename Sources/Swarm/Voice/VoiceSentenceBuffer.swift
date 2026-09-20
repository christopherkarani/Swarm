// VoiceSentenceBuffer.swift
// Swarm Framework
//
// Pure sentence splitter for speak-while-generating.

import Foundation

/// Accumulates streamed text and emits speakable sentences.
///
/// A terminator emits only when the pending sentence is at least
/// `minSpeakCharacters` long. `flush()` emits leftover non-whitespace.
struct VoiceSentenceBuffer: Sendable {
    private var pending = ""
    private let minSpeakCharacters: Int
    private let sentenceTerminators: Set<Character>

    init(
        minSpeakCharacters: Int = VoiceSessionConfiguration.default.minSpeakCharacters,
        sentenceTerminators: Set<Character> = VoiceSessionConfiguration.default.sentenceTerminators
    ) {
        self.minSpeakCharacters = minSpeakCharacters
        self.sentenceTerminators = sentenceTerminators
    }

    /// Appends a fragment and returns newly completed sentences, including terminators.
    mutating func append(_ fragment: String) -> [String] {
        pending += fragment
        var emitted: [String] = []
        while let terminatorIndex = pending.firstIndex(where: { sentenceTerminators.contains($0) }) {
            let sentence = String(pending[...terminatorIndex])
            let remainderStart = pending.index(after: terminatorIndex)
            if sentence.count >= minSpeakCharacters {
                emitted.append(sentence)
                pending = String(pending[remainderStart...])
            } else {
                break
            }
        }
        return emitted
    }

    /// Emits remaining non-whitespace, or `nil` if nothing speakable is buffered.
    mutating func flush() -> String? {
        guard pending.contains(where: { !$0.isWhitespace }) else {
            pending = ""
            return nil
        }
        let result = pending
        pending = ""
        return result
    }
}
