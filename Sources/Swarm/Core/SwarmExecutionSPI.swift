import Foundation

@_spi(ColonyInternal) public protocol SwarmExecutionChannelKey<Value>: Sendable {
    associatedtype Value: Sendable
    associatedtype ID: Hashable & Sendable

    var swarmExecutionChannelID: ID { get }
}

@_spi(ColonyInternal) public protocol SwarmExecutionSchema: SendableMetatype {
    associatedtype Snapshot: Sendable
    associatedtype Context: Sendable
    associatedtype ResumePayload: Sendable
    associatedtype InterruptPayload: Sendable
    associatedtype EventKind: Sendable
    associatedtype ChannelID: Hashable & Sendable

    static var localOnlyChannelIDs: Set<ChannelID> { get }

    static func read<Value: Sendable>(
        _ snapshot: Snapshot,
        channelID: ChannelID,
        as type: Value.Type
    ) throws -> Value
}

@_spi(ColonyInternal) public struct SwarmNodeID: Sendable, Hashable, Equatable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

@_spi(ColonyInternal) public struct SwarmTaskID: Sendable, Hashable, Equatable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

@_spi(ColonyInternal) public struct SwarmRunID: Sendable, Hashable, Equatable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

@_spi(ColonyInternal) public struct SwarmThreadID: Sendable, Hashable, Equatable, Codable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

@_spi(ColonyInternal) public struct SwarmInterruptID: Sendable, Hashable, Equatable, Codable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

@_spi(ColonyInternal) public struct SwarmRunResume<Payload: Sendable>: Sendable {
    public let interruptID: SwarmInterruptID
    public let payload: Payload

    public init(interruptID: SwarmInterruptID, payload: Payload) {
        self.interruptID = interruptID
        self.payload = payload
    }
}

@_spi(ColonyInternal) public struct SwarmInputContext: Sendable {
    public let runID: SwarmRunID
    public let stepIndex: Int

    public init(runID: SwarmRunID, stepIndex: Int) {
        self.runID = runID
        self.stepIndex = stepIndex
    }
}

@_spi(ColonyInternal) public struct SwarmAnyWrite<Schema: SwarmExecutionSchema>: Sendable {
    public let channelID: Schema.ChannelID
    private let valueProvider: @Sendable () -> any Sendable

    public init<Key: SwarmExecutionChannelKey>(_ key: Key, _ value: Key.Value)
    where Key.ID == Schema.ChannelID {
        channelID = key.swarmExecutionChannelID
        valueProvider = { value }
    }

    public func value() -> any Sendable {
        valueProvider()
    }
}

@_spi(ColonyInternal) public struct SwarmTaskLocalStore<Schema: SwarmExecutionSchema>: Sendable {
    public static var empty: SwarmTaskLocalStore<Schema> {
        SwarmTaskLocalStore(storage: [:])
    }

    private var storage: [Schema.ChannelID: any Sendable]

    public init(storage: [Schema.ChannelID: any Sendable]) {
        self.storage = storage
    }

    public mutating func set<Key: SwarmExecutionChannelKey>(_ key: Key, _ value: Key.Value) throws
    where Key.ID == Schema.ChannelID {
        storage[key.swarmExecutionChannelID] = value
    }

    public func get<Key: SwarmExecutionChannelKey>(_ key: Key) throws -> Key.Value
    where Key.ID == Schema.ChannelID {
        guard let value = storage[key.swarmExecutionChannelID] else {
            throw SwarmRuntimeError.executionChannelMissing(String(describing: key.swarmExecutionChannelID))
        }
        guard let typed = value as? Key.Value else {
            throw SwarmRuntimeError.executionChannelTypeMismatch(String(describing: key.swarmExecutionChannelID))
        }
        return typed
    }
}

@_spi(ColonyInternal) public struct SwarmStoreView<Schema: SwarmExecutionSchema>: Sendable {
    private let snapshot: Schema.Snapshot
    private let local: SwarmTaskLocalStore<Schema>?

    public init(snapshot: Schema.Snapshot, local: SwarmTaskLocalStore<Schema>? = nil) {
        self.snapshot = snapshot
        self.local = local
    }

    public func get<Key: SwarmExecutionChannelKey>(_ key: Key) throws -> Key.Value
    where Key.ID == Schema.ChannelID {
        if let local,
           Schema.localOnlyChannelIDs.contains(key.swarmExecutionChannelID)
        {
            return try local.get(key)
        }

        return try Schema.read(snapshot, channelID: key.swarmExecutionChannelID, as: Key.Value.self)
    }
}

@_spi(ColonyInternal) public struct SwarmTaskSeed<Schema: SwarmExecutionSchema>: Sendable {
    public let nodeID: SwarmNodeID
    public let local: SwarmTaskLocalStore<Schema>

    public init(nodeID: SwarmNodeID, local: SwarmTaskLocalStore<Schema>) {
        self.nodeID = nodeID
        self.local = local
    }
}

@_spi(ColonyInternal) public enum SwarmGraphNext: Sendable, Equatable {
    case end
    case to([SwarmNodeID])
}

@_spi(ColonyInternal) public struct SwarmInterruptRequest<Payload: Sendable>: Sendable {
    public let payload: Payload

    public init(payload: Payload) {
        self.payload = payload
    }
}

@_spi(ColonyInternal) public struct SwarmExecutionEnvironment: Sendable {
    public let clock: any SwarmClock
    public let logger: any SwarmLogger
    public let model: SwarmAnyModelClient?
    public let modelRouter: (any SwarmModelRouter)?
    public let inferenceHints: SwarmInferenceHints?
    public let tools: SwarmAnyToolRegistry?

    public init(
        clock: any SwarmClock,
        logger: any SwarmLogger,
        model: SwarmAnyModelClient?,
        modelRouter: (any SwarmModelRouter)?,
        inferenceHints: SwarmInferenceHints?,
        tools: SwarmAnyToolRegistry?
    ) {
        self.clock = clock
        self.logger = logger
        self.model = model
        self.modelRouter = modelRouter
        self.inferenceHints = inferenceHints
        self.tools = tools
    }
}

@_spi(ColonyInternal) public struct SwarmExecutionRun<Schema: SwarmExecutionSchema>: Sendable {
    public let runID: SwarmRunID
    public let attemptID: any Sendable
    public let threadID: SwarmThreadID
    public let taskID: SwarmTaskID
    public let stepIndex: Int
    public let resume: SwarmRunResume<Schema.ResumePayload>?

    public init(
        runID: SwarmRunID,
        attemptID: any Sendable,
        threadID: SwarmThreadID,
        taskID: SwarmTaskID,
        stepIndex: Int,
        resume: SwarmRunResume<Schema.ResumePayload>? = nil
    ) {
        self.runID = runID
        self.attemptID = attemptID
        self.threadID = threadID
        self.taskID = taskID
        self.stepIndex = stepIndex
        self.resume = resume
    }
}

@_spi(ColonyInternal) public struct SwarmGraphInput<Schema: SwarmExecutionSchema>: Sendable {
    public let store: SwarmStoreView<Schema>
    public let context: Schema.Context
    public let run: SwarmExecutionRun<Schema>
    public let environment: SwarmExecutionEnvironment
    private let streamEmitter: @Sendable (Schema.EventKind, [String: String]) -> Void

    public init(
        store: SwarmStoreView<Schema>,
        context: Schema.Context,
        run: SwarmExecutionRun<Schema>,
        environment: SwarmExecutionEnvironment,
        streamEmitter: @escaping @Sendable (Schema.EventKind, [String: String]) -> Void
    ) {
        self.store = store
        self.context = context
        self.run = run
        self.environment = environment
        self.streamEmitter = streamEmitter
    }

    public func emitStream(_ kind: Schema.EventKind, _ metadata: [String: String] = [:]) {
        streamEmitter(kind, metadata)
    }
}

@_spi(ColonyInternal) public struct SwarmGraphOutput<Schema: SwarmExecutionSchema>: Sendable {
    public let writes: [SwarmAnyWrite<Schema>]
    public let next: SwarmGraphNext
    public let interrupt: SwarmInterruptRequest<Schema.InterruptPayload>?
    public let spawn: [SwarmTaskSeed<Schema>]

    public init(
        writes: [SwarmAnyWrite<Schema>] = [],
        next: SwarmGraphNext = .end,
        interrupt: SwarmInterruptRequest<Schema.InterruptPayload>? = nil,
        spawn: [SwarmTaskSeed<Schema>] = []
    ) {
        self.writes = writes
        self.next = next
        self.interrupt = interrupt
        self.spawn = spawn
    }
}
