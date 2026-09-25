import Foundation
import Mutex

/// Execution state and event plumbing for ``HiveRuntime``.
///
/// Extracted from `HiveRuntime.swift` to keep the runtime file focused on
/// scheduling and step execution. All types are module-internal.

struct HiveFrontierTask<Schema: HiveSchema>: Sendable {
    let seed: HiveTaskSeed<Schema>
    let provenance: HiveTaskProvenance
    let isJoinSeed: Bool
}

struct ThreadState<Schema: HiveSchema>: Sendable {
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

struct WriteRecord<Schema: HiveSchema>: Sendable {
    let channelID: HiveChannelID
    let value: any Sendable
    let emissionIndex: Int
    let taskOrdinal: Int
    let spec: AnyHiveChannelSpec<Schema>
}

struct TaskWrites<Schema: HiveSchema>: Sendable {
    var global: [WriteRecord<Schema>] = []
    var taskLocal: [WriteRecord<Schema>] = []
}

struct CommitResult<Schema: HiveSchema>: Sendable {
    let global: HiveGlobalStore<Schema>
    let frontier: [HiveFrontierTask<Schema>]
    let deferredFrontier: [HiveFrontierTask<Schema>]
    let joinSeenParents: [String: HiveBitset]
    let writtenGlobalChannels: [HiveChannelID]
}

struct StepOutcome<Schema: HiveSchema>: Sendable {
    let nextState: ThreadState<Schema>
    let writtenGlobalChannels: [HiveChannelID]
    let dropped: HiveDroppedEventCounts
    let selectedInterrupt: HiveInterrupt<Schema>?
    let checkpointToSave: HiveCheckpoint<Schema>?
}

struct HiveDroppedEventCounts: Sendable {
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

final class HiveDroppedEventCounter: Sendable {
    private let counts = Mutex(HiveDroppedEventCounts())

    func record(_ enqueueResult: HiveEventEnqueueResult) {
        counts.withLock { $0.record(enqueueResult) }
    }

    func snapshot() -> HiveDroppedEventCounts {
        counts.withLock { $0 }
    }
}

struct BufferedStreamEvent: Sendable {
    let kind: HiveEventKind
    let metadata: [String: String]
    let taskOrdinal: Int
}

final class HivePerAttemptStreamBuffer: Sendable {
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

struct TaskExecutionResult<Schema: HiveSchema>: Sendable {
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

struct SeedKey: Hashable, Sendable {
    let nodeID: HiveNodeID
    let fingerprint: Data
}

final class HiveEventEmitter: Sendable {
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
