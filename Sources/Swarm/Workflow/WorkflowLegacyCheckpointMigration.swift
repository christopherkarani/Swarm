#if SWARM_INTEGRATIONS
import Foundation
import HiveCore

/// Checkpoint store wrapper that migrates pre-phase-enum checkpoints on load.
///
/// Loads matching the current schema version pass through untouched; anything
/// else is offered to ``WorkflowLegacyCheckpointMigrator`` so durable runs
/// checkpointed by earlier Swarm releases resume instead of failing with a
/// version mismatch.
struct WorkflowLegacyMigratingCheckpointStore: HiveCheckpointStore {
    typealias Schema = WorkflowDurableSchema

    private let inner: AnyHiveCheckpointStore<Schema>
    private let schemaVersion: String
    private let graphVersion: String

    init(
        inner: AnyHiveCheckpointStore<Schema>,
        schemaVersion: String,
        graphVersion: String
    ) {
        self.inner = inner
        self.schemaVersion = schemaVersion
        self.graphVersion = graphVersion
    }

    func save(_ checkpoint: HiveCheckpoint<Schema>) async throws {
        try await inner.save(checkpoint)
    }

    func save(_ checkpoint: HiveCheckpoint<Schema>, expectedLatestID: HiveCheckpointID?) async throws {
        try await inner.save(checkpoint, expectedLatestID: expectedLatestID)
    }

    func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<Schema>? {
        guard let checkpoint = try await inner.loadLatest(threadID: threadID) else { return nil }
        guard checkpoint.schemaVersion != schemaVersion else { return checkpoint }
        return try WorkflowLegacyCheckpointMigrator.migrate(
            checkpoint,
            schemaVersion: schemaVersion,
            graphVersion: graphVersion
        )
    }

    func listCheckpoints(threadID: HiveThreadID, limit: Int?) async throws -> [HiveCheckpointSummary] {
        try await inner.listCheckpoints(threadID: threadID, limit: limit)
    }

    func loadCheckpoint(threadID: HiveThreadID, id: HiveCheckpointID) async throws -> HiveCheckpoint<Schema>? {
        guard let checkpoint = try await inner.loadCheckpoint(threadID: threadID, id: id) else { return nil }
        guard checkpoint.schemaVersion != schemaVersion else { return checkpoint }
        return try WorkflowLegacyCheckpointMigrator.migrate(
            checkpoint,
            schemaVersion: schemaVersion,
            graphVersion: graphVersion
        )
    }
}

extension WorkflowLegacyMigratingCheckpointStore: HiveCheckpointQueryableStore {}

/// Rewrites checkpoints persisted in the pre-phase-enum six-channel layout into
/// the current three-channel phase-enum layout.
///
/// The legacy channels (`workflow.currentInput`, `workflow.lastResult`,
/// `workflow.stepCursor`, `workflow.iterationCursor`, `workflow.completed`,
/// `workflow.signature`) are decoded with the same deterministic JSON codecs
/// that wrote them, then folded into one ``WorkflowDurablePhase``:
/// `completed == true` becomes `.completed` (synthesizing the result from the
/// current input when no step ever committed), otherwise `.running` carries the
/// cursors and snapshot forward. A synthesized completion cannot leave pending
/// cursors behind because the cursors are dropped with the legacy layout.
///
/// Version bookkeeping (`channelVersionsByChannelID`, `versionsSeenByNodeID`,
/// `updatedChannelsLastCommit`) is pruned to channel IDs the current schema
/// still registers: legacy checkpoints carry the removed channel IDs in these
/// maps, and the runtime rejects any unknown ID there as corrupt. Surviving
/// channels keep their write history; the phase channel starts at version 0
/// like any newly registered channel.
///
/// Checkpoints without the legacy discriminator channel are returned untouched
/// so the runtime raises its regular version-mismatch error rather than
/// guessing at an unknown format.
enum WorkflowLegacyCheckpointMigrator {
    static func migrate(
        _ checkpoint: HiveCheckpoint<WorkflowDurableSchema>,
        schemaVersion: String,
        graphVersion: String
    ) throws -> HiveCheckpoint<WorkflowDurableSchema> {
        let legacyData = checkpoint.globalDataByChannelID
        guard legacyData[LegacyRunState.completedChannelID] != nil else {
            return checkpoint
        }

        let legacy = try LegacyRunState(globalDataByChannelID: legacyData)
        let phase: WorkflowDurablePhase
        if legacy.completed {
            phase = .completed(legacy.lastResult ?? WorkflowResultSnapshot(AgentResult(output: legacy.currentInput)))
        } else {
            phase = .running(
                stepCursor: legacy.stepCursor,
                iterationCursor: legacy.iterationCursor,
                lastResult: legacy.lastResult
            )
        }

        var migratedData: [String: Data] = [:]
        migratedData[WorkflowDurableSchema.phaseKey.id.rawValue] =
            try WorkflowCheckpointCodec<WorkflowDurablePhase>().encode(phase)
        migratedData[WorkflowDurableSchema.currentInputKey.id.rawValue] =
            try WorkflowCheckpointCodec<String>().encode(legacy.currentInput)
        migratedData[WorkflowDurableSchema.signatureKey.id.rawValue] =
            try WorkflowCheckpointCodec<String>().encode(legacy.signature)

        let registeredGlobalIDs = Set(
            WorkflowDurableSchema.channelSpecs
                .filter { $0.scope == .global }
                .map { $0.id.rawValue }
        )

        return HiveCheckpoint(
            id: checkpoint.id,
            threadID: checkpoint.threadID,
            runID: checkpoint.runID,
            stepIndex: checkpoint.stepIndex,
            schemaVersion: schemaVersion,
            graphVersion: graphVersion,
            checkpointFormatVersion: checkpoint.checkpointFormatVersion,
            channelVersionsByChannelID: checkpoint.channelVersionsByChannelID
                .filter { registeredGlobalIDs.contains($0.key) },
            versionsSeenByNodeID: checkpoint.versionsSeenByNodeID.mapValues { versions in
                versions.filter { registeredGlobalIDs.contains($0.key) }
            },
            updatedChannelsLastCommit: checkpoint.updatedChannelsLastCommit
                .filter { registeredGlobalIDs.contains($0) },
            globalDataByChannelID: migratedData,
            frontier: checkpoint.frontier,
            deferredFrontier: checkpoint.deferredFrontier,
            joinBarrierSeenByJoinID: checkpoint.joinBarrierSeenByJoinID,
            interruption: checkpoint.interruption,
            lineage: checkpoint.lineage
        )
    }
}

/// Channel identifiers and decoded values of the pre-phase-enum durable layout.
private struct LegacyRunState {
    static let currentInputChannelID = "workflow.currentInput"
    static let signatureChannelID = "workflow.signature"
    static let stepCursorChannelID = "workflow.stepCursor"
    static let iterationCursorChannelID = "workflow.iterationCursor"
    static let completedChannelID = "workflow.completed"
    static let lastResultChannelID = "workflow.lastResult"

    let currentInput: String
    let signature: String
    let stepCursor: Int
    let iterationCursor: Int
    let completed: Bool
    let lastResult: WorkflowResultSnapshot?

    init(globalDataByChannelID data: [String: Data]) throws {
        // Missing entries fall back to start-of-run values; entries that are
        // present but undecodable fail loudly instead of fabricating state.
        currentInput = try Self.decoded(data[Self.currentInputChannelID], as: String.self) ?? ""
        signature = try Self.decoded(data[Self.signatureChannelID], as: String.self) ?? ""
        stepCursor = try Self.decoded(data[Self.stepCursorChannelID], as: Int.self) ?? 0
        iterationCursor = try Self.decoded(data[Self.iterationCursorChannelID], as: Int.self) ?? 0
        completed = try Self.decoded(data[Self.completedChannelID], as: Bool.self) ?? false
        lastResult = try Self.decoded(data[Self.lastResultChannelID], as: WorkflowResultSnapshot?.self) ?? nil
    }

    private static func decoded<Value: Codable & Sendable>(_ data: Data?, as _: Value.Type) throws -> Value? {
        guard let data else { return nil }
        return try WorkflowCheckpointCodec<Value>().decode(data)
    }
}
#endif
