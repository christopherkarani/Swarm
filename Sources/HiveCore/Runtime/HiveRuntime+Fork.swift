import Foundation

extension HiveRuntime {
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
                case .unsupported:
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
}
