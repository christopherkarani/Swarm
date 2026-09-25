// SessionSnapshotTests.swift
// SwarmTests
//
// Tests for session snapshots and restore helpers.

import Foundation
@testable import Swarm
import Testing

@Suite("SessionSnapshot")
struct SessionSnapshotTests {
    @Test("Snapshot captures session ID and items in order")
    func snapshotCapturesIDAndItems() async throws {
        let session = InMemorySession(sessionId: "snap-1")
        try await session.addItem(.user("first"))
        try await session.addItem(.assistant("second"))

        let snapshot = try await session.snapshot()

        #expect(snapshot.sessionId == "snap-1")
        #expect(snapshot.schemaVersion == SessionSnapshot.currentSchemaVersion)
        #expect(snapshot.items.map(\.content) == ["first", "second"])
    }

    @Test("Snapshot data round-trips through JSON")
    func snapshotDataRoundTrips() async throws {
        let session = InMemorySession(sessionId: "snap-2")
        try await session.addItem(.user("hello"))

        let data = try await session.snapshotData()
        #expect(String(data: data, encoding: .utf8)?.contains("snap-2") == true)

        let restored = InMemorySession(sessionId: "snap-2")
        try await restored.restore(from: data)
        #expect(try await restored.getAllItems().map(\.content) == ["hello"])
    }

    @Test("Restore replaces existing items")
    func restoreReplacesItems() async throws {
        let session = InMemorySession(sessionId: "snap-3")
        try await session.addItem(.user("stale"))

        let snapshot = SessionSnapshot(sessionId: "snap-3", items: [.user("fresh")])
        try await session.restore(from: snapshot)

        #expect(try await session.getAllItems().map(\.content) == ["fresh"])
    }

    @Test("Restore rejects foreign session IDs")
    func restoreRejectsForeignID() async throws {
        let session = InMemorySession(sessionId: "snap-4")
        let foreign = SessionSnapshot(sessionId: "other", items: [.user("x")])

        await #expect(throws: SessionError.invalidState(reason: "Snapshot belongs to session 'other', not 'snap-4'")) {
            try await session.restore(from: foreign)
        }
    }

    @Test("Unknown schema versions are rejected")
    func unknownSchemaVersionRejected() throws {
        let snapshot = SessionSnapshot(sessionId: "snap-5", items: [], schemaVersion: 999)
        let data = try snapshot.encoded()

        #expect(throws: SessionError.invalidState(reason: "Unsupported session snapshot schema version 999")) {
            try SessionSnapshot(encoded: data)
        }
    }

    @Test("Malformed JSON throws a decoding error")
    func malformedJSONThrows() {
        #expect(throws: DecodingError.self) {
            try SessionSnapshot(encoded: Data("not json".utf8))
        }
    }
}
