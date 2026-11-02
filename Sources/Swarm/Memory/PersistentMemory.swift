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
///
/// ## Backend Failures
///
/// The ``Memory`` protocol methods cannot throw, so they fall back to an
/// empty result on backend failure (documented per member) and record the
/// error in ``lastFailure``. Use the throwing variants — ``store(_:)``,
/// ``storeAll(_:)``, ``messageCount()``, ``fetchMessages()``, and
/// ``deleteMessages()`` — when a caller must tell "empty" apart from
/// "backend unavailable".
public actor PersistentMemory: Memory {
    // MARK: Public

    /// The conversation ID for this memory instance.
    public let conversationId: String

    /// Maximum messages to retain (0 = unlimited).
    public let maxMessages: Int

    /// Token estimator for context formatting.
    public let tokenEstimator: any TokenEstimator

    /// Number of stored messages.
    ///
    /// Returns `0` when the backend fails, recording the error in
    /// ``lastFailure``. Use ``messageCount()`` to receive the error instead.
    public var count: Int {
        get async {
            await recovering(.count, fallback: 0) {
                try await messageCount()
            }
        }
    }

    /// Whether no messages are stored.
    ///
    /// Returns `true` when the backend fails, recording the error in
    /// ``lastFailure``; a `true` result with a non-`nil` ``lastFailure`` means
    /// "unknown", not "empty". Use ``messageCount()`` to receive the error.
    public var isEmpty: Bool {
        get async { await count == 0 }
    }

    /// The most recent backend failure, or `nil` while the backend is healthy.
    ///
    /// Set whenever a non-throwing member (``add(_:)``, ``count``,
    /// ``allMessages()``, …) swallows a backend error, and cleared by the next
    /// backend operation that succeeds. The throwing variants propagate their
    /// errors and update this value the same way.
    public private(set) var lastFailure: PersistentMemoryFailure?

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

    /// Stores a message, trimming to ``maxMessages`` when set.
    ///
    /// On backend failure the message is not stored; the error is logged and
    /// recorded in ``lastFailure``. Use ``store(_:)`` to receive the error.
    public func add(_ message: MemoryMessage) async {
        await recovering(.store, fallback: ()) {
            try await store(message)
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

    /// All stored messages, oldest first.
    ///
    /// Returns `[]` when the backend fails, recording the error in
    /// ``lastFailure``. Use ``fetchMessages()`` to receive the error.
    public func allMessages() async -> [MemoryMessage] {
        await recovering(.fetch, fallback: []) {
            try await fetchMessages()
        }
    }

    /// Deletes all messages for this conversation.
    ///
    /// On backend failure the error is logged and recorded in
    /// ``lastFailure``. Use ``deleteMessages()`` to receive the error.
    public func clear() async {
        await recovering(.clear, fallback: ()) {
            try await deleteMessages()
        }
    }

    // MARK: - Throwing Variants

    /// Stores a message and propagates backend errors.
    ///
    /// Trims to ``maxMessages`` after a successful store when set. A trim
    /// failure does not throw (the message is already stored); it is logged
    /// and recorded in ``lastFailure``.
    /// - Throws: The backend's store error.
    public func store(_ message: MemoryMessage) async throws {
        try await tracking(.store) {
            try await backend.store(message, conversationId: conversationId)
        }
        await trimToMaxMessages()
    }

    /// Stores messages in one batch and propagates backend errors.
    ///
    /// Trims to ``maxMessages`` after a successful store when set. A trim
    /// failure does not throw (the message is already stored); it is logged
    /// and recorded in ``lastFailure``.
    /// - Throws: The backend's store error.
    public func storeAll(_ messages: [MemoryMessage]) async throws {
        try await tracking(.store) {
            try await backend.storeAll(messages, conversationId: conversationId)
        }
        await trimToMaxMessages()
    }

    /// The number of stored messages, propagating backend errors.
    public func messageCount() async throws -> Int {
        try await tracking(.count) {
            try await backend.messageCount(conversationId: conversationId)
        }
    }

    /// All stored messages, oldest first, propagating backend errors.
    public func fetchMessages() async throws -> [MemoryMessage] {
        try await tracking(.fetch) {
            try await backend.fetchMessages(conversationId: conversationId)
        }
    }

    /// Deletes all messages for this conversation, propagating backend errors.
    public func deleteMessages() async throws {
        try await tracking(.clear) {
            try await backend.deleteMessages(conversationId: conversationId)
        }
    }

    // MARK: - Additional Methods

    /// Retrieves the N most recent messages.
    ///
    /// Returns `[]` when the backend fails, recording the error in
    /// ``lastFailure``.
    ///
    /// - Parameter limit: Maximum number of messages to retrieve.
    /// - Returns: Array of recent messages.
    public func getRecentMessages(limit: Int) async -> [MemoryMessage] {
        await recovering(.fetch, fallback: []) {
            try await tracking(.fetch) {
                try await backend.fetchRecentMessages(conversationId: conversationId, limit: limit)
            }
        }
    }

    /// Adds multiple messages in a single batch operation.
    ///
    /// On backend failure the error is logged and recorded in
    /// ``lastFailure``. Use ``storeAll(_:)`` to receive the error.
    ///
    /// - Parameter messages: The messages to add.
    public func addAll(_ messages: [MemoryMessage]) async {
        await recovering(.store, fallback: ()) {
            try await storeAll(messages)
        }
    }

    // MARK: Private

    private let backend: any PersistentMemoryBackend

    // MARK: - Private Helpers

    /// Runs a backend operation, updating ``lastFailure`` from its outcome.
    private func tracking<T: Sendable>(
        _ operation: PersistentMemoryFailure.Operation,
        _ body: () async throws -> T
    ) async throws -> T {
        do {
            let value = try await body()
            lastFailure = nil
            return value
        } catch {
            lastFailure = PersistentMemoryFailure(operation: operation, error: error)
            throw error
        }
    }

    /// Runs an already-tracked operation for a non-throwing member, logging
    /// failures and returning `fallback`. `body` must record its own outcome
    /// via ``tracking(_:_:)`` so a nested failure (e.g. a trim after a
    /// successful store) is not overwritten here.
    private func recovering<T: Sendable>(
        _ operation: PersistentMemoryFailure.Operation,
        fallback: T,
        _ body: () async throws -> T
    ) async -> T {
        do {
            return try await body()
        } catch {
            Log.memory.error("PersistentMemory: \(operation.rawValue) failed: \(error.localizedDescription)")
            return fallback
        }
    }

    private func trimToMaxMessages() async {
        guard maxMessages > 0 else { return }

        await recovering(.trim, fallback: ()) {
            try await tracking(.trim) {
                let currentCount = try await backend.messageCount(conversationId: conversationId)
                guard currentCount > maxMessages else { return }

                // Use backend's optimized deletion method
                try await backend.deleteOldestMessages(
                    conversationId: conversationId,
                    keepRecent: maxMessages
                )

                Log.memory.debug("Trimmed memory from \(currentCount) to \(maxMessages) messages")
            }
        }
    }
}

// MARK: - PersistentMemoryFailure

/// A backend failure recorded by ``PersistentMemory``.
///
/// Read it from ``PersistentMemory/lastFailure`` to tell an empty memory
/// apart from one whose backend is unavailable.
public struct PersistentMemoryFailure: Sendable, Equatable {
    /// The memory operation that failed.
    public enum Operation: String, Sendable, Equatable {
        /// Storing one or more messages.
        case store
        /// Fetching messages.
        case fetch
        /// Counting messages (also backs `isEmpty`).
        case count
        /// Deleting the conversation's messages.
        case clear
        /// Trimming to `maxMessages` after a store.
        case trim
    }

    /// The memory operation that failed.
    public let operation: Operation

    /// The backend error's localized description.
    public let message: String

    /// Creates a failure record.
    /// - Parameters:
    ///   - operation: The memory operation that failed.
    ///   - message: Human-readable description of the backend error.
    public init(operation: Operation, message: String) {
        self.operation = operation
        self.message = message
    }

    init(operation: Operation, error: any Error) {
        self.init(operation: operation, message: error.localizedDescription)
    }
}
