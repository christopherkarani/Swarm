import Foundation

extension HiveRuntime {
    public func getCheckpointHistory(
        threadID: HiveThreadID,
        limit: Int? = nil
    ) async throws -> [HiveCheckpointSummary] {
        guard let store = environment.checkpointStore else {
            throw HiveCheckpointQueryError.unsupported(operation: .listCheckpoints)
        }
        return try await store.listCheckpoints(threadID: threadID, limit: limit)
    }

    public func getCheckpoint(
        threadID: HiveThreadID,
        id: HiveCheckpointID
    ) async throws -> HiveCheckpoint<Schema>? {
        guard let store = environment.checkpointStore else {
            throw HiveCheckpointQueryError.unsupported(operation: .loadCheckpointByID)
        }
        return try await store.loadCheckpoint(threadID: threadID, id: id)
    }

    /// Returns discoverable checkpoint-query capabilities for the configured store.
    public func checkpointCapabilities() -> HiveCheckpointStoreCapabilities {
        environment.checkpointStore?.capabilities ?? .none
    }

    public func getLatestStore(threadID: HiveThreadID) -> HiveGlobalStore<Schema>? {
        threadStates[threadID]?.global
    }

    public func getLatestCheckpoint(threadID: HiveThreadID) async throws -> HiveCheckpoint<Schema>? {
        guard let store = environment.checkpointStore else { return nil }
        return try await store.loadLatest(threadID: threadID)
    }

    /// Returns a unified state snapshot for the given thread.
    /// Checks in-memory state first (O(1)), then falls back to the checkpoint store.
    /// Returns `nil` when no state exists for the thread.
    public func getState(threadID: HiveThreadID) async throws -> HiveRuntimeStateSnapshot<Schema>? {
        if let state = threadStates[threadID] {
            return try snapshot(
                threadID: threadID,
                state: state,
                checkpointSummary: nil
            )
        }

        guard let store = environment.checkpointStore else { return nil }
        guard let checkpoint = try await store.loadLatest(threadID: threadID) else { return nil }
        let state = try decodeCheckpoint(checkpoint, debugPayloads: false)
        let summary = HiveCheckpointSummary(
            id: checkpoint.id,
            threadID: checkpoint.threadID,
            runID: checkpoint.runID,
            stepIndex: checkpoint.stepIndex,
            schemaVersion: checkpoint.schemaVersion,
            graphVersion: checkpoint.graphVersion
        )
        return try snapshot(
            threadID: threadID,
            state: state,
            checkpointSummary: summary
        )
    }

    /// Returns accumulated fork lifecycle events emitted by this runtime instance.
    public func getForkEventHistory(limit: Int? = nil) -> [HiveEvent] {
        guard let limit else { return forkEventHistory }
        if limit <= 0 { return [] }
        if limit >= forkEventHistory.count { return forkEventHistory }
        return Array(forkEventHistory.suffix(limit))
    }

    /// Returns deduplicated, lexicographically sorted node IDs from a frontier.
    /// A node can appear multiple times in the frontier (scheduled by both a router and a static
    /// edge). `nextNodes` must deduplicate for a consistent API contract.
    private func deduplicatedNextNodes(from frontier: [HiveFrontierTask<Schema>]) -> [HiveNodeID] {
        Array(Set(frontier.map(\.seed.nodeID))).sorted {
            HiveOrdering.lexicographicallyPrecedes($0.rawValue, $1.rawValue)
        }
    }

    private func snapshot(
        threadID: HiveThreadID,
        state: ThreadState<Schema>,
        checkpointSummary: HiveCheckpointSummary?
    ) throws -> HiveRuntimeStateSnapshot<Schema> {
        let globalHashes = try makeGlobalChannelPayloadHashes(from: state.global)
        let frontierSummary = try makeFrontierSummary(from: state.frontier)
        let interruption = try makeInterruptionSnapshot(from: state.interruption)
        return HiveRuntimeStateSnapshot(
            threadID: threadID,
            runID: state.runID,
            stepIndex: state.stepIndex,
            interruption: interruption,
            checkpointID: checkpointSummary?.id ?? state.latestCheckpointID,
            checkpoint: checkpointSummary,
            globalChannelPayloadHashesByID: globalHashes,
            frontierSummary: frontierSummary,
            store: state.global
        )
    }
}
