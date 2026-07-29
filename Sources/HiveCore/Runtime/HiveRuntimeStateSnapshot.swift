import Foundation

/// Stable interruption metadata included in runtime state snapshots.
public struct HiveRuntimeInterruptionSnapshot: Sendable, Equatable, Codable {
    public let interruptID: HiveInterruptID
    public let payloadHash: String

    public init(interruptID: HiveInterruptID, payloadHash: String) {
        self.interruptID = interruptID
        self.payloadHash = payloadHash
    }
}

/// Stable, deterministic projection of a frontier task.
public struct HiveRuntimeFrontierSummary: Sendable, Equatable, Codable {
    public let nodeID: HiveNodeID
    public let provenance: HiveTaskProvenance
    public let taskLocalFingerprintHash: String

    public init(
        nodeID: HiveNodeID,
        provenance: HiveTaskProvenance,
        taskLocalFingerprintHash: String
    ) {
        self.nodeID = nodeID
        self.provenance = provenance
        self.taskLocalFingerprintHash = taskLocalFingerprintHash
    }
}

/// Point-in-time deterministic runtime state snapshot for one thread.
public struct HiveRuntimeStateSnapshot<Schema: HiveSchema>: Sendable {
    public let threadID: HiveThreadID
    public let runID: HiveRunID
    public let stepIndex: Int
    public let interruption: HiveRuntimeInterruptionSnapshot?
    public let checkpointID: HiveCheckpointID?

    /// Checkpoint summary retained for compatibility with existing state-inspection call sites.
    public let checkpoint: HiveCheckpointSummary?

    /// Canonical payload hash for each global channel.
    public let globalChannelPayloadHashesByID: [HiveChannelID: String]

    /// Stable frontier representation for deterministic comparisons.
    public let frontierSummary: [HiveRuntimeFrontierSummary]

    /// Typed projection of global values.
    /// This is intentionally schema-bound (no untyped Any surface).
    public let store: HiveGlobalStore<Schema>

    public init(
        threadID: HiveThreadID,
        runID: HiveRunID,
        stepIndex: Int,
        interruption: HiveRuntimeInterruptionSnapshot?,
        checkpointID: HiveCheckpointID?,
        checkpoint: HiveCheckpointSummary?,
        globalChannelPayloadHashesByID: [HiveChannelID: String],
        frontierSummary: [HiveRuntimeFrontierSummary],
        store: HiveGlobalStore<Schema>
    ) {
        self.threadID = threadID
        self.runID = runID
        self.stepIndex = stepIndex
        self.interruption = interruption
        self.checkpointID = checkpointID
        self.checkpoint = checkpoint
        self.globalChannelPayloadHashesByID = globalChannelPayloadHashesByID
        self.frontierSummary = frontierSummary
        self.store = store
    }

    /// Compatibility convenience for callers that only need next frontier nodes.
    public var nextNodes: [HiveNodeID] {
        var seen: Set<String> = []
        var nodes: [HiveNodeID] = []
        nodes.reserveCapacity(frontierSummary.count)
        for entry in frontierSummary {
            if seen.insert(entry.nodeID.rawValue).inserted {
                nodes.append(entry.nodeID)
            }
        }
        nodes.sort { HiveOrdering.lexicographicallyPrecedes($0.rawValue, $1.rawValue) }
        return nodes
    }

    /// Returns a typed value projection when `store` is available.
    public func value<Value: Sendable>(for key: HiveChannelKey<Schema, Value>) throws -> Value? {
        try store.get(key)
    }

    /// Deterministic hash for snapshot comparison in tests and replay tooling.
    public var deterministicRepresentationHash: String {
        var data = Data("HSS2".utf8)
        data.append(contentsOf: threadID.rawValue.utf8)
        data.append(0)
        data.append(contentsOf: runID.rawValue.uuidString.utf8)
        data.append(0)
        data.append(contentsOf: String(stepIndex).utf8)
        data.append(0)
        if let interruption {
            data.append(contentsOf: interruption.interruptID.rawValue.utf8)
            data.append(0)
            data.append(contentsOf: interruption.payloadHash.utf8)
        }
        data.append(0)
        if let checkpointID {
            data.append(contentsOf: checkpointID.rawValue.utf8)
        }
        data.append(0)

        for (channelID, payloadHash) in globalChannelPayloadHashesByID
            .sorted(by: { HiveOrdering.lexicographicallyPrecedes($0.key.rawValue, $1.key.rawValue) }) {
            data.append(contentsOf: channelID.rawValue.utf8)
            data.append(0)
            data.append(contentsOf: payloadHash.utf8)
            data.append(0)
        }

        for entry in frontierSummary {
            data.append(contentsOf: entry.nodeID.rawValue.utf8)
            data.append(0)
            data.append(contentsOf: entry.provenance.rawValue.utf8)
            data.append(0)
            data.append(contentsOf: entry.taskLocalFingerprintHash.utf8)
            data.append(0)
        }

        let digest = HiveSHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
