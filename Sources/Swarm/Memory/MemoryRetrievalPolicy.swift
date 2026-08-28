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
///
/// Item-aware retrieval is now a defaulted requirement on ``Memory``; implement
/// ``Memory/context(for:)`` directly instead of conforming to this protocol.
@available(*, deprecated, message: "Implement context(for: MemoryQuery) on your Memory conformance instead.")
public protocol MemoryRetrievalPolicyAware: Memory {
    /// Retrieves context relevant to the query while respecting item-level budgets.
    func context(for query: MemoryQuery) async -> String
}

public extension Memory {
    /// Default item-aware retrieval: falls back to ``Memory/context(for:tokenLimit:)``
    /// using the query text and total token budget, ignoring per-item budgets.
    func context(for query: MemoryQuery) async -> String {
        await context(for: query.text, tokenLimit: query.tokenLimit)
    }
}

/// Optional policy hook for memories that should not ingest session history automatically.
///
/// The seeding policy is now a defaulted requirement on ``Memory``; implement
/// ``Memory/allowsAutomaticSessionSeeding`` directly instead of conforming to
/// this protocol.
@available(*, deprecated, message: "Implement allowsAutomaticSessionSeeding on your Memory conformance instead.")
public protocol MemorySessionImportPolicy: Sendable {
    /// Whether the agent runtime may seed session history into this memory store.
    var allowsAutomaticSessionSeeding: Bool { get }
}
