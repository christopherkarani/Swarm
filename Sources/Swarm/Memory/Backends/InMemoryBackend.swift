// InMemoryBackend.swift
// Swarm Framework
//
// In-memory implementation of PersistentMemoryBackend.

import Foundation

/// In-memory implementation of `PersistentMemoryBackend`.
///
/// Useful for:
/// - Testing without database dependencies
/// - Stateless server deployments
/// - Development and prototyping
///
/// **In-memory storage does not survive process exit.** All conversations
/// are discarded when the process terminates. Use ``SwiftDataBackend`` or a
/// custom disk/database ``PersistentMemoryBackend`` for durable storage.
///
/// ## Usage
///
/// ```swift
/// let backend = InMemoryBackend()
/// let memory = PersistentMemory(backend: backend)
///
/// await memory.add(.user("Hello"))
/// let messages = await memory.allMessages()
/// ```
public actor InMemoryBackend: PersistentMemoryBackend {
    // MARK: Public

    /// Returns total message count across all conversations.
    public var totalMessageCount: Int {
        storage.values.reduce(0) { $0 + $1.count }
    }

    /// Returns the number of conversations.
    public var conversationCount: Int {
        storage.count
    }

    /// Creates a new in-memory backend.
    public init() {}

    // MARK: - PersistentMemoryBackend Protocol

    public func store(_ message: MemoryMessage, conversationId: String) async throws {
        let stored = StoredMessage(message: message, timestamp: Date())
        storage[conversationId, default: []].append(stored)
    }

    public func fetchMessages(conversationId: String) async throws -> [MemoryMessage] {
        let stored = storage[conversationId] ?? []
        return stored.map(\.message)
    }

    public func fetchRecentMessages(conversationId: String, limit: Int) async throws -> [MemoryMessage] {
        let stored = storage[conversationId] ?? []
        let recent = stored.suffix(limit)
        return recent.map(\.message)
    }

    public func deleteMessages(conversationId: String) async throws {
        storage.removeValue(forKey: conversationId)
    }

    public func messageCount(conversationId: String) async throws -> Int {
        storage[conversationId]?.count ?? 0
    }

    public func allConversationIds() async throws -> [String] {
        Array(storage.keys).sorted()
    }

    public func storeAll(_ messages: [MemoryMessage], conversationId: String) async throws {
        let timestamp = Date()
        let stored = messages.map { StoredMessage(message: $0, timestamp: timestamp) }
        storage[conversationId, default: []].append(contentsOf: stored)
    }

    public func deleteOldestMessages(conversationId: String, keepRecent: Int) async throws {
        guard var messages = storage[conversationId], messages.count > keepRecent else { return }
        // Keep only the most recent N messages
        messages = Array(messages.suffix(keepRecent))
        storage[conversationId] = messages
    }

    public func deleteLastMessage(conversationId: String) async throws -> MemoryMessage? {
        guard var messages = storage[conversationId], !messages.isEmpty else {
            return nil
        }

        // O(1) operation: remove and return the last element
        let lastStored = messages.removeLast()
        storage[conversationId] = messages

        return lastStored.message
    }

    // MARK: - Additional Convenience Methods

    /// Clears all data from all conversations.
    public func clearAll() async {
        storage.removeAll()
    }

    // MARK: Private

    /// Internal storage representation with timestamp.
    private struct StoredMessage: Sendable {
        let message: MemoryMessage
        let timestamp: Date
    }

    private var storage: [String: [StoredMessage]] = [:]
}
