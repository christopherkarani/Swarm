import CryptoKit
import Foundation
import HiveCore
import Swarm

// MARK: - EventSchemaVersion

enum EventSchemaVersion: Sendable {
    static let metadataKey = "hive.eventSchemaVersion"
    static let current = "hsw.v1"
}

// MARK: - HiveCheckpointQueryCapability

enum HiveCheckpointQueryCapability: Sendable, Equatable {
    case unavailable
    case latestOnly
    case queryable
}

// MARK: - HiveStateSnapshotSource

enum HiveStateSnapshotSource: Sendable, Equatable {
    case memory
    case checkpoint
    case memoryAndCheckpoint
    case trackerOnly
}

// MARK: - HiveRuntimeFrontierSummary

struct HiveRuntimeFrontierSummary: Sendable, Equatable {
    struct Entry: Sendable, Equatable {
        let nodeID: HiveNodeID
        let provenance: HiveTaskProvenance
        let localFingerprintHash: String

        init(
            nodeID: HiveNodeID,
            provenance: HiveTaskProvenance,
            localFingerprintHash: String
        ) {
            self.nodeID = nodeID
            self.provenance = provenance
            self.localFingerprintHash = localFingerprintHash
        }
    }

    let count: Int
    let hash: String
    let entries: [Entry]

    init(count: Int, hash: String, entries: [Entry]) {
        self.count = count
        self.hash = hash
        self.entries = entries
    }
}

// MARK: - HiveRuntimeChannelStateSummary

struct HiveRuntimeChannelStateSummary: Sendable, Equatable {
    struct Entry: Sendable, Equatable {
        let channelID: HiveChannelID
        let payloadHash: String

        init(channelID: HiveChannelID, payloadHash: String) {
            self.channelID = channelID
            self.payloadHash = payloadHash
        }
    }

    let hash: String
    let entries: [Entry]

    init(hash: String, entries: [Entry]) {
        self.hash = hash
        self.entries = entries
    }
}

// MARK: - HiveRuntimeInterruptionSummary

struct HiveRuntimeInterruptionSummary<Schema: HiveSchema>: Sendable, Equatable {
    let interruptID: HiveInterruptID
    let payloadHash: String?

    init(interruptID: HiveInterruptID, payloadHash: String?) {
        self.interruptID = interruptID
        self.payloadHash = payloadHash
    }
}

// MARK: - HiveRuntimeStateSnapshot

struct HiveRuntimeStateSnapshot<Schema: HiveSchema>: Sendable, Equatable {
    let threadID: HiveThreadID
    let runID: HiveRunID?
    let stepIndex: Int?
    let interruption: HiveRuntimeInterruptionSummary<Schema>?
    let checkpointID: HiveCheckpointID?
    let frontier: HiveRuntimeFrontierSummary
    let channelState: HiveRuntimeChannelStateSummary?
    let eventSchemaVersion: String
    let source: HiveStateSnapshotSource

    init(
        threadID: HiveThreadID,
        runID: HiveRunID?,
        stepIndex: Int?,
        interruption: HiveRuntimeInterruptionSummary<Schema>?,
        checkpointID: HiveCheckpointID?,
        frontier: HiveRuntimeFrontierSummary,
        channelState: HiveRuntimeChannelStateSummary?,
        eventSchemaVersion: String,
        source: HiveStateSnapshotSource
    ) {
        self.threadID = threadID
        self.runID = runID
        self.stepIndex = stepIndex
        self.interruption = interruption
        self.checkpointID = checkpointID
        self.frontier = frontier
        self.channelState = channelState
        self.eventSchemaVersion = eventSchemaVersion
        self.source = source
    }
}

// MARK: - HiveCanonicalEventRecord

struct HiveCanonicalEventRecord: Sendable, Codable, Equatable {
    let eventIndex: UInt64
    let stepIndex: Int?
    let taskOrdinal: Int?
    let kind: String
    let attributes: [String: String]
    let metadata: [String: String]

    init(
        eventIndex: UInt64,
        stepIndex: Int?,
        taskOrdinal: Int?,
        kind: String,
        attributes: [String: String],
        metadata: [String: String]
    ) {
        self.eventIndex = eventIndex
        self.stepIndex = stepIndex
        self.taskOrdinal = taskOrdinal
        self.kind = kind
        self.attributes = attributes
        self.metadata = metadata
    }
}

// MARK: - HiveCanonicalTranscript

struct HiveCanonicalTranscript: Sendable, Codable, Equatable {
    let schemaVersion: String
    let events: [HiveCanonicalEventRecord]

    init(schemaVersion: String, events: [HiveCanonicalEventRecord]) {
        self.schemaVersion = schemaVersion
        self.events = events
    }
}

// MARK: - HiveDeterminismDiff

struct HiveDeterminismDiff: Sendable, Equatable {
    let path: String
    let expected: String
    let actual: String

    init(path: String, expected: String, actual: String) {
        self.path = path
        self.expected = expected
        self.actual = actual
    }
}

// MARK: - HiveTranscriptCompatibilityError

enum HiveTranscriptCompatibilityError: Error, Sendable, Equatable {
    case missingSchemaVersion(eventIndex: Int)
    case incompatibleSchemaVersion(expected: String, found: String, eventIndex: Int)
}

// MARK: - HiveCancelCheckpointResolution

enum HiveCancelCheckpointResolution: Sendable, Equatable {
    case notCancelled
    case cancelledWithoutCheckpoint(latestCheckpointID: HiveCheckpointID?)
    case cancelledAfterCheckpointSaved(checkpointID: HiveCheckpointID)
}

// MARK: - HiveDeterminism

enum HiveDeterminism {
    // MARK: Internal

    static func projectTranscript(
        _ events: [HiveEvent],
        expectedSchemaVersion: String = EventSchemaVersion.current
    ) throws -> HiveCanonicalTranscript {
        var records: [HiveCanonicalEventRecord] = []
        records.reserveCapacity(events.count)

        for (index, event) in events.enumerated() {
            guard let found = event.metadata[EventSchemaVersion.metadataKey] else {
                throw HiveTranscriptCompatibilityError.missingSchemaVersion(eventIndex: index)
            }
            guard found == expectedSchemaVersion else {
                throw HiveTranscriptCompatibilityError.incompatibleSchemaVersion(
                    expected: expectedSchemaVersion,
                    found: found,
                    eventIndex: index
                )
            }

            let canonical = canonicalKind(event.kind)
            records.append(
                HiveCanonicalEventRecord(
                    eventIndex: event.id.eventIndex,
                    stepIndex: event.id.stepIndex,
                    taskOrdinal: event.id.taskOrdinal,
                    kind: canonical.kind,
                    attributes: canonical.attributes,
                    metadata: canonicalMetadata(event.metadata)
                )
            )
        }

        records.sort { lhs, rhs in
            if lhs.eventIndex == rhs.eventIndex {
                let leftStep = lhs.stepIndex ?? -1
                let rightStep = rhs.stepIndex ?? -1
                if leftStep == rightStep {
                    return (lhs.taskOrdinal ?? -1) < (rhs.taskOrdinal ?? -1)
                }
                return leftStep < rightStep
            }
            return lhs.eventIndex < rhs.eventIndex
        }

        return HiveCanonicalTranscript(
            schemaVersion: expectedSchemaVersion,
            events: records
        )
    }

    static func transcriptHash(
        _ events: [HiveEvent],
        expectedSchemaVersion: String = EventSchemaVersion.current
    ) throws -> String {
        // Hash projection intentionally excludes runtime-assigned event indices to avoid
        // non-determinism from concurrency-driven emission ordering.
        var records: [HiveTranscriptHashEventRecord] = []
        records.reserveCapacity(events.count)

        for (index, event) in events.enumerated() {
            guard let found = event.metadata[EventSchemaVersion.metadataKey] else {
                throw HiveTranscriptCompatibilityError.missingSchemaVersion(eventIndex: index)
            }
            guard found == expectedSchemaVersion else {
                throw HiveTranscriptCompatibilityError.incompatibleSchemaVersion(
                    expected: expectedSchemaVersion,
                    found: found,
                    eventIndex: index
                )
            }

            let canonical = canonicalKind(event.kind)
            records.append(
                HiveTranscriptHashEventRecord(
                    stepIndex: event.id.stepIndex,
                    taskOrdinal: event.id.taskOrdinal,
                    kind: canonical.kind,
                    attributes: canonical.attributes,
                    metadata: canonicalMetadata(event.metadata)
                )
            )
        }

        records.sort { lhs, rhs in
            lhs.sortKey.utf8.lexicographicallyPrecedes(rhs.sortKey.utf8)
        }

        let projection = HiveTranscriptHashProjection(schemaVersion: expectedSchemaVersion, events: records)
        return try hashEncodable(projection)
    }

    static func finalStateHash(
        _ snapshot: HiveRuntimeStateSnapshot<some HiveSchema>,
        includeRuntimeIdentity: Bool = false
    ) throws -> String {
        let canonical = CanonicalStateProjection(
            threadID: snapshot.threadID.rawValue,
            runID: includeRuntimeIdentity ? snapshot.runID?.rawValue.uuidString : nil,
            stepIndex: snapshot.stepIndex,
            interruptID: includeRuntimeIdentity ? snapshot.interruption?.interruptID.rawValue : nil,
            interruptionPayloadHash: snapshot.interruption?.payloadHash,
            checkpointID: includeRuntimeIdentity ? snapshot.checkpointID?.rawValue : nil,
            frontierCount: snapshot.frontier.count,
            frontierHash: snapshot.frontier.hash,
            frontierEntries: snapshot.frontier.entries.map {
                CanonicalFrontierEntry(
                    nodeID: $0.nodeID.rawValue,
                    provenance: $0.provenance.rawValue,
                    localFingerprintHash: $0.localFingerprintHash
                )
            },
            channelHash: snapshot.channelState?.hash,
            channelEntries: snapshot.channelState?.entries.map {
                CanonicalChannelEntry(channelID: $0.channelID.rawValue, payloadHash: $0.payloadHash)
            } ?? [],
            eventSchemaVersion: snapshot.eventSchemaVersion,
            source: String(describing: snapshot.source)
        )
        return try hashEncodable(canonical)
    }

    static func firstTranscriptDiff(
        expected: HiveCanonicalTranscript,
        actual: HiveCanonicalTranscript
    ) -> HiveDeterminismDiff? {
        if expected.schemaVersion != actual.schemaVersion {
            return HiveDeterminismDiff(
                path: "schemaVersion",
                expected: expected.schemaVersion,
                actual: actual.schemaVersion
            )
        }

        if expected.events.count != actual.events.count {
            return HiveDeterminismDiff(
                path: "events.count",
                expected: String(expected.events.count),
                actual: String(actual.events.count)
            )
        }

        for index in expected.events.indices {
            let lhs = expected.events[index]
            let rhs = actual.events[index]
            if lhs.eventIndex != rhs.eventIndex {
                return diff(path: "events[\(index)].eventIndex", lhs.eventIndex, rhs.eventIndex)
            }
            if lhs.stepIndex != rhs.stepIndex {
                return diff(path: "events[\(index)].stepIndex", lhs.stepIndex, rhs.stepIndex)
            }
            if lhs.taskOrdinal != rhs.taskOrdinal {
                return diff(path: "events[\(index)].taskOrdinal", lhs.taskOrdinal, rhs.taskOrdinal)
            }
            if lhs.kind != rhs.kind {
                return diff(path: "events[\(index)].kind", lhs.kind, rhs.kind)
            }
            if let metadataDiff = firstDictionaryDiff(
                expected: lhs.metadata,
                actual: rhs.metadata,
                pathPrefix: "events[\(index)].metadata"
            ) {
                return metadataDiff
            }
            if let attributesDiff = firstDictionaryDiff(
                expected: lhs.attributes,
                actual: rhs.attributes,
                pathPrefix: "events[\(index)].attributes"
            ) {
                return attributesDiff
            }
        }

        return nil
    }

    static func firstStateDiff<Schema: HiveSchema>(
        expected: HiveRuntimeStateSnapshot<Schema>,
        actual: HiveRuntimeStateSnapshot<Schema>,
        includeRuntimeIdentity: Bool = false
    ) -> HiveDeterminismDiff? {
        if expected.threadID != actual.threadID {
            return diff(path: "threadID", expected.threadID.rawValue, actual.threadID.rawValue)
        }
        if includeRuntimeIdentity, expected.runID != actual.runID {
            return diff(
                path: "runID",
                expected.runID?.rawValue.uuidString,
                actual.runID?.rawValue.uuidString
            )
        }
        if expected.stepIndex != actual.stepIndex {
            return diff(path: "stepIndex", expected.stepIndex, actual.stepIndex)
        }
        if includeRuntimeIdentity, expected.checkpointID != actual.checkpointID {
            return diff(path: "checkpointID", expected.checkpointID?.rawValue, actual.checkpointID?.rawValue)
        }
        if includeRuntimeIdentity, expected.interruption?.interruptID != actual.interruption?.interruptID {
            return diff(
                path: "interruption.interruptID",
                expected.interruption?.interruptID.rawValue,
                actual.interruption?.interruptID.rawValue
            )
        }
        if expected.interruption?.payloadHash != actual.interruption?.payloadHash {
            return diff(
                path: "interruption.payloadHash",
                expected.interruption?.payloadHash,
                actual.interruption?.payloadHash
            )
        }
        if expected.frontier.count != actual.frontier.count {
            return diff(path: "frontier.count", expected.frontier.count, actual.frontier.count)
        }
        if expected.frontier.hash != actual.frontier.hash {
            return diff(path: "frontier.hash", expected.frontier.hash, actual.frontier.hash)
        }
        if expected.frontier.entries.count != actual.frontier.entries.count {
            return diff(
                path: "frontier.entries.count",
                expected.frontier.entries.count,
                actual.frontier.entries.count
            )
        }
        for index in expected.frontier.entries.indices {
            let lhs = expected.frontier.entries[index]
            let rhs = actual.frontier.entries[index]
            if lhs.nodeID != rhs.nodeID {
                return diff(path: "frontier.entries[\(index)].nodeID", lhs.nodeID.rawValue, rhs.nodeID.rawValue)
            }
            if lhs.provenance != rhs.provenance {
                return diff(path: "frontier.entries[\(index)].provenance", lhs.provenance.rawValue, rhs.provenance.rawValue)
            }
            if lhs.localFingerprintHash != rhs.localFingerprintHash {
                return diff(
                    path: "frontier.entries[\(index)].localFingerprintHash",
                    lhs.localFingerprintHash,
                    rhs.localFingerprintHash
                )
            }
        }

        if expected.channelState?.hash != actual.channelState?.hash {
            return diff(path: "channelState.hash", expected.channelState?.hash, actual.channelState?.hash)
        }

        let lhsEntries = expected.channelState?.entries ?? []
        let rhsEntries = actual.channelState?.entries ?? []
        if lhsEntries.count != rhsEntries.count {
            return diff(path: "channelState.entries.count", lhsEntries.count, rhsEntries.count)
        }
        for index in lhsEntries.indices {
            if lhsEntries[index].channelID != rhsEntries[index].channelID {
                return diff(
                    path: "channelState.entries[\(index)].channelID",
                    lhsEntries[index].channelID.rawValue,
                    rhsEntries[index].channelID.rawValue
                )
            }
            if lhsEntries[index].payloadHash != rhsEntries[index].payloadHash {
                return diff(
                    path: "channelState.entries[\(index)].payloadHash",
                    lhsEntries[index].payloadHash,
                    rhsEntries[index].payloadHash
                )
            }
        }

        if expected.eventSchemaVersion != actual.eventSchemaVersion {
            return diff(
                path: "eventSchemaVersion",
                expected.eventSchemaVersion,
                actual.eventSchemaVersion
            )
        }
        if expected.source != actual.source {
            return diff(path: "source", String(describing: expected.source), String(describing: actual.source))
        }
        return nil
    }

    static func classifyCancelCheckpointRace(
        events: [HiveEvent],
        outcome: HiveRunOutcome<some HiveSchema>
    ) -> HiveCancelCheckpointResolution {
        guard case let .cancelled(_, checkpointID) = outcome else {
            return .notCancelled
        }
        let latestCheckpointEvent = events
            .filter { event in
                if case .checkpointSaved = event.kind { return true }
                return false
            }
            .max(by: { $0.id.eventIndex < $1.id.eventIndex })

        if let latestCheckpointEvent, case let .checkpointSaved(id) = latestCheckpointEvent.kind {
            return .cancelledAfterCheckpointSaved(checkpointID: id)
        }
        return .cancelledWithoutCheckpoint(latestCheckpointID: checkpointID)
    }

    // MARK: Private

    private struct CanonicalStateProjection: Codable {
        let threadID: String
        let runID: String?
        let stepIndex: Int?
        let interruptID: String?
        let interruptionPayloadHash: String?
        let checkpointID: String?
        let frontierCount: Int
        let frontierHash: String
        let frontierEntries: [CanonicalFrontierEntry]
        let channelHash: String?
        let channelEntries: [CanonicalChannelEntry]
        let eventSchemaVersion: String
        let source: String
    }

    private struct CanonicalFrontierEntry: Codable {
        let nodeID: String
        let provenance: String
        let localFingerprintHash: String
    }

    private struct CanonicalChannelEntry: Codable {
        let channelID: String
        let payloadHash: String
    }

    private static func canonicalKind(_ kind: HiveEventKind) -> (kind: String, attributes: [String: String]) {
        switch kind {
        case let .runStarted(threadID):
            ("runStarted", ["threadID": threadID.rawValue])
        case .runFinished:
            ("runFinished", [:])
        case let .runInterrupted(interruptID):
            ("runInterrupted", ["interruptID": interruptID.rawValue])
        case let .runResumed(interruptID):
            ("runResumed", ["interruptID": interruptID.rawValue])
        case let .runCancelled(cause):
            ("runCancelled", ["cause": String(describing: cause)])
        case let .forkStarted(sourceThreadID, targetThreadID, sourceCheckpointID):
            (
                "forkStarted",
                [
                    "sourceThreadID": sourceThreadID.rawValue,
                    "targetThreadID": targetThreadID.rawValue,
                    "sourceCheckpointID": sourceCheckpointID?.rawValue ?? "nil",
                ]
            )
        case let .forkCompleted(sourceThreadID, targetThreadID, sourceCheckpointID, targetCheckpointID):
            (
                "forkCompleted",
                [
                    "sourceThreadID": sourceThreadID.rawValue,
                    "targetThreadID": targetThreadID.rawValue,
                    "sourceCheckpointID": sourceCheckpointID.rawValue,
                    "targetCheckpointID": targetCheckpointID?.rawValue ?? "nil",
                ]
            )
        case let .forkFailed(sourceThreadID, targetThreadID, sourceCheckpointID, errorCode):
            (
                "forkFailed",
                [
                    "sourceThreadID": sourceThreadID.rawValue,
                    "targetThreadID": targetThreadID.rawValue,
                    "sourceCheckpointID": sourceCheckpointID?.rawValue ?? "nil",
                    "errorCode": errorCode,
                ]
            )
        case let .stepStarted(stepIndex, frontierCount):
            ("stepStarted", ["stepIndex": String(stepIndex), "frontierCount": String(frontierCount)])
        case let .stepFinished(stepIndex, nextFrontierCount):
            ("stepFinished", ["stepIndex": String(stepIndex), "nextFrontierCount": String(nextFrontierCount)])
        case let .taskStarted(node, _):
            ("taskStarted", ["nodeID": node.rawValue])
        case let .taskFinished(node, _):
            ("taskFinished", ["nodeID": node.rawValue])
        case let .taskFailed(node, _, errorDescription):
            ("taskFailed", ["nodeID": node.rawValue, "errorDescription": errorDescription])
        case let .writeApplied(channelID, _):
            // payloadHash includes runtime identity (e.g., message IDs) and is not stable across fresh runtimes.
            ("writeApplied", ["channelID": channelID.rawValue])
        case let .checkpointSaved(checkpointID):
            ("checkpointSaved", ["checkpointID": checkpointID.rawValue])
        case let .checkpointLoaded(checkpointID):
            ("checkpointLoaded", ["checkpointID": checkpointID.rawValue])
        case let .storeSnapshot(channelValues):
            (
                "storeSnapshot",
                [
                    "channels": canonicalChannelValueSummary(channelValues)
                ]
            )
        case let .channelUpdates(channelValues):
            (
                "channelUpdates",
                [
                    "channels": canonicalChannelValueSummary(channelValues)
                ]
            )
        case let .modelInvocationStarted(model):
            ("modelInvocationStarted", ["model": model])
        case let .modelToken(text):
            ("modelToken", ["text": text])
        case .modelInvocationFinished:
            ("modelInvocationFinished", [:])
        case let .toolInvocationStarted(name):
            ("toolInvocationStarted", ["name": name])
        case let .toolInvocationFinished(name, success):
            ("toolInvocationFinished", ["name": name, "success": String(success)])
        case let .streamBackpressure(droppedModelTokenEvents, droppedDebugEvents):
            (
                "streamBackpressure",
                [
                    "droppedModelTokenEvents": String(droppedModelTokenEvents),
                    "droppedDebugEvents": String(droppedDebugEvents)
                ]
            )
        case let .customDebug(name):
            ("customDebug", ["name": name])
        }
    }

    private static func canonicalChannelValueSummary(_ values: [HiveSnapshotValue]) -> String {
        let items = values
            .map { value in
                (value.channelID.rawValue, value.payloadHash)
            }
            .sorted { lhs, rhs in
                lhs.0.utf8.lexicographicallyPrecedes(rhs.0.utf8)
            }
            .map { "\($0)|\($1)" }
        return items.joined(separator: ";")
    }

    private static func canonicalMetadata(_ metadata: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: metadata.sorted { lhs, rhs in
            lhs.key.utf8.lexicographicallyPrecedes(rhs.key.utf8)
        })
    }

    private static func hashEncodable(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        return try sha256Hex(encoder.encode(value))
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func diff<Value>(path: String, _ expected: Value, _ actual: Value) -> HiveDeterminismDiff {
        HiveDeterminismDiff(path: path, expected: String(describing: expected), actual: String(describing: actual))
    }

    private static func firstDictionaryDiff(
        expected: [String: String],
        actual: [String: String],
        pathPrefix: String
    ) -> HiveDeterminismDiff? {
        let allKeys = Set(expected.keys).union(actual.keys).sorted { lhs, rhs in
            lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
        }
        for key in allKeys {
            let lhs = expected[key]
            let rhs = actual[key]
            if lhs != rhs {
                return diff(path: "\(pathPrefix).\(key)", lhs, rhs)
            }
        }
        return nil
    }
}

// MARK: - HiveTranscriptHashProjection

private struct HiveTranscriptHashProjection: Codable, Sendable, Equatable {
    let schemaVersion: String
    let events: [HiveTranscriptHashEventRecord]
}

// MARK: - HiveTranscriptHashEventRecord

private struct HiveTranscriptHashEventRecord: Codable, Sendable, Equatable {
    let stepIndex: Int?
    let taskOrdinal: Int?
    let kind: String
    let attributes: [String: String]
    let metadata: [String: String]

    var sortKey: String {
        let step = stepIndex.map(String.init) ?? "nil"
        let task = taskOrdinal.map(String.init) ?? "nil"
        let attributesKey = attributes
            .map { ($0.key, $0.value) }
            .sorted { $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) }
            .map { "\($0)=\($1)" }
            .joined(separator: "&")
        let metadataKey = metadata
            .map { ($0.key, $0.value) }
            .sorted { $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) }
            .map { "\($0)=\($1)" }
            .joined(separator: "&")
        return "\(step)|\(task)|\(kind)|\(attributesKey)|\(metadataKey)"
    }
}

extension GraphRunController {
    // MARK: Internal

    static func decorate(event: HiveEvent) -> HiveEvent {
        var metadata = event.metadata
        if metadata[EventSchemaVersion.metadataKey] == nil {
            metadata[EventSchemaVersion.metadataKey] = EventSchemaVersion.current
        }
        return HiveEvent(id: event.id, kind: event.kind, metadata: metadata)
    }

    func validateRunOptions(_ options: HiveRunOptions) throws {
        let environment = runtime.environmentSnapshot

        if environment.modelRouter == nil, environment.model == nil {
            throw HiveRuntimeError.modelClientMissing
        }
        if environment.tools == nil {
            throw HiveRuntimeError.toolRegistryMissing
        }

        guard options.maxSteps >= 0 else {
            throw HiveRuntimeError.invalidRunOptions("maxSteps must be >= 0")
        }
        guard options.maxConcurrentTasks >= 1 else {
            throw HiveRuntimeError.invalidRunOptions("maxConcurrentTasks must be >= 1")
        }
        guard options.eventBufferCapacity >= 1 else {
            throw HiveRuntimeError.invalidRunOptions("eventBufferCapacity must be >= 1")
        }
        if case let .every(steps) = options.checkpointPolicy, steps < 1 {
            throw HiveRuntimeError.invalidRunOptions("checkpointPolicy.every requires steps >= 1")
        }

        if environment.context.toolApprovalPolicy != .never, environment.checkpointStore == nil {
            throw HiveRuntimeError.checkpointStoreMissing
        }
        switch options.checkpointPolicy {
        case .disabled:
            break
        case .every,
             .everyStep,
             .onInterrupt:
            if environment.checkpointStore == nil {
                throw HiveRuntimeError.checkpointStoreMissing
            }
        }

        if let policy = environment.context.compactionPolicy {
            guard environment.context.tokenizer != nil else {
                throw HiveRuntimeError.invalidRunOptions("Compaction policy requires a tokenizer.")
            }
            if policy.maxTokens < 1 || policy.preserveLastMessages < 0 {
                throw HiveRuntimeError.invalidRunOptions("Invalid compaction policy bounds.")
            }
        }

        if let outputProjection = options.outputProjectionOverride {
            let specsByID = Dictionary(ChatGraph.Schema.channelSpecs.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            if case let .channels(ids) = outputProjection {
                for id in ids {
                    guard let spec = specsByID[id] else {
                        throw HiveRuntimeError.invalidRunOptions(
                            "output projection includes unknown channel \(id.rawValue)"
                        )
                    }
                    if spec.scope == .taskLocal {
                        throw HiveRuntimeError.invalidRunOptions(
                            "output projection includes task-local channel \(id.rawValue)"
                        )
                    }
                }
            }
        }
    }

    func validateResumeRequest(_ request: RunResumeRequest) async throws {
        guard runtime.environmentSnapshot.checkpointStore != nil else {
            throw HiveRuntimeError.checkpointStoreMissing
        }
        guard let checkpoint = try await runtime.getLatestCheckpoint(threadID: request.threadID) else {
            throw HiveRuntimeError.noCheckpointToResume
        }
        guard checkpoint.schemaVersion.isEmpty == false else {
            throw HiveRuntimeError.checkpointCorrupt(
                field: "schemaVersion",
                errorDescription: "missing schema version"
            )
        }
        guard checkpoint.graphVersion.isEmpty == false else {
            throw HiveRuntimeError.checkpointCorrupt(
                field: "graphVersion",
                errorDescription: "missing graph version"
            )
        }
        guard checkpoint.checkpointFormatVersion == "HCP1" || checkpoint.checkpointFormatVersion == "HCP2" else {
            throw HiveRuntimeError.checkpointCorrupt(
                field: "checkpointFormatVersion",
                errorDescription: "unsupported format \(checkpoint.checkpointFormatVersion)"
            )
        }
        guard let interruption = checkpoint.interruption else {
            throw HiveRuntimeError.noInterruptToResume
        }
        guard interruption.id == request.interruptID else {
            throw HiveRuntimeError.resumeInterruptMismatch(
                expected: interruption.id,
                found: request.interruptID
            )
        }
    }

    func decorate(
        handle: HiveRunHandle<ChatGraph.Schema>,
        threadID: HiveThreadID,
        eventBufferCapacity: Int
    ) -> HiveRunHandle<ChatGraph.Schema> {
        let bufferSize = max(1, eventBufferCapacity)
        let stream = StreamHelper.makeTrackedStream(bufferSize: bufferSize) { continuation in
            for try await event in handle.events {
                let decorated = Self.decorate(event: event)
                await stateTracker.record(event: decorated, threadID: threadID)
                continuation.yield(decorated)
            }
            continuation.finish()
        }

        let outcome = Task<HiveRunOutcome<ChatGraph.Schema>, Error> {
            try await withTaskCancellationHandler(operation: {
                let resolved = try await handle.outcome.value
                await stateTracker.record(outcome: resolved, threadID: threadID, runID: handle.runID)
                return resolved
            }, onCancel: {
                handle.outcome.cancel()
            })
        }

        return HiveRunHandle(
            runID: handle.runID,
            attemptID: handle.attemptID,
            events: stream,
            outcome: outcome
        )
    }

    func applyExternalWrites(
        _ request: ExternalWriteRequest
    ) async throws -> HiveRunHandle<ChatGraph.Schema> {
        try validateRunOptions(request.options)
        try Self.validateExternalWrites(request.writes)

        if let state = try await getState(threadID: request.threadID),
           let interruption = state.interruption {
            throw HiveRuntimeError.interruptPending(interruptID: interruption.interruptID)
        }

        let handle = await runtime.applyExternalWrites(
            threadID: request.threadID,
            writes: request.writes,
            options: request.options
        )
        await stateTracker.markAttemptStarted(threadID: request.threadID, runID: handle.runID)
        return decorate(handle: handle, threadID: request.threadID, eventBufferCapacity: request.options.eventBufferCapacity)
    }

    func checkpointQueryCapability(
        probeThreadID: HiveThreadID = HiveThreadID("__hive_checkpoint_capability_probe__")
    ) async -> HiveCheckpointQueryCapability {
        guard runtime.environmentSnapshot.checkpointStore != nil else {
            return .unavailable
        }
        do {
            _ = try await runtime.getCheckpointHistory(threadID: probeThreadID, limit: 1)
            return .queryable
        } catch let error as HiveCheckpointQueryError {
            if case .unsupported = error {
                return .latestOnly
            }
            return .queryable
        } catch {
            return .queryable
        }
    }

    func getCheckpointHistory(
        threadID: HiveThreadID,
        limit: Int? = nil
    ) async throws -> [HiveCheckpointSummary] {
        try await runtime.getCheckpointHistory(threadID: threadID, limit: limit)
    }

    func getCheckpoint(
        threadID: HiveThreadID,
        id: HiveCheckpointID
    ) async throws -> HiveCheckpoint<ChatGraph.Schema>? {
        try await runtime.getCheckpoint(threadID: threadID, id: id)
    }

    func getState(
        threadID: HiveThreadID
    ) async throws -> HiveRuntimeStateSnapshot<ChatGraph.Schema>? {
        let tracked = await stateTracker.snapshot(threadID: threadID)
        let runtimeSnapshot = try await runtime.getState(threadID: threadID)

        if let runtimeSnapshot {
            let interruption = Self.resolveInterruptionSummary(
                runtimeInterruption: runtimeSnapshot.interruption,
                tracked: tracked
            )
            return HiveRuntimeStateSnapshot(
                threadID: runtimeSnapshot.threadID,
                runID: tracked?.runID ?? runtimeSnapshot.runID,
                stepIndex: tracked?.stepIndex ?? runtimeSnapshot.stepIndex,
                interruption: interruption,
                checkpointID: tracked?.checkpointID ?? runtimeSnapshot.checkpointID,
                frontier: runtimeSnapshot.frontier,
                channelState: runtimeSnapshot.channelState,
                eventSchemaVersion: tracked?.eventSchemaVersion ?? runtimeSnapshot.eventSchemaVersion,
                source: runtimeSnapshot.source
            )
        }

        guard let tracked else {
            return nil
        }
        return HiveRuntimeStateSnapshot(
            threadID: threadID,
            runID: tracked.runID,
            stepIndex: tracked.stepIndex,
            interruption: tracked.interruptID.map {
                HiveRuntimeInterruptionSummary<ChatGraph.Schema>(
                    interruptID: $0,
                    payloadHash: nil
                )
            },
            checkpointID: tracked.checkpointID,
            frontier: Self.resolveFrontierSummary(checkpoint: nil, fallbackCount: tracked.frontierCount),
            channelState: nil,
            eventSchemaVersion: tracked.eventSchemaVersion ?? EventSchemaVersion.current,
            source: .trackerOnly
        )
    }

    // MARK: Fileprivate

    fileprivate static func resolveInterruptionSummary(
        checkpoint: HiveCheckpoint<ChatGraph.Schema>?,
        trackedInterruptID: HiveInterruptID?
    ) throws -> HiveRuntimeInterruptionSummary<ChatGraph.Schema>? {
        if let interruption = checkpoint?.interruption {
            let payloadHash = try stablePayloadHash(interruption.payload)
            return HiveRuntimeInterruptionSummary(
                interruptID: interruption.id,
                payloadHash: payloadHash
            )
        }
        if let trackedInterruptID {
            return HiveRuntimeInterruptionSummary(
                interruptID: trackedInterruptID,
                payloadHash: nil
            )
        }
        return nil
    }

    fileprivate static func resolveFrontierSummary(
        checkpoint: HiveCheckpoint<ChatGraph.Schema>?,
        fallbackCount: Int?
    ) -> HiveRuntimeFrontierSummary {
        if let checkpoint {
            let entries = checkpoint.frontier.map { entry in
                HiveRuntimeFrontierSummary.Entry(
                    nodeID: entry.nodeID,
                    provenance: entry.provenance,
                    localFingerprintHash: hexLower(entry.localFingerprint)
                )
            }.sorted { lhs, rhs in
                if lhs.nodeID.rawValue == rhs.nodeID.rawValue {
                    if lhs.provenance.rawValue == rhs.provenance.rawValue {
                        return lhs.localFingerprintHash.utf8.lexicographicallyPrecedes(rhs.localFingerprintHash.utf8)
                    }
                    return lhs.provenance.rawValue.utf8.lexicographicallyPrecedes(rhs.provenance.rawValue.utf8)
                }
                return lhs.nodeID.rawValue.utf8.lexicographicallyPrecedes(rhs.nodeID.rawValue.utf8)
            }
            let digestInput = entries
                .map { "\($0.nodeID.rawValue)|\($0.provenance.rawValue)|\($0.localFingerprintHash)" }
                .joined(separator: ";")
            return HiveRuntimeFrontierSummary(
                count: checkpoint.frontier.count,
                hash: sha256Hex(Data(digestInput.utf8)),
                entries: entries
            )
        }

        let count = fallbackCount ?? 0
        return HiveRuntimeFrontierSummary(
            count: count,
            hash: sha256Hex(Data("count:\(count)".utf8)),
            entries: []
        )
    }

    fileprivate static func resolveChannelSummary(
        store: HiveGlobalStore<ChatGraph.Schema>?,
        checkpoint: HiveCheckpoint<ChatGraph.Schema>?
    ) throws -> HiveRuntimeChannelStateSummary? {
        if let store {
            return try resolveChannelSummaryFromStore(store)
        }
        if let checkpoint {
            let entries = checkpoint.globalDataByChannelID
                .map { rawID, payload in
                    HiveRuntimeChannelStateSummary.Entry(
                        channelID: HiveChannelID(rawID),
                        payloadHash: sha256Hex(payload)
                    )
                }
                .sorted { lhs, rhs in
                    lhs.channelID.rawValue.utf8.lexicographicallyPrecedes(rhs.channelID.rawValue.utf8)
                }
            let digestInput = entries.map { "\($0.channelID.rawValue)|\($0.payloadHash)" }.joined(separator: ";")
            return HiveRuntimeChannelStateSummary(
                hash: sha256Hex(Data(digestInput.utf8)),
                entries: entries
            )
        }
        return nil
    }

    fileprivate static func resolveChannelSummaryFromStore(
        _ store: HiveGlobalStore<ChatGraph.Schema>
    ) throws -> HiveRuntimeChannelStateSummary {
        let canonicalMessages: [HiveAgentsMessageForStateHash] = try store
            .get(ChatGraph.Schema.messagesKey)
            .map { message in
                HiveAgentsMessageForStateHash(
                    role: message.role,
                    content: message.content,
                    name: message.name,
                    toolCallID: message.toolCallID,
                    toolCalls: message.toolCalls,
                    op: message.op
                )
            }

        let entries: [HiveRuntimeChannelStateSummary.Entry] = try [
            HiveRuntimeChannelStateSummary.Entry(
                channelID: ChatGraph.Schema.messagesKey.id,
                payloadHash: sha256Hex(HiveStateSnapshotCodec.messages.encode(canonicalMessages))
            ),
            HiveRuntimeChannelStateSummary.Entry(
                channelID: ChatGraph.Schema.pendingToolCallsKey.id,
                payloadHash: sha256Hex(HiveStateSnapshotCodec.pendingToolCalls.encode(store.get(ChatGraph.Schema.pendingToolCallsKey)))
            ),
            HiveRuntimeChannelStateSummary.Entry(
                channelID: ChatGraph.Schema.finalAnswerKey.id,
                payloadHash: sha256Hex(HiveStateSnapshotCodec.finalAnswer.encode(store.get(ChatGraph.Schema.finalAnswerKey)))
            ),
            HiveRuntimeChannelStateSummary.Entry(
                channelID: ChatGraph.Schema.llmInputMessagesKey.id,
                payloadHash: sha256Hex(HiveStateSnapshotCodec.llmInputMessages.encode(store.get(ChatGraph.Schema.llmInputMessagesKey)))
            ),
            HiveRuntimeChannelStateSummary.Entry(
                channelID: ChatGraph.Schema.membraneCheckpointDataKey.id,
                payloadHash: sha256Hex(HiveStateSnapshotCodec.membraneCheckpointData.encode(store.get(ChatGraph.Schema.membraneCheckpointDataKey)))
            )
        ]
        let sortedEntries = entries.sorted { lhs, rhs in
            lhs.channelID.rawValue.utf8.lexicographicallyPrecedes(rhs.channelID.rawValue.utf8)
        }
        let digestInput = sortedEntries.map { "\($0.channelID.rawValue)|\($0.payloadHash)" }.joined(separator: ";")
        return HiveRuntimeChannelStateSummary(
            hash: sha256Hex(Data(digestInput.utf8)),
            entries: sortedEntries
        )
    }

    fileprivate static func stablePayloadHash(_ payload: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        return try sha256Hex(encoder.encode(payload))
    }

    // MARK: Private

    private static func resolveInterruptionSummary(
        runtimeInterruption: HiveRuntimeInterruptionSummary<ChatGraph.Schema>?,
        tracked: HiveTrackedThreadState?
    ) -> HiveRuntimeInterruptionSummary<ChatGraph.Schema>? {
        guard let tracked else {
            return runtimeInterruption
        }

        if let trackedInterruptID = tracked.interruptID {
            return HiveRuntimeInterruptionSummary<ChatGraph.Schema>(
                interruptID: trackedInterruptID,
                payloadHash: nil
            )
        }

        guard let runtimeInterruption else {
            return nil
        }

        let hasTrackedLifecycleSignal = tracked.stepIndex != nil
            || tracked.frontierCount != nil
            || tracked.checkpointID != nil
            || tracked.eventSchemaVersion != nil

        if hasTrackedLifecycleSignal {
            return nil
        }

        return runtimeInterruption
    }

    private static func validateExternalWrites(
        _ writes: [AnyHiveWrite<ChatGraph.Schema>]
    ) throws {
        let specsByID = Dictionary(uniqueKeysWithValues: ChatGraph.Schema.channelSpecs.map { ($0.id, $0) })
        var writeCounts: [HiveChannelID: Int] = [:]

        for write in writes {
            guard let spec = specsByID[write.channelID] else {
                throw HiveRuntimeError.unknownChannelID(write.channelID)
            }
            guard spec.scope == .global else {
                throw HiveRuntimeError.taskLocalWriteNotAllowed
            }
            let actualValueTypeID = String(reflecting: type(of: write.value))
            if actualValueTypeID != spec.valueTypeID {
                throw HiveRuntimeError.channelTypeMismatch(
                    channelID: write.channelID,
                    expectedValueTypeID: spec.valueTypeID,
                    actualValueTypeID: actualValueTypeID
                )
            }
            writeCounts[write.channelID, default: 0] += 1
        }

        for (channelID, count) in writeCounts {
            guard let spec = specsByID[channelID] else { continue }
            if spec.updatePolicy == .single, count > 1 {
                throw HiveRuntimeError.updatePolicyViolation(
                    channelID: channelID,
                    policy: .single,
                    writeCount: count
                )
            }
        }
    }
}

extension HiveRuntime where Schema == ChatGraph.Schema {
    func getState(
        threadID: HiveThreadID
    ) async throws -> HiveRuntimeStateSnapshot<Schema>? {
        let store = getLatestStore(threadID: threadID)
        let checkpoint = try await getLatestCheckpoint(threadID: threadID)

        guard store != nil || checkpoint != nil else {
            return nil
        }

        let source: HiveStateSnapshotSource = if store != nil, checkpoint != nil {
            .memoryAndCheckpoint
        } else if store != nil {
            .memory
        } else {
            .checkpoint
        }

        return try HiveRuntimeStateSnapshot(
            threadID: threadID,
            runID: checkpoint?.runID,
            stepIndex: checkpoint?.stepIndex,
            interruption: GraphRunController.resolveInterruptionSummary(
                checkpoint: checkpoint,
                trackedInterruptID: nil
            ),
            checkpointID: checkpoint?.id,
            frontier: GraphRunController.resolveFrontierSummary(
                checkpoint: checkpoint,
                fallbackCount: nil
            ),
            channelState: GraphRunController.resolveChannelSummary(
                store: store,
                checkpoint: checkpoint
            ),
            eventSchemaVersion: EventSchemaVersion.current,
            source: source
        )
    }
}

// MARK: - HiveAgentsMessageForStateHash

private struct HiveAgentsMessageForStateHash: Codable, Sendable {
    let role: HiveChatRole
    let content: String
    let name: String?
    let toolCallID: String?
    let toolCalls: [HiveToolCall]
    let op: HiveChatMessageOp?
}

// MARK: - HiveStateSnapshotCodec

private enum HiveStateSnapshotCodec {
    static let messages = HiveCodableJSONCodec<[HiveAgentsMessageForStateHash]>()
    static let pendingToolCalls = HiveCodableJSONCodec<[HiveToolCall]>()
    static let finalAnswer = HiveCodableJSONCodec<String?>()
    static let llmInputMessages = HiveCodableJSONCodec<[HiveChatMessage]?>()
    static let membraneCheckpointData = HiveCodableJSONCodec<Data?>()
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func hexLower(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

// MARK: - HiveAgentsStateTracker

actor HiveAgentsStateTracker {
    // MARK: Internal

    func markAttemptStarted(threadID: HiveThreadID, runID: HiveRunID) {
        var state = states[threadID] ?? HiveTrackedThreadState()
        state.runID = runID
        states[threadID] = state
    }

    func record(event: HiveEvent, threadID: HiveThreadID) {
        var state = states[threadID] ?? HiveTrackedThreadState()
        state.runID = event.id.runID
        if let schemaVersion = event.metadata[EventSchemaVersion.metadataKey] {
            state.eventSchemaVersion = schemaVersion
        }

        switch event.kind {
        case let .stepStarted(stepIndex, frontierCount):
            state.stepIndex = stepIndex
            state.frontierCount = frontierCount
        case let .stepFinished(stepIndex, nextFrontierCount):
            state.stepIndex = stepIndex + 1
            state.frontierCount = nextFrontierCount
        case let .runInterrupted(interruptID):
            state.interruptID = interruptID
        case .runResumed:
            state.interruptID = nil
        case let .checkpointSaved(checkpointID):
            state.checkpointID = checkpointID
        case let .checkpointLoaded(checkpointID):
            state.checkpointID = checkpointID
        default:
            break
        }

        states[threadID] = state
    }

    func record(
        outcome: HiveRunOutcome<ChatGraph.Schema>,
        threadID: HiveThreadID,
        runID: HiveRunID
    ) {
        var state = states[threadID] ?? HiveTrackedThreadState()
        state.runID = runID

        switch outcome {
        case let .interrupted(interruption):
            state.interruptID = interruption.interrupt.id
            state.checkpointID = interruption.checkpointID
        case let .cancelled(_, checkpointID),
             let .finished(_, checkpointID),
             let .outOfSteps(_, _, checkpointID):
            state.interruptID = nil
            if let checkpointID {
                state.checkpointID = checkpointID
            }
        }

        states[threadID] = state
    }

    func snapshot(threadID: HiveThreadID) -> HiveTrackedThreadState? {
        states[threadID]
    }

    // MARK: Private

    private var states: [HiveThreadID: HiveTrackedThreadState] = [:]
}

// MARK: - HiveTrackedThreadState

struct HiveTrackedThreadState: Sendable {
    var runID: HiveRunID?
    var stepIndex: Int?
    var interruptID: HiveInterruptID?
    var checkpointID: HiveCheckpointID?
    var frontierCount: Int?
    var eventSchemaVersion: String?
}
