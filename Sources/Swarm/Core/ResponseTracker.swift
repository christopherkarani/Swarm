// ResponseTracker.swift
// Swarm Framework
//
// Tracks agent responses for conversation continuation with bounded storage.

import Foundation
import Logging

// MARK: - SessionMetadata

/// Information about a session's activity.
///
/// Contains metadata about when a session was last accessed,
/// useful for session lifecycle management and cleanup decisions.
public struct SessionMetadata: Sendable, Equatable {
    /// The session identifier.
    public let sessionId: String

    /// The last time the session was accessed (response recorded).
    public let lastAccessTime: Date

    /// The number of responses currently tracked for this session.
    public let responseCount: Int

    /// Creates session metadata.
    ///
    /// - Parameters:
    ///   - sessionId: The session identifier.
    ///   - lastAccessTime: The last access timestamp.
    ///   - responseCount: The number of responses tracked.
    public init(sessionId: String, lastAccessTime: Date, responseCount: Int) {
        self.sessionId = sessionId
        self.lastAccessTime = lastAccessTime
        self.responseCount = responseCount
    }
}

// MARK: - ResponseTracker

/// Tracks agent responses for conversation continuation.
///
/// `ResponseTracker` maintains a bounded history of agent responses per session,
/// enabling conversation continuation across multiple interactions. The tracker
/// automatically manages memory by trimming oldest responses when limits are exceeded.
///
/// ## Bounded Storage
///
/// History is automatically trimmed to prevent unbounded memory growth.
/// When the limit is exceeded, oldest responses are removed first (FIFO).
/// The default limit is 100 responses per session, configurable at initialization.
///
/// ## Session Isolation
///
/// Each session maintains its own independent history. Sessions are identified
/// by string IDs, allowing flexible session management strategies.
///
/// ## Thread Safety
///
/// `ResponseTracker` is implemented as an actor, ensuring thread-safe access
/// to response history from concurrent contexts.
///
/// ## Example
///
/// ```swift
/// let tracker = ResponseTracker()
///
/// // Record responses for a session
/// await tracker.recordResponse(response1, sessionId: "user_123")
/// await tracker.recordResponse(response2, sessionId: "user_123")
///
/// // Get latest response ID for continuation
/// if let latestId = await tracker.getLatestResponseId(for: "user_123") {
///     print("Latest response: \(latestId)")
/// }
///
/// // Retrieve specific response
/// if let response = await tracker.getResponse(responseId: latestId, sessionId: "user_123") {
///     print("Output: \(response.output)")
/// }
///
/// // Get recent history
/// let history = await tracker.getHistory(for: "user_123", limit: 10)
/// for response in history {
///     print("\(response.agentName): \(response.output)")
/// }
///
/// // Clear when done
/// await tracker.clearHistory(for: "user_123")
/// ```
///
/// ## Memory Management
///
/// ```swift
/// // Custom history size for memory-constrained environments
/// let compactTracker = ResponseTracker(maxHistorySize: 20)
///
/// // Record many responses - oldest are automatically removed
/// for i in 0..<50 {
///     await compactTracker.recordResponse(responses[i], sessionId: "session")
/// }
///
/// // Only the most recent 20 responses are retained
/// let count = await compactTracker.getCount(for: "session")
/// print(count)  // 20
/// ```
public actor ResponseTracker {
    // MARK: Public

    // MARK: - Public Properties

    /// Maximum number of responses to track per session.
    ///
    /// When the history exceeds this limit, the oldest responses
    /// are automatically removed to maintain the bound.
    nonisolated public let maxHistorySize: Int

    /// Maximum number of sessions to track simultaneously.
    ///
    /// When the number of sessions exceeds this limit, the least recently
    /// used (LRU) sessions are automatically evicted to prevent unbounded
    /// memory growth.
    ///
    /// Set to `nil` for unlimited sessions (use with caution in production).
    /// Default: 1000 sessions
    nonisolated public let maxSessions: Int?

    // MARK: - Initialization

    /// Creates a response tracker with the specified history and session limits.
    ///
    /// - Parameters:
    ///   - maxHistorySize: Maximum responses to store per session.
    ///     Must be greater than 0. Default: 100
    ///   - maxSessions: Maximum number of sessions to track simultaneously.
    ///     When exceeded, least recently used sessions are evicted.
    ///     Set to `nil` for unlimited sessions. Default: 1000
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Default tracker with 100 responses/session, 1000 sessions
    /// let defaultTracker = ResponseTracker()
    ///
    /// // Compact tracker for memory-constrained environments
    /// let compactTracker = ResponseTracker(maxHistorySize: 20, maxSessions: 100)
    ///
    /// // Large tracker for detailed history needs
    /// let largeTracker = ResponseTracker(maxHistorySize: 500, maxSessions: 5000)
    ///
    /// // Unlimited sessions (use with caution in production)
    /// let unlimitedTracker = ResponseTracker(maxSessions: nil)
    /// ```
    ///   - now: Clock used for time-window decisions (e.g. session cleanup).
    ///     Defaults to the module's shared wall clock. Tests inject a fake
    ///     clock so window boundaries flip without `Task.sleep`.
    public init(
        maxHistorySize: Int = 100,
        maxSessions: Int? = 1000,
        now: @escaping @Sendable () -> Date = { TurnEnvironment.live.now() }
    ) {
        if maxHistorySize < 1 {
            Log.agents.warning("ResponseTracker: maxHistorySize \(maxHistorySize) must be >= 1; using 1")
        }
        if let maxSessions, maxSessions < 1 {
            Log.agents.warning("ResponseTracker: maxSessions \(maxSessions) must be >= 1; using 1")
        }
        self.maxHistorySize = max(1, maxHistorySize)
        self.maxSessions = if let maxSessions {
            max(1, maxSessions)
        } else {
            nil
        }
        self.now = now
    }

    // MARK: - Recording

    /// Records a new response for a session.
    ///
    /// If the history exceeds `maxHistorySize` after adding the response,
    /// the oldest responses are automatically removed to maintain the bound.
    ///
    /// - Parameters:
    ///   - response: The response to record.
    ///   - sessionId: The session identifier for grouping responses.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let tracker = ResponseTracker(maxHistorySize: 3)
    ///
    /// // Record responses
    /// await tracker.recordResponse(response1, sessionId: "chat")
    /// await tracker.recordResponse(response2, sessionId: "chat")
    /// await tracker.recordResponse(response3, sessionId: "chat")
    /// await tracker.recordResponse(response4, sessionId: "chat")
    ///
    /// // Only responses 2, 3, 4 remain (response1 was trimmed)
    /// let count = await tracker.getCount(for: "chat")
    /// print(count)  // 3
    /// ```
    public func recordResponse(_ response: AgentResponse, sessionId: String) {
        guard !sessionId.isEmpty else { return }
        guard !response.responseId.isEmpty else { return }

        var history = responseHistory[sessionId] ?? []
        history.append(response)

        // CRITICAL: Trim oldest responses to prevent unbounded growth per session
        if history.count > maxHistorySize {
            history = Array(history.suffix(maxHistorySize))
        }

        responseHistory[sessionId] = history

        // Update session access time for LRU tracking.
        //
        // Prefer the response timestamp so callers can backfill/persist history with
        // meaningful access times; never allow the access time to move backwards.
        let candidate = response.timestamp
        if let existing = sessionAccessTimes[sessionId] {
            sessionAccessTimes[sessionId] = max(existing, candidate)
        } else {
            sessionAccessTimes[sessionId] = candidate
        }

        // CRITICAL: Enforce maximum session limit using LRU eviction
        if let maxSessions, sessionAccessTimes.count > maxSessions {
            evictLeastRecentlyUsedSessions(keepingMostRecent: maxSessions)
        }
    }

    // MARK: - Retrieval

    /// Gets the most recent response ID for a session.
    ///
    /// This is useful for conversation continuation, where the latest
    /// response ID can be used to reference the previous context.
    ///
    /// - Parameter sessionId: The session identifier.
    /// - Returns: The response ID of the most recent response, or `nil` if
    ///   no responses exist for the session.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Check if session has prior context
    /// if let previousResponseId = await tracker.getLatestResponseId(for: "user_123") {
    ///     // Continue conversation with reference to previous response
    ///     let request = AgentRequest(
    ///         prompt: "What else can you tell me?",
    ///         previousResponseId: previousResponseId
    ///     )
    /// }
    /// ```
    public func getLatestResponseId(for sessionId: String) -> String? {
        responseHistory[sessionId]?.last?.responseId
    }

    /// Gets a specific response by its ID within a session.
    ///
    /// - Parameters:
    ///   - responseId: The unique identifier of the response to retrieve.
    ///   - sessionId: The session identifier where the response is stored.
    /// - Returns: The matching response, or `nil` if not found.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Retrieve a specific response for analysis
    /// if let response = await tracker.getResponse(
    ///     responseId: "abc-123",
    ///     sessionId: "user_456"
    /// ) {
    ///     print("LegacyAgent: \(response.agentName)")
    ///     print("Output: \(response.output)")
    ///     print("Tool calls: \(response.toolCalls.count)")
    /// }
    /// ```
    public func getResponse(responseId: String, sessionId: String) -> AgentResponse? {
        responseHistory[sessionId]?.first { $0.responseId == responseId }
    }

    /// Gets the response history for a session.
    ///
    /// Responses are returned in chronological order (oldest first).
    /// An optional limit can be specified to retrieve only the most recent responses.
    ///
    /// - Parameters:
    ///   - sessionId: The session identifier.
    ///   - limit: Optional maximum number of responses to return.
    ///     When specified, returns the most recent `limit` responses.
    ///     When `nil`, returns all responses for the session.
    /// - Returns: Array of responses in chronological order. Empty if no
    ///   responses exist for the session.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Get all history
    /// let allHistory = await tracker.getHistory(for: "session_123")
    ///
    /// // Get only last 5 responses
    /// let recentHistory = await tracker.getHistory(for: "session_123", limit: 5)
    ///
    /// // Display conversation
    /// for response in recentHistory {
    ///     print("[\(response.agentName)] \(response.output)")
    /// }
    /// ```
    public func getHistory(for sessionId: String, limit: Int? = nil) -> [AgentResponse] {
        guard let history = responseHistory[sessionId] else {
            return []
        }

        if let limit {
            return Array(history.suffix(limit))
        }
        return history
    }

    // MARK: - Clearing

    /// Clears the response history for a specific session.
    ///
    /// This removes all tracked responses for the given session,
    /// freeing associated memory.
    ///
    /// - Parameter sessionId: The session identifier to clear.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Clear history when user logs out
    /// await tracker.clearHistory(for: "user_session_123")
    ///
    /// // Verify cleared
    /// let count = await tracker.getCount(for: "user_session_123")
    /// print(count)  // 0
    /// ```
    public func clearHistory(for sessionId: String) {
        responseHistory.removeValue(forKey: sessionId)
        sessionAccessTimes.removeValue(forKey: sessionId)
    }

    /// Clears all response history across all sessions.
    ///
    /// This is useful for application shutdown or memory pressure situations.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Clear everything on app termination
    /// await tracker.clearAllHistory()
    ///
    /// // All sessions are now empty
    /// let sessions = await tracker.getAllSessionIds()
    /// print(sessions.isEmpty)  // true
    /// ```
    public func clearAllHistory() {
        responseHistory.removeAll()
        sessionAccessTimes.removeAll()
    }

    // MARK: - Statistics

    /// Gets the count of responses tracked for a session.
    ///
    /// - Parameter sessionId: The session identifier.
    /// - Returns: Number of responses tracked, or 0 if session has no history.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let count = await tracker.getCount(for: "active_session")
    /// print("Conversation has \(count) exchanges")
    /// ```
    public func getCount(for sessionId: String) -> Int {
        responseHistory[sessionId]?.count ?? 0
    }

    /// Gets all session IDs that have recorded history.
    ///
    /// This is useful for administrative purposes such as listing
    /// active sessions or performing bulk operations.
    ///
    /// - Returns: Array of session IDs with at least one recorded response.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // List all active sessions
    /// let sessions = await tracker.getAllSessionIds()
    /// for sessionId in sessions {
    ///     let count = await tracker.getCount(for: sessionId)
    ///     print("Session \(sessionId): \(count) responses")
    /// }
    /// ```
    public func getAllSessionIds() -> [String] {
        Array(responseHistory.keys)
    }

    /// Gets the total count of responses across all sessions.
    ///
    /// - Returns: Total number of responses tracked across all sessions.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let total = await tracker.getTotalResponseCount()
    /// print("Tracking \(total) responses across all sessions")
    /// ```
    public func getTotalResponseCount() -> Int {
        responseHistory.values.reduce(0) { $0 + $1.count }
    }

    // MARK: - Session Cleanup

    /// Removes sessions that were last accessed before a specified date.
    ///
    /// This is useful for implementing time-based session expiration policies.
    /// Sessions are considered "accessed" when a response is recorded via
    /// `recordResponse(_:sessionId:)`.
    ///
    /// - Parameter date: Sessions last accessed before this date will be removed.
    /// - Returns: The number of sessions removed.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Remove sessions older than 7 days
    /// let sevenDaysAgo = Calendar.current.date(
    ///     byAdding: .day,
    ///     value: -7,
    ///     to: Date()
    /// )!
    /// let removed = await tracker.removeSessions(lastAccessedBefore: sevenDaysAgo)
    /// print("Removed \(removed) inactive sessions")
    /// ```
    ///
    /// ## Privacy Note
    ///
    /// This method permanently removes session data. Ensure your application's
    /// data retention policy allows automatic deletion before using this API.
    @discardableResult
    public func removeSessions(lastAccessedBefore date: Date) -> Int {
        let sessionsToRemove = sessionAccessTimes.filter { $0.value < date }

        for (sessionId, _) in sessionsToRemove {
            responseHistory.removeValue(forKey: sessionId)
            sessionAccessTimes.removeValue(forKey: sessionId)
        }

        return sessionsToRemove.count
    }

    /// Removes sessions that have not been accessed within a specified time interval.
    ///
    /// This is a convenience method for time-based cleanup using relative durations
    /// instead of absolute dates.
    ///
    /// - Parameter interval: Sessions not accessed within this duration will be removed.
    /// - Returns: The number of sessions removed.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Remove sessions inactive for more than 24 hours
    /// let removed = await tracker.removeSessions(notAccessedWithin: .hours(24))
    /// print("Cleaned up \(removed) stale sessions")
    ///
    /// // Remove sessions inactive for more than 30 days
    /// let removed = await tracker.removeSessions(notAccessedWithin: .days(30))
    /// ```
    @discardableResult
    public func removeSessions(notAccessedWithin interval: TimeInterval) -> Int {
        let threshold = now().addingTimeInterval(-interval)
        return removeSessions(lastAccessedBefore: threshold)
    }

    /// Gets metadata for a specific session.
    ///
    /// Returns information about when the session was last accessed and
    /// how many responses are currently tracked. Useful for implementing
    /// custom cleanup policies or session monitoring.
    ///
    /// - Parameter sessionId: The session identifier.
    /// - Returns: Session metadata, or `nil` if the session does not exist.
    ///
    /// ## Example
    ///
    /// ```swift
    /// if let metadata = await tracker.getSessionMetadata(for: "user_123") {
    ///     print("Session last active: \(metadata.lastAccessTime)")
    ///     print("Response count: \(metadata.responseCount)")
    ///
    ///     // Check if session is stale
    ///     let hoursSinceAccess = Date().timeIntervalSince(metadata.lastAccessTime) / 3600
    ///     if hoursSinceAccess > 24 {
    ///         await tracker.clearHistory(for: "user_123")
    ///     }
    /// }
    /// ```
    public func getSessionMetadata(for sessionId: String) -> SessionMetadata? {
        guard let lastAccessTime = sessionAccessTimes[sessionId],
              let responseCount = responseHistory[sessionId]?.count else {
            return nil
        }

        return SessionMetadata(
            sessionId: sessionId,
            lastAccessTime: lastAccessTime,
            responseCount: responseCount
        )
    }

    /// Gets metadata for all tracked sessions.
    ///
    /// Returns an array of session metadata sorted by last access time
    /// (most recent first). Useful for administrative dashboards or
    /// bulk cleanup operations.
    ///
    /// - Returns: Array of session metadata for all active sessions.
    ///   Empty array if no sessions are tracked.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // List all sessions sorted by activity
    /// let allSessions = await tracker.getAllSessionMetadata()
    /// for metadata in allSessions {
    ///     print("\(metadata.sessionId): \(metadata.responseCount) responses, " +
    ///           "last active \(metadata.lastAccessTime)")
    /// }
    ///
    /// // Find and remove sessions with no recent activity
    /// let staleThreshold = Date().addingTimeInterval(-7 * 24 * 3600)
    /// for metadata in allSessions where metadata.lastAccessTime < staleThreshold {
    ///     await tracker.clearHistory(for: metadata.sessionId)
    /// }
    /// ```
    public func getAllSessionMetadata() -> [SessionMetadata] {
        sessionAccessTimes.compactMap { sessionId, lastAccessTime in
            guard let responseCount = responseHistory[sessionId]?.count else {
                return nil
            }
            return SessionMetadata(
                sessionId: sessionId,
                lastAccessTime: lastAccessTime,
                responseCount: responseCount
            )
        }.sorted { $0.lastAccessTime > $1.lastAccessTime }
    }

    // MARK: Private

    // MARK: - Private Properties

    /// Clock used for time-window decisions (session cleanup). Injectable for tests.
    private let now: @Sendable () -> Date

    /// Storage for response history keyed by session ID.
    private var responseHistory: [String: [AgentResponse]] = [:]

    /// LRU tracking: maps session IDs to their last access time.
    /// Used to evict least recently used sessions when maxSessions is exceeded.
    private var sessionAccessTimes: [String: Date] = [:]

    // MARK: - Private Methods

    /// Evicts the least recently used sessions to maintain the session limit.
    ///
    /// - Parameter keepingMostRecent: Number of most recently used sessions to keep.
    private func evictLeastRecentlyUsedSessions(keepingMostRecent limit: Int) {
        // Sort sessions by access time (oldest first)
        let sortedSessions = sessionAccessTimes.sorted { $0.value < $1.value }

        // Calculate how many to evict
        let evictCount = sortedSessions.count - limit
        guard evictCount > 0 else { return }

        // Evict oldest sessions
        for (sessionId, _) in sortedSessions.prefix(evictCount) {
            responseHistory.removeValue(forKey: sessionId)
            sessionAccessTimes.removeValue(forKey: sessionId)
        }
    }
}
