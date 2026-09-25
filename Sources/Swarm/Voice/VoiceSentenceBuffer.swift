// VoiceSentenceBuffer.swift
// Swarm Framework
//
// Pure sentence splitter for speak-while-generating.

import Foundation

/// Accumulates streamed text and emits speakable sentences.
///
/// A terminator emits the buffered span up to and including it once that span
/// is at least `minSpeakCharacters` long. Short prefixes do not head-of-line
/// block later terminators: they accumulate into the following sentence until
/// the combined span is speakable. `flush()` emits leftover non-whitespace.
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
        var searchStart = pending.startIndex
        while searchStart < pending.endIndex,
              let terminatorIndex = pending[searchStart...].firstIndex(where: { sentenceTerminators.contains($0) }) {
            let sentence = String(pending[...terminatorIndex])
            let remainderStart = pending.index(after: terminatorIndex)
            if sentence.count >= minSpeakCharacters {
                emitted.append(sentence)
                pending = String(pending[remainderStart...])
                searchStart = pending.startIndex
            } else {
                // Short prefix: scan past it so a later terminator can complete
                // a speakable sentence instead of head-of-line blocking on this one.
                searchStart = remainderStart
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
