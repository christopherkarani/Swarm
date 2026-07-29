/// Optional delegate for higher-level text compression and fact extraction.
public protocol CompressionDelegate: Sendable {
    /// Compress text to fit within targetTokens.
    /// Implementations can be extractive or abstractive.
    ///
    /// - Parameters:
    ///   - text: Input text to compress.
    ///   - targetTokens: Desired token ceiling for output.
    /// - Returns: Compressed text.
    /// - Throws: Delegate-specific compression failures.
    func compress(_ text: String, targetTokens: Int) async throws -> String

    /// Extract standalone factual statements from text.
    ///
    /// - Parameter text: Source text.
    /// - Returns: Extracted fact strings.
    /// - Throws: Delegate-specific extraction failures.
    func extractFacts(from text: String) async throws -> [String]
}
