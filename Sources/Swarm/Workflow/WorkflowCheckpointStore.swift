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

protocol WorkflowCheckpointFileOperating: AnyObject, Sendable {
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func fileExists(atPath path: String) -> Bool
    func createDirectory(at url: URL) throws
    func removeItem(at url: URL) throws
    func read(from url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
}

/// FileManager is not Sendable; this operator is only used from the store actor.
final class FoundationWorkflowCheckpointFileOperator: WorkflowCheckpointFileOperating, @unchecked Sendable {
    private let fileManager = FileManager.default

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

struct WorkflowCheckpointManifest: Codable, Sendable, Equatable {
    var version: Int
    var runs: [String: [WorkflowCheckpointManifestEntry]]
}

struct WorkflowCheckpointManifestEntry: Codable, Sendable, Equatable {
    var checkpointID: String
    var stepIndex: Int
    var fileName: String
}

actor WorkflowFileCheckpointStore: WorkflowDurableCheckpointStore, HiveCheckpointStore {
    typealias Schema = WorkflowDurableSchema

    static let manifestFileName = "workflow-checkpoints.manifest.json"

    private let directory: URL
    private let retention: WorkflowCheckpointRetention
    private let files: any WorkflowCheckpointFileOperating

    init(
        directory: URL,
        retention: WorkflowCheckpointRetention = .default,
        files: any WorkflowCheckpointFileOperating = FoundationWorkflowCheckpointFileOperator()
    ) {
        self.directory = directory
        self.retention = retention
        self.files = files
    }

    nonisolated var runtimeStore: AnyHiveCheckpointStore<WorkflowDurableSchema> {
        AnyHiveCheckpointStore(self)
    }

    func containsCheckpoint(for checkpointID: String) async throws -> Bool {
        try await loadLatest(threadID: HiveThreadID(checkpointID)) != nil
    }

    func save(_ checkpoint: HiveCheckpoint<WorkflowDurableSchema>) async throws {
        try ensureDirectoryExists()
        let fileName = checkpointFileName(
            threadID: checkpoint.threadID,
            checkpointID: checkpoint.id
        )
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        try files.write(JSONEncoder().encode(checkpoint), to: url)

        var manifest = try loadManifestForWrite()
        var entries = manifest.runs[checkpoint.threadID.rawValue, default: []]
        entries.removeAll { $0.checkpointID == checkpoint.id.rawValue }
        entries.append(
            WorkflowCheckpointManifestEntry(
                checkpointID: checkpoint.id.rawValue,
                stepIndex: checkpoint.stepIndex,
                fileName: fileName
            )
        )
        entries.sort(by: Self.isOlderThan)
        let pruned = prune(entries)
        manifest.runs[checkpoint.threadID.rawValue] = pruned.kept
        try writeManifest(manifest)
        try deleteFiles(named: pruned.removed.map(\.fileName))
    }

    func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<WorkflowDurableSchema>? {
        try ensureDirectoryExists()
        let manifest = try loadManifestForRead()
        let entries = (manifest.runs[threadID.rawValue] ?? []).sorted(by: Self.isOlderThan)
        let decoder = JSONDecoder()

        for entry in entries.reversed() {
            let url = directory.appendingPathComponent(entry.fileName, isDirectory: false)
            do {
                let data = try files.read(from: url)
                let checkpoint = try decoder.decode(HiveCheckpoint<WorkflowDurableSchema>.self, from: data)
                guard checkpoint.threadID == threadID else { continue }
                return checkpoint
            } catch {
                Log.orchestration.warning(
                    "Skipping corrupt workflow checkpoint at \(entry.fileName): \(error)"
                )
            }
        }

        return nil
    }

    private func loadManifestForRead() throws -> WorkflowCheckpointManifest {
        if let manifest = try readManifest() {
            return manifest
        }
        let rebuilt = try rebuildManifest()
        try writeManifest(rebuilt)
        return rebuilt
    }

    private func loadManifestForWrite() throws -> WorkflowCheckpointManifest {
        if let manifest = try readManifest() {
            return manifest
        }
        return WorkflowCheckpointManifest(version: 1, runs: [:])
    }

    private func readManifest() throws -> WorkflowCheckpointManifest? {
        let url = manifestURL
        guard files.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try files.read(from: url)
            return try JSONDecoder().decode(WorkflowCheckpointManifest.self, from: data)
        } catch {
            Log.orchestration.warning("Skipping corrupt workflow checkpoint manifest: \(error)")
            return nil
        }
    }

    private func writeManifest(_ manifest: WorkflowCheckpointManifest) throws {
        try files.write(JSONEncoder().encode(manifest), to: manifestURL)
    }

    private func rebuildManifest() throws -> WorkflowCheckpointManifest {
        let urls = try files.contentsOfDirectory(at: directory)
        var runs: [String: [WorkflowCheckpointManifestEntry]] = [:]
        let decoder = JSONDecoder()

        for fileURL in urls {
            let name = fileURL.lastPathComponent
            guard name.hasPrefix("workflow-"),
                  name.hasSuffix(".json"),
                  name != Self.manifestFileName
            else {
                continue
            }
            do {
                let checkpoint = try decoder.decode(
                    HiveCheckpoint<WorkflowDurableSchema>.self,
                    from: files.read(from: fileURL)
                )
                runs[checkpoint.threadID.rawValue, default: []].append(
                    WorkflowCheckpointManifestEntry(
                        checkpointID: checkpoint.id.rawValue,
                        stepIndex: checkpoint.stepIndex,
                        fileName: name
                    )
                )
            } catch {
                Log.orchestration.warning("Skipping corrupt workflow checkpoint at \(name): \(error)")
            }
        }

        for key in runs.keys {
            runs[key]?.sort(by: Self.isOlderThan)
        }
        return WorkflowCheckpointManifest(version: 1, runs: runs)
    }

    private func prune(
        _ entries: [WorkflowCheckpointManifestEntry]
    ) -> (kept: [WorkflowCheckpointManifestEntry], removed: [WorkflowCheckpointManifestEntry]) {
        let limit = retention.maxCheckpointsPerRun
        guard entries.count > limit else {
            return (entries, [])
        }
        let removed = Array(entries.prefix(entries.count - limit))
        let kept = Array(entries.suffix(limit))
        return (kept, removed)
    }

    private func deleteFiles(named names: [String]) throws {
        for name in names {
            let url = directory.appendingPathComponent(name, isDirectory: false)
            guard files.fileExists(atPath: url.path) else { continue }
            do {
                try files.removeItem(at: url)
            } catch {
                Log.orchestration.warning("Failed to delete pruned workflow checkpoint \(name): \(error)")
            }
        }
    }

    private var manifestURL: URL {
        directory.appendingPathComponent(Self.manifestFileName, isDirectory: false)
    }

    private func checkpointFileName(threadID: HiveThreadID, checkpointID: HiveCheckpointID) -> String {
        "\(filePrefix(for: threadID))\(sanitize(checkpointID.rawValue)).json"
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
        if !files.fileExists(atPath: directory.path) {
            try files.createDirectory(at: directory)
        }
    }

    private static func isOlderThan(
        _ lhs: WorkflowCheckpointManifestEntry,
        _ rhs: WorkflowCheckpointManifestEntry
    ) -> Bool {
        if lhs.stepIndex != rhs.stepIndex {
            return lhs.stepIndex < rhs.stepIndex
        }
        return lhs.checkpointID < rhs.checkpointID
    }
}
#endif
