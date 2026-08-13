// ConversationMemory.swift
// Swarm Framework
//
// Simple FIFO memory that maintains a fixed number of recent messages.

import Foundation

// MARK: - ConversationMemory

/// A simple FIFO memory that maintains a fixed number of recent messages.
///
/// `ConversationMemory` is the most basic memory implementation, storing
/// the N most recent messages. When the limit is exceeded, the oldest
/// messages are automatically removed.
///
/// ## Usage
///
/// ```swift
/// let memory = ConversationMemory(maxMessages: 50)
/// await memory.add(.user("Hello"))
/// await memory.add(.assistant("Hi there!"))
/// let context = await memory.context(for: "greeting", tokenLimit: 1000)
/// ```
///
/// ## Thread Safety
///
/// As an actor, `ConversationMemory` is automatically thread-safe.
/// All operations are serialized through the actor's executor.
public actor ConversationMemory: Memory {
    // MARK: Public

    /// Maximum number of messages to retain.
    public let maxMessages: Int

    public var count: Int {
        messages.count
    }

    /// Whether the memory contains no messages.
    public var isEmpty: Bool { messages.isEmpty }

    /// Creates a new conversation memory.
    ///
    /// - Parameters:
    ///   - maxMessages: Maximum messages to retain (default: 100).
    ///   - tokenEstimator: Estimator used by ``context(for:tokenLimit:)``.
    ///     Defaults to ``CharacterBasedTokenEstimator`` (~4 characters per token).
    public init(
        maxMessages: Int = 100,
        tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared
    ) {
        self.maxMessages = max(1, maxMessages)
        self.tokenEstimator = tokenEstimator
    }

    // MARK: - AgentMemory Conformance

    public func add(_ message: MemoryMessage) async {
        messages.append(message)

        // Trim oldest messages if over limit
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
    }

    public func context(for _: String, tokenLimit: Int) async -> String {
        MemoryMessage.formatContext(messages, tokenLimit: tokenLimit, tokenEstimator: tokenEstimator)
    }

    public func allMessages() async -> [MemoryMessage] {
        messages
    }

    public func clear() async {
        messages.removeAll()
    }

    // MARK: Private

    /// Token estimator for context retrieval.
    private let tokenEstimator: any TokenEstimator

    /// Internal message storage.
    private var messages: [MemoryMessage] = []
}

// MARK: - Batch Operations

public extension ConversationMemory {
    /// Adds multiple messages at once.
    ///
    /// More efficient than adding messages individually when importing
    /// conversation history.
    ///
    /// - Parameter newMessages: Messages to add in order.
    func addAll(_ newMessages: [MemoryMessage]) async {
        messages.append(contentsOf: newMessages)

        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
    }

    /// Returns the most recent N messages.
    ///
    /// - Parameter n: Number of messages to return.
    /// - Returns: Array of recent messages (may be fewer than N if memory has less).
    func getRecentMessages(_ n: Int) async -> [MemoryMessage] {
        Array(messages.suffix(min(n, messages.count)))
    }

    /// Returns the oldest N messages.
    ///
    /// - Parameter n: Number of messages to return.
    /// - Returns: Array of oldest messages (may be fewer than N if memory has less).
    func getOldestMessages(_ n: Int) async -> [MemoryMessage] {
        Array(messages.prefix(min(n, messages.count)))
    }
}

// MARK: - Query Operations

public extension ConversationMemory {
    /// Returns the most recent message, if any.
    var lastMessage: MemoryMessage? {
        messages.last
    }

    /// Returns the first message, if any.
    var firstMessage: MemoryMessage? {
        messages.first
    }

    /// Returns messages matching a predicate.
    ///
    /// - Parameter predicate: Closure to test each message.
    /// - Returns: Array of messages where predicate returns true.
    func filter(_ predicate: @Sendable (MemoryMessage) -> Bool) async -> [MemoryMessage] {
        messages.filter(predicate)
    }

    /// Returns messages with a specific role.
    ///
    /// - Parameter role: The role to filter by.
    /// - Returns: Array of messages with the specified role.
    func messages(withRole role: MemoryMessage.Role) async -> [MemoryMessage] {
        messages.filter { $0.role == role }
    }
}

// MARK: - Diagnostic Information

public extension ConversationMemory {
    /// Returns diagnostic information about memory state.
    func diagnostics() async -> ConversationMemoryDiagnostics {
        ConversationMemoryDiagnostics(
            messageCount: messages.count,
            maxMessages: maxMessages,
            utilizationPercent: Double(messages.count) / Double(maxMessages) * 100,
            oldestTimestamp: messages.first?.timestamp,
            newestTimestamp: messages.last?.timestamp
        )
    }
}

// MARK: - ConversationMemoryDiagnostics

/// Diagnostic information for conversation memory.
public struct ConversationMemoryDiagnostics: Sendable {
    /// Current number of messages stored.
    public let messageCount: Int
    /// Maximum messages allowed.
    public let maxMessages: Int
    /// Percentage of capacity used.
    public let utilizationPercent: Double
    /// Timestamp of the oldest message.
    public let oldestTimestamp: Date?
    /// Timestamp of the newest message.
    public let newestTimestamp: Date?
}
