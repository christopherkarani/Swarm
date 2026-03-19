// AgentMemory.swift
// Swarm Framework
//
// Core protocol defining memory storage and retrieval for agents.

import Foundation

// MARK: - Memory

/// Actor protocol for agent memory systems.
///
/// Implement `Memory` to provide custom conversation history management,
/// RAG (Retrieval-Augmented Generation), or other context-aware storage.
/// The protocol is designed for actor conformance, providing automatic
/// thread-safety for memory operations.
///
/// ## Built-in Implementations
///
/// Swarm provides several memory implementations optimized for different use cases:
///
/// | Implementation | Best For | Key Feature |
/// |----------------|----------|-------------|
/// | ``ConversationMemory`` | Simple chat history | Rolling buffer of recent messages |
/// | ``VectorMemory`` | RAG, semantic search | Embedding-based similarity search |
/// | ``SlidingWindowMemory`` | Token-limited contexts | Token-bounded sliding window |
/// | ``SummaryMemory`` | Long conversations | Automatic summarization of old messages |
/// | ``HybridMemory`` | Complex applications | Combines short-term and long-term memory |
/// | ``PersistentMemory`` | Production apps | Pluggable storage backends |
///
/// ## Factory Methods
///
/// Create memory instances using the static factory methods:
///
/// ```swift
/// // Simple conversation history (most common)
/// let memory = Memory.conversation(maxMessages: 50)
///
/// // Semantic search with embeddings (for RAG)
/// let vectorMemory = Memory.vector(
///     embeddingProvider: myProvider,
///     similarityThreshold: 0.75
/// )
///
/// // Token-bounded sliding window
/// let slidingMemory = Memory.slidingWindow(maxTokens: 8000)
///
/// // With automatic summarization
/// let summaryMemory = Memory.summary(
///     configuration: .init(recentMessageCount: 30)
/// )
/// ```
///
/// ## Attaching to Agents
///
/// Memory is attached to agents using the fluent API:
///
/// ```swift
/// let agent = Agent(
///     id: "assistant",
///     model: gpt4,
///     instructions: "You are a helpful assistant."
/// )
/// .withMemory(.conversation(maxMessages: 100))
/// ```
///
/// ## Implementing Custom Memory
///
/// Create custom memory by conforming an actor to the `Memory` protocol:
///
/// ```swift
/// public actor CustomMemory: Memory {
///     private var messages: [MemoryMessage] = []
///
///     public var count: Int { messages.count }
///     public var isEmpty: Bool { messages.isEmpty }
///
///     public func add(_ message: MemoryMessage) async {
///         self.messages.append(message)
///     }
///
///     public func context(for query: String, tokenLimit: Int) async -> String {
///         // Return relevant context based on query
///         MemoryMessage.formatContext(messages, tokenLimit: tokenLimit)
///     }
///
///     public func allMessages() async -> [MemoryMessage] {
///         messages
///     }
///
///     public func clear() async {
///         messages.removeAll()
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// All `Memory` implementations should be actors or provide equivalent
/// thread-safety guarantees. The protocol inherits from `Sendable` to ensure
/// safe concurrent access across isolation boundaries.
///
/// - SeeAlso: ``ConversationMemory``, ``VectorMemory``, ``SlidingWindowMemory``,
///   ``SummaryMemory``, ``HybridMemory``, ``PersistentMemory``, ``MemoryMessage``
public protocol Memory: Actor, Sendable {
    /// The number of messages currently stored.
    ///
    /// This property should be efficient to compute without fetching
    /// all messages. For example:
    ///
    /// ```swift
    /// public var count: Int { messages.count }
    /// ```
    var count: Int { get async }

    /// Whether the memory contains no messages.
    ///
    /// Implementations should provide an efficient check that avoids
    /// fetching all messages when possible. For example:
    ///
    /// ```swift
    /// public var isEmpty: Bool { messages.isEmpty }
    /// ```
    var isEmpty: Bool { get async }

    /// Adds a message to memory.
    ///
    /// The implementation determines how the message is stored and whether
    /// any eviction policies are applied (e.g., removing old messages when
    /// a maximum is reached).
    ///
    /// - Parameter message: The message to store. Contains the role
    ///   (user, assistant, system, tool), content, timestamp, and metadata.
    ///
    /// - SeeAlso: ``MemoryMessage``
    func add(_ message: MemoryMessage) async

    /// Retrieves context relevant to the query within token limits.
    ///
    /// This is the primary method for retrieving conversation history or
    /// relevant context to include in LLM prompts. The implementation
    /// determines how to select and format messages:
    ///
    /// - Simple implementations may return the most recent messages
    /// - Advanced implementations may use semantic search (``VectorMemory``)
    /// - Some implementations may summarize old messages (``SummaryMemory``)
    ///
    /// The returned string should be formatted appropriately for inclusion
    /// in a system prompt or chat history. The `MemoryMessage.formatContext`
    /// helper can assist with this.
    ///
    /// - Parameters:
    ///   - query: The query to find relevant context for. May be the user's
    ///     current input, a search query, or empty for recent-only context.
    ///   - tokenLimit: Maximum tokens to include in the context. Implementations
    ///     should respect this limit to avoid exceeding model context windows.
    /// - Returns: A formatted string containing relevant context, ready for
    ///   inclusion in LLM prompts.
    ///
    /// - SeeAlso: ``MemoryMessage/formatContext(_:tokenLimit:tokenEstimator:)``
    func context(for query: String, tokenLimit: Int) async -> String

    /// Returns all messages currently in memory.
    ///
    /// This method returns the complete message history in chronological
    /// order (oldest first). Use with caution on large memories as this
    /// may be expensive.
    ///
    /// - Returns: Array of all stored messages in chronological order.
    ///
    /// - SeeAlso: ``MemoryMessage``
    func allMessages() async -> [MemoryMessage]

    /// Removes all messages from memory.
    ///
    /// After calling this method, ``isEmpty`` should return `true` and
    /// ``count`` should return `0`. This is typically used when starting
    /// a new conversation or resetting the agent state.
    func clear() async
}

// MARK: - MemoryMessage Context Formatting

public extension MemoryMessage {
    /// Formats messages into a context string within token limits.
    ///
    /// This helper method processes messages from most recent to oldest,
    /// including as many as fit within the token budget. Messages are
    /// joined with double newlines for clear separation.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let messages = [
    ///     MemoryMessage.user("Hello"),
    ///     MemoryMessage.assistant("Hi there!")
    /// ]
    /// let context = MemoryMessage.formatContext(messages, tokenLimit: 1000)
    /// // Returns:
    /// // [user]: Hello
    /// //
    /// // [assistant]: Hi there!
    /// ```
    ///
    /// - Parameters:
    ///   - messages: Messages to format, typically from ``Memory/allMessages()``.
    ///   - tokenLimit: Maximum tokens allowed in the resulting context.
    ///   - tokenEstimator: Estimator for token counting. Defaults to
    ///     `CharacterBasedTokenEstimator.shared`.
    /// - Returns: Formatted context string with messages joined by double newlines.
    ///
    /// - SeeAlso: ``TokenEstimator``, ``CharacterBasedTokenEstimator``
    static func formatContext(
        _ messages: [MemoryMessage],
        tokenLimit: Int,
        tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared
    ) -> String {
        var result: [String] = []
        var currentTokens = 0

        // Process messages in reverse (most recent first) then reverse result
        for message in messages.reversed() {
            let formatted = message.formattedContent
            let messageTokens = tokenEstimator.estimateTokens(for: formatted)

            if currentTokens + messageTokens <= tokenLimit {
                result.append(formatted)
                currentTokens += messageTokens
            } else {
                break
            }
        }

        return result.reversed().joined(separator: "\n\n")
    }

    /// Formats messages into a context string within token limits with a custom separator.
    ///
    /// This variant allows specifying a custom separator between messages,
    /// useful for different prompt formatting requirements.
    ///
    /// - Parameters:
    ///   - messages: Messages to format.
    ///   - tokenLimit: Maximum tokens allowed.
    ///   - separator: String to join messages (e.g., `"\n"` for single newlines,
    ///     `"\n---\n"` for visual separation).
    ///   - tokenEstimator: Estimator for token counting.
    /// - Returns: Formatted context string.
    static func formatContext(
        _ messages: [MemoryMessage],
        tokenLimit: Int,
        separator: String,
        tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared
    ) -> String {
        var result: [String] = []
        var currentTokens = 0
        let separatorTokens = tokenEstimator.estimateTokens(for: separator)

        for message in messages.reversed() {
            let formatted = message.formattedContent
            let messageTokens = tokenEstimator.estimateTokens(for: formatted)
            let totalNeeded = messageTokens + (result.isEmpty ? 0 : separatorTokens)

            if currentTokens + totalNeeded <= tokenLimit {
                result.append(formatted)
                currentTokens += totalNeeded
            } else {
                break
            }
        }

        return result.reversed().joined(separator: separator)
    }
}

// MARK: - Memory Factory Extensions (V3)

extension Memory where Self == ConversationMemory {
    /// Creates a ``ConversationMemory`` with a maximum message count.
    ///
    /// This is the simplest memory implementation, storing a rolling buffer
    /// of recent messages. When the limit is exceeded, oldest messages are
    /// automatically removed.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Default: 100 messages
    /// let agent = myAgent.withMemory(.conversation())
    ///
    /// // Custom limit
    /// let agent = myAgent.withMemory(.conversation(maxMessages: 50))
    /// ```
    ///
    /// ## When to Use
    ///
    /// - Simple chatbots with short conversation history
    /// - When you want predictable memory bounds
    /// - When semantic search is not needed
    /// - For testing and prototyping
    ///
    /// - Parameter maxMessages: Maximum messages to retain (default: 100).
    /// - Returns: A ``ConversationMemory`` instance.
    ///
    /// - SeeAlso: ``ConversationMemory``
    public static func conversation(maxMessages: Int = 100) -> ConversationMemory {
        ConversationMemory(maxMessages: maxMessages)
    }
}

extension Memory where Self == SlidingWindowMemory {
    /// Creates a ``SlidingWindowMemory`` with a maximum token count.
    ///
    /// This memory maintains messages within a token budget, removing oldest
    /// messages when the token limit would be exceeded. More precise than
    /// ``ConversationMemory`` when working with models that have strict
    /// context window limits.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Default: 4000 tokens
    /// let agent = myAgent.withMemory(.slidingWindow())
    ///
    /// // For models with larger context windows
    /// let agent = myAgent.withMemory(.slidingWindow(maxTokens: 16000))
    /// ```
    ///
    /// ## When to Use
    ///
    /// - When you need precise token budget management
    /// - Working with models that have strict context limits
    /// - Long-form conversations where message count varies
    ///
    /// - Parameter maxTokens: Maximum tokens to retain (default: 4000).
    /// - Returns: A ``SlidingWindowMemory`` instance.
    ///
    /// - SeeAlso: ``SlidingWindowMemory``
    public static func slidingWindow(maxTokens: Int = 4000) -> SlidingWindowMemory {
        SlidingWindowMemory(maxTokens: maxTokens)
    }
}

extension Memory where Self == PersistentMemory {
    /// Creates a ``PersistentMemory`` with a pluggable storage backend.
    ///
    /// Persistent memory survives app restarts by using a storage backend
    /// like SwiftData, Core Data, or custom implementations. Defaults to
    /// an in-memory backend for testing.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // In-memory (for testing)
    /// let agent = myAgent.withMemory(.persistent())
    ///
    /// // With SwiftData backend
    /// let agent = myAgent.withMemory(.persistent(
    ///     backend: SwiftDataMemoryBackend(),
    ///     conversationId: "user-123-thread-1"
    /// ))
    /// ```
    ///
    /// ## When to Use
    ///
    /// - Production applications requiring conversation persistence
    /// - Multi-session conversations across app restarts
    /// - When you need to query conversation history later
    ///
    /// - Parameters:
    ///   - backend: The storage backend (default: `InMemoryBackend()`).
    ///   - conversationId: Unique identifier for this conversation (default: random UUID).
    ///   - maxMessages: Maximum messages to retain; 0 means unlimited (default: 0).
    /// - Returns: A ``PersistentMemory`` instance.
    ///
    /// - SeeAlso: ``PersistentMemory``, ``PersistentMemoryBackend``
    public static func persistent(
        backend: any PersistentMemoryBackend = InMemoryBackend(),
        conversationId: String = UUID().uuidString,
        maxMessages: Int = 0
    ) -> PersistentMemory {
        PersistentMemory(
            backend: backend,
            conversationId: conversationId,
            maxMessages: maxMessages
        )
    }
}

extension Memory where Self == HybridMemory {
    /// Creates a ``HybridMemory`` combining short-term and summarized long-term memory.
    ///
    /// Hybrid memory keeps recent messages in full detail while summarizing
    /// older messages to retain context without exceeding token limits.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Default configuration
    /// let agent = myAgent.withMemory(.hybrid())
    ///
    /// // Custom configuration
    /// let config = HybridMemory.Configuration(
    ///     shortTermMaxMessages: 50,
    ///     summaryTriggerThreshold: 100
    /// )
    /// let agent = myAgent.withMemory(.hybrid(configuration: config))
    /// ```
    ///
    /// ## When to Use
    ///
    /// - Long-running conversations where old context matters
    /// - When you need both detail (recent) and breadth (old)
    /// - Cost-conscious applications (summaries use fewer tokens)
    ///
    /// - Parameters:
    ///   - configuration: Behavior configuration (default: `.default`).
    ///   - summarizer: Summarization service (default: `TruncatingSummarizer.shared`).
    /// - Returns: A ``HybridMemory`` instance.
    ///
    /// - SeeAlso: ``HybridMemory``, ``Summarizer``
    public static func hybrid(
        configuration: HybridMemory.Configuration = .default,
        summarizer: any Summarizer = TruncatingSummarizer.shared
    ) -> HybridMemory {
        HybridMemory(configuration: configuration, summarizer: summarizer)
    }
}

extension Memory where Self == SummaryMemory {
    /// Creates a ``SummaryMemory`` that automatically summarizes old messages.
    ///
    /// Summary memory keeps a fixed number of recent messages in full form
    /// while continuously summarizing older messages. More aggressive than
    /// ``HybridMemory`` in condensing history.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Default: 50 recent messages
    /// let agent = myAgent.withMemory(.summary())
    ///
    /// // Keep more recent messages
    /// let agent = myAgent.withMemory(.summary(
    ///     configuration: .init(recentMessageCount: 100)
    /// ))
    /// ```
    ///
    /// ## When to Use
    ///
    /// - Very long conversations where history must be preserved
    /// - When token budget is very constrained
    /// - Applications where approximate context is sufficient
    ///
    /// - Parameters:
    ///   - configuration: Behavior configuration (default: `.default`).
    ///   - summarizer: Summarization service (default: `TruncatingSummarizer.shared`).
    /// - Returns: A ``SummaryMemory`` instance.
    ///
    /// - SeeAlso: ``SummaryMemory``
    public static func summary(
        configuration: SummaryMemory.Configuration = .default,
        summarizer: any Summarizer = TruncatingSummarizer.shared
    ) -> SummaryMemory {
        SummaryMemory(configuration: configuration, summarizer: summarizer)
    }
}

extension Memory where Self == VectorMemory {
    /// Creates a ``VectorMemory`` backed by semantic embeddings.
    ///
    /// Vector memory enables semantic search over conversation history,
    /// retrieving messages that are conceptually similar to the query
    /// even if they don't share exact keywords.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let provider = OpenAIEmbeddingProvider(apiKey: key)
    ///
    /// // Default settings
    /// let agent = myAgent.withMemory(.vector(embeddingProvider: provider))
    ///
    /// // Custom similarity threshold and result limit
    /// let agent = myAgent.withMemory(.vector(
    ///     embeddingProvider: provider,
    ///     similarityThreshold: 0.8,
    ///     maxResults: 5
    /// ))
    /// ```
    ///
    /// ## When to Use
    ///
    /// - RAG (Retrieval-Augmented Generation) applications
    /// - Large knowledge bases where semantic relevance matters
    /// - When users ask questions related to previous topics
    /// - Conversations where context spans many messages
    ///
    /// ## Requirements
    ///
    /// Requires an ``EmbeddingProvider`` implementation. The provider handles
    /// converting text to vector embeddings for similarity comparison.
    ///
    /// - Parameters:
    ///   - embeddingProvider: Provider for generating text embeddings.
    ///   - similarityThreshold: Minimum similarity for results (0–1, default: 0.7).
    ///     Higher values return more relevant but potentially fewer results.
    ///   - maxResults: Maximum results to return from semantic search (default: 10).
    /// - Returns: A ``VectorMemory`` instance.
    ///
    /// - SeeAlso: ``VectorMemory``, ``EmbeddingProvider``
    public static func vector(
        embeddingProvider: any EmbeddingProvider,
        similarityThreshold: Float = 0.7,
        maxResults: Int = 10
    ) -> VectorMemory {
        VectorMemory(
            embeddingProvider: embeddingProvider,
            similarityThreshold: similarityThreshold,
            maxResults: maxResults
        )
    }
}
