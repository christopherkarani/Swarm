#if SWARM_INTEGRATIONS
import Foundation
import HiveCore

protocol WorkflowDurableCheckpointStore: Sendable {
    var runtimeStore: AnyHiveCheckpointStore<WorkflowDurableSchema> { get }
    func containsCheckpoint(for checkpointID: String) async throws -> Bool
}

extension WorkflowCheckpointing {
    var runtimeStore: AnyHiveCheckpointStore<WorkflowDurableSchema> {
        backend.runtimeStore
    }

    func containsCheckpoint(for checkpointID: String) async throws -> Bool {
        try await backend.containsCheckpoint(for: checkpointID)
    }
}

actor WorkflowInMemoryCheckpointStore: WorkflowDurableCheckpointStore, HiveCheckpointStore {
    typealias Schema = WorkflowDurableSchema

    private var checkpoints: [HiveCheckpoint<WorkflowDurableSchema>] = []

    nonisolated var runtimeStore: AnyHiveCheckpointStore<WorkflowDurableSchema> {
        AnyHiveCheckpointStore(self)
    }

    func containsCheckpoint(for checkpointID: String) async throws -> Bool {
        try await loadLatest(threadID: HiveThreadID(checkpointID)) != nil
    }

    func save(_ checkpoint: HiveCheckpoint<WorkflowDurableSchema>) async throws {
        checkpoints.append(checkpoint)
    }

    func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<WorkflowDurableSchema>? {
        checkpoints
            .filter { $0.threadID == threadID }
            .max { lhs, rhs in
                if lhs.stepIndex == rhs.stepIndex {
                    return lhs.id.rawValue < rhs.id.rawValue
                }
                return lhs.stepIndex < rhs.stepIndex
            }
    }
}

actor WorkflowFileCheckpointStore: WorkflowDurableCheckpointStore, HiveCheckpointStore {
    typealias Schema = WorkflowDurableSchema

    private let directory: URL
    private let fileManager = FileManager.default

    init(directory: URL) {
        self.directory = directory
    }

    nonisolated var runtimeStore: AnyHiveCheckpointStore<WorkflowDurableSchema> {
        AnyHiveCheckpointStore(self)
    }

    func containsCheckpoint(for checkpointID: String) async throws -> Bool {
        try await loadLatest(threadID: HiveThreadID(checkpointID)) != nil
    }

    func save(_ checkpoint: HiveCheckpoint<WorkflowDurableSchema>) async throws {
        try ensureDirectoryExists()
        let data = try JSONEncoder().encode(checkpoint)
        let url = checkpointFileURL(
            threadID: checkpoint.threadID,
            checkpointID: checkpoint.id
        )
        try data.write(to: url, options: .atomic)
    }

    func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<WorkflowDurableSchema>? {
        try ensureDirectoryExists()

        let threadPrefix = filePrefix(for: threadID)
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )

        let matching = files.filter { $0.lastPathComponent.hasPrefix(threadPrefix) }
        guard matching.isEmpty == false else { return nil }

        let decoder = JSONDecoder()
        var latest: HiveCheckpoint<WorkflowDurableSchema>?

        for fileURL in matching {
            let data = try Data(contentsOf: fileURL)
            let checkpoint = try decoder.decode(HiveCheckpoint<WorkflowDurableSchema>.self, from: data)
            guard checkpoint.threadID == threadID else { continue }

            if let existingLatest = latest {
                let isNewer = checkpoint.stepIndex > existingLatest.stepIndex ||
                    (checkpoint.stepIndex == existingLatest.stepIndex && checkpoint.id.rawValue > existingLatest.id.rawValue)
                if isNewer {
                    latest = checkpoint
                }
            } else {
                latest = checkpoint
            }
        }

        return latest
    }

    private func checkpointFileURL(threadID: HiveThreadID, checkpointID: HiveCheckpointID) -> URL {
        let name = "\(filePrefix(for: threadID))\(sanitize(checkpointID.rawValue)).json"
        return directory.appendingPathComponent(name, isDirectory: false)
    }

    private func filePrefix(for threadID: HiveThreadID) -> String {
        "workflow-\(sanitize(threadID.rawValue))-"
    }

    private func sanitize(_ raw: String) -> String {
        raw.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]"#,
            with: "_",
            options: .regularExpression
        )
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }
}
#endif
