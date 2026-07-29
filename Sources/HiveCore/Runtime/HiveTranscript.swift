import Foundation

public struct HiveTranscriptNormalizationOptions: Sendable, Equatable {
    public var normalizeRunIdentifiers: Bool
    public var normalizeEventIndices: Bool
    public var stripMetadataKeys: Set<String>

    public init(
        normalizeRunIdentifiers: Bool = true,
        normalizeEventIndices: Bool = true,
        stripMetadataKeys: Set<String> = ["timestamp", "time", "now", "wallClock", "clock"]
    ) {
        self.normalizeRunIdentifiers = normalizeRunIdentifiers
        self.normalizeEventIndices = normalizeEventIndices
        self.stripMetadataKeys = stripMetadataKeys
    }

    public static let swarmDeterministicDefault = HiveTranscriptNormalizationOptions()
}

public struct HiveTranscriptEventID: Codable, Sendable, Equatable {
    public let runID: String
    public let attemptID: String
    public let eventIndex: UInt64
    public let stepIndex: Int?
    public let taskOrdinal: Int?

    public init(
        runID: String,
        attemptID: String,
        eventIndex: UInt64,
        stepIndex: Int?,
        taskOrdinal: Int?
    ) {
        self.runID = runID
        self.attemptID = attemptID
        self.eventIndex = eventIndex
        self.stepIndex = stepIndex
        self.taskOrdinal = taskOrdinal
    }
}

public struct HiveTranscriptEvent: Codable, Sendable, Equatable {
    public let id: HiveTranscriptEventID
    public let kind: String
    public let fields: [String: String]
    public let metadata: [String: String]

    public init(
        id: HiveTranscriptEventID,
        kind: String,
        fields: [String: String],
        metadata: [String: String]
    ) {
        self.id = id
        self.kind = kind
        self.fields = fields
        self.metadata = metadata
    }
}

public struct HiveEventTranscript: Codable, Sendable, Equatable {
    public let schemaVersion: HiveEventSchemaVersion
    public let events: [HiveTranscriptEvent]

    public init(schemaVersion: HiveEventSchemaVersion, events: [HiveTranscriptEvent]) {
        self.schemaVersion = schemaVersion
        self.events = events
    }

    public init(
        events sourceEvents: [HiveEvent],
        normalization: HiveTranscriptNormalizationOptions = .swarmDeterministicDefault
    ) {
        let schemaVersion = sourceEvents.first?.schemaVersion ?? .current
        self.schemaVersion = schemaVersion
        self.events = sourceEvents.enumerated().map { offset, event in
            let normalizedID = HiveTranscriptEventID(
                runID: normalization.normalizeRunIdentifiers
                    ? "normalized-run"
                    : event.id.runID.rawValue.uuidString.lowercased(),
                attemptID: normalization.normalizeRunIdentifiers
                    ? "normalized-attempt"
                    : event.id.attemptID.rawValue.uuidString.lowercased(),
                eventIndex: normalization.normalizeEventIndices ? UInt64(offset) : event.id.eventIndex,
                stepIndex: event.id.stepIndex,
                taskOrdinal: event.id.taskOrdinal
            )
            let stableFields = normalization.normalizeRunIdentifiers
                ? Self.normalizedFields(
                    event.kind.stableFields,
                    for: event.kind,
                    eventOrdinal: offset,
                    stepIndex: event.id.stepIndex,
                    taskOrdinal: event.id.taskOrdinal
                )
                : event.kind.stableFields
            return HiveTranscriptEvent(
                id: normalizedID,
                kind: event.kind.stableName,
                fields: stableFields,
                metadata: event.metadata.filter { normalization.stripMetadataKeys.contains($0.key) == false }
            )
        }
    }

    public func validateReplayCompatibility(
        expected: HiveEventSchemaVersion = .current
    ) throws {
        guard schemaVersion == expected else {
            throw HiveEventReplayCompatibilityError.incompatibleSchemaVersion(
                expected: expected,
                found: schemaVersion
            )
        }
    }

    public func stableData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func transcriptHash() throws -> String {
        let data = try stableData()
        let digest = HiveSHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    public func firstDiff(comparedTo other: HiveEventTranscript) -> HiveTranscriptDiff? {
        if schemaVersion != other.schemaVersion {
            return HiveTranscriptDiff(
                eventIndex: 0,
                keyPath: "schemaVersion",
                lhs: schemaVersion.rawValue,
                rhs: other.schemaVersion.rawValue
            )
        }

        let sharedCount = min(events.count, other.events.count)
        for index in 0..<sharedCount {
            let lhs = events[index]
            let rhs = other.events[index]
            if lhs.id != rhs.id {
                if lhs.id.runID != rhs.id.runID {
                    return HiveTranscriptDiff(eventIndex: index, keyPath: "events[\(index)].id.runID", lhs: lhs.id.runID, rhs: rhs.id.runID)
                }
                if lhs.id.attemptID != rhs.id.attemptID {
                    return HiveTranscriptDiff(eventIndex: index, keyPath: "events[\(index)].id.attemptID", lhs: lhs.id.attemptID, rhs: rhs.id.attemptID)
                }
                if lhs.id.eventIndex != rhs.id.eventIndex {
                    return HiveTranscriptDiff(
                        eventIndex: index,
                        keyPath: "events[\(index)].id.eventIndex",
                        lhs: String(lhs.id.eventIndex),
                        rhs: String(rhs.id.eventIndex)
                    )
                }
                if lhs.id.stepIndex != rhs.id.stepIndex {
                    return HiveTranscriptDiff(
                        eventIndex: index,
                        keyPath: "events[\(index)].id.stepIndex",
                        lhs: lhs.id.stepIndex.map(String.init) ?? "nil",
                        rhs: rhs.id.stepIndex.map(String.init) ?? "nil"
                    )
                }
                if lhs.id.taskOrdinal != rhs.id.taskOrdinal {
                    return HiveTranscriptDiff(
                        eventIndex: index,
                        keyPath: "events[\(index)].id.taskOrdinal",
                        lhs: lhs.id.taskOrdinal.map(String.init) ?? "nil",
                        rhs: rhs.id.taskOrdinal.map(String.init) ?? "nil"
                    )
                }
            }

            if lhs.kind != rhs.kind {
                return HiveTranscriptDiff(
                    eventIndex: index,
                    keyPath: "events[\(index)].kind",
                    lhs: lhs.kind,
                    rhs: rhs.kind
                )
            }

            if lhs.fields != rhs.fields {
                let differingKey = Set(lhs.fields.keys)
                    .union(rhs.fields.keys)
                    .sorted(by: HiveOrdering.lexicographicallyPrecedes)
                    .first { lhs.fields[$0] != rhs.fields[$0] }
                    ?? "unknown"
                return HiveTranscriptDiff(
                    eventIndex: index,
                    keyPath: "events[\(index)].fields.\(differingKey)",
                    lhs: lhs.fields[differingKey] ?? "nil",
                    rhs: rhs.fields[differingKey] ?? "nil"
                )
            }

            if lhs.metadata != rhs.metadata {
                let differingKey = Set(lhs.metadata.keys)
                    .union(rhs.metadata.keys)
                    .sorted(by: HiveOrdering.lexicographicallyPrecedes)
                    .first { lhs.metadata[$0] != rhs.metadata[$0] }
                    ?? "unknown"
                return HiveTranscriptDiff(
                    eventIndex: index,
                    keyPath: "events[\(index)].metadata.\(differingKey)",
                    lhs: lhs.metadata[differingKey] ?? "nil",
                    rhs: rhs.metadata[differingKey] ?? "nil"
                )
            }
        }

        if events.count != other.events.count {
            return HiveTranscriptDiff(
                eventIndex: sharedCount,
                keyPath: "events.count",
                lhs: String(events.count),
                rhs: String(other.events.count)
            )
        }

        return nil
    }
}

public struct HiveTranscriptDiff: Sendable, Equatable {
    public let eventIndex: Int
    public let keyPath: String
    public let lhs: String
    public let rhs: String

    public init(eventIndex: Int, keyPath: String, lhs: String, rhs: String) {
        self.eventIndex = eventIndex
        self.keyPath = keyPath
        self.lhs = lhs
        self.rhs = rhs
    }
}

    public enum HiveTranscriptHasher {
    public static func transcriptHash(
        events: [HiveEvent],
        normalization: HiveTranscriptNormalizationOptions = .swarmDeterministicDefault
    ) throws -> String {
        try HiveEventTranscript(events: events, normalization: normalization).transcriptHash()
    }

    public static func finalStateHash<Schema: HiveSchema>(
        stateSnapshot: HiveRuntimeStateSnapshot<Schema>
    ) -> String {
        var data = Data("HFS1".utf8)
        data.append(contentsOf: stateSnapshot.threadID.rawValue.utf8)
        data.append(0)
        data.append(contentsOf: String(stateSnapshot.stepIndex).utf8)
        data.append(0)

        for (channelID, payloadHash) in stateSnapshot.globalChannelPayloadHashesByID
            .sorted(by: { HiveOrdering.lexicographicallyPrecedes($0.key.rawValue, $1.key.rawValue) }) {
            data.append(contentsOf: channelID.rawValue.utf8)
            data.append(0)
            data.append(contentsOf: payloadHash.utf8)
            data.append(0)
        }

        for entry in stateSnapshot.frontierSummary {
            data.append(contentsOf: entry.nodeID.rawValue.utf8)
            data.append(0)
            data.append(contentsOf: entry.provenance.rawValue.utf8)
            data.append(0)
            data.append(contentsOf: entry.taskLocalFingerprintHash.utf8)
            data.append(0)
        }

        if let interruption = stateSnapshot.interruption {
            data.append(contentsOf: interruption.payloadHash.utf8)
            data.append(0)
        }

        let digest = HiveSHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    public static func firstDiff(
        lhs: HiveEventTranscript,
        rhs: HiveEventTranscript
    ) -> HiveTranscriptDiff? {
        lhs.firstDiff(comparedTo: rhs)
    }
}

private extension HiveEventTranscript {
    static func normalizedFields(
        _ fields: [String: String],
        for kind: HiveEventKind,
        eventOrdinal: Int,
        stepIndex: Int?,
        taskOrdinal: Int?
    ) -> [String: String] {
        var normalized = fields
        switch kind {
        case .taskStarted, .taskFinished, .taskFailed:
            let stepToken = stepIndex.map(String.init) ?? "none"
            let taskToken = taskOrdinal.map(String.init) ?? String(eventOrdinal)
            normalized["taskID"] = "normalized-task-\(stepToken)-\(taskToken)"
        case .checkpointSaved, .checkpointLoaded:
            let stepToken = stepIndex.map(String.init) ?? "none"
            normalized["checkpointID"] = "normalized-checkpoint-\(stepToken)"
        case .runInterrupted, .runResumed:
            normalized["interruptID"] = "normalized-interrupt"
        case .forkStarted, .forkCompleted, .forkFailed:
            if normalized["sourceCheckpointID"] != nil {
                normalized["sourceCheckpointID"] = "normalized-source-checkpoint"
            }
            if normalized["targetCheckpointID"] != nil {
                normalized["targetCheckpointID"] = "normalized-target-checkpoint"
            }
        default:
            break
        }
        return normalized
    }
}

private extension HiveEventKind {
    var stableName: String {
        switch self {
        case .runStarted: return "run.started"
        case .runFinished: return "run.finished"
        case .runInterrupted: return "run.interrupted"
        case .runResumed: return "run.resumed"
        case .runCancelled: return "run.cancelled"
        case .forkStarted: return "fork.started"
        case .forkCompleted: return "fork.completed"
        case .forkFailed: return "fork.failed"
        case .stepStarted: return "step.started"
        case .stepFinished: return "step.finished"
        case .taskStarted: return "task.started"
        case .taskFinished: return "task.finished"
        case .taskFailed: return "task.failed"
        case .writeApplied: return "write.applied"
        case .checkpointSaved: return "checkpoint.saved"
        case .checkpointLoaded: return "checkpoint.loaded"
        case .storeSnapshot: return "store.snapshot"
        case .channelUpdates: return "channel.updates"
        case .streamBackpressure: return "stream.backpressure"
        case .customDebug: return "debug.custom"
        }
    }

    var stableFields: [String: String] {
        switch self {
        case .runStarted(let threadID):
            return ["threadID": threadID.rawValue]
        case .runFinished:
            return [:]
        case .runInterrupted(let interruptID):
            return ["interruptID": interruptID.rawValue]
        case .runResumed(let interruptID):
            return ["interruptID": interruptID.rawValue]
        case .runCancelled(let cause):
            return ["cause": cause.rawValue]
        case .forkStarted(let sourceThreadID, let targetThreadID, let sourceCheckpointID):
            return [
                "sourceThreadID": sourceThreadID.rawValue,
                "targetThreadID": targetThreadID.rawValue,
                "sourceCheckpointID": sourceCheckpointID?.rawValue ?? "nil"
            ]
        case .forkCompleted(let sourceThreadID, let targetThreadID, let sourceCheckpointID, let targetCheckpointID):
            return [
                "sourceThreadID": sourceThreadID.rawValue,
                "targetThreadID": targetThreadID.rawValue,
                "sourceCheckpointID": sourceCheckpointID.rawValue,
                "targetCheckpointID": targetCheckpointID?.rawValue ?? "nil"
            ]
        case .forkFailed(let sourceThreadID, let targetThreadID, let sourceCheckpointID, let errorCode):
            return [
                "sourceThreadID": sourceThreadID.rawValue,
                "targetThreadID": targetThreadID.rawValue,
                "sourceCheckpointID": sourceCheckpointID?.rawValue ?? "nil",
                "errorCode": errorCode
            ]
        case .stepStarted(let stepIndex, let frontierCount):
            return ["stepIndex": String(stepIndex), "frontierCount": String(frontierCount)]
        case .stepFinished(let stepIndex, let nextFrontierCount):
            return ["stepIndex": String(stepIndex), "nextFrontierCount": String(nextFrontierCount)]
        case .taskStarted(let node, let taskID):
            return ["node": node.rawValue, "taskID": taskID.rawValue]
        case .taskFinished(let node, let taskID):
            return ["node": node.rawValue, "taskID": taskID.rawValue]
        case .taskFailed(let node, let taskID, let errorDescription):
            return ["node": node.rawValue, "taskID": taskID.rawValue, "error": errorDescription]
        case .writeApplied(let channelID, let payloadHash):
            return ["channelID": channelID.rawValue, "payloadHash": payloadHash]
        case .checkpointSaved(let checkpointID):
            return ["checkpointID": checkpointID.rawValue]
        case .checkpointLoaded(let checkpointID):
            return ["checkpointID": checkpointID.rawValue]
        case .storeSnapshot(let channelValues):
            return ["channels": channelValues.map(\.channelID.rawValue).joined(separator: ",")]
        case .channelUpdates(let channelValues):
            return ["channels": channelValues.map(\.channelID.rawValue).joined(separator: ",")]
        case .streamBackpressure(let droppedDebugEvents):
            return ["droppedDebugEvents": String(droppedDebugEvents)]
        case .customDebug(let name):
            return ["name": name]
        }
    }
}
