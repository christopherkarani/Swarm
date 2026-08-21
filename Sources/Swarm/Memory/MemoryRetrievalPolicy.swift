import Foundation

/// Retrieval contract for memory implementations that support item-aware budgeting.
public struct MemoryQuery: Sendable, Equatable {
    /// User input or search text used to retrieve relevant memory.
    public let text: String

    /// Total token budget available to the memory implementation.
    ///
    /// Built-in memories measure this with ``CharacterBasedTokenEstimator``
    /// by default (~4 characters per token). That is a heuristic, not a
    /// model tokenizer.
    public let tokenLimit: Int

    /// Maximum number of retrieved items to include.
    public let maxItems: Int

    /// Maximum token budget for any single retrieved item.
    ///
    /// Same estimator heuristic as ``tokenLimit`` (~4 characters per token
    /// with the default ``CharacterBasedTokenEstimator``).
    public let maxItemTokens: Int

    public init(
        text: String,
        tokenLimit: Int,
        maxItems: Int,
        maxItemTokens: Int
    ) {
        self.text = text
        self.tokenLimit = max(0, tokenLimit)
        self.maxItems = max(1, maxItems)
        self.maxItemTokens = max(1, maxItemTokens)
    }
}

/// Optional memory extension for retrieval implementations that need more than a token limit.
@available(*, deprecated, message: "context(for: MemoryQuery) is a defaulted Memory requirement")
public protocol MemoryRetrievalPolicyAware: Memory {}

/// Optional policy hook for memories that should not ingest session history automatically.
@available(*, deprecated, message: "allowsAutomaticSessionSeeding is a defaulted Memory requirement")
public protocol MemorySessionImportPolicy: Sendable {}
