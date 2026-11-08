import Foundation

extension HiveRuntime {
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

    func resolveBaselineState(
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

    func loadCheckpointStateForResume(
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

    func decodeCheckpoint(
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
}
