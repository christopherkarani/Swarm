/// Seed used to schedule a task in the next frontier.
public struct HiveTaskSeed<Schema: HiveSchema>: Sendable {
    public let nodeID: HiveNodeID
    public let local: HiveTaskLocalStore<Schema>

    public init(nodeID: HiveNodeID, local: HiveTaskLocalStore<Schema> = .empty) {
        self.nodeID = nodeID
        self.local = local
    }
}

/// Origin of a scheduled task.
public enum HiveTaskProvenance: String, Codable, Sendable {
    case graph
    case spawn
}

/// Executable task derived from the frontier.
public struct HiveTask<Schema: HiveSchema>: Sendable {
    public let id: HiveTaskID
    public let ordinal: Int
    public let provenance: HiveTaskProvenance
    public let nodeID: HiveNodeID
    public let local: HiveTaskLocalStore<Schema>

    public init(
        id: HiveTaskID,
        ordinal: Int,
        provenance: HiveTaskProvenance,
        nodeID: HiveNodeID,
        local: HiveTaskLocalStore<Schema>
    ) {
        self.id = id
        self.ordinal = ordinal
        self.provenance = provenance
        self.nodeID = nodeID
        self.local = local
    }
}

/// Run-scoped context provided to each node.
public struct HiveRunContext<Schema: HiveSchema>: Sendable {
    public let runID: HiveRunID
    public let threadID: HiveThreadID
    public let attemptID: HiveRunAttemptID
    public let stepIndex: Int
    public let taskID: HiveTaskID
    public let options: HiveRunOptions
    public let resume: HiveResume<Schema>?

    public init(
        runID: HiveRunID,
        threadID: HiveThreadID,
        attemptID: HiveRunAttemptID,
        stepIndex: Int,
        taskID: HiveTaskID,
        options: HiveRunOptions = HiveRunOptions(),
        resume: HiveResume<Schema>?
    ) {
        self.runID = runID
        self.threadID = threadID
        self.attemptID = attemptID
        self.stepIndex = stepIndex
        self.taskID = taskID
        self.options = options
        self.resume = resume
    }
}

/// Node execution closure.
public typealias NodeAction<Schema: HiveSchema> =
    @Sendable (HiveNodeInput<Schema>) async throws -> HiveNodeOutput<Schema>

/// Inputs passed to a node execution.
public struct HiveNodeInput<Schema: HiveSchema>: Sendable {
    public let store: HiveStoreView<Schema>
    public let run: HiveRunContext<Schema>
    public let context: Schema.Context
    public let environment: HiveEnvironment<Schema>
    public let emitStream: @Sendable (_ kind: HiveStreamEventKind, _ metadata: [String: String]) -> Void
    public let emitDebug: @Sendable (_ name: String, _ metadata: [String: String]) -> Void

    public init(
        store: HiveStoreView<Schema>,
        run: HiveRunContext<Schema>,
        context: Schema.Context,
        environment: HiveEnvironment<Schema>,
        emitStream: @escaping @Sendable (_ kind: HiveStreamEventKind, _ metadata: [String: String]) -> Void,
        emitDebug: @escaping @Sendable (_ name: String, _ metadata: [String: String]) -> Void
    ) {
        self.store = store
        self.run = run
        self.context = context
        self.environment = environment
        self.emitStream = emitStream
        self.emitDebug = emitDebug
    }
}

/// Stream-only event kinds emitted by nodes.
public enum HiveStreamEventKind: Sendable {
    case customDebug(name: String)
}

/// Output of a node execution.
public struct HiveNodeOutput<Schema: HiveSchema>: Sendable {
    public var writes: [AnyHiveWrite<Schema>]
    public var spawn: [HiveTaskSeed<Schema>]
    public var next: Route
    public var interrupt: HiveInterruptRequest<Schema>?

    public init(
        writes: [AnyHiveWrite<Schema>] = [],
        spawn: [HiveTaskSeed<Schema>] = [],
        next: Route = .useGraphEdges,
        interrupt: HiveInterruptRequest<Schema>? = nil
    ) {
        self.writes = writes
        self.spawn = spawn
        self.next = next
        self.interrupt = interrupt
    }
}
