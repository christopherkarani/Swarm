// PersistentMemory.swift
// Swarm Framework
//
// Generic persistent memory using pluggable backends.

import Foundation

/// A persistent memory implementation that delegates to a backend.
///
/// Use this to create persistent memory with any backend:
/// - `InMemoryBackend` for testing
/// - `SwiftDataBackend` for Apple platforms
/// - Custom backends for servers (PostgreSQL, Redis, etc.)
///
/// ## Usage
///
/// ```swift
/// // Testing/development
/// let backend = InMemoryBackend()
/// let memory = PersistentMemory(backend: backend)
///
/// // Apple platforms
/// #if canImport(SwiftData)
/// let backend = try SwiftDataBackend.persistent()
/// let memory = PersistentMemory(backend: backend)
/// #endif
///
/// // Server with custom backend
/// let backend = PostgreSQLBackend(connectionString: "...")
/// let memory = PersistentMemory(backend: backend)
/// ```
public actor PersistentMemory: Memory {
    // MARK: Public

    /// The conversation ID for this memory instance.
    public let conversationId: String

    /// Maximum messages to retain (0 = unlimited).
    public let maxMessages: Int

    /// Token estimator for context formatting.
    public let tokenEstimator: any TokenEstimator

    public var count: Int {
        get async {
            do {
                return try await backend.messageCount(conversationId: conversationId)
            } catch {
                return 0
            }
        }
    }

    public var isEmpty: Bool {
        get async {
            do {
                let messageCount = try await backend.messageCount(conversationId: conversationId)
                return messageCount == 0
            } catch {
                return true
            }
        }
    }

    /// Creates a new persistent memory.
    ///
    /// - Parameters:
    ///   - backend: The storage backend to use.
    ///   - conversationId: Unique identifier for this conversation.
    ///   - maxMessages: Maximum messages to retain (0 = unlimited).
    ///   - tokenEstimator: Estimator used by ``context(for:tokenLimit:)``.
    ///     Defaults to ``CharacterBasedTokenEstimator`` (~4 characters per token).
    public init(
        backend: any PersistentMemoryBackend,
        conversationId: String = UUID().uuidString,
        maxMessages: Int = 0,
        tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared
    ) {
        self.backend = backend
        self.conversationId = conversationId
        self.maxMessages = maxMessages
        self.tokenEstimator = tokenEstimator
    }

    // MARK: - AgentMemory Protocol

    public func add(_ message: MemoryMessage) async {
        do {
            try await backend.store(message, conversationId: conversationId)

            if maxMessages > 0 {
                await trimToMaxMessages()
            }
        } catch {
            Log.memory.error("PersistentMemory: Failed to store message: \(error.localizedDescription)")
        }
    }

    public func context(for _: String, tokenLimit: Int) async -> String {
        let messages = await allMessages()
        return MemoryMessage.formatContext(
            messages,
            tokenLimit: tokenLimit,
            tokenEstimator: tokenEstimator
        )
    }

    public func allMessages() async -> [MemoryMessage] {
        do {
            return try await backend.fetchMessages(conversationId: conversationId)
        } catch {
            Log.memory.error("PersistentMemory: Failed to fetch messages: \(error.localizedDescription)")
            return []
        }
    }

    public func clear() async {
        do {
            try await backend.deleteMessages(conversationId: conversationId)
        } catch {
            Log.memory.error("PersistentMemory: Failed to clear messages: \(error.localizedDescription)")
        }
    }

    // MARK: - Additional Methods

    /// Retrieves the N most recent messages.
    ///
    /// - Parameter limit: Maximum number of messages to retrieve.
    /// - Returns: Array of recent messages.
    public func getRecentMessages(limit: Int) async -> [MemoryMessage] {
        do {
            return try await backend.fetchRecentMessages(
                conversationId: conversationId,
                limit: limit
            )
        } catch {
            Log.memory.error("PersistentMemory: Failed to fetch recent messages: \(error.localizedDescription)")
            return []
        }
    }

    /// Adds multiple messages in a single batch operation.
    ///
    /// - Parameter messages: The messages to add.
    public func addAll(_ messages: [MemoryMessage]) async {
        do {
            try await backend.storeAll(messages, conversationId: conversationId)

            if maxMessages > 0 {
                await trimToMaxMessages()
            }
        } catch {
            Log.memory.error("PersistentMemory: Failed to store messages: \(error.localizedDescription)")
        }
    }

    // MARK: Private

    private let backend: any PersistentMemoryBackend

    // MARK: - Private Helpers

    private func trimToMaxMessages() async {
        guard maxMessages > 0 else { return }

        do {
            let currentCount = try await backend.messageCount(conversationId: conversationId)
            guard currentCount > maxMessages else { return }

            // Use backend's optimized deletion method
            try await backend.deleteOldestMessages(
                conversationId: conversationId,
                keepRecent: maxMessages
            )

            Log.memory.debug("Trimmed memory from \(currentCount) to \(maxMessages) messages")
        } catch {
            Log.memory.error("PersistentMemory: Failed to trim messages: \(error.localizedDescription)")
        }
    }
}
