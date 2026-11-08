#if SWARM_INTEGRATIONS
import Foundation
import HiveCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A durable workflow checkpoint backend.
///
/// Class-bound so the engine can key its in-process resume guard on the
/// backend's identity.
protocol WorkflowDurableCheckpointStore: AnyObject, Sendable {
    var runtimeStore: AnyHiveCheckpointStore<WorkflowDurableSchema> { get }
    func containsCheckpoint(for checkpointID: String) async throws -> Bool
    /// Full checkpoint history for a run, ordered oldest first (newest last).
    func history(for checkpointID: String) async throws -> [HiveCheckpoint<WorkflowDurableSchema>]
}

extension WorkflowCheckpointing {
    var runtimeStore: AnyHiveCheckpointStore<WorkflowDurableSchema> {
        backend.runtimeStore
    }

    func containsCheckpoint(for checkpointID: String) async throws -> Bool {
        try await backend.containsCheckpoint(for: checkpointID)
    }

    func history(for checkpointID: String) async throws -> [HiveCheckpoint<WorkflowDurableSchema>] {
        try await backend.history(for: checkpointID)
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

    /// Atomic compare-and-swap: actor isolation makes the compare and the
    /// append one step.
    func save(
        _ checkpoint: HiveCheckpoint<WorkflowDurableSchema>,
        expectedLatestID: HiveCheckpointID?
    ) async throws {
        let latestID = latest(threadID: checkpoint.threadID)?.id
        guard latestID == expectedLatestID else {
            throw HiveCheckpointConflict(
                threadID: checkpoint.threadID,
                expectedLatestID: expectedLatestID,
                actualLatestID: latestID
            )
        }
        checkpoints.append(checkpoint)
    }

    func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<WorkflowDurableSchema>? {
        latest(threadID: threadID)
    }

    private func latest(threadID: HiveThreadID) -> HiveCheckpoint<WorkflowDurableSchema>? {
        checkpoints
            .filter { $0.threadID == threadID }
            .max { lhs, rhs in
                if lhs.stepIndex == rhs.stepIndex {
                    return lhs.id.rawValue < rhs.id.rawValue
                }
                return lhs.stepIndex < rhs.stepIndex
            }
    }

    func history(for checkpointID: String) async throws -> [HiveCheckpoint<WorkflowDurableSchema>] {
        history(threadID: HiveThreadID(checkpointID))
    }

    func listCheckpoints(threadID: HiveThreadID, limit: Int?) async throws -> [HiveCheckpointSummary] {
        let summaries = history(threadID: threadID).map(Self.summary)
        if let limit, limit >= 0 {
            return Array(summaries.suffix(limit))
        }
        return summaries
    }

    func loadCheckpoint(threadID: HiveThreadID, id: HiveCheckpointID) async throws -> HiveCheckpoint<WorkflowDurableSchema>? {
        history(threadID: threadID).first { $0.id == id }
    }

    private func history(threadID: HiveThreadID) -> [HiveCheckpoint<WorkflowDurableSchema>] {
        checkpoints
            .filter { $0.threadID == threadID }
            .sorted {
                if $0.stepIndex != $1.stepIndex {
                    return $0.stepIndex < $1.stepIndex
                }
                return $0.id.rawValue < $1.id.rawValue
            }
    }

    private static func summary(for checkpoint: HiveCheckpoint<WorkflowDurableSchema>) -> HiveCheckpointSummary {
        HiveCheckpointSummary(
            id: checkpoint.id,
            threadID: checkpoint.threadID,
            runID: checkpoint.runID,
            stepIndex: checkpoint.stepIndex,
            schemaVersion: checkpoint.schemaVersion,
            graphVersion: checkpoint.graphVersion,
            createdAt: nil,
            backendID: nil
        )
    }
}

extension WorkflowInMemoryCheckpointStore: HiveCheckpointQueryableStore {}

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
        try SecureFileIO.createDirectory(at: url)
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL) throws {
        try SecureFileIO.write(data, to: url)
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
        try withDirectoryLock {
            try write(checkpoint)
        }
    }

    /// Atomic compare-and-swap across processes sharing the directory.
    ///
    /// The compare and the write run under an exclusive advisory `flock` on
    /// the checkpoint directory; plain ``save(_:)`` takes the same lock, so
    /// two processes resuming the same run cannot both win.
    func save(
        _ checkpoint: HiveCheckpoint<WorkflowDurableSchema>,
        expectedLatestID: HiveCheckpointID?
    ) async throws {
        try ensureDirectoryExists()
        try withDirectoryLock {
            let latestID = try latest(threadID: checkpoint.threadID)?.id
            guard latestID == expectedLatestID else {
                throw HiveCheckpointConflict(
                    threadID: checkpoint.threadID,
                    expectedLatestID: expectedLatestID,
                    actualLatestID: latestID
                )
            }
            try write(checkpoint)
        }
    }

    private func write(_ checkpoint: HiveCheckpoint<WorkflowDurableSchema>) throws {
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
        return try latest(threadID: threadID)
    }

    private func latest(threadID: HiveThreadID) throws -> HiveCheckpoint<WorkflowDurableSchema>? {
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

    func history(for checkpointID: String) async throws -> [HiveCheckpoint<WorkflowDurableSchema>] {
        try ensureDirectoryExists()
        let threadID = HiveThreadID(checkpointID)
        let manifest = try loadManifestForRead()
        let entries = (manifest.runs[threadID.rawValue] ?? []).sorted(by: Self.isOlderThan)
        let decoder = JSONDecoder()
        var history: [HiveCheckpoint<WorkflowDurableSchema>] = []
        history.reserveCapacity(entries.count)

        for entry in entries {
            let url = directory.appendingPathComponent(entry.fileName, isDirectory: false)
            do {
                let data = try files.read(from: url)
                let checkpoint = try decoder.decode(HiveCheckpoint<WorkflowDurableSchema>.self, from: data)
                guard checkpoint.threadID == threadID else { continue }
                history.append(checkpoint)
            } catch {
                Log.orchestration.warning(
                    "Skipping corrupt workflow checkpoint at \(entry.fileName): \(error)"
                )
            }
        }

        return history
    }

    func listCheckpoints(threadID: HiveThreadID, limit: Int?) async throws -> [HiveCheckpointSummary] {
        let summaries = try await history(for: threadID.rawValue).map { checkpoint in
            HiveCheckpointSummary(
                id: checkpoint.id,
                threadID: checkpoint.threadID,
                runID: checkpoint.runID,
                stepIndex: checkpoint.stepIndex,
                schemaVersion: checkpoint.schemaVersion,
                graphVersion: checkpoint.graphVersion,
                createdAt: nil,
                backendID: nil
            )
        }
        if let limit, limit >= 0 {
            return Array(summaries.suffix(limit))
        }
        return summaries
    }

    func loadCheckpoint(threadID: HiveThreadID, id: HiveCheckpointID) async throws -> HiveCheckpoint<WorkflowDurableSchema>? {
        try await history(for: threadID.rawValue).first { $0.id == id }
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

    /// Runs `body` while holding an exclusive advisory lock on the directory.
    ///
    /// Locks the directory's own descriptor rather than a lock file, so the
    /// directory keeps holding only checkpoints and the manifest.
    private func withDirectoryLock<T>(_ body: () throws -> T) throws -> T {
        let lockPath = directory.path
        let descriptor = lockPath.withCString { open($0, O_RDONLY) }
        guard descriptor >= 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: lockPath])
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw CocoaError(.fileLocking, userInfo: [NSFilePathErrorKey: lockPath])
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
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

extension WorkflowFileCheckpointStore: HiveCheckpointQueryableStore {}
#endif
