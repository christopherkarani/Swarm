import Foundation

/// Compression intensity applied to a context chunk.
public enum CompressionLevel: Int, Codable, Sendable, Hashable, Comparable {
    /// No compression was applied.
    case none = 0
    /// Mild compression preserving most content.
    case light = 1
    /// Aggressive compression preserving only high-signal content.
    case heavy = 2
    /// Chunk was dropped to satisfy budget constraints.
    case dropped = 3

    /// Compares compression levels by intensity.
    public static func < (lhs: CompressionLevel, rhs: CompressionLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Formatting styles for serializing a ``ContextWindow``.
public enum FormatStyle: Sendable {
    /// Concatenates chunk text as raw paragraphs.
    case raw
    /// Emits ChatML tags.
    case chatML
    /// Emits Alpaca-style instruction blocks.
    case alpaca
    /// Uses a custom per-chunk template containing `{role}` and `{content}` tokens.
    case custom(template: String)
}

/// A single chunk included in the final context window.
public struct ContextChunk: Identifiable, Codable, Sendable, Hashable {
    /// Stable identifier for this chunk.
    public let id: UUID
    /// Chunk content as injected into the model prompt.
    public let content: String
    /// Role label for formatting.
    public let role: TurnRole
    /// Token count used for budget accounting.
    public let tokenCount: Int
    /// Relevance score assigned during ranking.
    public let score: Float
    /// Memory tier that produced this chunk.
    public let source: MemoryType
    /// Compression level applied before packing.
    public var compressionLevel: CompressionLevel
    /// Source timestamp used for ordering.
    public let timestamp: Date
    /// Indicates chunk is guaranteed by recency policy.
    public let isGuaranteedRecent: Bool
    /// Indicates chunk is the active system prompt.
    public let isSystemPrompt: Bool

    /// Creates a context chunk.
    ///
    /// - Parameters:
    ///   - id: Chunk identifier.
    ///   - content: Prompt text.
    ///   - role: Formatting role.
    ///   - tokenCount: Token count estimate.
    ///   - score: Ranking score.
    ///   - source: Memory source.
    ///   - compressionLevel: Applied compression level.
    ///   - timestamp: Source timestamp.
    ///   - isGuaranteedRecent: `true` for guaranteed recent turns.
    ///   - isSystemPrompt: `true` for system prompt chunk.
    public init(
        id: UUID = UUID(),
        content: String,
        role: TurnRole,
        tokenCount: Int,
        score: Float,
        source: MemoryType,
        compressionLevel: CompressionLevel = .none,
        timestamp: Date = .now,
        isGuaranteedRecent: Bool = false,
        isSystemPrompt: Bool = false
    ) {
        self.id = id
        self.content = content
        self.role = role
        self.tokenCount = tokenCount
        self.score = score
        self.source = source
        self.compressionLevel = compressionLevel
        self.timestamp = timestamp
        self.isGuaranteedRecent = isGuaranteedRecent
        self.isSystemPrompt = isSystemPrompt
    }
}

/// Final packed context sent to the model.
public struct ContextWindow: Codable, Sendable, Hashable {
    /// Ordered chunks included in the window.
    public let chunks: [ContextChunk]
    /// Total tokens consumed by `chunks`.
    public let totalTokens: Int
    /// Fraction of budget consumed in `[0, 1]`.
    public let budgetUsed: Float
    /// Effective token budget for this window.
    public let budget: Int
    /// Number of chunks retrieved from episodic or semantic memory.
    public let retrievedFromMemory: Int
    /// Number of chunks that were compressed.
    public let compressedChunks: Int

    /// Creates a context window from packed chunks.
    ///
    /// - Parameters:
    ///   - chunks: Packed chunks in final order.
    ///   - budget: Effective token budget.
    public init(chunks: [ContextChunk], budget: Int) {
        self.chunks = chunks
        self.budget = budget
        self.totalTokens = chunks.reduce(into: 0) { partial, chunk in
            partial += chunk.tokenCount
        }

        if budget > 0 {
            let ratio = Float(totalTokens) / Float(budget)
            self.budgetUsed = min(max(ratio, 0), 1)
        } else {
            self.budgetUsed = totalTokens == 0 ? 0 : 1
        }

        self.retrievedFromMemory = chunks.reduce(into: 0) { partial, chunk in
            let isRetrievedMemory = (chunk.source == .episodic || chunk.source == .semantic)
                && !chunk.isGuaranteedRecent
                && !chunk.isSystemPrompt
            if isRetrievedMemory {
                partial += 1
            }
        }

        self.compressedChunks = chunks.reduce(into: 0) { partial, chunk in
            if chunk.compressionLevel > .none {
                partial += 1
            }
        }
    }

    /// Serializes the window for model injection.
    ///
    /// - Parameter style: Output formatting style.
    /// - Returns: Formatted prompt string.
    public func formatted(style: FormatStyle) -> String {
        switch style {
        case .raw:
            return chunks.map(\ .content).joined(separator: "\n\n")
        case .chatML:
            return chunks
                .map { chunk in
                    "<|im_start|>\(chunk.role.rawValue)\n\(chunk.content)<|im_end|>"
                }
                .joined(separator: "\n")
        case .alpaca:
            return chunks
                .map { chunk in
                    switch chunk.role {
                    case .system:
                        return "### Instruction:\n\(chunk.content)\n\n"
                    case .user:
                        return "### Input:\n\(chunk.content)\n\n"
                    case .assistant:
                        return "### Response:\n\(chunk.content)\n\n"
                    case .tool:
                        return "### Tool Output:\n\(chunk.content)\n\n"
                    }
                }
                .joined()
        case .custom(let template):
            return chunks
                .map { chunk in
                    template
                        .replacingOccurrences(of: "{role}", with: chunk.role.rawValue)
                        .replacingOccurrences(of: "{content}", with: chunk.content)
                }
                .joined(separator: "\n")
        }
    }
}
