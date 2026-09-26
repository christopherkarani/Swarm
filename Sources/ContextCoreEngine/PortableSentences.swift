import Foundation

#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Portable sentence splitter used by the CPU compression path.
///
/// Uses `NLTokenizer` when NaturalLanguage is available and falls back to a
/// punctuation-and-newline split otherwise, so compression works without Apple
/// frameworks.
public enum PortableSentences: Sendable {
    /// Splits text into trimmed, non-empty sentences.
    public static func split(_ text: String) -> [String] {
        #if canImport(NaturalLanguage)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }
        return sentences
        #else
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "." || character == "!" || character == "?" || character == "\n" {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            sentences.append(tail)
        }
        return sentences
        #endif
    }
}
