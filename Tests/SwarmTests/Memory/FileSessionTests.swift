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
