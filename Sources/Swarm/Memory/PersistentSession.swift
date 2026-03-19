// PersistentSession.swift
// Swarm Framework
//
// Persistent session implementation using SwiftDataBackend.

#if canImport(SwiftData)
    import Foundation
    import SwiftData

    // MARK: - PersistentSession

    /// Persistent session implementation backed by SwiftData.
    ///
    /// `PersistentSession` stores conversation history using SwiftData,
    /// providing persistence across app launches. Data is stored either
    /// in-memory (for testing) or on disk (for production).
    ///
    /// This implementation is ideal for:
    /// - Long-running conversations that need persistence
    /// - Multi-session applications with shared backend
    /// - Production applications requiring data durability
    ///
    /// ## Thread Safety
    /// As an actor, `PersistentSession` provides automatic thread-safe access
    /// to all session data through Swift's actor isolation.
    ///
    /// ## Example Usage
    /// ```swift
    /// // Create a persistent session
    /// let session = try PersistentSession.persistent(sessionId: "user-123-chat")
    ///
    /// // Or for testing, use in-memory storage
    /// let testSession = try PersistentSession.inMemory(sessionId: "test-chat")
    ///
    /// // Add conversation messages
    /// try await session.addItem(.user("What's the weather?"))
    /// try await session.addItem(.assistant("It's sunny today!"))
    ///
    /// // Retrieve recent history
    /// let recent = try await session.getItems(limit: 10)
    /// ```
    ///
    /// ## Session Isolation
    /// Multiple sessions can share the same backend while maintaining
    /// complete data isolation through unique session IDs:
    ///
    /// ```swift
    /// let backend = try SwiftDataBackend.inMemory()
    /// let session1 = PersistentSession(sessionId: "chat-1", backend: backend)
    /// let session2 = PersistentSession(sessionId: "chat-2", backend: backend)
    ///
    /// // Each session's data is isolated from the other
    /// ```
    @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    public actor PersistentSession: Session {
        // MARK: Public

        /// Unique identifier for this session.
        ///
        /// The session ID is used as the conversation ID when storing
        /// messages in the backend, ensuring data isolation between sessions.
        nonisolated public let sessionId: String

        // MARK: - Session Protocol Properties

        /// Number of items currently stored in the session.
        ///
        /// This property queries the backend for the current message count
        /// for this session's conversation ID.
        ///
        /// - Note: This is a convenience property that returns `0` on backend errors.
        ///   The `Session` protocol defines `itemCount` as a non-throwing async property,
        ///   and Swift does not support throwing computed properties. For guaranteed
        ///   accuracy when error handling is critical, use `getItems(limit: nil)` and
        ///   check the array's count, which properly propagates errors.
        ///
        /// - Important: A return value of `0` may indicate either an empty session
        ///   or a backend error. Check logs for errors if unexpected results occur.
        public var itemCount: Int {
            get async {
                do {
                    return try await backend.messageCount(conversationId: sessionId)
                } catch {
                    let errMsg = "Failed to get item count for session '\(sessionId)'"
                    Log.memory.error("\(errMsg): \(error.localizedDescription). Returning 0.")
                    return 0
                }
            }
        }

        /// Whether the session contains no items.
        ///
        /// Returns `true` if `itemCount` is zero, `false` otherwise.
        public var isEmpty: Bool {
            get async {
                await itemCount == 0
            }
        }

        // MARK: - Initialization

        /// Creates a new persistent session with a custom backend.
        ///
        /// Use this initializer when you need to share a backend between
        /// multiple sessions or when you have a custom ModelContainer.
        ///
        /// - Parameters:
        ///   - sessionId: Unique identifier for the session.
        ///   - backend: The SwiftData backend to use for storage.
        public init(sessionId: String, backend: SwiftDataBackend) {
            self.sessionId = sessionId
            self.backend = backend
        }

        // MARK: - Factory Methods

        /// Creates a persistent session with disk storage.
        ///
        /// Data is persisted to the default SwiftData location on disk,
        /// surviving app restarts and device reboots.
        ///
        /// - Parameter sessionId: Unique identifier for the session.
        /// - Returns: A new persistent session with disk storage.
        /// - Throws: If the SwiftData container cannot be created.
        public static func persistent(sessionId: String) throws -> PersistentSession {
            let backend = try SwiftDataBackend.persistent()
            return PersistentSession(sessionId: sessionId, backend: backend)
        }

        /// Creates a persistent session with in-memory storage.
        ///
        /// Data is stored only in memory and is lost when the session
        /// is deallocated. Ideal for testing and temporary conversations.
        ///
        /// - Parameter sessionId: Unique identifier for the session.
        /// - Returns: A new persistent session with in-memory storage.
        /// - Throws: If the SwiftData container cannot be created.
        public static func inMemory(sessionId: String) throws -> PersistentSession {
            let backend = try SwiftDataBackend.inMemory()
            return PersistentSession(sessionId: sessionId, backend: backend)
        }

        /// Retrieves the item count with proper error propagation.
        ///
        /// Unlike `itemCount`, this method throws on backend errors, allowing callers
        /// to distinguish between an empty session and a backend failure.
        ///
        /// - Returns: The number of items in the session.
        /// - Throws: `SessionError.backendError` if the backend operation fails.
        public func getItemCount() async throws -> Int {
            do {
                return try await backend.messageCount(conversationId: sessionId)
            } catch {
                throw SessionError.backendError(
                    reason: "Failed to get item count for session '\(sessionId)'",
                    underlyingError: error.localizedDescription
                )
            }
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
        /// - Throws: If retrieval fails due to underlying storage issues.
        public func getItems(limit: Int?) async throws -> [MemoryMessage] {
            guard let limit else {
                // nil limit: return all messages
                return try await backend.fetchMessages(conversationId: sessionId)
            }

            guard limit > 0 else {
                // Zero or negative limit: return empty array
                return []
            }

            // Positive limit: return last N messages in chronological order
            return try await backend.fetchRecentMessages(conversationId: sessionId, limit: limit)
        }

        /// Adds items to the conversation history.
        ///
        /// Items are appended in the order they appear in the array,
        /// maintaining the conversation's chronological sequence.
        ///
        /// - Parameter items: Messages to add to the session.
        /// - Throws: If storage operation fails.
        public func addItems(_ items: [MemoryMessage]) async throws {
            try await backend.storeAll(items, conversationId: sessionId)
        }

        /// Removes and returns the most recent item from the session.
        ///
        /// Follows LIFO (Last-In-First-Out) semantics, removing the last added item.
        /// This is useful for undoing the last message or implementing retry logic.
        ///
        /// Uses an optimized O(1) operation that fetches and deletes only the last message,
        /// rather than an O(n) approach of fetching all, deleting all, and re-inserting.
        ///
        /// - Returns: The removed message, or `nil` if the session is empty.
        /// - Throws: If removal operation fails.
        public func popItem() async throws -> MemoryMessage? {
            try await backend.deleteLastMessage(conversationId: sessionId)
        }

        /// Clears all items from this session.
        ///
        /// The session ID remains unchanged after clearing, allowing the session
        /// to be reused for new conversations.
        ///
        /// - Throws: If clear operation fails.
        public func clearSession() async throws {
            try await backend.deleteMessages(conversationId: sessionId)
        }

        // MARK: Private

        /// The SwiftData backend used for persistence.
        private let backend: SwiftDataBackend
    }

    extension PersistentSession: ConversationBranchingSession {
        package func branchConversationSession() async throws -> any Session {
            let branched = PersistentSession(sessionId: UUID().uuidString, backend: backend)
            let originalItems = try await getAllItems()
            let items = originalItems.map { item in
                var metadata = item.metadata
                if metadata[SwarmTranscriptCodec.entryIDKey] == nil {
                    metadata[SwarmTranscriptCodec.entryIDKey] = item.id.uuidString
                }

                return MemoryMessage(
                    id: UUID(),
                    role: item.role,
                    content: item.content,
                    timestamp: item.timestamp,
                    metadata: metadata
                )
            }
            try await branched.addItems(items)
            return branched
        }
    }
#endif
