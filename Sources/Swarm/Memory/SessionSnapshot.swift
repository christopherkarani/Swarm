// SessionSnapshot.swift
// Swarm Framework
//
// Portable session capture: save, inspect, and restore conversation state.

import Foundation

/// A portable capture of one session's conversation state.
///
/// `SessionSnapshot` is the save/restore currency for ``Session``: any
/// session can produce one via ``Session/snapshot()``, and any session
/// with the same ID can adopt one via ``Session/restore(from:)``. The
/// encoded form is stable JSON, so snapshots can be stored, inspected,
/// transferred across processes, and reloaded after a restart.
///
/// ```swift
/// let data = try await session.snapshotData()
/// // ... later, or in another process ...
/// let restored = InMemorySession(sessionId: session.sessionId)
/// try await restored.restore(from: data)
/// ```
public struct SessionSnapshot: Sendable, Equatable, Codable {
    /// Schema version written by this Swarm version.
    public static let currentSchemaVersion = 1

    /// Schema version of this snapshot.
    public let schemaVersion: Int

    /// ID of the captured session.
    public let sessionId: String

    /// When the snapshot was taken.
    public let exportedAt: Date

    /// Captured items in chronological order (oldest first).
    public let items: [MemoryMessage]

    /// Creates a snapshot.
    ///
    /// - Parameters:
    ///   - sessionId: ID of the captured session.
    ///   - items: Items in chronological order (oldest first).
    ///   - exportedAt: Capture time. Default: now.
    ///   - schemaVersion: Schema version. Default: ``currentSchemaVersion``.
    public init(
        sessionId: String,
        items: [MemoryMessage],
        exportedAt: Date = Date(),
        schemaVersion: Int = SessionSnapshot.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.sessionId = sessionId
        self.exportedAt = exportedAt
        self.items = items
    }

    /// Encodes the snapshot as stable JSON (sorted keys, ISO-8601 dates).
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Decodes a snapshot, rejecting unknown schema versions.
    ///
    /// - Parameter data: JSON produced by ``encoded()``.
    /// - Throws: `DecodingError` for malformed JSON, or
    ///   `SessionError.invalidState` for an unsupported schema version.
    public init(encoded data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(SessionSnapshot.self, from: data)
        guard snapshot.schemaVersion == Self.currentSchemaVersion else {
            throw SessionError.invalidState(
                reason: "Unsupported session snapshot schema version \(snapshot.schemaVersion)"
            )
        }
        self = snapshot
    }
}

// MARK: - Session Snapshot Helpers

public extension Session {
    /// Captures the session's current items as a snapshot.
    func snapshot() async throws -> SessionSnapshot {
        SessionSnapshot(sessionId: sessionId, items: try await getAllItems())
    }

    /// Captures the session's current items as encoded snapshot data.
    func snapshotData() async throws -> Data {
        try await snapshot().encoded()
    }

    /// Replaces the session's items with a snapshot's items.
    ///
    /// - Parameter snapshot: Snapshot to adopt. Its session ID must match
    ///   this session's ID.
    /// - Throws: `SessionError.invalidState` when the session IDs differ.
    func restore(from snapshot: SessionSnapshot) async throws {
        guard snapshot.sessionId == sessionId else {
            throw SessionError.invalidState(
                reason: "Snapshot belongs to session '\(snapshot.sessionId)', not '\(sessionId)'"
            )
        }
        try await clearSession()
        try await addItems(snapshot.items)
    }

    /// Replaces the session's items with a decoded snapshot's items.
    ///
    /// - Parameter data: JSON produced by ``snapshotData()``.
    /// - Throws: `DecodingError` for malformed JSON, or
    ///   `SessionError.invalidState` for version or session-ID mismatches.
    func restore(from data: Data) async throws {
        try await restore(from: SessionSnapshot(encoded: data))
    }
}
