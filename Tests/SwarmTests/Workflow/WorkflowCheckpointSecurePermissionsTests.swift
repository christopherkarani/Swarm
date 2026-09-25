#if SWARM_INTEGRATIONS
import Foundation
import HiveCore
@testable import Swarm
import Testing

@Suite("Workflow checkpoint file permissions")
struct WorkflowCheckpointSecurePermissionsTests {
    @Test("saved checkpoints and the manifest are owner-only")
    func savedCheckpointsAreOwnerOnly() async throws {
        // Not pre-created: the store creates and hardens the directory.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-checkpoint-perms-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WorkflowFileCheckpointStore(directory: directory)
        let thread = HiveThreadID("run-permissions")
        try await store.save(makeCheckpoint(thread: thread, id: "cp-1", step: 1))

        #expect(try permissions(of: directory) == 0o700)
        #expect(
            try permissions(of: directory.appendingPathComponent("workflow-run-permissions-cp-1.json")) == 0o600
        )
        #expect(
            try permissions(of: directory.appendingPathComponent(WorkflowFileCheckpointStore.manifestFileName)) == 0o600
        )
    }

    @Test("pre-existing directories keep their permissions while files are owner-only")
    func preexistingDirectoriesKeepPermissions() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)

        let store = WorkflowFileCheckpointStore(directory: directory)
        let thread = HiveThreadID("run-shared-dir")
        try await store.save(makeCheckpoint(thread: thread, id: "cp-1", step: 1))

        // The store must not chmod directories it does not own.
        #expect(try permissions(of: directory) == 0o755)
        #expect(
            try permissions(of: directory.appendingPathComponent("workflow-run-shared-dir-cp-1.json")) == 0o600
        )
    }

    @Test("migrated checkpoint files stay loadable")
    func migratedCheckpointsStayLoadable() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WorkflowFileCheckpointStore(directory: directory)
        let thread = HiveThreadID("run-migrate")
        try await store.save(makeCheckpoint(thread: thread, id: "cp-1", step: 1))

        let file = directory.appendingPathComponent("workflow-run-migrate-cp-1.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

        _ = try WorkflowCheckpointing.hardenFilePermissions(in: directory)
        #expect(try permissions(of: file) == 0o600)

        let latest = try await store.loadLatest(threadID: thread)
        #expect(latest?.id.rawValue == "cp-1")
    }
}

private func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swarm-checkpoint-perms-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func permissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let raw = attributes[.posixPermissions] as? Int ?? 0
    return raw & 0o777
}

private func makeCheckpoint(
    thread: HiveThreadID,
    id: String,
    step: Int
) -> HiveCheckpoint<WorkflowDurableSchema> {
    HiveCheckpoint(
        id: HiveCheckpointID(id),
        threadID: thread,
        runID: HiveRunID(UUID()),
        stepIndex: step,
        schemaVersion: "1",
        graphVersion: "1",
        globalDataByChannelID: [:],
        frontier: [],
        joinBarrierSeenByJoinID: [:],
        interruption: nil
    )
}
#endif
