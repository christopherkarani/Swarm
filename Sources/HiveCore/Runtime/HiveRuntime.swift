import Foundation
import Mutex

// MARK: - HiveRuntime

/// Deterministic runtime for executing a compiled graph.
public actor HiveRuntime<Schema: HiveSchema>: Sendable {
    public init(graph: CompiledHiveGraph<Schema>, environment: HiveEnvironment<Schema>) throws {
        self.graph = graph
        self.environment = environment
        self.environmentSnapshot = environment
        let registry = try HiveSchemaRegistry<Schema>()
        self.registry = registry
        self.initialCache = HiveInitialCache(registry: registry)
        self.storeSupport = HiveStoreSupport(registry: registry)
        self.threadStates = [:]
        self.threadQueues = [:]
    }

    public func run(
        threadID: HiveThreadID,
        input: Schema.Input,
        options: HiveRunOptions
    ) -> HiveRunHandle<Schema> {
        do {
            try validateRunOptions(options)
            try validateRetryPolicies()
            try validateRequiredCodecs()
        } catch {
            return makeFailFastHandle(threadID: threadID, options: options, error: error)
        }

        let attemptID = HiveRunAttemptID(UUID())
        let runID = threadStates[threadID]?.runID ?? HiveRunID(UUID())
        let capacity = max(1, options.eventBufferCapacity)
        let streamController = HiveEventStreamController(capacity: capacity)
        let events = streamController.makeStream()

        let previous = threadQueues[threadID]
        let outcome = Task { [weak self] in
            if let previous {
                await previous.value
            }
            guard let self else {
                throw CancellationError()
            }
            return try await self.runAttempt(
                threadID: threadID,
                input: input,
                options: options,
                runID: runID,
                attemptID: attemptID,
                streamController: streamController
            )
        }

        threadQueues[threadID] = Task {
            _ = try? await outcome.value
        }

        return HiveRunHandle(
            runID: runID,
            attemptID: attemptID,
            events: events,
            outcome: outcome,
            streamController: streamController
        )
    }

    public func resume(
        threadID: HiveThreadID,
        interruptID: HiveInterruptID,
        payload: Schema.ResumePayload,
        options: HiveRunOptions
    ) -> HiveRunHandle<Schema> {
        do {
            try validateRunOptions(options)
            try validateRetryPolicies()
            try validateRequiredCodecs()
        } catch {
            return makeFailFastHandle(threadID: threadID, options: options, error: error)
        }

        let attemptID = HiveRunAttemptID(UUID())
        let runID = threadStates[threadID]?.runID ?? HiveRunID(UUID())
        let capacity = max(1, options.eventBufferCapacity)
        let streamController = HiveEventStreamController(capacity: capacity)
        let events = streamController.makeStream()

        let previous = threadQueues[threadID]
        let outcome = Task { [weak self] in
            if let previous {
                await previous.value
            }
            guard let self else { throw CancellationError() }
            return try await self.resumeAttempt(
                threadID: threadID,
                interruptID: interruptID,
                payload: payload,
                options: options,
                runID: runID,
                attemptID: attemptID,
                streamController: streamController
            )
        }

        threadQueues[threadID] = Task {
            _ = try? await outcome.value
        }

        return HiveRunHandle(
            runID: runID,
            attemptID: attemptID,
            events: events,
            outcome: outcome,
            streamController: streamController
        )
    }

    public func applyExternalWrites(
        threadID: HiveThreadID,
        writes: [AnyHiveWrite<Schema>],
        options: HiveRunOptions
    ) -> HiveRunHandle<Schema> {
        do {
            try validateRunOptions(options)
            try validateRetryPolicies()
            try validateRequiredCodecs()
        } catch {
            return makeFailFastHandle(threadID: threadID, options: options, error: error)
        }

        let attemptID = HiveRunAttemptID(UUID())
        let runID = threadStates[threadID]?.runID ?? HiveRunID(UUID())
        let capacity = max(1, options.eventBufferCapacity)
        let streamController = HiveEventStreamController(capacity: capacity)
        let events = streamController.makeStream()

        let previous = threadQueues[threadID]
        let outcome = Task { [weak self] in
            if let previous {
                await previous.value
            }
            guard let self else { throw CancellationError() }
            return try await self.applyExternalWritesAttempt(
                threadID: threadID,
                writes: writes,
                options: options,
                runID: runID,
                attemptID: attemptID,
                streamController: streamController
            )
        }

        threadQueues[threadID] = Task {
            _ = try? await outcome.value
        }

        return HiveRunHandle(
            runID: runID,
            attemptID: attemptID,
            events: events,
            outcome: outcome,
            streamController: streamController
        )
    }

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

    /// Creates an independent target thread lineage from a source checkpoint.
    public func fork(
        threadID sourceThreadID: HiveThreadID,
        to newThreadID: HiveThreadID,
        from checkpointID: HiveCheckpointID? = nil,
        options: HiveRunOptions? = nil
    ) async throws -> HiveForkResult<Schema> {
        if let options {
            try validateRunOptions(options)
            try validateRequiredCodecs()
        }

        let attemptID = makeForkAttemptID(
            sourceThreadID: sourceThreadID,
            targetThreadID: newThreadID,
            requestedCheckpointID: checkpointID
        )
        let provisionalRunID = makeForkRunID(
            sourceThreadID: sourceThreadID,
            targetThreadID: newThreadID,
            sourceCheckpointID: checkpointID
        )
        var eventIndex: UInt64 = 0
        emitForkLifecycleEvent(
            runID: provisionalRunID,
            attemptID: attemptID,
            eventIndex: &eventIndex,
            kind: .forkStarted(
                sourceThreadID: sourceThreadID,
                targetThreadID: newThreadID,
                sourceCheckpointID: checkpointID
            )
        )

        do {
            guard let store = environment.checkpointStore else {
                throw HiveRuntimeError.forkCheckpointStoreMissing
            }

            try await validateForkTargetAvailability(newThreadID, store: store)

            let sourceCheckpoint = try await resolveForkSourceCheckpoint(
                sourceThreadID: sourceThreadID,
                checkpointID: checkpointID,
                store: store
            )
            let sourceCheckpointID = sourceCheckpoint.id
            let targetRunID = provisionalRunID

            var targetState = try decodeCheckpointForFork(sourceCheckpoint, debugPayloads: options?.debugPayloads ?? false)
            targetState.runID = targetRunID
            targetState.latestCheckpointID = nil

            let lineage = makeForkLineage(
                sourceThreadID: sourceThreadID,
                sourceCheckpoint: sourceCheckpoint,
                targetThreadID: newThreadID,
                targetRunID: targetRunID
            )

            var targetCheckpointID: HiveCheckpointID?
            if shouldPersistForkCheckpoint(options: options) {
                let targetCheckpoint = try makeCheckpoint(
                    threadID: newThreadID,
                    state: targetState,
                    debugPayloads: options?.debugPayloads ?? false,
                    lineage: checkpointLineage(from: lineage)
                )
                try await saveCheckpoint(targetCheckpoint, to: store)
                targetCheckpointID = targetCheckpoint.id
                targetState.latestCheckpointID = targetCheckpoint.id
            }

            threadStates[newThreadID] = targetState

            emitForkLifecycleEvent(
                runID: targetRunID,
                attemptID: attemptID,
                eventIndex: &eventIndex,
                kind: .forkCompleted(
                    sourceThreadID: sourceThreadID,
                    targetThreadID: newThreadID,
                    sourceCheckpointID: sourceCheckpointID,
                    targetCheckpointID: targetCheckpointID
                )
            )

            return HiveForkResult(
                sourceThreadID: sourceThreadID,
                sourceCheckpointID: sourceCheckpointID,
                targetThreadID: newThreadID,
                targetCheckpointID: targetCheckpointID,
                runID: targetRunID,
                lineage: lineage
            )
        } catch let runtimeError as HiveRuntimeError {
            emitForkLifecycleEvent(
                runID: provisionalRunID,
                attemptID: attemptID,
                eventIndex: &eventIndex,
                kind: .forkFailed(
                    sourceThreadID: sourceThreadID,
                    targetThreadID: newThreadID,
                    sourceCheckpointID: checkpointID,
                    errorCode: forkRuntimeErrorCode(runtimeError)
                ),
                metadata: ["errorCode": forkRuntimeErrorCode(runtimeError)]
            )
            throw runtimeError
        } catch {
            emitForkLifecycleEvent(
                runID: provisionalRunID,
                attemptID: attemptID,
                eventIndex: &eventIndex,
                kind: .forkFailed(
                    sourceThreadID: sourceThreadID,
                    targetThreadID: newThreadID,
                    sourceCheckpointID: checkpointID,
                    errorCode: "fork_unknown_error"
                ),
                metadata: ["errorCode": "fork_unknown_error"]
            )
            throw error
        }
    }

    // MARK: - Private

    private let graph: CompiledHiveGraph<Schema>
    private let environment: HiveEnvironment<Schema>
    public nonisolated let environmentSnapshot: HiveEnvironment<Schema>
    private let registry: HiveSchemaRegistry<Schema>
    private let initialCache: HiveInitialCache<Schema>
    private let storeSupport: HiveStoreSupport<Schema>

    private var threadStates: [HiveThreadID: ThreadState<Schema>]
    private var threadQueues: [HiveThreadID: Task<Void, Never>]
    private var forkEventHistory: [HiveEvent] = []

    // MARK: - Streaming Mode Helpers

    /// Builds a snapshot of all global channel values for streaming.
    private func buildStoreSnapshot(state: ThreadState<Schema>, debugPayloads: Bool) throws -> [HiveSnapshotValue] {
        try registry.sortedChannelSpecs.compactMap { spec -> HiveSnapshotValue? in
            guard spec.scope == .global else { return nil }
            let hash = try payloadHash(for: spec.id, in: state.global)
            let debugVal: (any Sendable)? = debugPayloads ? (try? state.global.valueAny(for: spec.id)) : nil
            return HiveSnapshotValue(channelID: spec.id, payloadHash: hash, debugValue: debugVal)
        }
    }

    /// Builds channel update values for only the channels written in this step.
    private func buildChannelUpdates(writtenChannels: [HiveChannelID], state: ThreadState<Schema>, debugPayloads: Bool) throws -> [HiveSnapshotValue] {
        try writtenChannels.sorted(by: { $0.rawValue < $1.rawValue }).compactMap { channelID -> HiveSnapshotValue? in
            let hash = try payloadHash(for: channelID, in: state.global)
            let debugVal: (any Sendable)? = debugPayloads ? (try? state.global.valueAny(for: channelID)) : nil
            return HiveSnapshotValue(channelID: channelID, payloadHash: hash, debugValue: debugVal)
        }
    }

    /// Emits streaming mode events if enabled in options.
    private func emitStreamingEvents(
        mode: HiveStreamingMode,
        state: ThreadState<Schema>,
        writtenChannels: [HiveChannelID],
        debugPayloads: Bool,
        stepIndex: Int,
        emitter: HiveEventEmitter
    ) throws {
        guard mode != .events else { return }

        if mode == .values || mode == .combined {
            let snapshot = try buildStoreSnapshot(state: state, debugPayloads: debugPayloads)
            emitter.emit(
                kind: .storeSnapshot(channelValues: snapshot),
                stepIndex: stepIndex,
                taskOrdinal: nil,
                treatAsNonDroppable: true
            )
        }

        if mode == .updates || mode == .combined {
            let updates = try buildChannelUpdates(writtenChannels: writtenChannels, state: state, debugPayloads: debugPayloads)
            emitter.emit(
                kind: .channelUpdates(channelValues: updates),
                stepIndex: stepIndex,
                taskOrdinal: nil,
                treatAsNonDroppable: true
            )
        }
    }

    private func emitForkLifecycleEvent(
        runID: HiveRunID,
        attemptID: HiveRunAttemptID,
        eventIndex: inout UInt64,
        kind: HiveEventKind,
        metadata: [String: String] = [:]
    ) {
        let id = HiveEventID(
            runID: runID,
            attemptID: attemptID,
            eventIndex: eventIndex,
            stepIndex: nil,
            taskOrdinal: nil
        )
        forkEventHistory.append(HiveEvent(id: id, kind: kind, metadata: metadata))
        eventIndex &+= 1
    }

    private func validateForkTargetAvailability(
        _ targetThreadID: HiveThreadID,
        store: AnyHiveCheckpointStore<Schema>
    ) async throws {
        if threadStates[targetThreadID] != nil || threadQueues[targetThreadID] != nil {
            throw HiveRuntimeError.forkTargetThreadConflict(threadID: targetThreadID)
        }

        if try await store.loadLatest(threadID: targetThreadID) != nil {
            throw HiveRuntimeError.forkTargetThreadConflict(threadID: targetThreadID)
        }
    }

    private func resolveForkSourceCheckpoint(
        sourceThreadID: HiveThreadID,
        checkpointID: HiveCheckpointID?,
        store: AnyHiveCheckpointStore<Schema>
    ) async throws -> HiveCheckpoint<Schema> {
        if let checkpointID {
            do {
                guard let checkpoint = try await store.loadCheckpoint(threadID: sourceThreadID, id: checkpointID) else {
                    throw HiveRuntimeError.forkSourceCheckpointMissing(
                        threadID: sourceThreadID,
                        checkpointID: checkpointID
                    )
                }
                return checkpoint
            } catch let queryError as HiveCheckpointQueryError {
                switch queryError {
                case .unsupported(operation: _):
                    throw HiveRuntimeError.forkCheckpointQueryUnsupported
                }
            }
        }

        guard let latest = try await store.loadLatest(threadID: sourceThreadID) else {
            throw HiveRuntimeError.forkSourceCheckpointMissing(threadID: sourceThreadID, checkpointID: nil)
        }
        return latest
    }

    private func decodeCheckpointForFork(
        _ checkpoint: HiveCheckpoint<Schema>,
        debugPayloads: Bool
    ) throws -> ThreadState<Schema> {
        do {
            return try decodeCheckpoint(checkpoint, debugPayloads: debugPayloads)
        } catch let runtimeError as HiveRuntimeError {
            switch runtimeError {
            case let .checkpointVersionMismatch(expectedSchema, expectedGraph, foundSchema, foundGraph):
                throw HiveRuntimeError.forkSchemaGraphMismatch(
                    expectedSchema: expectedSchema,
                    expectedGraph: expectedGraph,
                    foundSchema: foundSchema,
                    foundGraph: foundGraph
                )
            case let .checkpointCorrupt(field, errorDescription):
                throw HiveRuntimeError.forkMalformedCheckpoint(
                    field: field,
                    errorDescription: errorDescription
                )
            case let .checkpointDecodeFailed(channelID, errorDescription):
                throw HiveRuntimeError.forkMalformedCheckpoint(
                    field: "channel.\(channelID.rawValue)",
                    errorDescription: errorDescription
                )
            case let .missingCodec(channelID):
                throw HiveRuntimeError.forkMalformedCheckpoint(
                    field: "codec.\(channelID.rawValue)",
                    errorDescription: "missing codec"
                )
            default:
                throw HiveRuntimeError.forkMalformedCheckpoint(
                    field: "checkpoint",
                    errorDescription: String(describing: runtimeError)
                )
            }
        }
    }

    private func shouldPersistForkCheckpoint(options: HiveRunOptions?) -> Bool {
        guard let options else { return false }
        switch options.checkpointPolicy {
        case .disabled:
            return false
        case .everyStep, .every, .onInterrupt:
            return true
        }
    }

    private func makeForkLineage(
        sourceThreadID: HiveThreadID,
        sourceCheckpoint: HiveCheckpoint<Schema>,
        targetThreadID: HiveThreadID,
        targetRunID: HiveRunID
    ) -> HiveForkLineage {
        var data = Data("HFL1".utf8)
        data.append(0)
        data.append(contentsOf: sourceThreadID.rawValue.utf8)
        data.append(0)
        data.append(contentsOf: sourceCheckpoint.id.rawValue.utf8)
        data.append(0)
        data.append(contentsOf: targetThreadID.rawValue.utf8)
        data.append(0)
        data.append(contentsOf: sourceCheckpoint.runID.rawValue.uuidString.utf8)
        data.append(0)
        data.append(contentsOf: targetRunID.rawValue.uuidString.utf8)
        data.append(0)
        data.append(contentsOf: graph.schemaVersion.utf8)
        data.append(0)
        data.append(contentsOf: graph.graphVersion.utf8)
        let lineageID = HiveSHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()

        return HiveForkLineage(
            lineageID: lineageID,
            sourceThreadID: sourceThreadID,
            sourceCheckpointID: sourceCheckpoint.id,
            targetThreadID: targetThreadID,
            sourceRunID: sourceCheckpoint.runID,
            targetRunID: targetRunID,
            schemaVersion: graph.schemaVersion,
            graphVersion: graph.graphVersion,
            createdAtNanoseconds: environment.clock.nowNanoseconds()
        )
    }

    private func checkpointLineage(from lineage: HiveForkLineage) -> HiveCheckpointLineage {
        HiveCheckpointLineage(
            lineageID: lineage.lineageID,
            sourceThreadID: lineage.sourceThreadID,
            sourceCheckpointID: lineage.sourceCheckpointID,
            targetThreadID: lineage.targetThreadID,
            sourceRunID: lineage.sourceRunID,
            targetRunID: lineage.targetRunID,
            schemaVersion: lineage.schemaVersion,
            graphVersion: lineage.graphVersion,
            createdAtNanoseconds: lineage.createdAtNanoseconds
        )
    }

    private func makeForkRunID(
        sourceThreadID: HiveThreadID,
        targetThreadID: HiveThreadID,
        sourceCheckpointID: HiveCheckpointID?
    ) -> HiveRunID {
        HiveRunID(
            deterministicUUID(
                prefix: "HFORK_RUN1",
                parts: [
                    sourceThreadID.rawValue,
                    targetThreadID.rawValue,
                    sourceCheckpointID?.rawValue ?? "latest"
                ]
            )
        )
    }

    private func makeForkAttemptID(
        sourceThreadID: HiveThreadID,
        targetThreadID: HiveThreadID,
        requestedCheckpointID: HiveCheckpointID?
    ) -> HiveRunAttemptID {
        HiveRunAttemptID(
            deterministicUUID(
                prefix: "HFORK_ATTEMPT1",
                parts: [
                    sourceThreadID.rawValue,
                    targetThreadID.rawValue,
                    requestedCheckpointID?.rawValue ?? "latest"
                ]
            )
        )
    }

    private func deterministicUUID(prefix: String, parts: [String]) -> UUID {
        var data = Data(prefix.utf8)
        for part in parts {
            data.append(0)
            data.append(contentsOf: part.utf8)
        }
        let digest = HiveSHA256.hash(data: data)
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuidBytes = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuidBytes)
    }

    private func forkRuntimeErrorCode(_ runtimeError: HiveRuntimeError) -> String {
        switch runtimeError {
        case .forkSourceCheckpointMissing:
            return "fork_source_checkpoint_missing"
        case .forkCheckpointStoreMissing:
            return "fork_checkpoint_store_missing"
        case .forkCheckpointQueryUnsupported:
            return "fork_checkpoint_query_unsupported"
        case .forkTargetThreadConflict:
            return "fork_target_thread_conflict"
        case .forkSchemaGraphMismatch:
            return "fork_schema_graph_mismatch"
        case .forkMalformedCheckpoint:
            return "fork_malformed_checkpoint"
        default:
            return "fork_runtime_error"
        }
    }

    private func makeFailFastHandle(
        threadID: HiveThreadID,
        options: HiveRunOptions,
        error: Error
    ) -> HiveRunHandle<Schema> {
        let attemptID = HiveRunAttemptID(UUID())
        let runID: HiveRunID
        if let existing = threadStates[threadID] {
            runID = existing.runID
        } else {
            runID = HiveRunID(UUID())
        }
        let capacity = max(1, options.eventBufferCapacity)
        let streamController = HiveEventStreamController(capacity: capacity)
        let events = streamController.makeStream()
        streamController.finish(throwing: error)

        let outcome = Task<HiveRunOutcome<Schema>, Error> {
            throw error
        }

        return HiveRunHandle(
            runID: runID,
            attemptID: attemptID,
            events: events,
            outcome: outcome,
            streamController: streamController
        )
    }

    private func ensureThreadState(for threadID: HiveThreadID) throws -> ThreadState<Schema> {
        if let existing = threadStates[threadID] {
            return existing
        }

        let state = try makeFreshThreadState(for: threadID)
        threadStates[threadID] = state
        return state
    }

    private func makeFreshThreadState(for _: HiveThreadID) throws -> ThreadState<Schema> {
        let runID = HiveRunID(UUID())
        let global = try HiveGlobalStore(registry: registry, initialCache: initialCache)
        let joinSeen = Dictionary(
            uniqueKeysWithValues: graph.joinEdges.map {
                ($0.id, HiveBitset(wordCount: graph.joinBitsetWordCount))
            }
        )
        return ThreadState(
            runID: runID,
            stepIndex: 0,
            global: global,
            frontier: [],
            deferredFrontier: [],
            joinSeenParents: joinSeen,
            interruption: nil,
            latestCheckpointID: nil,
            channelVersionsByChannelID: [:],
            versionsSeenByNodeID: [:],
            updatedChannelsLastCommit: [],
            nodeCaches: [:]
        )
    }

    private func resolveBaselineState(
        threadID: HiveThreadID,
        debugPayloads: Bool,
        emitter: HiveEventEmitter
    ) async throws -> ThreadState<Schema> {
        if let existing = threadStates[threadID] {
            return existing
        }

        guard let store = environment.checkpointStore else {
            let fresh = try makeFreshThreadState(for: threadID)
            threadStates[threadID] = fresh
            return fresh
        }

        let checkpoint = try await store.loadLatest(threadID: threadID)
        guard let checkpoint else {
            let fresh = try makeFreshThreadState(for: threadID)
            threadStates[threadID] = fresh
            return fresh
        }

        let state = try decodeCheckpoint(checkpoint, debugPayloads: debugPayloads)
        threadStates[threadID] = state
        emitter.emit(kind: .checkpointLoaded(checkpointID: checkpoint.id), stepIndex: nil, taskOrdinal: nil)
        return state
    }

    private func loadCheckpointStateForResume(
        threadID: HiveThreadID,
        interruptID: HiveInterruptID,
        debugPayloads: Bool,
        emitter: HiveEventEmitter
    ) async throws -> ThreadState<Schema> {
        guard let store = environment.checkpointStore else {
            throw HiveRuntimeError.checkpointStoreMissing
        }

        let checkpoint = try await store.loadLatest(threadID: threadID)
        guard let checkpoint else {
            throw HiveRuntimeError.noCheckpointToResume
        }

        let state = try decodeCheckpoint(checkpoint, debugPayloads: debugPayloads)
        guard let interruption = state.interruption else {
            throw HiveRuntimeError.noInterruptToResume
        }
        guard interruption.id == interruptID else {
            throw HiveRuntimeError.resumeInterruptMismatch(expected: interruption.id, found: interruptID)
        }

        threadStates[threadID] = state
        emitter.emit(kind: .checkpointLoaded(checkpointID: checkpoint.id), stepIndex: nil, taskOrdinal: nil)
        return state
    }

    private func decodeCheckpoint(
        _ checkpoint: HiveCheckpoint<Schema>,
        debugPayloads: Bool
    ) throws -> ThreadState<Schema> {
        guard checkpoint.schemaVersion == graph.schemaVersion,
              checkpoint.graphVersion == graph.graphVersion else {
            throw HiveRuntimeError.checkpointVersionMismatch(
                expectedSchema: graph.schemaVersion,
                expectedGraph: graph.graphVersion,
                foundSchema: checkpoint.schemaVersion,
                foundGraph: checkpoint.graphVersion
            )
        }

        let globalSpecs = registry.sortedChannelSpecs.filter { spec in
            spec.scope == .global && spec.persistence == .checkpointed
        }
        let allowedGlobalIDs = Set(globalSpecs.map { $0.id.rawValue })
        if let unexpected = checkpoint.globalDataByChannelID.keys
            .filter({ !allowedGlobalIDs.contains($0) })
            .sorted(by: HiveOrdering.lexicographicallyPrecedes)
            .first {
            throw HiveRuntimeError.checkpointCorrupt(
                field: "globalDataByChannelID",
                errorDescription: "unexpected channel id \(unexpected)"
            )
        }

        var checkpointedGlobals: [HiveChannelID: any Sendable] = [:]
        checkpointedGlobals.reserveCapacity(globalSpecs.count)
        for spec in globalSpecs {
            guard let data = checkpoint.globalDataByChannelID[spec.id.rawValue] else {
                throw HiveRuntimeError.checkpointDecodeFailed(
                    channelID: spec.id,
                    errorDescription: "missing entry"
                )
            }
            guard let decode = spec._decodeBox else {
                throw HiveRuntimeError.missingCodec(channelID: spec.id)
            }
            do {
                let value = try decode(data)
                try storeSupport.validateValueType(value, spec: spec)
                checkpointedGlobals[spec.id] = value
            } catch {
                throw HiveRuntimeError.checkpointDecodeFailed(
                    channelID: spec.id,
                    errorDescription: HiveErrorDescription.describe(error, debugPayloads: debugPayloads)
                )
            }
        }

        let global = try HiveGlobalStore(
            registry: registry,
            initialCache: initialCache,
            checkpointedValuesByID: checkpointedGlobals
        )

        func decodeFrontier(
            _ entries: [HiveCheckpointTask],
            fieldPrefix: String
        ) throws -> [HiveFrontierTask<Schema>] {
            var frontier: [HiveFrontierTask<Schema>] = []
            frontier.reserveCapacity(entries.count)

            for entry in entries {
                guard entry.localFingerprint.count == 32 else {
                    throw HiveRuntimeError.checkpointCorrupt(
                        field: "\(fieldPrefix).localFingerprint",
                        errorDescription: "expected 32 bytes"
                    )
                }

                var overlay = HiveTaskLocalStore<Schema>(registry: registry)
                let sortedKeys = entry.localDataByChannelID.keys.sorted(by: HiveOrdering.lexicographicallyPrecedes)
                for key in sortedKeys {
                    let channelID = HiveChannelID(key)
                    guard let spec = registry.channelSpecsByID[channelID],
                          spec.scope == .taskLocal else {
                        throw HiveRuntimeError.checkpointDecodeFailed(
                            channelID: channelID,
                            errorDescription: "unknown task-local channel"
                        )
                    }
                    guard let decode = spec._decodeBox else {
                        throw HiveRuntimeError.missingCodec(channelID: channelID)
                    }
                    guard let data = entry.localDataByChannelID[key] else { continue }
                    do {
                        let value = try decode(data)
                        try overlay.setAny(value, for: channelID)
                    } catch {
                        throw HiveRuntimeError.checkpointDecodeFailed(
                            channelID: channelID,
                            errorDescription: HiveErrorDescription.describe(error, debugPayloads: debugPayloads)
                        )
                    }
                }

                let recomputed = try HiveTaskLocalFingerprint.digest(
                    registry: registry,
                    initialCache: initialCache,
                    overlay: overlay,
                    debugPayloads: debugPayloads
                )
                guard recomputed == entry.localFingerprint else {
                    throw HiveRuntimeError.checkpointCorrupt(
                        field: "\(fieldPrefix).localFingerprint",
                        errorDescription: "fingerprint mismatch"
                    )
                }

                frontier.append(
                    HiveFrontierTask(
                        seed: HiveTaskSeed(nodeID: entry.nodeID, local: overlay),
                        provenance: entry.provenance,
                        isJoinSeed: false
                    )
                )
            }

            return frontier
        }

        let frontier = try decodeFrontier(checkpoint.frontier, fieldPrefix: "frontier")
        let deferredFrontier = try decodeFrontier(checkpoint.deferredFrontier, fieldPrefix: "deferredFrontier")

        let expectedJoinIDs = Set(graph.joinEdges.map(\.id))
        let actualJoinIDs = Set(checkpoint.joinBarrierSeenByJoinID.keys)
        if expectedJoinIDs != actualJoinIDs {
            let missing = expectedJoinIDs.subtracting(actualJoinIDs)
                .sorted(by: HiveOrdering.lexicographicallyPrecedes)
                .first
            let extra = actualJoinIDs.subtracting(expectedJoinIDs)
                .sorted(by: HiveOrdering.lexicographicallyPrecedes)
                .first
            let description: String
            if let missing {
                description = "missing join id \(missing)"
            } else if let extra {
                description = "unexpected join id \(extra)"
            } else {
                description = "join keys mismatch"
            }
            throw HiveRuntimeError.checkpointCorrupt(
                field: "joinBarrierSeenByJoinID",
                errorDescription: description
            )
        }

        var joinSeenParents: [String: HiveBitset] = [:]
        joinSeenParents.reserveCapacity(graph.joinEdges.count)
        for edge in graph.joinEdges {
            guard let seenParents = checkpoint.joinBarrierSeenByJoinID[edge.id] else {
                throw HiveRuntimeError.checkpointCorrupt(
                    field: "joinBarrierSeenByJoinID",
                    errorDescription: "missing join id \(edge.id)"
                )
            }
            let allowed = Set(edge.parents.map(\.rawValue))
            var previous: String?
            for parent in seenParents {
                guard allowed.contains(parent) else {
                    throw HiveRuntimeError.checkpointCorrupt(
                        field: "joinBarrierSeenByJoinID",
                        errorDescription: "unexpected parent \(parent)"
                    )
                }
                if let previous,
                   !HiveOrdering.lexicographicallyPrecedes(previous, parent) {
                    throw HiveRuntimeError.checkpointCorrupt(
                        field: "joinBarrierSeenByJoinID",
                        errorDescription: "parents not strictly sorted"
                    )
                }
                previous = parent
            }

            var seenMask = HiveBitset(wordCount: graph.joinBitsetWordCount)
            for parent in seenParents {
                let parentID = HiveNodeID(parent)
                guard let ordinal = graph.nodeOrdinalByID[parentID] else {
                    throw HiveRuntimeError.checkpointCorrupt(
                        field: "joinBarrierSeenByJoinID",
                        errorDescription: "unknown parent \(parent)"
                    )
                }
                seenMask.insert(ordinal)
            }
            joinSeenParents[edge.id] = seenMask
        }

        var channelVersionsByChannelID: [HiveChannelID: UInt64] = [:]
        channelVersionsByChannelID.reserveCapacity(checkpoint.channelVersionsByChannelID.count)
        for (rawID, version) in checkpoint.channelVersionsByChannelID {
            let channelID = HiveChannelID(rawID)
            guard let spec = registry.channelSpecsByID[channelID], spec.scope == .global else {
                throw HiveRuntimeError.checkpointCorrupt(
                    field: "channelVersionsByChannelID",
                    errorDescription: "unknown or non-global channel id \(rawID)"
                )
            }
            if version > 0 {
                channelVersionsByChannelID[channelID] = version
            }
        }

        var versionsSeenByNodeID: [HiveNodeID: [HiveChannelID: UInt64]] = [:]
        versionsSeenByNodeID.reserveCapacity(checkpoint.versionsSeenByNodeID.count)
        for (rawNodeID, rawChannelVersions) in checkpoint.versionsSeenByNodeID {
            let nodeID = HiveNodeID(rawNodeID)
            guard graph.nodesByID[nodeID] != nil else {
                throw HiveRuntimeError.checkpointCorrupt(
                    field: "versionsSeenByNodeID",
                    errorDescription: "unknown node id \(rawNodeID)"
                )
            }
            var perChannel: [HiveChannelID: UInt64] = [:]
            perChannel.reserveCapacity(rawChannelVersions.count)
            for (rawChannelID, seenVersion) in rawChannelVersions {
                let channelID = HiveChannelID(rawChannelID)
                guard let spec = registry.channelSpecsByID[channelID], spec.scope == .global else {
                    throw HiveRuntimeError.checkpointCorrupt(
                        field: "versionsSeenByNodeID",
                        errorDescription: "unknown or non-global channel id \(rawChannelID)"
                    )
                }
                perChannel[channelID] = seenVersion
            }
            versionsSeenByNodeID[nodeID] = perChannel
        }

        var updatedChannelsLastCommit: [HiveChannelID] = []
        updatedChannelsLastCommit.reserveCapacity(checkpoint.updatedChannelsLastCommit.count)
        for rawID in checkpoint.updatedChannelsLastCommit {
            let channelID = HiveChannelID(rawID)
            guard let spec = registry.channelSpecsByID[channelID], spec.scope == .global else {
                throw HiveRuntimeError.checkpointCorrupt(
                    field: "updatedChannelsLastCommit",
                    errorDescription: "unknown or non-global channel id \(rawID)"
                )
            }
            updatedChannelsLastCommit.append(channelID)
        }

        return ThreadState(
            runID: checkpoint.runID,
            stepIndex: checkpoint.stepIndex,
            global: global,
            frontier: frontier,
            deferredFrontier: deferredFrontier,
            joinSeenParents: joinSeenParents,
            interruption: checkpoint.interruption,
            latestCheckpointID: checkpoint.id,
            channelVersionsByChannelID: channelVersionsByChannelID,
            versionsSeenByNodeID: versionsSeenByNodeID,
            updatedChannelsLastCommit: updatedChannelsLastCommit,
            nodeCaches: [:]
        )
    }

    private func runAttempt(
        threadID: HiveThreadID,
        input: Schema.Input,
        options: HiveRunOptions,
        runID: HiveRunID,
        attemptID: HiveRunAttemptID,
        streamController: HiveEventStreamController
    ) async throws -> HiveRunOutcome<Schema> {
        let emitter = HiveEventEmitter(
            runID: runID,
            attemptID: attemptID,
            streamController: streamController
        )

        emitter.emit(kind: .runStarted(threadID: threadID), stepIndex: nil, taskOrdinal: nil)

        do {
            try validateRunOptions(options)
            try validateRetryPolicies()
            try validateRequiredCodecs()

            var state = try await resolveBaselineState(
                threadID: threadID,
                debugPayloads: options.debugPayloads,
                emitter: emitter
            )
            rebindLoadedStateRunIDIfNeeded(state: &state, to: runID, threadID: threadID)

            let inputContext = HiveInputContext(threadID: threadID, runID: state.runID, stepIndex: state.stepIndex)
            let inputWrites = try Schema.inputWrites(input, inputContext: inputContext)

            if let interruption = state.interruption {
                // A pending interrupt can only be superseded by explicit new input writes.
                // If there is no new input payload, fail closed and keep interruption pending.
                guard inputWrites.isEmpty == false else {
                    throw HiveRuntimeError.interruptPending(interruptID: interruption.id)
                }

                state.interruption = nil
                state.frontier = []
                state.joinSeenParents = [:]
            }

            if state.frontier.isEmpty {
                state.frontier = graph.start.map {
                    HiveFrontierTask(seed: HiveTaskSeed(nodeID: $0), provenance: .graph, isJoinSeed: false)
                }
            }

            if !inputWrites.isEmpty {
                var global = state.global
                let writtenChannels = try applyInputWrites(inputWrites, to: &global)
                state.global = global
                state.updatedChannelsLastCommit = writtenChannels
                if !writtenChannels.isEmpty {
                    for channelID in writtenChannels {
                        let currentVersion = state.channelVersionsByChannelID[channelID] ?? 0
                        state.channelVersionsByChannelID[channelID] = currentVersion &+ 1
                    }
                }
            }
            threadStates[threadID] = state

            return try await executeRunLoop(
                initialState: state,
                threadID: threadID,
                options: options,
                attemptID: attemptID,
                emitter: emitter,
                streamController: streamController
            )
        } catch let cancellation as RuntimeCancellation {
            throw cancellation
        } catch {
            streamController.finish(throwing: error)
            throw error
        }
    }

    private func resumeAttempt(
        threadID: HiveThreadID,
        interruptID: HiveInterruptID,
        payload: Schema.ResumePayload,
        options: HiveRunOptions,
        runID: HiveRunID,
        attemptID: HiveRunAttemptID,
        streamController: HiveEventStreamController
    ) async throws -> HiveRunOutcome<Schema> {
        let emitter = HiveEventEmitter(
            runID: runID,
            attemptID: attemptID,
            streamController: streamController
        )

        emitter.emit(kind: .runStarted(threadID: threadID), stepIndex: nil, taskOrdinal: nil)

        do {
            try validateRunOptions(options)
            try validateRetryPolicies()
            try validateRequiredCodecs()

            var state = try await loadCheckpointStateForResume(
                threadID: threadID,
                interruptID: interruptID,
                debugPayloads: options.debugPayloads,
                emitter: emitter
            )
            rebindLoadedStateRunIDIfNeeded(state: &state, to: runID, threadID: threadID)

            emitter.emit(kind: .runResumed(interruptID: interruptID), stepIndex: nil, taskOrdinal: nil)

            let resume = HiveResume<Schema>(interruptID: interruptID, payload: payload)

            return try await executeRunLoop(
                initialState: state,
                threadID: threadID,
                options: options,
                attemptID: attemptID,
                emitter: emitter,
                streamController: streamController,
                firstStepResume: resume,
                clearInterruptionAfterFirstStep: true
            )
        } catch let cancellation as RuntimeCancellation {
            throw cancellation
        } catch {
            streamController.finish(throwing: error)
            throw error
        }
    }

    /// Shared run-loop extracted from `runAttempt` and `resumeAttempt`.
    ///
    /// Executes supersteps in a `while true` loop until the graph finishes, is interrupted,
    /// runs out of steps, or is cancelled. Handles `RuntimeCancellation` internally (returns
    /// `.cancelled`); all other errors propagate to the caller.
    ///
    /// - Parameters:
    ///   - initialState: Thread state with frontier already populated.
    ///   - threadID: The thread ID used for `threadStates[threadID] = state`.
    ///   - options: Run options (maxSteps, checkpoint policy, streaming mode, etc.).
    ///   - attemptID: Current attempt ID passed through to `executeStep`.
    ///   - emitter: Event emitter for lifecycle events.
    ///   - streamController: Stream controller to finish on terminal outcomes.
    ///   - firstStepResume: If non-nil, passed to `executeStep` only on the first iteration
    ///     (used by `resumeAttempt` to deliver the resume payload).
    ///   - clearInterruptionAfterFirstStep: If `true`, clears `nextState.interruption` after
    ///     the first step when no new interrupt was selected (used by `resumeAttempt`).
    private func executeRunLoop(
        initialState: ThreadState<Schema>,
        threadID: HiveThreadID,
        options: HiveRunOptions,
        attemptID: HiveRunAttemptID,
        emitter: HiveEventEmitter,
        streamController: HiveEventStreamController,
        firstStepResume: HiveResume<Schema>? = nil,
        clearInterruptionAfterFirstStep: Bool = false
    ) async throws -> HiveRunOutcome<Schema> {
        var state = initialState
        var stepsExecutedThisAttempt = 0
        var firstStepDone = false

        do {
            while true {
                if Task.isCancelled {
                    let output = try buildOutput(options: options, state: state)
                    emitter.emit(
                        kind: .runCancelled(cause: .explicitRequest),
                        stepIndex: nil,
                        taskOrdinal: nil
                    )
                    streamController.finish()
                    return .cancelled(output: output, checkpointID: state.latestCheckpointID)
                }

                if state.frontier.isEmpty {
                    if !state.deferredFrontier.isEmpty {
                        state.frontier = state.deferredFrontier
                        state.deferredFrontier = []
                        threadStates[threadID] = state
                        continue
                    }
                    let output = try buildOutput(options: options, state: state)
                    emitter.emit(kind: .runFinished, stepIndex: nil, taskOrdinal: nil)
                    streamController.finish()
                    return .finished(output: output, checkpointID: state.latestCheckpointID)
                }

                if stepsExecutedThisAttempt == options.maxSteps {
                    let output = try buildOutput(options: options, state: state)
                    emitter.emit(kind: .runFinished, stepIndex: nil, taskOrdinal: nil)
                    streamController.finish()
                    return .outOfSteps(maxSteps: options.maxSteps, output: output, checkpointID: state.latestCheckpointID)
                }

                let stepOutcome = try await executeStep(
                    state: state,
                    threadID: threadID,
                    attemptID: attemptID,
                    options: options,
                    emitter: emitter,
                    resume: (!firstStepDone) ? firstStepResume : nil
                )

                var nextState = stepOutcome.nextState

                // For resumeAttempt: clear the pending interruption after the first successfully
                // committed resumed step, unless a new interrupt is selected in that same commit.
                if clearInterruptionAfterFirstStep && !firstStepDone {
                    if stepOutcome.selectedInterrupt == nil {
                        nextState.interruption = nil
                    }
                }
                firstStepDone = true

                if let checkpoint = stepOutcome.checkpointToSave {
                    guard let store = environment.checkpointStore else {
                        throw HiveRuntimeError.checkpointStoreMissing
                    }
                    try await saveCheckpoint(checkpoint, to: store)
                    nextState.latestCheckpointID = checkpoint.id
                }

                state = nextState
                threadStates[threadID] = nextState
                stepsExecutedThisAttempt += 1

                if !stepOutcome.writtenGlobalChannels.isEmpty {
                    for channelID in stepOutcome.writtenGlobalChannels {
                        let payloadHash = try payloadHash(for: channelID, in: state.global)
                        emitter.emit(
                            kind: .writeApplied(channelID: channelID, payloadHash: payloadHash),
                            stepIndex: state.stepIndex - 1,
                            taskOrdinal: nil,
                            metadata: try writeAppliedMetadata(
                                for: channelID,
                                in: state.global,
                                debugPayloads: options.debugPayloads
                            )
                        )
                    }
                }

                if stepOutcome.dropped.droppedDebugEvents > 0 {
                    emitter.emit(
                        kind: .streamBackpressure(droppedDebugEvents: stepOutcome.dropped.droppedDebugEvents),
                        stepIndex: state.stepIndex - 1,
                        taskOrdinal: nil
                    )
                }

                if let checkpoint = stepOutcome.checkpointToSave {
                    emitter.emit(
                        kind: .checkpointSaved(checkpointID: checkpoint.id),
                        stepIndex: state.stepIndex - 1,
                        taskOrdinal: nil
                    )
                }

                try emitStreamingEvents(
                    mode: options.streamingMode,
                    state: state,
                    writtenChannels: stepOutcome.writtenGlobalChannels,
                    debugPayloads: options.debugPayloads,
                    stepIndex: state.stepIndex - 1,
                    emitter: emitter
                )

                emitter.emit(
                    kind: .stepFinished(stepIndex: state.stepIndex - 1, nextFrontierCount: state.frontier.count),
                    stepIndex: state.stepIndex - 1,
                    taskOrdinal: nil
                )

                if let interrupt = stepOutcome.selectedInterrupt {
                    let checkpointID = stepOutcome.checkpointToSave?.id ?? state.latestCheckpointID
                    guard let checkpointID else {
                        throw HiveRuntimeError.internalInvariantViolation(
                            "Interrupted outcome requires a checkpoint ID."
                        )
                    }
                    emitter.emit(kind: .runInterrupted(interruptID: interrupt.id), stepIndex: nil, taskOrdinal: nil)
                    streamController.finish()
                    return .interrupted(interruption: HiveInterruption(interrupt: interrupt, checkpointID: checkpointID))
                }

                if state.frontier.isEmpty && state.deferredFrontier.isEmpty {
                    let output = try buildOutput(options: options, state: state)
                    emitter.emit(kind: .runFinished, stepIndex: nil, taskOrdinal: nil)
                    streamController.finish()
                    return .finished(output: output, checkpointID: state.latestCheckpointID)
                }

                // Give the cancellation flag a fair observation point between committed steps.
                await Task.yield()
            }
        } catch let cancellation as RuntimeCancellation {
            guard let state = threadStates[threadID] else {
                throw cancellation
            }
            let output = try buildOutput(options: options, state: state)
            emitter.emit(
                kind: .runCancelled(cause: cancellation.eventCause),
                stepIndex: nil,
                taskOrdinal: nil
            )
            streamController.finish()
            return .cancelled(output: output, checkpointID: state.latestCheckpointID)
        }
    }

    private func applyExternalWritesAttempt(
        threadID: HiveThreadID,
        writes: [AnyHiveWrite<Schema>],
        options: HiveRunOptions,
        runID: HiveRunID,
        attemptID: HiveRunAttemptID,
        streamController: HiveEventStreamController
    ) async throws -> HiveRunOutcome<Schema> {
        let emitter = HiveEventEmitter(
            runID: runID,
            attemptID: attemptID,
            streamController: streamController
        )
        var cancellationState: ThreadState<Schema>? = threadStates[threadID]

        emitter.emit(kind: .runStarted(threadID: threadID), stepIndex: nil, taskOrdinal: nil)

        do {
            try validateRunOptions(options)
            try validateRetryPolicies()
            try validateRequiredCodecs()

            var state = try await resolveBaselineState(
                threadID: threadID,
                debugPayloads: options.debugPayloads,
                emitter: emitter
            )
            rebindLoadedStateRunIDIfNeeded(state: &state, to: runID, threadID: threadID)
            cancellationState = state
            if let interruption = state.interruption {
                throw HiveRuntimeError.interruptPending(interruptID: interruption.id)
            }

            let stepIndex = state.stepIndex
            emitter.emit(kind: .stepStarted(stepIndex: stepIndex, frontierCount: 0), stepIndex: stepIndex, taskOrdinal: nil)

            var postGlobal = state.global
            let writtenChannels = try applyExternalWrites(writes, to: &postGlobal)

            var nextState = state
            nextState.stepIndex += 1
            nextState.global = postGlobal
            // Frontier and join barriers remain unchanged.
            nextState.updatedChannelsLastCommit = writtenChannels
            if !writtenChannels.isEmpty {
                for channelID in writtenChannels {
                    let currentVersion = nextState.channelVersionsByChannelID[channelID] ?? 0
                    nextState.channelVersionsByChannelID[channelID] = currentVersion &+ 1
                }
            }

            let checkpointToSave: HiveCheckpoint<Schema>?
            if environment.checkpointStore != nil {
                checkpointToSave = try makeCheckpoint(threadID: threadID, state: nextState, debugPayloads: options.debugPayloads)
            } else {
                checkpointToSave = nil
            }

            if let checkpointToSave {
                guard let store = environment.checkpointStore else {
                    throw HiveRuntimeError.checkpointStoreMissing
                }
                try await saveCheckpoint(checkpointToSave, to: store)
                nextState.latestCheckpointID = checkpointToSave.id
            }

            state = nextState
            threadStates[threadID] = nextState

            if !writtenChannels.isEmpty {
                for channelID in writtenChannels {
                    let payloadHash = try payloadHash(for: channelID, in: state.global)
                    emitter.emit(
                        kind: .writeApplied(channelID: channelID, payloadHash: payloadHash),
                        stepIndex: stepIndex,
                        taskOrdinal: nil,
                        metadata: try writeAppliedMetadata(
                            for: channelID,
                            in: state.global,
                            debugPayloads: options.debugPayloads
                        )
                    )
                }
            }

            if let checkpointToSave {
                emitter.emit(
                    kind: .checkpointSaved(checkpointID: checkpointToSave.id),
                    stepIndex: stepIndex,
                    taskOrdinal: nil
                )
            }

            try emitStreamingEvents(
                mode: options.streamingMode,
                state: state,
                writtenChannels: writtenChannels,
                debugPayloads: options.debugPayloads,
                stepIndex: stepIndex,
                emitter: emitter
            )

            emitter.emit(
                kind: .stepFinished(stepIndex: stepIndex, nextFrontierCount: state.frontier.count),
                stepIndex: stepIndex,
                taskOrdinal: nil
            )

            let output = try buildOutput(options: options, state: state)
            emitter.emit(kind: .runFinished, stepIndex: nil, taskOrdinal: nil)
            streamController.finish()
            return .finished(output: output, checkpointID: state.latestCheckpointID)
        } catch let cancellation as RuntimeCancellation {
            guard let state = cancellationState ?? threadStates[threadID] else {
                throw cancellation
            }
            let output = try buildOutput(options: options, state: state)
            emitter.emit(
                kind: .runCancelled(cause: cancellation.eventCause),
                stepIndex: nil,
                taskOrdinal: nil
            )
            streamController.finish()
            return .cancelled(output: output, checkpointID: state.latestCheckpointID)
        } catch {
            streamController.finish(throwing: error)
            throw error
        }
    }

    /// Internal sentinel used to represent runtime-observed cancellation without treating arbitrary user-thrown
    /// `CancellationError` values as cancellation.
    private enum RuntimeCancellation: Error, Sendable {
        case checkpointPersistenceRace
        case executionObserved

        var eventCause: HiveRunCancellationCause {
            switch self {
            case .checkpointPersistenceRace:
                return .checkpointPersistenceRace
            case .executionObserved:
                return .executionObserved
            }
        }
    }

    private func saveCheckpoint(
        _ checkpoint: HiveCheckpoint<Schema>,
        to store: AnyHiveCheckpointStore<Schema>
    ) async throws {
        do {
            try await store.save(checkpoint)
        } catch is CancellationError {
            throw RuntimeCancellation.checkpointPersistenceRace
        }
    }

    /// Ensures loaded checkpoint state uses the active run handle's run ID.
    /// This keeps handle/event IDs and newly persisted checkpoints in sync on cold-start restores.
    private func rebindLoadedStateRunIDIfNeeded(
        state: inout ThreadState<Schema>,
        to runID: HiveRunID,
        threadID: HiveThreadID
    ) {
        guard state.runID != runID else { return }
        state.runID = runID
        threadStates[threadID] = state
    }

    public func validateRunOptions(_ options: HiveRunOptions) throws {
        guard options.maxSteps >= 0 else {
            throw HiveRunOptionsValidationError.invalidBounds(
                option: "maxSteps",
                reason: "must be >= 0"
            )
        }
        guard options.maxConcurrentTasks >= 1 else {
            throw HiveRunOptionsValidationError.invalidBounds(
                option: "maxConcurrentTasks",
                reason: "must be >= 1"
            )
        }
        guard options.eventBufferCapacity >= 1 else {
            throw HiveRunOptionsValidationError.invalidBounds(
                option: "eventBufferCapacity",
                reason: "must be >= 1"
            )
        }
        if case let .every(steps) = options.checkpointPolicy, steps < 1 {
            throw HiveRunOptionsValidationError.invalidBounds(
                option: "checkpointPolicy.every(steps:)",
                reason: "steps must be >= 1"
            )
        }
        if options.deterministicStreamBuffering, options.streamingMode != .events {
            throw HiveRunOptionsValidationError.unsupportedCombination(
                reason: "deterministicStreamBuffering is only supported when streamingMode == .events"
            )
        }
        switch options.checkpointPolicy {
        case .disabled:
            break
        case .everyStep, .every, .onInterrupt:
            if environment.checkpointStore == nil {
                throw HiveRunOptionsValidationError.missingRequiredComponent(
                    component: "checkpointStore",
                    reason: "checkpointPolicy requires a configured checkpoint store"
                )
            }
        }
        if let override = options.outputProjectionOverride {
            _ = try normalizedOutputProjection(override)
        }
    }

    private func validateRetryPolicies() throws {
        var invalid: HiveNodeID?
        for (id, node) in graph.nodesByID {
            if case let .exponentialBackoff(_, factor, maxAttempts, _) = node.retryPolicy {
                let invalidPolicy = maxAttempts < 1 || !factor.isFinite || factor < 1.0
                if invalidPolicy {
                    if let current = invalid {
                        if HiveOrdering.lexicographicallyPrecedes(id.rawValue, current.rawValue) {
                            invalid = id
                        }
                    } else {
                        invalid = id
                    }
                }
            }
        }
        if let invalid {
            throw HiveRunOptionsValidationError.unsupportedCombination(
                reason: "invalid retry policy for node \(invalid.rawValue)"
            )
        }
    }

    private func validateRequiredCodecs() throws {
        if let missing = registry.firstMissingRequiredCodecID() {
            throw HiveRuntimeError.missingCodec(channelID: missing)
        }
    }

    private func normalizedOutputProjection(_ projection: HiveOutputProjection) throws -> HiveOutputProjection {
        let normalized = projection.normalized()
        switch normalized {
        case .fullStore:
            return normalized
        case .channels(let ids):
            for id in ids {
                guard let spec = registry.channelSpecsByID[id] else {
                    throw HiveRunOptionsValidationError.unsupportedCombination(
                        reason: "output projection includes unknown channel \(id.rawValue)"
                    )
                }
                if spec.scope == .taskLocal {
                    throw HiveRunOptionsValidationError.unsupportedCombination(
                        reason: "output projection includes task-local channel \(id.rawValue)"
                    )
                }
            }
            return normalized
        }
    }

    private func buildOutput(options: HiveRunOptions, state: ThreadState<Schema>) throws -> HiveRunOutput<Schema> {
        let projection = try normalizedOutputProjection(
            options.outputProjectionOverride ?? graph.outputProjection
        )

        switch projection {
        case .fullStore:
            return .fullStore(state.global)
        case .channels(let ids):
            var values: [HiveProjectedChannelValue] = []
            values.reserveCapacity(ids.count)
            for id in ids {
                let value = try state.global.valueAny(for: id)
                values.append(HiveProjectedChannelValue(id: id, value: value))
            }
            return .channels(values)
        }
    }

    private func applyInputWrites(
        _ writes: [AnyHiveWrite<Schema>],
        to global: inout HiveGlobalStore<Schema>
    ) throws -> [HiveChannelID] {
        var globalWritesByChannel: [HiveChannelID: [AnyHiveWrite<Schema>]] = [:]
        for write in writes {
            guard let spec = registry.channelSpecsByID[write.channelID] else {
                throw HiveRuntimeError.unknownChannelID(write.channelID)
            }
            if spec.scope != .global {
                throw HiveRuntimeError.taskLocalWriteNotAllowed
            }
            try storeSupport.validateValueType(write.value, spec: spec)
            globalWritesByChannel[write.channelID, default: []].append(write)
        }

        var written: [HiveChannelID] = []
        for spec in registry.sortedChannelSpecs where spec.scope == .global {
            let writesForChannel = globalWritesByChannel[spec.id] ?? []
            if writesForChannel.isEmpty { continue }
            if spec.updatePolicy == .single, writesForChannel.count > 1 {
                throw HiveRuntimeError.updatePolicyViolation(
                    channelID: spec.id,
                    policy: .single,
                    writeCount: writesForChannel.count
                )
            }
            var current = try global.valueAny(for: spec.id)
            for write in writesForChannel {
                current = try spec._reduceBox(current, write.value)
            }
            try global.setAny(current, for: spec.id)
            written.append(spec.id)
        }

        return written
    }

    private func selectInterrupt(
        tasks: [HiveTask<Schema>],
        outputs: [HiveNodeOutput<Schema>]
    ) throws -> HiveInterrupt<Schema>? {
        // Selection is by smallest taskOrdinal (i.e., earliest task in this step).
        for (index, output) in outputs.enumerated() {
            if let request = output.interrupt {
                let winningTaskID = tasks[index].id
                let interruptID = makeInterruptID(winningTaskID: winningTaskID)
                return HiveInterrupt(id: interruptID, payload: request.payload)
            }
        }
        return nil
    }

    private func makeInterruptID(winningTaskID: HiveTaskID) -> HiveInterruptID {
        var bytes = Data()
        bytes.append(contentsOf: "HINT1".utf8)
        bytes.append(contentsOf: winningTaskID.rawValue.utf8)
        let hash = HiveSHA256.hash(data: bytes)
        let hex = hash.compactMap { String(format: "%02x", $0) }.joined()
        return HiveInterruptID(hex)
    }

    private func applyExternalWrites(
        _ writes: [AnyHiveWrite<Schema>],
        to global: inout HiveGlobalStore<Schema>
    ) throws -> [HiveChannelID] {
        func validateValueType(_ value: any Sendable, spec: AnyHiveChannelSpec<Schema>) throws {
            let expectedValueTypeID = spec.valueTypeID
            let actualValueTypeID = String(reflecting: type(of: value))
            guard expectedValueTypeID == actualValueTypeID else {
                throw HiveExternalWriteError.payloadTypeMismatch(
                    channelID: spec.id,
                    expectedValueTypeID: expectedValueTypeID,
                    actualValueTypeID: actualValueTypeID
                )
            }
        }

        var writesByChannel: [HiveChannelID: [AnyHiveWrite<Schema>]] = [:]
        for write in writes {
            guard let spec = registry.channelSpecsByID[write.channelID] else {
                throw HiveExternalWriteError.unknownChannel(channelID: write.channelID)
            }
            if spec.scope != .global {
                throw HiveExternalWriteError.scopeMismatch(
                    channelID: write.channelID,
                    expected: .global,
                    actual: spec.scope
                )
            }
            try validateValueType(write.value, spec: spec)
            writesByChannel[write.channelID, default: []].append(write)
        }

        // Enforce `.single` using the provided external writes array grouping.
        for spec in registry.sortedChannelSpecs where spec.scope == .global {
            let channelWrites = writesByChannel[spec.id] ?? []
            if spec.updatePolicy == .single, channelWrites.count > 1 {
                throw HiveExternalWriteError.updatePolicyViolation(
                    channelID: spec.id,
                    policy: .single,
                    writeCount: channelWrites.count
                )
            }
        }

        var written: [HiveChannelID] = []
        for spec in registry.sortedChannelSpecs where spec.scope == .global {
            let channelWrites = writesByChannel[spec.id] ?? []
            if channelWrites.isEmpty { continue }
            var current = try global.valueAny(for: spec.id)
            for write in channelWrites {
                current = try spec._reduceBox(current, write.value)
            }
            try global.setAny(current, for: spec.id)
            written.append(spec.id)
        }

        return written
    }

    private func makeCheckpoint(
        threadID: HiveThreadID,
        state: ThreadState<Schema>,
        debugPayloads: Bool,
        lineage: HiveCheckpointLineage? = nil
    ) throws -> HiveCheckpoint<Schema> {
        let checkpointID = try makeCheckpointID(runID: state.runID, stepIndex: state.stepIndex)

        var globalDataByChannelID: [String: Data] = [:]
        for spec in registry.sortedChannelSpecs where spec.scope == .global && spec.persistence == .checkpointed {
            guard let encode = spec._encodeBox else {
                throw HiveRuntimeError.missingCodec(channelID: spec.id)
            }
            let value = try state.global.valueAny(for: spec.id)
            do {
                globalDataByChannelID[spec.id.rawValue] = try encode(value)
            } catch {
                throw HiveRuntimeError.checkpointEncodeFailed(
                    channelID: spec.id,
                    errorDescription: HiveErrorDescription.describe(error, debugPayloads: debugPayloads)
                )
            }
        }

        let taskLocalSpecs = registry.sortedChannelSpecs.filter { $0.scope == .taskLocal }
        func encodeFrontier(_ entries: [HiveFrontierTask<Schema>]) throws -> [HiveCheckpointTask] {
            var encoded: [HiveCheckpointTask] = []
            encoded.reserveCapacity(entries.count)

            for entry in entries {
                let fingerprint = try HiveTaskLocalFingerprint.digest(
                    registry: registry,
                    initialCache: initialCache,
                    overlay: entry.seed.local,
                    debugPayloads: debugPayloads
                )

                var localDataByChannelID: [String: Data] = [:]
                for spec in taskLocalSpecs where spec.persistence == .checkpointed {
                    guard let value = entry.seed.local.valueAny(for: spec.id) else { continue }
                    guard let encode = spec._encodeBox else {
                        throw HiveRuntimeError.missingCodec(channelID: spec.id)
                    }
                    do {
                        localDataByChannelID[spec.id.rawValue] = try encode(value)
                    } catch {
                        throw HiveRuntimeError.checkpointEncodeFailed(
                            channelID: spec.id,
                            errorDescription: HiveErrorDescription.describe(error, debugPayloads: debugPayloads)
                        )
                    }
                }

                encoded.append(
                    HiveCheckpointTask(
                        provenance: entry.provenance,
                        nodeID: entry.seed.nodeID,
                        localFingerprint: fingerprint,
                        localDataByChannelID: localDataByChannelID
                    )
                )
            }

            return encoded
        }

        let checkpointFrontier = try encodeFrontier(state.frontier)
        let checkpointDeferredFrontier = try encodeFrontier(state.deferredFrontier)

        var joinBarrierSeenByJoinID: [String: [String]] = [:]
        joinBarrierSeenByJoinID.reserveCapacity(graph.joinEdges.count)
        for edge in graph.joinEdges {
            let seenMask = state.joinSeenParents[edge.id] ?? HiveBitset(wordCount: graph.joinBitsetWordCount)
            var sortedParents: [String] = []
            sortedParents.reserveCapacity(edge.parents.count)
            for parent in edge.parents {
                guard let ordinal = graph.nodeOrdinalByID[parent] else { continue }
                if seenMask.contains(ordinal) {
                    sortedParents.append(parent.rawValue)
                }
            }
            joinBarrierSeenByJoinID[edge.id] = sortedParents
        }

        var channelVersionsByChannelID: [String: UInt64] = [:]
        channelVersionsByChannelID.reserveCapacity(state.channelVersionsByChannelID.count)
        for (channelID, version) in state.channelVersionsByChannelID where version > 0 {
            channelVersionsByChannelID[channelID.rawValue] = version
        }

        var versionsSeenByNodeID: [String: [String: UInt64]] = [:]
        versionsSeenByNodeID.reserveCapacity(state.versionsSeenByNodeID.count)
        for (nodeID, perChannel) in state.versionsSeenByNodeID {
            var rawPerChannel: [String: UInt64] = [:]
            rawPerChannel.reserveCapacity(perChannel.count)
            for (channelID, seenVersion) in perChannel {
                rawPerChannel[channelID.rawValue] = seenVersion
            }
            versionsSeenByNodeID[nodeID.rawValue] = rawPerChannel
        }

        return HiveCheckpoint(
            id: checkpointID,
            threadID: threadID,
            runID: state.runID,
            stepIndex: state.stepIndex,
            schemaVersion: graph.schemaVersion,
            graphVersion: graph.graphVersion,
            checkpointFormatVersion: lineage == nil ? "HCP2" : "HCP3",
            channelVersionsByChannelID: channelVersionsByChannelID,
            versionsSeenByNodeID: versionsSeenByNodeID,
            updatedChannelsLastCommit: state.updatedChannelsLastCommit.map(\.rawValue),
            globalDataByChannelID: globalDataByChannelID,
            frontier: checkpointFrontier,
            deferredFrontier: checkpointDeferredFrontier,
            joinBarrierSeenByJoinID: joinBarrierSeenByJoinID,
            interruption: state.interruption,
            lineage: lineage
        )
    }

    private func makeCheckpointID(runID: HiveRunID, stepIndex: Int) throws -> HiveCheckpointID {
        guard let stepValue = UInt32(exactly: stepIndex) else {
            throw HiveRuntimeError.stepIndexOutOfRange(stepIndex: stepIndex)
        }

        var bytes = Data()
        bytes.append(contentsOf: "HCP1".utf8)
        var uuid = runID.rawValue.uuid
        withUnsafeBytes(of: &uuid) { bytes.append(contentsOf: $0) }
        appendUInt32BE(stepValue, to: &bytes)

        let hash = HiveSHA256.hash(data: bytes)
        let hex = hash.compactMap { String(format: "%02x", $0) }.joined()
        return HiveCheckpointID(hex)
    }

    private func executeStep(
        state: ThreadState<Schema>,
        threadID: HiveThreadID,
        attemptID: HiveRunAttemptID,
        options: HiveRunOptions,
        emitter: HiveEventEmitter,
        resume: HiveResume<Schema>?
    ) async throws -> StepOutcome<Schema> {
        var state = state
        let stepIndex = state.stepIndex
        guard UInt32(exactly: stepIndex) != nil else {
            throw HiveRuntimeError.stepIndexOutOfRange(stepIndex: stepIndex)
        }

        let frontier = state.frontier
        let tasks = try buildTasks(
            frontier: frontier,
            runID: state.runID,
            stepIndex: stepIndex,
            debugPayloads: options.debugPayloads
        )

        snapshotVersionsSeenForStepStart(tasks: tasks, state: &state)

        emitter.emit(
            kind: .stepStarted(stepIndex: stepIndex, frontierCount: tasks.count),
            stepIndex: stepIndex,
            taskOrdinal: nil
        )

        for task in tasks {
            emitter.emit(
                kind: .taskStarted(node: task.nodeID, taskID: task.id),
                stepIndex: stepIndex,
                taskOrdinal: task.ordinal
            )
        }

        if Task.isCancelled {
            for task in tasks {
                emitter.emit(
                    kind: .taskFailed(
                        node: task.nodeID,
                        taskID: task.id,
                        errorDescription: HiveErrorDescription.describe(CancellationError(), debugPayloads: options.debugPayloads)
                    ),
                    stepIndex: stepIndex,
                    taskOrdinal: task.ordinal
                )
            }
            throw RuntimeCancellation.executionObserved
        }

        let droppedCounter = HiveDroppedEventCounter()

        // Cache lookup: skip execution for tasks with a cache hit.
        let cacheNowNs = DispatchTime.now().uptimeNanoseconds
        let cachePreStoreView = HiveStoreView(
            global: state.global,
            taskLocal: HiveTaskLocalStore(registry: registry),
            initialCache: initialCache,
            registry: registry
        )
        var cachedResultsByTaskIndex: [Int: HiveNodeOutput<Schema>] = [:]
        for (index, task) in tasks.enumerated() {
            guard let node = graph.nodesByID[task.nodeID],
                  let cachePolicy = node.cachePolicy
            else { continue }
            // Compute cache key — log failures instead of silently disabling caching.
            let cacheKey: String
            do {
                cacheKey = try cachePolicy.keyProvider.cacheKey(forNode: task.nodeID, store: cachePreStoreView)
            } catch {
                environment.logger.debug(
                    "Cache key computation failed for node \(task.nodeID.rawValue): \(error)",
                    metadata: [:]
                )
                continue
            }
            guard var nodeCache = state.nodeCaches[task.nodeID] else { continue }
            let cachedOutput = nodeCache.lookup(key: cacheKey, policy: cachePolicy, nowNanoseconds: cacheNowNs)
            // Always write back: persists LRU order update AND expired-entry removal to state.
            // Without this writeback, HiveNodeCache is a value type whose mutations inside
            // lookup() are silently discarded, breaking LRU eviction ordering.
            state.nodeCaches[task.nodeID] = nodeCache
            guard let cachedOutput else { continue }
            cachedResultsByTaskIndex[index] = cachedOutput
        }

        // Only execute tasks that were not cache hits.
        let uncachedIndices = tasks.indices.filter { cachedResultsByTaskIndex[$0] == nil }
        let uncachedTasks = uncachedIndices.map { tasks[$0] }

        let executionResults = await Self.executeTasks(
            tasks: uncachedTasks,
            options: options,
            stepIndex: stepIndex,
            threadID: threadID,
            attemptID: attemptID,
            runID: state.runID,
            graph: graph,
            environment: environment,
            registry: registry,
            initialCache: initialCache,
            preStepGlobal: state.global,
            resume: resume,
            emitter: emitter,
            droppedCounter: droppedCounter
        )

        // Merge cached and fresh results back into a full-sized array.
        var results = Array(repeating: TaskExecutionResult<Schema>.empty, count: tasks.count)
        for (resultIndex, taskIndex) in uncachedIndices.enumerated() {
            results[taskIndex] = executionResults[resultIndex]
        }
        for (taskIndex, cachedOutput) in cachedResultsByTaskIndex {
            results[taskIndex] = TaskExecutionResult(
                output: cachedOutput,
                error: nil,
                streamEvents: nil,
                streamDrops: HiveDroppedEventCounts()
            )
        }

        if Task.isCancelled || results.contains(where: { $0.error is RuntimeCancellation }) {
            if options.deterministicStreamBuffering == false {
                // Live stream events already emitted (if any). Ensure determinism for task failure surface.
            }

            for task in tasks {
                emitter.emit(
                    kind: .taskFailed(
                        node: task.nodeID,
                        taskID: task.id,
                        errorDescription: HiveErrorDescription.describe(CancellationError(), debugPayloads: options.debugPayloads)
                    ),
                    stepIndex: stepIndex,
                    taskOrdinal: task.ordinal
                )
            }
            throw RuntimeCancellation.executionObserved
        }

        var dropped = droppedCounter.snapshot()
        if options.deterministicStreamBuffering {
            for result in results {
                dropped.droppedDebugEvents += result.streamDrops.droppedDebugEvents
            }

            for result in results {
                guard let events = result.streamEvents else { continue }
                for event in events {
                    let enqueueResult = emitter.emit(
                        kind: event.kind,
                        stepIndex: stepIndex,
                        taskOrdinal: event.taskOrdinal,
                        metadata: event.metadata,
                        treatAsNonDroppable: true
                    )
                    dropped.record(enqueueResult)
                }
            }
        }

        var firstError: Error?
        for (index, result) in results.enumerated() {
            let task = tasks[index]
            if let error = result.error {
                if firstError == nil {
                    firstError = error
                }
                emitter.emit(
                    kind: .taskFailed(
                        node: task.nodeID,
                        taskID: task.id,
                        errorDescription: HiveErrorDescription.describe(error, debugPayloads: options.debugPayloads)
                    ),
                    stepIndex: stepIndex,
                    taskOrdinal: task.ordinal
                )
            } else {
                emitter.emit(
                    kind: .taskFinished(node: task.nodeID, taskID: task.id),
                    stepIndex: stepIndex,
                    taskOrdinal: task.ordinal
                )
            }
        }

        if let firstError {
            throw firstError
        }

        var outputs: [HiveNodeOutput<Schema>] = []
        outputs.reserveCapacity(results.count)
        for result in results {
            guard let output = result.output else {
                throw HiveRuntimeError.internalInvariantViolation(
                    "Task result missing output without error."
                )
            }
            outputs.append(output)
        }

        // Cache: store new outputs for nodes with a cache policy.
        var updatedNodeCaches = state.nodeCaches
        let storeNowNs = DispatchTime.now().uptimeNanoseconds
        for (index, output) in outputs.enumerated() {
            let task = tasks[index]
            guard let node = graph.nodesByID[task.nodeID],
                  let cachePolicy = node.cachePolicy,
                  let cacheKey = try? cachePolicy.keyProvider.cacheKey(forNode: task.nodeID, store: cachePreStoreView)
            else { continue }
            var nodeCache = updatedNodeCaches[task.nodeID] ?? HiveNodeCache()
            nodeCache.store(key: cacheKey, output: output, policy: cachePolicy, nowNanoseconds: storeNowNs)
            updatedNodeCaches[task.nodeID] = nodeCache
        }

        let commitResult = try commitStep(
            state: state,
            tasks: tasks,
            outputs: outputs,
            options: options
        )

        var nextState = state
        nextState.stepIndex += 1
        nextState.global = commitResult.global
        nextState.joinSeenParents = commitResult.joinSeenParents
        nextState.updatedChannelsLastCommit = commitResult.writtenGlobalChannels
        nextState.nodeCaches = updatedNodeCaches
        if !commitResult.writtenGlobalChannels.isEmpty {
            for channelID in commitResult.writtenGlobalChannels {
                let current = nextState.channelVersionsByChannelID[channelID] ?? 0
                nextState.channelVersionsByChannelID[channelID] = current &+ 1
            }
        }
        nextState.frontier = filterFrontierForTriggers(
            commitResult.frontier,
            channelVersionsByChannelID: nextState.channelVersionsByChannelID,
            versionsSeenByNodeID: nextState.versionsSeenByNodeID
        )
        nextState.deferredFrontier = state.deferredFrontier + commitResult.deferredFrontier

        let selectedInterrupt = try selectInterrupt(tasks: tasks, outputs: outputs)
        var checkpointToSave: HiveCheckpoint<Schema>?
        let shouldSaveForPolicy: Bool
        switch options.checkpointPolicy {
        case .disabled:
            shouldSaveForPolicy = false
        case .everyStep:
            shouldSaveForPolicy = true
        case .every(let steps):
            shouldSaveForPolicy = steps > 0 && (nextState.stepIndex % steps == 0)
        case .onInterrupt:
            shouldSaveForPolicy = selectedInterrupt != nil
        }

        let shouldSave = shouldSaveForPolicy || selectedInterrupt != nil
        if shouldSave {
            // Commit-time enforcement: checkpoint boundaries require checkpoint store.
            guard environment.checkpointStore != nil else {
                throw HiveRuntimeError.checkpointStoreMissing
            }
            if let selectedInterrupt {
                nextState.interruption = selectedInterrupt
            }
            checkpointToSave = try makeCheckpoint(
                threadID: threadID,
                state: nextState,
                debugPayloads: options.debugPayloads
            )
        }

        return StepOutcome(
            nextState: nextState,
            writtenGlobalChannels: commitResult.writtenGlobalChannels,
            dropped: dropped,
            selectedInterrupt: selectedInterrupt,
            checkpointToSave: checkpointToSave
        )
    }

    private func buildTasks(
        frontier: [HiveFrontierTask<Schema>],
        runID: HiveRunID,
        stepIndex: Int,
        debugPayloads: Bool
    ) throws -> [HiveTask<Schema>] {
        var tasks: [HiveTask<Schema>] = []
        tasks.reserveCapacity(frontier.count)

        for (ordinal, entry) in frontier.enumerated() {
            guard UInt32(exactly: ordinal) != nil else {
                throw HiveRuntimeError.taskOrdinalOutOfRange(ordinal: ordinal)
            }
            let fingerprint = try HiveTaskLocalFingerprint.digest(
                registry: registry,
                initialCache: initialCache,
                overlay: entry.seed.local,
                debugPayloads: debugPayloads
            )
            let taskID = try makeTaskID(
                runID: runID,
                stepIndex: stepIndex,
                nodeID: entry.seed.nodeID,
                ordinal: ordinal,
                localFingerprint: fingerprint
            )
            tasks.append(
                HiveTask(
                    id: taskID,
                    ordinal: ordinal,
                    provenance: entry.provenance,
                    nodeID: entry.seed.nodeID,
                    local: entry.seed.local
                )
            )
        }
        return tasks
    }

    private func snapshotVersionsSeenForStepStart(
        tasks: [HiveTask<Schema>],
        state: inout ThreadState<Schema>
    ) {
        if tasks.isEmpty { return }

        for task in tasks {
            guard let node = graph.nodesByID[task.nodeID] else { continue }
            let channels = node.runWhen.triggerChannels
            if channels.isEmpty { continue }

            var perChannel = state.versionsSeenByNodeID[task.nodeID] ?? [:]
            perChannel.reserveCapacity(max(perChannel.count, channels.count))
            for channelID in channels {
                perChannel[channelID] = state.channelVersionsByChannelID[channelID] ?? 0
            }
            state.versionsSeenByNodeID[task.nodeID] = perChannel
        }
    }

    private func filterFrontierForTriggers(
        _ frontier: [HiveFrontierTask<Schema>],
        channelVersionsByChannelID: [HiveChannelID: UInt64],
        versionsSeenByNodeID: [HiveNodeID: [HiveChannelID: UInt64]]
    ) -> [HiveFrontierTask<Schema>] {
        if frontier.isEmpty { return [] }

        func channelChanged(
            channelID: HiveChannelID,
            seen: [HiveChannelID: UInt64]?
        ) -> Bool {
            let current = channelVersionsByChannelID[channelID] ?? 0
            guard let seenValue = seen?[channelID] else { return true }
            return current > seenValue
        }

        var filtered: [HiveFrontierTask<Schema>] = []
        filtered.reserveCapacity(frontier.count)

        for entry in frontier {
            if entry.isJoinSeed {
                filtered.append(entry)
                continue
            }

            guard let node = graph.nodesByID[entry.seed.nodeID] else {
                filtered.append(entry)
                continue
            }

            switch node.runWhen.normalized {
            case .always:
                filtered.append(entry)
            case .anyOf(let channels):
                if channels.isEmpty {
                    filtered.append(entry)
                    continue
                }
                let seen = versionsSeenByNodeID[entry.seed.nodeID]
                if channels.contains(where: { channelChanged(channelID: $0, seen: seen) }) {
                    filtered.append(entry)
                }
            case .allOf(let channels):
                if channels.isEmpty {
                    filtered.append(entry)
                    continue
                }
                let seen = versionsSeenByNodeID[entry.seed.nodeID]
                if channels.allSatisfy({ channelChanged(channelID: $0, seen: seen) }) {
                    filtered.append(entry)
                }
            }
        }

        return filtered
    }

    private static func executeTasks(
        tasks: [HiveTask<Schema>],
        options: HiveRunOptions,
        stepIndex: Int,
        threadID: HiveThreadID,
        attemptID: HiveRunAttemptID,
        runID: HiveRunID,
        graph: CompiledHiveGraph<Schema>,
        environment: HiveEnvironment<Schema>,
        registry: HiveSchemaRegistry<Schema>,
        initialCache: HiveInitialCache<Schema>,
        preStepGlobal: HiveGlobalStore<Schema>,
        resume: HiveResume<Schema>?,
        emitter: HiveEventEmitter,
        droppedCounter: HiveDroppedEventCounter
    ) async -> [TaskExecutionResult<Schema>] {
        if tasks.isEmpty { return [] }
        let concurrency = max(1, min(options.maxConcurrentTasks, tasks.count))
        var results = Array(repeating: TaskExecutionResult<Schema>.empty, count: tasks.count)

        await withTaskGroup(of: (Int, TaskExecutionResult<Schema>).self) { group in
            var nextIndex = 0
            var cancellationObserved = false
            func addTask(_ index: Int) {
                let task = tasks[index]
                group.addTask {
                    let result = await Self.executeTask(
                        task: task,
                        stepIndex: stepIndex,
                        threadID: threadID,
                        attemptID: attemptID,
                        runID: runID,
                        options: options,
                        graph: graph,
                        environment: environment,
                        registry: registry,
                        initialCache: initialCache,
                        preStepGlobal: preStepGlobal,
                        resume: resume,
                        emitter: emitter,
                        droppedCounter: droppedCounter
                    )
                    return (index, result)
                }
            }

            while nextIndex < concurrency {
                addTask(nextIndex)
                nextIndex += 1
            }

            while let (index, result) = await group.next() {
                results[index] = result

                if cancellationObserved == false {
                    // If any task reports cancellation (including CancellationError during retry-backoff sleep),
                    // treat the step as cancelled and cancel remaining in-flight tasks.
                    if Task.isCancelled || (result.error is RuntimeCancellation) {
                        cancellationObserved = true
                        group.cancelAll()
                    }
                }

                if cancellationObserved == false, nextIndex < tasks.count {
                    addTask(nextIndex)
                    nextIndex += 1
                }
            }
        }

        return results
    }

    private static func executeTask(
        task: HiveTask<Schema>,
        stepIndex: Int,
        threadID: HiveThreadID,
        attemptID: HiveRunAttemptID,
        runID: HiveRunID,
        options: HiveRunOptions,
        graph: CompiledHiveGraph<Schema>,
        environment: HiveEnvironment<Schema>,
        registry: HiveSchemaRegistry<Schema>,
        initialCache: HiveInitialCache<Schema>,
        preStepGlobal: HiveGlobalStore<Schema>,
        resume: HiveResume<Schema>?,
        emitter: HiveEventEmitter,
        droppedCounter: HiveDroppedEventCounter
    ) async -> TaskExecutionResult<Schema> {
        guard let node = graph.nodesByID[task.nodeID] else {
            return TaskExecutionResult(error: HiveRuntimeError.unknownNodeID(task.nodeID))
        }

        switch node.retryPolicy {
        case .none:
            return await runNodeAttempt(
                node: node,
                task: task,
                stepIndex: stepIndex,
                threadID: threadID,
                attemptID: attemptID,
                runID: runID,
                options: options,
                environment: environment,
                registry: registry,
                initialCache: initialCache,
                preStepGlobal: preStepGlobal,
                resume: resume,
                emitter: emitter,
                droppedCounter: droppedCounter
            )
        case let .exponentialBackoff(initialNanoseconds, factor, maxAttempts, maxNanoseconds):
            var attempt = 1
            while attempt <= maxAttempts {
                let result = await runNodeAttempt(
                    node: node,
                    task: task,
                    stepIndex: stepIndex,
                    threadID: threadID,
                    attemptID: attemptID,
                    runID: runID,
                    options: options,
                    environment: environment,
                    registry: registry,
                    initialCache: initialCache,
                    preStepGlobal: preStepGlobal,
                    resume: resume,
                    emitter: emitter,
                    droppedCounter: droppedCounter
                )
                if result.error == nil {
                    return result
                }
                if attempt == maxAttempts {
                    return result
                }
                if Task.isCancelled {
                    return TaskExecutionResult(error: RuntimeCancellation.executionObserved)
                }

                let delay = Self.retryDelayNanoseconds(
                    initialNanoseconds: initialNanoseconds,
                    factor: factor,
                    attempt: attempt,
                    maxNanoseconds: maxNanoseconds
                )
                do {
                    try await environment.clock.sleep(nanoseconds: delay)
                } catch is CancellationError {
                    return TaskExecutionResult(error: RuntimeCancellation.executionObserved)
                } catch {
                    return TaskExecutionResult(error: error)
                }
                attempt += 1
            }
            return TaskExecutionResult(error: HiveRuntimeError.invalidRunOptions("retry attempts exhausted"))
        }
    }

    private static func retryDelayNanoseconds(
        initialNanoseconds: UInt64,
        factor: Double,
        attempt: Int,
        maxNanoseconds: UInt64
    ) -> UInt64 {
        // Spec: attempts are 1-based, and the delay for a failure before attempt+1 is:
        // min(maxNanoseconds, floor(initialNanoseconds * pow(factor, attempt-1))).
        let exponent = Double(max(0, attempt - 1))
        let raw = Double(initialNanoseconds) * pow(factor, exponent)
        let floored = raw.rounded(.down)
        let capped = min(Double(maxNanoseconds), floored)
        if capped <= 0 { return 0 }
        return UInt64(capped)
    }

    private static func runNodeAttempt(
        node: HiveCompiledNode<Schema>,
        task: HiveTask<Schema>,
        stepIndex: Int,
        threadID: HiveThreadID,
        attemptID: HiveRunAttemptID,
        runID: HiveRunID,
        options: HiveRunOptions,
        environment: HiveEnvironment<Schema>,
        registry: HiveSchemaRegistry<Schema>,
        initialCache: HiveInitialCache<Schema>,
        preStepGlobal: HiveGlobalStore<Schema>,
        resume: HiveResume<Schema>?,
        emitter: HiveEventEmitter,
        droppedCounter: HiveDroppedEventCounter
    ) async -> TaskExecutionResult<Schema> {
        let bufferingCapacity = max(1, options.eventBufferCapacity)
        let streamBuffer: HivePerAttemptStreamBuffer? = options.deterministicStreamBuffering
            ? HivePerAttemptStreamBuffer(capacity: bufferingCapacity, stepIndex: stepIndex, taskOrdinal: task.ordinal)
            : nil

        let storeView = HiveStoreView(
            global: preStepGlobal,
            taskLocal: task.local,
            initialCache: initialCache,
            registry: registry
        )

        let runContext = HiveRunContext<Schema>(
            runID: runID,
            threadID: threadID,
            attemptID: attemptID,
            stepIndex: stepIndex,
            taskID: task.id,
            options: options,
            resume: resume
        )

        let input = HiveNodeInput(
            store: storeView,
            run: runContext,
            context: environment.context,
            environment: environment,
            emitStream: { kind, metadata in
                if let streamBuffer {
                    streamBuffer.record(kind: mapStream(kind), metadata: metadata)
                    return
                }
                let enqueueResult = emitter.emit(
                    kind: mapStream(kind),
                    stepIndex: stepIndex,
                    taskOrdinal: task.ordinal,
                    metadata: metadata
                )
                droppedCounter.record(enqueueResult)
            },
            emitDebug: { name, metadata in
                if let streamBuffer {
                    streamBuffer.record(kind: .customDebug(name: name), metadata: metadata)
                    return
                }
                let enqueueResult = emitter.emit(
                    kind: .customDebug(name: name),
                    stepIndex: stepIndex,
                    taskOrdinal: task.ordinal,
                    metadata: metadata
                )
                droppedCounter.record(enqueueResult)
            }
        )

        do {
            let output = try await node.run(input)
            if let streamBuffer {
                let snapshot = streamBuffer.snapshot()
                if let overflowError = snapshot.overflowError {
                    return TaskExecutionResult(error: overflowError)
                }
                return TaskExecutionResult(output: output, streamEvents: snapshot.events, streamDrops: snapshot.dropped)
            }
            return TaskExecutionResult(output: output, error: nil, streamEvents: nil, streamDrops: .init())
        } catch {
            if options.deterministicStreamBuffering {
                // Failed-attempt stream events are discarded in this mode.
                return TaskExecutionResult(error: error)
            }
            return TaskExecutionResult(error: error)
        }
    }

    private func commitStep(
        state: ThreadState<Schema>,
        tasks: [HiveTask<Schema>],
        outputs: [HiveNodeOutput<Schema>],
        options: HiveRunOptions
    ) throws -> CommitResult<Schema> {
        let (perTaskWrites, globalWritesByChannel) = try collectWrites(tasks: tasks, outputs: outputs)

        var postGlobal = state.global

        for spec in registry.sortedChannelSpecs where spec.scope == .global {
            let writes = globalWritesByChannel[spec.id] ?? []
            if writes.isEmpty { continue }
            if spec.updatePolicy == .single, writes.count > 1 {
                throw HiveRuntimeError.updatePolicyViolation(
                    channelID: spec.id,
                    policy: .single,
                    writeCount: writes.count
                )
            }
        }

        var writtenGlobalChannels: [HiveChannelID] = []
        for spec in registry.sortedChannelSpecs where spec.scope == .global {
            guard let writes = globalWritesByChannel[spec.id], !writes.isEmpty else { continue }
            let ordered = writes.sorted { lhs, rhs in
                if lhs.taskOrdinal == rhs.taskOrdinal {
                    return lhs.emissionIndex < rhs.emissionIndex
                }
                return lhs.taskOrdinal < rhs.taskOrdinal
            }
            var current = try postGlobal.valueAny(for: spec.id)
            for write in ordered {
                current = try spec._reduceBox(current, write.value)
            }
            try postGlobal.setAny(current, for: spec.id)
            writtenGlobalChannels.append(spec.id)
        }

        // Reset ephemeral channels to initial value after each superstep commit.
        for spec in registry.sortedChannelSpecs where spec.scope == .global && spec.persistence.resetsAfterStep {
            let initialValue = spec._initialBox()
            try postGlobal.setAny(initialValue, for: spec.id)
        }

        var postTaskLocal: [HiveTaskLocalStore<Schema>] = []
        postTaskLocal.reserveCapacity(tasks.count)

        for (index, task) in tasks.enumerated() {
            var overlay = task.local
            let writes = perTaskWrites[index].taskLocal

            var writesByChannel: [HiveChannelID: [WriteRecord<Schema>]] = [:]
            for write in writes {
                writesByChannel[write.channelID, default: []].append(write)
            }

            for spec in registry.sortedChannelSpecs where spec.scope == .taskLocal {
                let channelWrites = writesByChannel[spec.id] ?? []
                if channelWrites.isEmpty { continue }
                if spec.updatePolicy == .single, channelWrites.count > 1 {
                    throw HiveRuntimeError.updatePolicyViolation(
                        channelID: spec.id,
                        policy: .single,
                        writeCount: channelWrites.count
                    )
                }
                let ordered = channelWrites.sorted { $0.emissionIndex < $1.emissionIndex }
                var current = try (overlay.valueAny(for: spec.id) ?? initialCache.valueAny(for: spec.id))
                for write in ordered {
                    current = try spec._reduceBox(current, write.value)
                }
                try overlay.setAny(current, for: spec.id)
            }
            postTaskLocal.append(overlay)
        }

        var nextGraphSeeds: [HiveTaskSeed<Schema>] = []
        var nextSpawnSeeds: [HiveTaskSeed<Schema>] = []

        for (index, task) in tasks.enumerated() {
            let output = outputs[index]
            if !output.spawn.isEmpty {
                nextSpawnSeeds.append(contentsOf: output.spawn)
            }

            let normalizedNext = output.next.normalized
            switch normalizedNext {
            case .useGraphEdges:
                break
            case .end:
                continue
            case .to(let nodes):
                for node in nodes {
                    nextGraphSeeds.append(HiveTaskSeed(nodeID: node))
                }
                continue
            }

            if let router = graph.routersByFrom[task.nodeID] {
                let routerGlobal = try applyGlobalWritesForTask(
                    taskIndex: index,
                    preStepGlobal: state.global,
                    perTaskWrites: perTaskWrites
                )
                let routerView = HiveStoreView(
                    global: routerGlobal,
                    taskLocal: postTaskLocal[index],
                    initialCache: initialCache,
                    registry: registry
                )
                let routed = router(routerView).normalized
                switch routed {
                case .useGraphEdges:
                    let staticEdges = graph.staticEdgesByFrom[task.nodeID] ?? []
                    for node in staticEdges {
                        nextGraphSeeds.append(HiveTaskSeed(nodeID: node))
                    }
                case .end:
                    break
                case .to(let nodes):
                    for node in nodes {
                        nextGraphSeeds.append(HiveTaskSeed(nodeID: node))
                    }
                }
            } else {
                let staticEdges = graph.staticEdgesByFrom[task.nodeID] ?? []
                for node in staticEdges {
                    nextGraphSeeds.append(HiveTaskSeed(nodeID: node))
                }
            }
        }

        var joinSeen = state.joinSeenParents
        var joinSeedKeys: Set<SeedKey> = []
        var completedNodesMask = HiveBitset(wordCount: graph.joinBitsetWordCount)
        for task in tasks {
            if let ordinal = graph.nodeOrdinalByID[task.nodeID] {
                completedNodesMask.insert(ordinal)
            }
        }

        for task in tasks {
            for edge in graph.joinEdgesByTarget[task.nodeID] ?? [] {
                guard let parentMask = graph.joinParentMaskByJoinID[edge.id] else { continue }
                if joinSeen[edge.id] == parentMask {
                    joinSeen[edge.id] = HiveBitset(wordCount: graph.joinBitsetWordCount)
                }
            }
        }

        var affectedJoinIDs: Set<String> = []
        affectedJoinIDs.reserveCapacity(tasks.count)
        for task in tasks {
            for edge in graph.joinEdgesByParent[task.nodeID] ?? [] {
                affectedJoinIDs.insert(edge.id)
            }
        }

        var affectedEdges: [HiveJoinEdge] = []
        affectedEdges.reserveCapacity(affectedJoinIDs.count)
        for joinID in affectedJoinIDs {
            guard let edge = graph.joinEdgeByID[joinID] else { continue }
            affectedEdges.append(edge)
        }
        affectedEdges.sort { lhs, rhs in
            let left = graph.joinEdgeOrderByID[lhs.id] ?? 0
            let right = graph.joinEdgeOrderByID[rhs.id] ?? 0
            return left < right
        }

        for edge in affectedEdges {
            guard let parentMask = graph.joinParentMaskByJoinID[edge.id] else { continue }
            let wasAvailable = (joinSeen[edge.id] == parentMask)
            var seen = joinSeen[edge.id] ?? HiveBitset(wordCount: graph.joinBitsetWordCount)
            for parent in edge.parents {
                guard let ordinal = graph.nodeOrdinalByID[parent] else { continue }
                if completedNodesMask.contains(ordinal) {
                    seen.insert(ordinal)
                }
            }
            joinSeen[edge.id] = seen
            let isAvailable = (seen == parentMask)
            if !wasAvailable && isAvailable {
                let seed = HiveTaskSeed<Schema>(nodeID: edge.target)
                nextGraphSeeds.append(seed)
                let fingerprint = try HiveTaskLocalFingerprint.digest(
                    registry: registry,
                    initialCache: initialCache,
                    overlay: seed.local,
                    debugPayloads: options.debugPayloads
                )
                joinSeedKeys.insert(SeedKey(nodeID: seed.nodeID, fingerprint: fingerprint))
            }
        }

        let dedupedGraphSeeds = try dedupeGraphSeeds(nextGraphSeeds, options: options)

        try validateSeedNodes(dedupedGraphSeeds.map(\.seed), spawnSeeds: nextSpawnSeeds)

        var nextFrontier: [HiveFrontierTask<Schema>] = []
        nextFrontier.reserveCapacity(dedupedGraphSeeds.count + nextSpawnSeeds.count)
        for entry in dedupedGraphSeeds {
            nextFrontier.append(
                HiveFrontierTask(
                    seed: entry.seed,
                    provenance: .graph,
                    isJoinSeed: joinSeedKeys.contains(entry.key)
                )
            )
        }
        for seed in nextSpawnSeeds {
            nextFrontier.append(HiveFrontierTask(seed: seed, provenance: .spawn, isJoinSeed: false))
        }

        var normalFrontier: [HiveFrontierTask<Schema>] = []
        var deferredNextFrontier: [HiveFrontierTask<Schema>] = []
        for task in nextFrontier {
            if graph.nodesByID[task.seed.nodeID]?.options.contains(.deferred) == true {
                deferredNextFrontier.append(task)
            } else {
                normalFrontier.append(task)
            }
        }

        return CommitResult(
            global: postGlobal,
            frontier: normalFrontier,
            deferredFrontier: deferredNextFrontier,
            joinSeenParents: joinSeen,
            writtenGlobalChannels: writtenGlobalChannels
        )
    }

    private func collectWrites(
        tasks: [HiveTask<Schema>],
        outputs: [HiveNodeOutput<Schema>]
    ) throws -> ([TaskWrites<Schema>], [HiveChannelID: [WriteRecord<Schema>]]) {
        var perTaskWrites: [TaskWrites<Schema>] = Array(repeating: TaskWrites(), count: tasks.count)
        var globalWritesByChannel: [HiveChannelID: [WriteRecord<Schema>]] = [:]

        for (taskIndex, output) in outputs.enumerated() {
            for (emissionIndex, write) in output.writes.enumerated() {
                guard let spec = registry.channelSpecsByID[write.channelID] else {
                    throw HiveRuntimeError.unknownChannelID(write.channelID)
                }
                try storeSupport.validateValueType(write.value, spec: spec)
                let record = WriteRecord(
                    channelID: write.channelID,
                    value: write.value,
                    emissionIndex: emissionIndex,
                    taskOrdinal: taskIndex,
                    spec: spec
                )
                switch spec.scope {
                case .global:
                    perTaskWrites[taskIndex].global.append(record)
                    globalWritesByChannel[write.channelID, default: []].append(record)
                case .taskLocal:
                    perTaskWrites[taskIndex].taskLocal.append(record)
                }
            }
        }

        return (perTaskWrites, globalWritesByChannel)
    }

    private func applyGlobalWritesForTask(
        taskIndex: Int,
        preStepGlobal: HiveGlobalStore<Schema>,
        perTaskWrites: [TaskWrites<Schema>]
    ) throws -> HiveGlobalStore<Schema> {
        var global = preStepGlobal
        let writes = perTaskWrites[taskIndex].global.sorted { $0.emissionIndex < $1.emissionIndex }
        if writes.isEmpty {
            return global
        }
        // Router "fresh read" requires applying this task's global writes in ascending emission order.
        // Channels are independent, but error precedence (e.g., reducer throws) must follow emission order.
        for write in writes {
            let current = try global.valueAny(for: write.channelID)
            let reduced = try write.spec._reduceBox(current, write.value)
            try global.setAny(reduced, for: write.channelID)
        }

        return global
    }

    private func dedupeGraphSeeds(
        _ seeds: [HiveTaskSeed<Schema>],
        options: HiveRunOptions
    ) throws -> [(seed: HiveTaskSeed<Schema>, key: SeedKey)] {
        var seen: Set<SeedKey> = []
        var deduped: [(seed: HiveTaskSeed<Schema>, key: SeedKey)] = []
        deduped.reserveCapacity(seeds.count)

        for seed in seeds {
            let fingerprint = try HiveTaskLocalFingerprint.digest(
                registry: registry,
                initialCache: initialCache,
                overlay: seed.local,
                debugPayloads: options.debugPayloads
            )
            let key = SeedKey(nodeID: seed.nodeID, fingerprint: fingerprint)
            if seen.insert(key).inserted {
                deduped.append((seed: seed, key: key))
            }
        }

        return deduped
    }

    private func validateSeedNodes(
        _ graphSeeds: [HiveTaskSeed<Schema>],
        spawnSeeds: [HiveTaskSeed<Schema>]
    ) throws {
        for seed in graphSeeds {
            guard graph.nodesByID[seed.nodeID] != nil else {
                throw HiveRuntimeError.unknownNodeID(seed.nodeID)
            }
        }
        for seed in spawnSeeds {
            guard graph.nodesByID[seed.nodeID] != nil else {
                throw HiveRuntimeError.unknownNodeID(seed.nodeID)
            }
        }
    }

    private func makeTaskID(
        runID: HiveRunID,
        stepIndex: Int,
        nodeID: HiveNodeID,
        ordinal: Int,
        localFingerprint: Data
    ) throws -> HiveTaskID {
        guard let stepValue = UInt32(exactly: stepIndex) else {
            throw HiveRuntimeError.stepIndexOutOfRange(stepIndex: stepIndex)
        }
        guard let ordinalValue = UInt32(exactly: ordinal) else {
            throw HiveRuntimeError.taskOrdinalOutOfRange(ordinal: ordinal)
        }
        guard localFingerprint.count == 32 else {
            throw HiveRuntimeError.invalidTaskLocalFingerprintLength(
                expected: 32,
                actual: localFingerprint.count
            )
        }

        var bytes = Data()
        var uuid = runID.rawValue.uuid
        withUnsafeBytes(of: &uuid) { bytes.append(contentsOf: $0) }

        appendUInt32BE(stepValue, to: &bytes)
        bytes.append(0)
        bytes.append(contentsOf: nodeID.rawValue.utf8)
        bytes.append(0)
        appendUInt32BE(ordinalValue, to: &bytes)
        bytes.append(localFingerprint)

        let hash = HiveSHA256.hash(data: bytes)
        let hex = hash.compactMap { String(format: "%02x", $0) }.joined()
        return HiveTaskID(hex)
    }

    private func payloadHash(for channelID: HiveChannelID, in global: HiveGlobalStore<Schema>) throws -> String {
        let spec = try storeSupport.requireSpec(for: channelID)
        let value = try global.valueAny(for: channelID)
        let bytes = try canonicalBytes(for: value, spec: spec)
        let hash = HiveSHA256.hash(data: bytes)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func makeGlobalChannelPayloadHashes(
        from global: HiveGlobalStore<Schema>
    ) throws -> [HiveChannelID: String] {
        var hashes: [HiveChannelID: String] = [:]
        hashes.reserveCapacity(registry.sortedChannelSpecs.count)
        for spec in registry.sortedChannelSpecs where spec.scope == .global {
            hashes[spec.id] = try payloadHash(for: spec.id, in: global)
        }
        return hashes
    }

    private func makeInterruptionSnapshot(
        from interruption: HiveInterrupt<Schema>?
    ) throws -> HiveRuntimeInterruptionSnapshot? {
        guard let interruption else { return nil }
        let payloadBytes: Data
        if let stableJSON = try stableJSONDataIfEncodable(interruption.payload) {
            payloadBytes = stableJSON
        } else {
            payloadBytes = Data(String(reflecting: type(of: interruption.payload)).utf8)
        }
        let digest = HiveSHA256.hash(data: payloadBytes)
        let payloadHash = digest.compactMap { String(format: "%02x", $0) }.joined()
        return HiveRuntimeInterruptionSnapshot(
            interruptID: interruption.id,
            payloadHash: payloadHash
        )
    }

    private func makeFrontierSummary(
        from frontier: [HiveFrontierTask<Schema>]
    ) throws -> [HiveRuntimeFrontierSummary] {
        var summary: [HiveRuntimeFrontierSummary] = []
        summary.reserveCapacity(frontier.count)
        for entry in frontier {
            let fingerprint = try HiveTaskLocalFingerprint.digest(
                registry: registry,
                initialCache: initialCache,
                overlay: entry.seed.local,
                debugPayloads: false
            )
            let digest = HiveSHA256.hash(data: fingerprint)
            let fingerprintHash = digest.compactMap { String(format: "%02x", $0) }.joined()
            summary.append(
                HiveRuntimeFrontierSummary(
                    nodeID: entry.seed.nodeID,
                    provenance: entry.provenance,
                    taskLocalFingerprintHash: fingerprintHash
                )
            )
        }
        summary.sort { lhs, rhs in
            if lhs.nodeID != rhs.nodeID {
                return HiveOrdering.lexicographicallyPrecedes(lhs.nodeID.rawValue, rhs.nodeID.rawValue)
            }
            if lhs.provenance != rhs.provenance {
                return HiveOrdering.lexicographicallyPrecedes(lhs.provenance.rawValue, rhs.provenance.rawValue)
            }
            return HiveOrdering.lexicographicallyPrecedes(lhs.taskLocalFingerprintHash, rhs.taskLocalFingerprintHash)
        }
        return summary
    }

    private func writeAppliedMetadata(
        for channelID: HiveChannelID,
        in global: HiveGlobalStore<Schema>,
        debugPayloads: Bool
    ) throws -> [String: String] {
        guard debugPayloads else { return [:] }
        let spec = try storeSupport.requireSpec(for: channelID)
        let value = try global.valueAny(for: channelID)

        var encoding: String = "unhashable"
        var payload: String = ""

        if let encode = spec._encodeBox {
            do {
                let data = try encode(value)
                encoding = "codec.base64"
                payload = data.base64EncodedString()
            } catch {
                if let json = try stableJSONDataIfEncodable(value) {
                    encoding = "json.utf8"
                    payload = String(decoding: json, as: UTF8.self)
                }
            }
        } else if let json = try stableJSONDataIfEncodable(value) {
            encoding = "json.utf8"
            payload = String(decoding: json, as: UTF8.self)
        }

        return [
            "valueTypeID": spec.valueTypeID,
            "codecID": spec.codecID ?? "",
            "payloadEncoding": encoding,
            "payload": payload
        ]
    }

    private func appendUInt32BE(_ value: UInt32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private func canonicalBytes(for value: any Sendable, spec: AnyHiveChannelSpec<Schema>) throws -> Data {
        if let encode = spec._encodeBox {
            do {
                return try encode(value)
            } catch {
                if let json = try stableJSONDataIfEncodable(value) {
                    return json
                }
                return Data(("unhashable:" + spec.valueTypeID).utf8)
            }
        }

        if let json = try stableJSONDataIfEncodable(value) {
            return json
        }

        return Data(("unhashable:" + spec.valueTypeID).utf8)
    }

    private func stableJSONDataIfEncodable(_ value: any Sendable) throws -> Data? {
        guard let encodable = value as? any Encodable else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        return try encoder.encode(HiveAnyEncodable(encodable))
    }

    private struct HiveAnyEncodable: Encodable {
        let encodable: any Encodable

        init(_ encodable: any Encodable) {
            self.encodable = encodable
        }

        func encode(to encoder: Encoder) throws {
            try encodable.encode(to: encoder)
        }
    }

    private static func mapStream(_ kind: HiveStreamEventKind) -> HiveEventKind {
        switch kind {
        case .customDebug(let name):
            return .customDebug(name: name)
        }
    }
}

private struct HiveFrontierTask<Schema: HiveSchema>: Sendable {
    let seed: HiveTaskSeed<Schema>
    let provenance: HiveTaskProvenance
    let isJoinSeed: Bool
}

private struct ThreadState<Schema: HiveSchema>: Sendable {
    var runID: HiveRunID
    var stepIndex: Int
    var global: HiveGlobalStore<Schema>
    var frontier: [HiveFrontierTask<Schema>]
    var deferredFrontier: [HiveFrontierTask<Schema>]
    var joinSeenParents: [String: HiveBitset]
    var interruption: HiveInterrupt<Schema>?
    var latestCheckpointID: HiveCheckpointID?
    var channelVersionsByChannelID: [HiveChannelID: UInt64]
    var versionsSeenByNodeID: [HiveNodeID: [HiveChannelID: UInt64]]
    var updatedChannelsLastCommit: [HiveChannelID]
    var nodeCaches: [HiveNodeID: HiveNodeCache<Schema>]
}

private struct WriteRecord<Schema: HiveSchema>: Sendable {
    let channelID: HiveChannelID
    let value: any Sendable
    let emissionIndex: Int
    let taskOrdinal: Int
    let spec: AnyHiveChannelSpec<Schema>
}

private struct TaskWrites<Schema: HiveSchema>: Sendable {
    var global: [WriteRecord<Schema>] = []
    var taskLocal: [WriteRecord<Schema>] = []
}

private struct CommitResult<Schema: HiveSchema>: Sendable {
    let global: HiveGlobalStore<Schema>
    let frontier: [HiveFrontierTask<Schema>]
    let deferredFrontier: [HiveFrontierTask<Schema>]
    let joinSeenParents: [String: HiveBitset]
    let writtenGlobalChannels: [HiveChannelID]
}

private struct StepOutcome<Schema: HiveSchema>: Sendable {
    let nextState: ThreadState<Schema>
    let writtenGlobalChannels: [HiveChannelID]
    let dropped: HiveDroppedEventCounts
    let selectedInterrupt: HiveInterrupt<Schema>?
    let checkpointToSave: HiveCheckpoint<Schema>?
}

private struct HiveDroppedEventCounts: Sendable {
    var droppedDebugEvents: Int = 0

    mutating func record(_ enqueueResult: HiveEventEnqueueResult) {
        switch enqueueResult {
        case .droppedDebug:
            droppedDebugEvents += 1
        case .enqueued, .terminated:
            break
        }
    }
}

private final class HiveDroppedEventCounter: Sendable {
    private let counts = Mutex(HiveDroppedEventCounts())

    func record(_ enqueueResult: HiveEventEnqueueResult) {
        counts.withLock { $0.record(enqueueResult) }
    }

    func snapshot() -> HiveDroppedEventCounts {
        counts.withLock { $0 }
    }
}

private struct BufferedStreamEvent: Sendable {
    let kind: HiveEventKind
    let metadata: [String: String]
    let taskOrdinal: Int
}

private final class HivePerAttemptStreamBuffer: Sendable {
    private struct State {
        var events: [BufferedStreamEvent]
        var dropped: HiveDroppedEventCounts
        var overflowError: Error?
    }

    private let capacity: Int
    private let stepIndex: Int
    private let taskOrdinal: Int
    private let state: Mutex<State>

    init(capacity: Int, stepIndex: Int, taskOrdinal: Int) {
        self.capacity = max(1, capacity)
        self.stepIndex = stepIndex
        self.taskOrdinal = taskOrdinal
        var initialEvents: [BufferedStreamEvent] = []
        initialEvents.reserveCapacity(min(8, self.capacity))
        self.state = Mutex(State(events: initialEvents, dropped: HiveDroppedEventCounts(), overflowError: nil))
    }

    func record(kind: HiveEventKind, metadata: [String: String]) {
        state.withLock { state in
            guard state.overflowError == nil else { return }

            if state.events.count < capacity {
                state.events.append(BufferedStreamEvent(kind: kind, metadata: metadata, taskOrdinal: taskOrdinal))
                return
            }

            switch kind {
            case .customDebug:
                state.dropped.droppedDebugEvents += 1
            default:
                state.overflowError = HiveRuntimeError.internalInvariantViolation(
                    "Non-droppable stream event buffer overflow (stepIndex=\(stepIndex), taskOrdinal=\(taskOrdinal), perTaskCapacity=\(capacity))"
                )
            }
        }
    }

    func snapshot() -> (events: [BufferedStreamEvent], dropped: HiveDroppedEventCounts, overflowError: Error?) {
        state.withLock { (events: $0.events, dropped: $0.dropped, overflowError: $0.overflowError) }
    }
}

private struct TaskExecutionResult<Schema: HiveSchema>: Sendable {
    let output: HiveNodeOutput<Schema>?
    let error: Error?
    let streamEvents: [BufferedStreamEvent]?
    let streamDrops: HiveDroppedEventCounts

    static var empty: TaskExecutionResult<Schema> {
        TaskExecutionResult(output: nil, error: nil, streamEvents: nil, streamDrops: .init())
    }

    init(
        output: HiveNodeOutput<Schema>?,
        error: Error?,
        streamEvents: [BufferedStreamEvent]?,
        streamDrops: HiveDroppedEventCounts
    ) {
        self.output = output
        self.error = error
        self.streamEvents = streamEvents
        self.streamDrops = streamDrops
    }

    init(output: HiveNodeOutput<Schema>, streamEvents: [BufferedStreamEvent], streamDrops: HiveDroppedEventCounts) {
        self.output = output
        self.error = nil
        self.streamEvents = streamEvents
        self.streamDrops = streamDrops
    }

    init(error: Error) {
        self.output = nil
        self.error = error
        self.streamEvents = nil
        self.streamDrops = .init()
    }
}

private struct SeedKey: Hashable, Sendable {
    let nodeID: HiveNodeID
    let fingerprint: Data
}

private final class HiveEventEmitter: Sendable {
    private struct State {
        var eventIndex: UInt64 = 0
    }

    private let runID: HiveRunID
    private let attemptID: HiveRunAttemptID
    private let streamController: HiveEventStreamController
    private let state = Mutex(State())

    init(
        runID: HiveRunID,
        attemptID: HiveRunAttemptID,
        streamController: HiveEventStreamController
    ) {
        self.runID = runID
        self.attemptID = attemptID
        self.streamController = streamController
    }

    @discardableResult
    func emit(
        kind: HiveEventKind,
        stepIndex: Int?,
        taskOrdinal: Int?,
        metadata: [String: String] = [:],
        treatAsNonDroppable: Bool = false
    ) -> HiveEventEnqueueResult {
        state.withLock { state in
            let nextIndex = state.eventIndex
            let result = streamController.enqueue(
                eventIndex: nextIndex,
                runID: runID,
                attemptID: attemptID,
                kind: kind,
                stepIndex: stepIndex,
                taskOrdinal: taskOrdinal,
                metadata: metadata,
                treatAsNonDroppable: treatAsNonDroppable
            )
            if case .enqueued = result {
                state.eventIndex += 1
            }
            return result
        }
    }
}
