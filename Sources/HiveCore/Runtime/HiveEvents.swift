/// Stable identifier for a run event.
public struct HiveEventID: Hashable, Codable, Sendable {
    public let runID: HiveRunID
    public let attemptID: HiveRunAttemptID
    public let eventIndex: UInt64
    public let stepIndex: Int?
    public let taskOrdinal: Int?

    public init(
        runID: HiveRunID,
        attemptID: HiveRunAttemptID,
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

/// Version marker for event-schema/replay compatibility checks.
public enum HiveEventSchemaVersion: String, Codable, Sendable, Equatable {
    case v0 = "HES0"
    case v1 = "HES1"

    public static let current: HiveEventSchemaVersion = .v1
}

/// Classified cancellation causes used by lifecycle events.
public enum HiveRunCancellationCause: String, Codable, Sendable, Equatable {
    case explicitRequest
    case checkpointPersistenceRace
    case executionObserved
}

/// Event emitted by the runtime event stream.
public struct HiveEvent: Sendable {
    public let schemaVersion: HiveEventSchemaVersion
    public let id: HiveEventID
    public let kind: HiveEventKind
    public let metadata: [String: String]

    public init(
        schemaVersion: HiveEventSchemaVersion = .current,
        id: HiveEventID,
        kind: HiveEventKind,
        metadata: [String: String]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.kind = kind
        self.metadata = metadata
    }
}

/// A single channel's value in a store snapshot or channel update event.
public struct HiveSnapshotValue: Sendable {
    public let channelID: HiveChannelID
    public let payloadHash: String
    public let debugValue: (any Sendable)?

    public init(channelID: HiveChannelID, payloadHash: String, debugValue: (any Sendable)? = nil) {
        self.channelID = channelID
        self.payloadHash = payloadHash
        self.debugValue = debugValue
    }
}

/// Event kinds emitted during a run.
public enum HiveEventKind: Sendable {
    case runStarted(threadID: HiveThreadID)
    case runFinished
    case runInterrupted(interruptID: HiveInterruptID)
    case runResumed(interruptID: HiveInterruptID)
    case runCancelled(cause: HiveRunCancellationCause)
    case forkStarted(sourceThreadID: HiveThreadID, targetThreadID: HiveThreadID, sourceCheckpointID: HiveCheckpointID?)
    case forkCompleted(
        sourceThreadID: HiveThreadID,
        targetThreadID: HiveThreadID,
        sourceCheckpointID: HiveCheckpointID,
        targetCheckpointID: HiveCheckpointID?
    )
    case forkFailed(
        sourceThreadID: HiveThreadID,
        targetThreadID: HiveThreadID,
        sourceCheckpointID: HiveCheckpointID?,
        errorCode: String
    )

    case stepStarted(stepIndex: Int, frontierCount: Int)
    case stepFinished(stepIndex: Int, nextFrontierCount: Int)

    case taskStarted(node: HiveNodeID, taskID: HiveTaskID)
    case taskFinished(node: HiveNodeID, taskID: HiveTaskID)
    case taskFailed(node: HiveNodeID, taskID: HiveTaskID, errorDescription: String)

    case writeApplied(channelID: HiveChannelID, payloadHash: String)
    case checkpointSaved(checkpointID: HiveCheckpointID)
    case checkpointLoaded(checkpointID: HiveCheckpointID)

    case storeSnapshot(channelValues: [HiveSnapshotValue])
    case channelUpdates(channelValues: [HiveSnapshotValue])

    case streamBackpressure(droppedDebugEvents: Int)
    case customDebug(name: String)
}
