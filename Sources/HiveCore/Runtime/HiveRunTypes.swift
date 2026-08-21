/// Output value for a projected channel.
///
/// Prefer ``HiveChannelProjection/get(_:)`` on ``HiveRunOutput/channels(_:)``.
public struct HiveProjectedChannelValue: Sendable {
    public let id: HiveChannelID
    public let value: any Sendable

    public init(id: HiveChannelID, value: any Sendable) {
        self.id = id
        self.value = value
    }
}

/// Typed read surface for a subset of global channel values.
public struct HiveChannelProjection<Schema: HiveSchema>: Sendable {
    private let valuesByID: [HiveChannelID: any Sendable]
    private let access: HiveStoreSupport<Schema>

    init(valuesByID: [HiveChannelID: any Sendable], registry: HiveSchemaRegistry<Schema>) {
        self.valuesByID = valuesByID
        self.access = HiveStoreSupport(registry: registry)
    }

    /// Reads a channel through its schema-bound key.
    public func get<Value: Sendable>(_ key: HiveChannelKey<Schema, Value>) throws -> Value {
        let spec = try access.requireSpec(for: key.id)
        guard let value = valuesByID[key.id] else {
            throw HiveRuntimeError.storeValueMissing(channelID: key.id)
        }
        return try access.cast(value, for: key, spec: spec)
    }
}

/// Output of a completed run attempt.
public enum HiveRunOutput<Schema: HiveSchema>: Sendable {
    case fullStore(HiveGlobalStore<Schema>)
    case channels(HiveChannelProjection<Schema>)
}

/// Terminal result of a run attempt.
public enum HiveRunOutcome<Schema: HiveSchema>: Sendable {
    case finished(output: HiveRunOutput<Schema>, checkpointID: HiveCheckpointID?)
    case interrupted(interruption: HiveInterruption<Schema>)
    case cancelled(output: HiveRunOutput<Schema>, checkpointID: HiveCheckpointID?)
    case outOfSteps(maxSteps: Int, output: HiveRunOutput<Schema>, checkpointID: HiveCheckpointID?)
}

/// Handle for observing a running attempt.
public struct HiveRunHandle<Schema: HiveSchema>: Sendable {
    public let runID: HiveRunID
    public let attemptID: HiveRunAttemptID
    public let events: AsyncThrowingStream<HiveEvent, Error>
    public let outcome: Task<HiveRunOutcome<Schema>, Error>
    private let streamController: HiveEventStreamController?

    public init(
        runID: HiveRunID,
        attemptID: HiveRunAttemptID,
        events: AsyncThrowingStream<HiveEvent, Error>,
        outcome: Task<HiveRunOutcome<Schema>, Error>
    ) {
        self.runID = runID
        self.attemptID = attemptID
        self.events = events
        self.outcome = outcome
        self.streamController = nil
    }

    init(
        runID: HiveRunID,
        attemptID: HiveRunAttemptID,
        events: AsyncThrowingStream<HiveEvent, Error>,
        outcome: Task<HiveRunOutcome<Schema>, Error>,
        streamController: HiveEventStreamController
    ) {
        self.runID = runID
        self.attemptID = attemptID
        self.events = events
        self.outcome = outcome
        self.streamController = streamController
    }
}

/// Structured lineage metadata for a forked thread.
public struct HiveForkLineage: Sendable, Codable, Equatable {
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

/// Result of forking a checkpoint/thread into a new thread lineage.
public struct HiveForkResult<Schema: HiveSchema>: Sendable {
    public let sourceThreadID: HiveThreadID
    public let sourceCheckpointID: HiveCheckpointID
    public let targetThreadID: HiveThreadID
    public let targetCheckpointID: HiveCheckpointID?
    public let runID: HiveRunID
    public let lineage: HiveForkLineage?

    public init(
        sourceThreadID: HiveThreadID,
        sourceCheckpointID: HiveCheckpointID,
        targetThreadID: HiveThreadID,
        targetCheckpointID: HiveCheckpointID?,
        runID: HiveRunID,
        lineage: HiveForkLineage?
    ) {
        self.sourceThreadID = sourceThreadID
        self.sourceCheckpointID = sourceCheckpointID
        self.targetThreadID = targetThreadID
        self.targetCheckpointID = targetCheckpointID
        self.runID = runID
        self.lineage = lineage
    }
}
