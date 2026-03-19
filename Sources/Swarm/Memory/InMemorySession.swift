// InMemorySession.swift
// Swarm Framework
//
// In-memory implementation of the Session protocol.

import Foundation

// MARK: - InMemorySession

/// In-memory session implementation for testing and simple use cases.
///
/// `InMemorySession` stores conversation history in memory, providing
/// fast access for single-process applications. Data is lost when the
/// session is deallocated.
///
/// This implementation is ideal for:
/// - Unit testing and development
/// - Short-lived conversations
/// - Applications that don't require persistence
///
/// ## Thread Safety
/// As an actor, `InMemorySession` provides automatic thread-safe access
/// to all session data through Swift's actor isolation.
///
/// ## Example Usage
/// ```swift
/// // Create with auto-generated session ID
/// let session = InMemorySession()
///
/// // Or with a custom session ID
/// let customSession = InMemorySession(sessionId: "user-123-chat")
///
/// // Add conversation messages
/// try await session.addItem(.user("What's the weather?"))
/// try await session.addItem(.assistant("It's sunny today!"))
///
/// // Retrieve recent history
/// let recent = try await session.getItems(limit: 10)
/// ```
public actor InMemorySession: Session {
    // MARK: Public

    /// Unique identifier for this session.
    nonisolated public let sessionId: String

    // MARK: - Session Protocol Properties

    /// Number of items currently stored in the session.
    public var itemCount: Int {
        items.count
    }

    /// Whether the session contains no items.
    public var isEmpty: Bool {
        items.isEmpty
    }

    // MARK: - Initialization

    /// Creates a new in-memory session.
    ///
    /// - Parameter sessionId: Unique identifier for the session.
    ///   Defaults to a new UUID string if not provided.
    public init(sessionId: String = UUID().uuidString) {
        self.sessionId = sessionId
    }

    /// Retrieves the item count with proper error propagation.
    ///
    /// For in-memory sessions, this operation cannot fail, so it simply
    /// returns the current item count.
    ///
    /// - Returns: The number of items in the session.
    public func getItemCount() async throws -> Int {
        items.count
    }

    // MARK: - Session Protocol Methods

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
    public func getItems(limit: Int?) async throws -> [MemoryMessage] {
        guard let limit else {
            return items
        }

        guard limit > 0 else {
            return []
        }

        // Return last N items in chronological order
        let startIndex = max(0, items.count - limit)
        return Array(items[startIndex...])
    }

    /// Adds items to the conversation history.
    ///
    /// Items are appended in the order they appear in the array,
    /// maintaining the conversation's chronological sequence.
    ///
    /// - Parameter newItems: Messages to add to the session.
    public func addItems(_ newItems: [MemoryMessage]) async throws {
        items.append(contentsOf: newItems)
    }

    /// Removes and returns the most recent item from the session.
    ///
    /// Follows LIFO (Last-In-First-Out) semantics.
    ///
    /// - Returns: The removed message, or `nil` if the session is empty.
    public func popItem() async throws -> MemoryMessage? {
        guard !items.isEmpty else {
            return nil
        }
        return items.removeLast()
    }

    /// Clears all items from this session.
    ///
    /// The session ID remains unchanged, allowing the session to be
    /// reused for new conversations.
    public func clearSession() async throws {
        items.removeAll()
    }

    // MARK: Private

    /// Internal storage for messages.
    private var items: [MemoryMessage] = []
}

extension InMemorySession: ConversationBranchingSession {
    package func branchConversationSession() async throws -> any Session {
        let branched = InMemorySession()
        try await branched.addItems(items)
        return branched
    }
}
