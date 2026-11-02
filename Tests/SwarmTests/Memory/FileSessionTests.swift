// FileSessionTests.swift
// SwarmTests
//
// Tests for the file-backed cross-platform session.

import Foundation
@testable import Swarm
import Testing

@Suite("FileSession")
struct FileSessionTests {
    @Test("History survives across instances with the same ID")
    func historySurvivesAcrossInstances() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        let session = FileSession(sessionId: "file-1", directory: directory)
        try await session.addItem(.user("remember me"))
        #expect(await session.itemCount == 1)

        let resumed = FileSession(sessionId: "file-1", directory: directory)
        #expect(try await resumed.getAllItems().map(\.content) == ["remember me"])
        #expect(try await resumed.getItemCount() == 1)
    }

    @Test("Missing file starts empty")
    func missingFileStartsEmpty() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        let session = FileSession(sessionId: "file-new", directory: directory)
        #expect(await session.isEmpty)
        #expect(try await session.popItem() == nil)
    }

    @Test("Mutations persist through pop and clear")
    func mutationsPersist() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        let session = FileSession(sessionId: "file-2", directory: directory)
        try await session.addItems([.user("a"), .user("b")])
        _ = try await session.popItem()

        let reloaded = FileSession(sessionId: "file-2", directory: directory)
        #expect(try await reloaded.getAllItems().map(\.content) == ["a"])

        try await reloaded.clearSession()
        let cleared = FileSession(sessionId: "file-2", directory: directory)
        #expect(await cleared.isEmpty)
    }

    @Test("Stored file is inspectable snapshot JSON")
    func storedFileIsSnapshotJSON() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        let session = FileSession(sessionId: "file-3", directory: directory)
        try await session.addItem(.user("visible"))

        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        #expect(contents.count == 1)
        let data = try Data(contentsOf: contents[0])
        let snapshot = try SessionSnapshot(encoded: data)
        #expect(snapshot.sessionId == "file-3")
        #expect(snapshot.items.map(\.content) == ["visible"])
    }

    @Test("Foreign snapshot data is rejected")
    func foreignSnapshotDataRejected() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        let writer = FileSession(sessionId: "file-4", directory: directory)
        try await writer.addItem(.user("mine"))
        let data = try await writer.snapshotData()

        let other = FileSession(sessionId: "file-other", directory: directory)
        await #expect(throws: SessionError.self) {
            try await other.restore(from: data)
        }
    }

    @Test("Corrupt files surface retrieval failures")
    func corruptFileSurfacesRetrievalFailure() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        let url = directory.appendingPathComponent("file-bad.json")
        try Data("{{bad json".utf8).write(to: url)

        let session = FileSession(sessionId: "file-bad", directory: directory)
        await #expect(throws: SessionError.self) {
            try await session.getAllItems()
        }
    }

    @Test("Hostile session IDs cannot escape the directory")
    func hostileIDsStayInDirectory() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        let session = FileSession(sessionId: "../../escape", directory: directory)
        try await session.addItem(.user("x"))

        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        #expect(contents.count == 1)
        #expect(contents[0].lastPathComponent.contains("/") == false)
        let resumed = FileSession(sessionId: "../../escape", directory: directory)
        #expect(try await resumed.getAllItems().count == 1)
    }

    @Test("A corrupt file is never overwritten by later writes")
    func corruptFileIsNeverOverwritten() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        let session = FileSession(sessionId: "file-corrupt", directory: directory)
        let original = Data("{{not a snapshot".utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try original.write(to: session.fileURL)

        // The first add fails to load; the second must not treat the session
        // as loaded-and-empty and replace the file.
        await #expect(throws: SessionError.self) {
            try await session.addItem(.user("first"))
        }
        await #expect(throws: SessionError.self) {
            try await session.addItem(.user("second"))
        }
        await #expect(throws: SessionError.self) {
            try await session.clearSession()
        }

        #expect(try Data(contentsOf: session.fileURL) == original)
    }

    @Test("IDs that sanitize to the same name use distinct files")
    func sanitizerCollisionsUseDistinctFiles() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        let slash = FileSession(sessionId: "user/1", directory: directory)
        let underscore = FileSession(sessionId: "user_1", directory: directory)
        #expect(slash.fileURL != underscore.fileURL)

        try await slash.addItem(.user("from slash"))
        try await underscore.addItem(.user("from underscore"))

        let reloadedSlash = FileSession(sessionId: "user/1", directory: directory)
        let reloadedUnderscore = FileSession(sessionId: "user_1", directory: directory)
        #expect(try await reloadedSlash.getAllItems().map(\.content) == ["from slash"])
        #expect(try await reloadedUnderscore.getAllItems().map(\.content) == ["from underscore"])
    }

    @Test("Legacy sanitized-name files are still read and migrated")
    func legacyFilesAreReadAndMigrated() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        let legacyURL = directory.appendingPathComponent("legacy-1.json")
        let snapshot = SessionSnapshot(sessionId: "legacy-1", items: [.user("old history")])
        try snapshot.encoded().write(to: legacyURL)

        let session = FileSession(sessionId: "legacy-1", directory: directory)
        #expect(try await session.getAllItems().map(\.content) == ["old history"])

        try await session.addItem(.user("new"))
        #expect(FileManager.default.fileExists(atPath: session.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))

        let reloaded = FileSession(sessionId: "legacy-1", directory: directory)
        #expect(try await reloaded.getAllItems().map(\.content) == ["old history", "new"])
    }

    @Test("A legacy file owned by a colliding ID is ignored, not adopted")
    func legacyFileOfCollidingIDIsIgnored() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        // Legacy layout stored "user/1" at user_1.json.
        let legacyURL = directory.appendingPathComponent("user_1.json")
        let legacyBytes = try SessionSnapshot(sessionId: "user/1", items: [.user("slash history")]).encoded()
        try legacyBytes.write(to: legacyURL)

        let underscore = FileSession(sessionId: "user_1", directory: directory)
        #expect(try await underscore.getAllItems().isEmpty)
        try await underscore.addItem(.user("underscore history"))

        #expect(try Data(contentsOf: legacyURL) == legacyBytes)
        let slash = FileSession(sessionId: "user/1", directory: directory)
        #expect(try await slash.getAllItems().map(\.content) == ["slash history"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-file-session-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
