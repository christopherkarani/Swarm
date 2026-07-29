import Foundation

/// Counts tokens for a text string under a model-specific scheme.
public protocol TokenCounter: Sendable {
    /// Returns the token count for a text input.
    ///
    /// - Parameter text: Input text.
    /// - Returns: Estimated token count.
    func count(_ text: String) -> Int
}

/// Lightweight heuristic token counter used by default.
public struct ApproximateTokenCounter: TokenCounter, Sendable {
    /// Creates a default approximate token counter.
    public init() {}

    /// Estimates token count from alphanumeric segments.
    ///
    /// - Parameter text: Input text.
    /// - Returns: Approximate count scaled by `1.3`.
    public func count(_ text: String) -> Int {
        guard !text.isEmpty else {
            return 0
        }

        let words = text.split { character in
            !(character.isLetter || character.isNumber)
        }

        guard !words.isEmpty else {
            return 0
        }

        return Int(ceil(Double(words.count) * 1.3))
    }
}
