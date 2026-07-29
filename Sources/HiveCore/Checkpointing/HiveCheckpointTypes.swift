import Foundation

/// Optional fork lineage metadata persisted alongside checkpoints.
public struct HiveCheckpointLineage: Codable, Sendable, Equatable {
    public let lineageID: String
    public let sourceThreadID: HiveThreadID
    public let sourceCheckpointID: HiveCheckpointID
    public let targetThreadID: HiveThreadID
    public let sourceRunID: HiveRunID
    public let targetRunID: HiveRunID
    public let schemaVersion: String
    public let graphVersion: String
    public let createdAtNanoseconds: UInt64

    public init(
        lineageID: String,
        sourceThreadID: HiveThreadID,
        sourceCheckpointID: HiveCheckpointID,
        targetThreadID: HiveThreadID,
        sourceRunID: HiveRunID,
        targetRunID: HiveRunID,
        schemaVersion: String,
        graphVersion: String,
        createdAtNanoseconds: UInt64
    ) {
        self.lineageID = lineageID
        self.sourceThreadID = sourceThreadID
        self.sourceCheckpointID = sourceCheckpointID
        self.targetThreadID = targetThreadID
        self.sourceRunID = sourceRunID
        self.targetRunID = targetRunID
        self.schemaVersion = schemaVersion
        self.graphVersion = graphVersion
        self.createdAtNanoseconds = createdAtNanoseconds
    }
}

/// Stable identifier for a checkpoint.
public struct HiveCheckpointID: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Lightweight metadata describing an available checkpoint in a store.
public struct HiveCheckpointSummary: Codable, Sendable, Equatable {
    public let id: HiveCheckpointID
    public let threadID: HiveThreadID
    public let runID: HiveRunID
    public let stepIndex: Int

    public let schemaVersion: String?
    public let graphVersion: String?
    public let createdAt: Date?
    public let backendID: String?

    public init(
        id: HiveCheckpointID,
        threadID: HiveThreadID,
        runID: HiveRunID,
        stepIndex: Int,
        schemaVersion: String? = nil,
        graphVersion: String? = nil,
        createdAt: Date? = nil,
        backendID: String? = nil
    ) {
        self.id = id
        self.threadID = threadID
        self.runID = runID
        self.stepIndex = stepIndex
        self.schemaVersion = schemaVersion
        self.graphVersion = graphVersion
        self.createdAt = createdAt
        self.backendID = backendID
    }
}

/// Persisted frontier task snapshot.
public struct HiveCheckpointTask: Codable, Sendable {
    public let provenance: HiveTaskProvenance
    public let nodeID: HiveNodeID
    public let localFingerprint: Data
    public let localDataByChannelID: [String: Data]

    public init(
        provenance: HiveTaskProvenance,
        nodeID: HiveNodeID,
        localFingerprint: Data,
        localDataByChannelID: [String: Data]
    ) {
        self.provenance = provenance
        self.nodeID = nodeID
        self.localFingerprint = localFingerprint
        self.localDataByChannelID = localDataByChannelID
    }
}

/// Persisted snapshot of runtime state for resume.
public struct HiveCheckpoint<Schema: HiveSchema>: Codable, Sendable {
    public let id: HiveCheckpointID
    public let threadID: HiveThreadID
    public let runID: HiveRunID
    public let stepIndex: Int
    public let schemaVersion: String
    public let graphVersion: String
    /// Checkpoint format tag for forwards/backwards compatibility.
    ///
    /// - `"HCP1"`: v1 format without channel-versioning fields.
    /// - `"HCP2"`: v1.1 format with channel versioning + triggers state.
    public let checkpointFormatVersion: String
    /// Version counters for global channels (missing entry implies version 0).
    public let channelVersionsByChannelID: [String: UInt64]
    /// Per-node versionsSeen snapshots for trigger channels.
    public let versionsSeenByNodeID: [String: [String: UInt64]]
    /// Optional convenience field for debugging: channels written in the last committed step.
    public let updatedChannelsLastCommit: [String]
    public let globalDataByChannelID: [String: Data]
    public let frontier: [HiveCheckpointTask]
    public let deferredFrontier: [HiveCheckpointTask]
    public let joinBarrierSeenByJoinID: [String: [String]]
    public let interruption: HiveInterrupt<Schema>?
    public let lineage: HiveCheckpointLineage?

    public init(
        id: HiveCheckpointID,
        threadID: HiveThreadID,
        runID: HiveRunID,
        stepIndex: Int,
        schemaVersion: String,
        graphVersion: String,
        globalDataByChannelID: [String: Data],
        frontier: [HiveCheckpointTask],
        deferredFrontier: [HiveCheckpointTask] = [],
        joinBarrierSeenByJoinID: [String: [String]],
        interruption: HiveInterrupt<Schema>?,
        lineage: HiveCheckpointLineage?
    ) {
        self.id = id
        self.threadID = threadID
        self.runID = runID
        self.stepIndex = stepIndex
        self.schemaVersion = schemaVersion
        self.graphVersion = graphVersion
        self.checkpointFormatVersion = "HCP2"
        self.channelVersionsByChannelID = [:]
        self.versionsSeenByNodeID = [:]
        self.updatedChannelsLastCommit = []
        self.globalDataByChannelID = globalDataByChannelID
        self.frontier = frontier
        self.deferredFrontier = deferredFrontier
        self.joinBarrierSeenByJoinID = joinBarrierSeenByJoinID
        self.interruption = interruption
        self.lineage = lineage
    }

    public init(
        id: HiveCheckpointID,
        threadID: HiveThreadID,
        runID: HiveRunID,
        stepIndex: Int,
        schemaVersion: String,
        graphVersion: String,
        globalDataByChannelID: [String: Data],
        frontier: [HiveCheckpointTask],
        deferredFrontier: [HiveCheckpointTask] = [],
        joinBarrierSeenByJoinID: [String: [String]],
        interruption: HiveInterrupt<Schema>?
    ) {
        self.init(
            id: id,
            threadID: threadID,
            runID: runID,
            stepIndex: stepIndex,
            schemaVersion: schemaVersion,
            graphVersion: graphVersion,
            globalDataByChannelID: globalDataByChannelID,
            frontier: frontier,
            deferredFrontier: deferredFrontier,
            joinBarrierSeenByJoinID: joinBarrierSeenByJoinID,
            interruption: interruption,
            lineage: nil
        )
    }

    public init(
        id: HiveCheckpointID,
        threadID: HiveThreadID,
        runID: HiveRunID,
        stepIndex: Int,
        schemaVersion: String,
        graphVersion: String,
        checkpointFormatVersion: String,
        channelVersionsByChannelID: [String: UInt64],
        versionsSeenByNodeID: [String: [String: UInt64]],
        updatedChannelsLastCommit: [String],
        globalDataByChannelID: [String: Data],
        frontier: [HiveCheckpointTask],
        deferredFrontier: [HiveCheckpointTask] = [],
        joinBarrierSeenByJoinID: [String: [String]],
        interruption: HiveInterrupt<Schema>?,
        lineage: HiveCheckpointLineage?
    ) {
        self.id = id
        self.threadID = threadID
        self.runID = runID
        self.stepIndex = stepIndex
        self.schemaVersion = schemaVersion
        self.graphVersion = graphVersion
        self.checkpointFormatVersion = checkpointFormatVersion
        self.channelVersionsByChannelID = channelVersionsByChannelID
        self.versionsSeenByNodeID = versionsSeenByNodeID
        self.updatedChannelsLastCommit = updatedChannelsLastCommit
        self.globalDataByChannelID = globalDataByChannelID
        self.frontier = frontier
        self.deferredFrontier = deferredFrontier
        self.joinBarrierSeenByJoinID = joinBarrierSeenByJoinID
        self.interruption = interruption
        self.lineage = lineage
    }

    public init(
        id: HiveCheckpointID,
        threadID: HiveThreadID,
        runID: HiveRunID,
        stepIndex: Int,
        schemaVersion: String,
        graphVersion: String,
        checkpointFormatVersion: String,
        channelVersionsByChannelID: [String: UInt64],
        versionsSeenByNodeID: [String: [String: UInt64]],
        updatedChannelsLastCommit: [String],
        globalDataByChannelID: [String: Data],
        frontier: [HiveCheckpointTask],
        deferredFrontier: [HiveCheckpointTask] = [],
        joinBarrierSeenByJoinID: [String: [String]],
        interruption: HiveInterrupt<Schema>?
    ) {
        self.init(
            id: id,
            threadID: threadID,
            runID: runID,
            stepIndex: stepIndex,
            schemaVersion: schemaVersion,
            graphVersion: graphVersion,
            checkpointFormatVersion: checkpointFormatVersion,
            channelVersionsByChannelID: channelVersionsByChannelID,
            versionsSeenByNodeID: versionsSeenByNodeID,
            updatedChannelsLastCommit: updatedChannelsLastCommit,
            globalDataByChannelID: globalDataByChannelID,
            frontier: frontier,
            deferredFrontier: deferredFrontier,
            joinBarrierSeenByJoinID: joinBarrierSeenByJoinID,
            interruption: interruption,
            lineage: nil
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case threadID
        case runID
        case stepIndex
        case schemaVersion
        case graphVersion
        case checkpointFormatVersion
        case channelVersionsByChannelID
        case versionsSeenByNodeID
        case updatedChannelsLastCommit
        case globalDataByChannelID
        case frontier
        case deferredFrontier
        case joinBarrierSeenByJoinID
        case interruption
        case lineage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(HiveCheckpointID.self, forKey: .id)
        self.threadID = try container.decode(HiveThreadID.self, forKey: .threadID)
        self.runID = try container.decode(HiveRunID.self, forKey: .runID)
        self.stepIndex = try container.decode(Int.self, forKey: .stepIndex)
        self.schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        self.graphVersion = try container.decode(String.self, forKey: .graphVersion)

        self.checkpointFormatVersion = try container.decodeIfPresent(String.self, forKey: .checkpointFormatVersion) ?? "HCP1"
        self.channelVersionsByChannelID = try container.decodeIfPresent([String: UInt64].self, forKey: .channelVersionsByChannelID) ?? [:]
        self.versionsSeenByNodeID = try container.decodeIfPresent([String: [String: UInt64]].self, forKey: .versionsSeenByNodeID) ?? [:]
        self.updatedChannelsLastCommit = try container.decodeIfPresent([String].self, forKey: .updatedChannelsLastCommit) ?? []

        self.globalDataByChannelID = try container.decode([String: Data].self, forKey: .globalDataByChannelID)
        self.frontier = try container.decode([HiveCheckpointTask].self, forKey: .frontier)
        self.deferredFrontier = try container.decodeIfPresent([HiveCheckpointTask].self, forKey: .deferredFrontier) ?? []
        self.joinBarrierSeenByJoinID = try container.decode([String: [String]].self, forKey: .joinBarrierSeenByJoinID)
        self.interruption = try container.decodeIfPresent(HiveInterrupt<Schema>.self, forKey: .interruption)
        self.lineage = try container.decodeIfPresent(HiveCheckpointLineage.self, forKey: .lineage)
    }
}

/// Storage backend for checkpoints.
public protocol HiveCheckpointStore: Sendable {
    associatedtype Schema: HiveSchema
    func save(_ checkpoint: HiveCheckpoint<Schema>) async throws
    func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<Schema>?
}

/// Discoverable capabilities for a configured checkpoint store.
public struct HiveCheckpointStoreCapabilities: Sendable, Equatable {
    public let supportsListCheckpoints: Bool
    public let supportsLoadCheckpointByID: Bool

    public init(
        supportsListCheckpoints: Bool,
        supportsLoadCheckpointByID: Bool
    ) {
        self.supportsListCheckpoints = supportsListCheckpoints
        self.supportsLoadCheckpointByID = supportsLoadCheckpointByID
    }

    public static let none = HiveCheckpointStoreCapabilities(
        supportsListCheckpoints: false,
        supportsLoadCheckpointByID: false
    )

    public static let queryable = HiveCheckpointStoreCapabilities(
        supportsListCheckpoints: true,
        supportsLoadCheckpointByID: true
    )
}

/// Optional checkpoint store capability: list and load checkpoints by identifier.
public protocol HiveCheckpointQueryableStore: HiveCheckpointStore {
    func listCheckpoints(threadID: HiveThreadID, limit: Int?) async throws -> [HiveCheckpointSummary]
    func loadCheckpoint(threadID: HiveThreadID, id: HiveCheckpointID) async throws -> HiveCheckpoint<Schema>?
}

/// Type-erased checkpoint store wrapper.
public struct AnyHiveCheckpointStore<Schema: HiveSchema>: Sendable {
    private let _save: @Sendable (HiveCheckpoint<Schema>) async throws -> Void
    private let _loadLatest: @Sendable (HiveThreadID) async throws -> HiveCheckpoint<Schema>?
    private let _listCheckpoints: (@Sendable (HiveThreadID, Int?) async throws -> [HiveCheckpointSummary])?
    private let _loadCheckpoint: (@Sendable (HiveThreadID, HiveCheckpointID) async throws -> HiveCheckpoint<Schema>?)?
    public let capabilities: HiveCheckpointStoreCapabilities

    public init<S: HiveCheckpointStore>(_ store: S) where S.Schema == Schema {
        self._save = store.save
        self._loadLatest = store.loadLatest
        self._listCheckpoints = nil
        self._loadCheckpoint = nil
        self.capabilities = .none
    }

    public init<Q: HiveCheckpointQueryableStore>(_ store: Q) where Q.Schema == Schema {
        self._save = store.save
        self._loadLatest = store.loadLatest
        self._listCheckpoints = { threadID, limit in
            try await store.listCheckpoints(threadID: threadID, limit: limit)
        }
        self._loadCheckpoint = { threadID, checkpointID in
            try await store.loadCheckpoint(threadID: threadID, id: checkpointID)
        }
        self.capabilities = .queryable
    }

    public func save(_ checkpoint: HiveCheckpoint<Schema>) async throws {
        try await _save(checkpoint)
    }

    public func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<Schema>? {
        try await _loadLatest(threadID)
    }

    public func listCheckpoints(
        threadID: HiveThreadID,
        limit: Int? = nil
    ) async throws -> [HiveCheckpointSummary] {
        guard let _listCheckpoints else {
            throw HiveCheckpointQueryError.unsupported(operation: .listCheckpoints)
        }
        return try await _listCheckpoints(threadID, limit)
    }

    public func loadCheckpoint(
        threadID: HiveThreadID,
        id: HiveCheckpointID
    ) async throws -> HiveCheckpoint<Schema>? {
        guard let _loadCheckpoint else {
            throw HiveCheckpointQueryError.unsupported(operation: .loadCheckpointByID)
        }
        return try await _loadCheckpoint(threadID, id)
    }
}
