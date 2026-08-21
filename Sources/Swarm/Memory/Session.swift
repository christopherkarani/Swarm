// Session.swift
// Swarm Framework
//
// Protocol defining session-based conversation history management.

import Foundation

// MARK: - Session

/// Protocol for managing conversation session history.
///
/// Sessions provide automatic conversation history management across agent runs,
/// enabling multi-turn conversations without manual history tracking.
///
/// Conforming types must be actors to ensure thread-safe access to session data.
///
/// ## Example Usage
/// ```swift
/// let session = InMemorySession()
///
/// // Add messages to session
/// try await session.addItem(.user("Hello!"))
/// try await session.addItem(.assistant("Hi there!"))
///
/// // Retrieve conversation history
/// let history = try await session.getAllItems()
///
/// // Get recent messages only
/// let recent = try await session.getItems(limit: 5)
/// ```
public protocol Session: Actor, Sendable {
    /// Unique identifier for this session.
    ///
    /// Session IDs are used to distinguish between different conversation contexts
    /// and should remain constant throughout the session's lifecycle.
    ///
    /// This property is `nonisolated` because session IDs are immutable and can
    /// be safely accessed without actor isolation.
    nonisolated var sessionId: String { get }

    /// Number of items currently stored in the session.
    ///
    /// This property provides efficient access to the item count without
    /// needing to retrieve all items.
    var itemCount: Int { get async }

    /// Whether the session contains no items.
    ///
    /// Returns `true` if `itemCount` is zero, `false` otherwise.
    var isEmpty: Bool { get async }

    /// Retrieves the item count with proper error propagation.
    ///
    /// Unlike `itemCount`, this method throws on backend errors, allowing callers
    /// to distinguish between an empty session and a backend failure.
    ///
    /// - Returns: The number of items in the session.
    /// - Throws: `SessionError` if the backend operation fails.
    func getItemCount() async throws -> Int

    /// Retrieves conversation history from the session.
    ///
    /// Items are returned in chronological order (oldest first).
    /// When a limit is specified, returns the most recent N items
    /// while still maintaining chronological order.
    ///
    /// - Parameter limit: Maximum number of items to retrieve.
    ///   - `nil`: Returns all items
    ///   - Positive value: Returns the last N items in chronological order
    ///   - Zero or negative: Returns an empty array
    /// - Returns: Array of messages in chronological order.
    /// - Throws: If retrieval fails due to underlying storage issues.
    func getItems(limit: Int?) async throws -> [MemoryMessage]

    /// Adds items to the conversation history.
    ///
    /// Items are appended to the session in the order they appear in the array,
    /// maintaining the conversation's chronological sequence.
    ///
    /// - Parameter items: Messages to add to the session.
    /// - Throws: If storage operation fails.
    func addItems(_ items: [MemoryMessage]) async throws

    /// Removes and returns the most recent item from the session.
    ///
    /// Follows LIFO (Last-In-First-Out) semantics, removing the last added item.
    /// This is useful for undoing the last message or implementing retry logic.
    ///
    /// - Returns: The removed message, or `nil` if the session is empty.
    /// - Throws: If removal operation fails.
    func popItem() async throws -> MemoryMessage?

    /// Clears all items from this session.
    ///
    /// The session ID remains unchanged after clearing, allowing the session
    /// to be reused for new conversations.
    ///
    /// - Throws: If clear operation fails.
    func clearSession() async throws

    /// Creates an isolated copy of this session for conversation branching.
    func branchConversationSession() async throws -> any Session
}

// MARK: - SessionError

/// Errors that can occur during session operations.
public enum SessionError: Error, Sendable {
    /// Failed to retrieve items from the session.
    /// - Parameters:
    ///   - reason: Human-readable description of what went wrong.
    ///   - underlyingError: The original error that caused the failure, if any.
    case retrievalFailed(reason: String, underlyingError: String? = nil)

    /// Failed to store items in the session.
    case storageFailed(reason: String, underlyingError: String? = nil)

    /// Failed to delete items from the session.
    case deletionFailed(reason: String, underlyingError: String? = nil)

    /// Session is in an invalid state.
    case invalidState(reason: String)

    /// Backend operation failed.
    case backendError(reason: String, underlyingError: String? = nil)
}

// MARK: Equatable

extension SessionError: Equatable {
    public static func == (lhs: SessionError, rhs: SessionError) -> Bool {
        switch (lhs, rhs) {
        case let (.retrievalFailed(r1, u1), .retrievalFailed(r2, u2)):
            r1 == r2 && u1 == u2
        case let (.storageFailed(r1, u1), .storageFailed(r2, u2)):
            r1 == r2 && u1 == u2
        case let (.deletionFailed(r1, u1), .deletionFailed(r2, u2)):
            r1 == r2 && u1 == u2
        case let (.invalidState(r1), .invalidState(r2)):
            r1 == r2
        case let (.backendError(r1, u1), .backendError(r2, u2)):
            r1 == r2 && u1 == u2
        default:
            false
        }
    }
}

// MARK: LocalizedError

extension SessionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .retrievalFailed(reason, underlying):
            if let underlying {
                return "Failed to retrieve session items: \(reason). Underlying: \(underlying)"
            }
            return "Failed to retrieve session items: \(reason)"

        case let .storageFailed(reason, underlying):
            if let underlying {
                return "Failed to store session items: \(reason). Underlying: \(underlying)"
            }
            return "Failed to store session items: \(reason)"

        case let .deletionFailed(reason, underlying):
            if let underlying {
                return "Failed to delete session items: \(reason). Underlying: \(underlying)"
            }
            return "Failed to delete session items: \(reason)"

        case let .invalidState(reason):
            return "Session in invalid state: \(reason)"

        case let .backendError(reason, underlying):
            if let underlying {
                return "Session backend error: \(reason). Underlying: \(underlying)"
            }
            return "Session backend error: \(reason)"
        }
    }
}

// MARK: - Default Extension Methods

public extension Session {
    /// Adds a single item to the conversation history.
    ///
    /// This is a convenience method that wraps a single message in an array
    /// and delegates to `addItems(_:)`.
    ///
    /// - Parameter item: The message to add.
    /// - Throws: If storage operation fails.
    func addItem(_ item: MemoryMessage) async throws {
        try await addItems([item])
    }

    /// Retrieves all items from the session.
    ///
    /// This is a convenience method equivalent to calling `getItems(limit: nil)`.
    ///
    /// - Returns: All messages in chronological order.
    /// - Throws: If retrieval fails.
    func getAllItems() async throws -> [MemoryMessage] {
        try await getItems(limit: nil)
    }

    /// Default implementation that delegates to itemCount.
    ///
    /// Implementations should override this for proper error handling.
    func getItemCount() async throws -> Int {
        await itemCount
    }

    func branchConversationSession() async throws -> any Session {
        let branched = InMemorySession()
        let items = try await getAllItems()
        try await branched.addItems(items)
        return branched
    }
}
