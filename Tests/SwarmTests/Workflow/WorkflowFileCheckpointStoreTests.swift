#if SWARM_INTEGRATIONS
import Foundation
import HiveCore
@testable import Swarm
import Testing

@Suite("Workflow file checkpoint store")
struct WorkflowFileCheckpointStoreTests {
    @Test("pruning keeps exactly N checkpoints per run")
    func pruningKeepsExactlyNPerRun() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WorkflowFileCheckpointStore(
            directory: directory,
            retention: WorkflowCheckpointRetention(maxCheckpointsPerRun: 3)
        )
        let thread = HiveThreadID("run-prune")

        for step in 0 ..< 7 {
            try await store.save(makeCheckpoint(thread: thread, id: "cp-\(step)", step: step))
        }

        let names = try checkpointFileNames(in: directory)
        #expect(names.count == 3)
        #expect(names.contains("workflow-run-prune-cp-4.json"))
        #expect(names.contains("workflow-run-prune-cp-5.json"))
        #expect(names.contains("workflow-run-prune-cp-6.json"))
        #expect(!names.contains("workflow-run-prune-cp-0.json"))

        let latest = try await store.loadLatest(threadID: thread)
        #expect(latest?.id.rawValue == "cp-6")
        #expect(latest?.stepIndex == 6)
    }

    @Test("pruning is isolated per run")
    func pruningIsIsolatedPerRun() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WorkflowFileCheckpointStore(
            directory: directory,
            retention: WorkflowCheckpointRetention(maxCheckpointsPerRun: 2)
        )

        for step in 0 ..< 4 {
            try await store.save(makeCheckpoint(thread: HiveThreadID("alpha"), id: "a-\(step)", step: step))
            try await store.save(makeCheckpoint(thread: HiveThreadID("beta"), id: "b-\(step)", step: step))
        }

        let names = try checkpointFileNames(in: directory)
        #expect(names.filter { $0.contains("alpha") }.count == 2)
        #expect(names.filter { $0.contains("beta") }.count == 2)
    }

    @Test("load reads the manifest instead of scanning the directory")
    func loadReadsManifestNotDirectoryScan() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let files = CountingWorkflowCheckpointFileOperator()
        let store = WorkflowFileCheckpointStore(
            directory: directory,
            retention: WorkflowCheckpointRetention(maxCheckpointsPerRun: 4),
            files: files
        )
        let thread = HiveThreadID("run-index")
        try await store.save(makeCheckpoint(thread: thread, id: "cp-1", step: 1))
        try await store.save(makeCheckpoint(thread: thread, id: "cp-2", step: 2))

        files.resetCounts()
        let latest = try await store.loadLatest(threadID: thread)

        #expect(latest?.id.rawValue == "cp-2")
        #expect(files.contentsOfDirectoryCount == 0)
        #expect(files.readURLs.contains { $0.lastPathComponent == WorkflowFileCheckpointStore.manifestFileName })
        #expect(files.readURLs.contains { $0.lastPathComponent == "workflow-run-index-cp-2.json" })
        #expect(!files.readURLs.contains { $0.lastPathComponent == "workflow-run-index-cp-1.json" })
    }

    @Test("corrupt checkpoint files are skipped loudly and are not fatal")
    func corruptCheckpointsAreSkipped() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WorkflowFileCheckpointStore(
            directory: directory,
            retention: WorkflowCheckpointRetention(maxCheckpointsPerRun: 8)
        )
        let thread = HiveThreadID("run-corrupt")
        try await store.save(makeCheckpoint(thread: thread, id: "good", step: 1))
        try await store.save(makeCheckpoint(thread: thread, id: "bad", step: 2))

        let corruptURL = directory.appendingPathComponent("workflow-run-corrupt-bad.json")
        try Data("{not-json".utf8).write(to: corruptURL, options: .atomic)

        let latest = try await store.loadLatest(threadID: thread)
        #expect(latest?.id.rawValue == "good")
        #expect(latest?.stepIndex == 1)
    }

    @Test("all-corrupt entries return nil instead of throwing")
    func allCorruptEntriesReturnNil() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WorkflowFileCheckpointStore(
            directory: directory,
            retention: .default
        )
        let thread = HiveThreadID("run-all-corrupt")
        try await store.save(makeCheckpoint(thread: thread, id: "only", step: 1))
        try Data("[]".utf8).write(
            to: directory.appendingPathComponent("workflow-run-all-corrupt-only.json"),
            options: .atomic
        )

        let latest = try await store.loadLatest(threadID: thread)
        #expect(latest == nil)
    }
}

private func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swarm-checkpoint-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func checkpointFileNames(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .map(\.lastPathComponent)
        .filter { $0.hasPrefix("workflow-") && $0.hasSuffix(".json") && $0 != WorkflowFileCheckpointStore.manifestFileName }
        .sorted()
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

private final class CountingWorkflowCheckpointFileOperator: WorkflowCheckpointFileOperating, @unchecked Sendable {
    private let lock = NSLock()
    private let foundation = FoundationWorkflowCheckpointFileOperator()
    private var directoryCount = 0
    private var reads: [URL] = []

    var contentsOfDirectoryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return directoryCount
    }

    var readURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return reads
    }

    func resetCounts() {
        lock.lock()
        defer { lock.unlock() }
        directoryCount = 0
        reads = []
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        lock.lock()
        directoryCount += 1
        lock.unlock()
        return try foundation.contentsOfDirectory(at: url)
    }

    func fileExists(atPath path: String) -> Bool {
        foundation.fileExists(atPath: path)
    }

    func createDirectory(at url: URL) throws {
        try foundation.createDirectory(at: url)
    }

    func removeItem(at url: URL) throws {
        try foundation.removeItem(at: url)
    }

    func read(from url: URL) throws -> Data {
        lock.lock()
        reads.append(url)
        lock.unlock()
        return try foundation.read(from: url)
    }

    func write(_ data: Data, to url: URL) throws {
        try foundation.write(data, to: url)
    }
}
#endif
