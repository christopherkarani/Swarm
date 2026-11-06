import Foundation

extension HiveRuntime {
    func makeCheckpoint(
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
}
