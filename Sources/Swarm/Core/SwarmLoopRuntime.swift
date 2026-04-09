import Foundation

@_spi(ColonyInternal) public struct SwarmLoopRuntimeConfiguration<
    Schema: SwarmExecutionSchema,
    ThreadID: Sendable,
    RunID: Sendable,
    AttemptID: Sendable,
    InterruptID: Sendable & Equatable,
    CheckpointID: Sendable,
    Checkpoint: Sendable,
    Options: Sendable,
    Outcome: Sendable
>: Sendable {
    public typealias Emit = @Sendable (Schema.EventKind, [String: String], Int?, Int?) async -> Void
    public typealias StreamEmit = @Sendable (Schema.EventKind, [String: String], Int?, Int?) -> Void
    public typealias Apply = @Sendable (
        [SwarmAnyWrite<Schema>],
        inout Schema.Snapshot,
        @escaping @Sendable (Schema.EventKind) async -> Void
    ) throws -> Void
    public typealias ToolExecute = @Sendable (
        SwarmTaskSeed<Schema>,
        Schema.Snapshot,
        SwarmExecutionRun<Schema>,
        Int,
        @escaping StreamEmit
    ) async throws -> [SwarmAnyWrite<Schema>]

    public let threadID: ThreadID
    public let context: Schema.Context
    public let environment: SwarmExecutionEnvironment
    public let emptySnapshot: @Sendable () -> Schema.Snapshot
    public let loadCheckpointByInterruptID: @Sendable (ThreadID, InterruptID) async throws -> Checkpoint?
    public let saveCheckpoint: @Sendable (Checkpoint) async throws -> Void
    public let checkpointRunID: @Sendable (Checkpoint) -> RunID
    public let checkpointStepIndex: @Sendable (Checkpoint) -> Int
    public let checkpointSnapshot: @Sendable (Checkpoint) -> Schema.Snapshot
    public let checkpointID: @Sendable (Checkpoint) -> CheckpointID
    public let makeCheckpoint: @Sendable (ThreadID, RunID, AttemptID, Int, Schema.Snapshot) -> Checkpoint
    public let makeInterruptedCheckpoint: @Sendable (ThreadID, RunID, AttemptID, Int, InterruptID, Schema.Snapshot) -> Checkpoint
    public let makeInterruptID: @Sendable () -> InterruptID
    public let noInterruptToResumeError: @Sendable () -> Error
    public let resumeMismatchError: @Sendable (InterruptID, InterruptID) -> Error
    public let swarmRunID: @Sendable (RunID) -> SwarmRunID
    public let swarmThreadID: @Sendable (ThreadID) -> SwarmThreadID
    public let inputWrites: @Sendable (String, SwarmInputContext) throws -> [SwarmAnyWrite<Schema>]
    public let makeTaskID: @Sendable (SwarmRunID, Int, Int?) -> SwarmTaskID
    public let makeRunContext: @Sendable (SwarmRunID, AttemptID, SwarmThreadID, SwarmTaskID, Int, SwarmRunResume<Schema.ResumePayload>?) -> SwarmExecutionRun<Schema>
    public let makeGraphInput: @Sendable (Schema.Snapshot, SwarmExecutionRun<Schema>, SwarmTaskLocalStore<Schema>?, @escaping StreamEmit) -> SwarmGraphInput<Schema>
    public let preModel: @Sendable (SwarmGraphInput<Schema>) async throws -> SwarmGraphOutput<Schema>
    public let model: @Sendable (SwarmGraphInput<Schema>) async throws -> SwarmGraphOutput<Schema>
    public let shouldEndAfterModel: @Sendable (Schema.Snapshot) -> Bool
    public let hasPendingToolCalls: @Sendable (Schema.Snapshot) -> Bool
    public let tools: @Sendable (SwarmGraphInput<Schema>) async throws -> SwarmGraphOutput<Schema>
    public let toolExecute: ToolExecute
    public let applyWrites: Apply
    public let maxSteps: @Sendable (Options) -> Int
    public let maxConcurrentTasks: @Sendable (Options) -> Int
    public let shouldCheckpoint: @Sendable (Options, Int, Bool) -> Bool
    public let resumeInterruptID: @Sendable (SwarmRunResume<Schema.ResumePayload>) -> InterruptID
    public let runStartedEvent: @Sendable (ThreadID) -> Schema.EventKind
    public let runResumedEvent: @Sendable (InterruptID) -> Schema.EventKind
    public let stepStartedEvent: @Sendable (Int, Int) -> Schema.EventKind
    public let stepFinishedEvent: @Sendable (Int, Int) -> Schema.EventKind
    public let checkpointSavedEvent: @Sendable (CheckpointID) -> Schema.EventKind
    public let runInterruptedEvent: @Sendable (InterruptID) -> Schema.EventKind
    public let runFinishedEvent: @Sendable () -> Schema.EventKind
    public let taskStartedEvent: @Sendable (String, String) -> Schema.EventKind
    public let taskFinishedEvent: @Sendable (String, String) -> Schema.EventKind
    public let finishedOutcome: @Sendable (Schema.Snapshot, CheckpointID?) -> Outcome
    public let interruptedOutcome: @Sendable (InterruptID, Schema.InterruptPayload, CheckpointID) -> Outcome
    public let outOfStepsOutcome: @Sendable (Int, Schema.Snapshot, CheckpointID?) -> Outcome

    public init(
        threadID: ThreadID,
        context: Schema.Context,
        environment: SwarmExecutionEnvironment,
        emptySnapshot: @escaping @Sendable () -> Schema.Snapshot,
        loadCheckpointByInterruptID: @escaping @Sendable (ThreadID, InterruptID) async throws -> Checkpoint?,
        saveCheckpoint: @escaping @Sendable (Checkpoint) async throws -> Void,
        checkpointRunID: @escaping @Sendable (Checkpoint) -> RunID,
        checkpointStepIndex: @escaping @Sendable (Checkpoint) -> Int,
        checkpointSnapshot: @escaping @Sendable (Checkpoint) -> Schema.Snapshot,
        checkpointID: @escaping @Sendable (Checkpoint) -> CheckpointID,
        makeCheckpoint: @escaping @Sendable (ThreadID, RunID, AttemptID, Int, Schema.Snapshot) -> Checkpoint,
        makeInterruptedCheckpoint: @escaping @Sendable (ThreadID, RunID, AttemptID, Int, InterruptID, Schema.Snapshot) -> Checkpoint,
        makeInterruptID: @escaping @Sendable () -> InterruptID,
        noInterruptToResumeError: @escaping @Sendable () -> Error,
        resumeMismatchError: @escaping @Sendable (InterruptID, InterruptID) -> Error,
        swarmRunID: @escaping @Sendable (RunID) -> SwarmRunID,
        swarmThreadID: @escaping @Sendable (ThreadID) -> SwarmThreadID,
        inputWrites: @escaping @Sendable (String, SwarmInputContext) throws -> [SwarmAnyWrite<Schema>],
        makeTaskID: @escaping @Sendable (SwarmRunID, Int, Int?) -> SwarmTaskID,
        makeRunContext: @escaping @Sendable (SwarmRunID, AttemptID, SwarmThreadID, SwarmTaskID, Int, SwarmRunResume<Schema.ResumePayload>?) -> SwarmExecutionRun<Schema>,
        makeGraphInput: @escaping @Sendable (Schema.Snapshot, SwarmExecutionRun<Schema>, SwarmTaskLocalStore<Schema>?, @escaping StreamEmit) -> SwarmGraphInput<Schema>,
        preModel: @escaping @Sendable (SwarmGraphInput<Schema>) async throws -> SwarmGraphOutput<Schema>,
        model: @escaping @Sendable (SwarmGraphInput<Schema>) async throws -> SwarmGraphOutput<Schema>,
        shouldEndAfterModel: @escaping @Sendable (Schema.Snapshot) -> Bool,
        hasPendingToolCalls: @escaping @Sendable (Schema.Snapshot) -> Bool,
        tools: @escaping @Sendable (SwarmGraphInput<Schema>) async throws -> SwarmGraphOutput<Schema>,
        toolExecute: @escaping ToolExecute,
        applyWrites: @escaping Apply,
        maxSteps: @escaping @Sendable (Options) -> Int,
        maxConcurrentTasks: @escaping @Sendable (Options) -> Int,
        shouldCheckpoint: @escaping @Sendable (Options, Int, Bool) -> Bool,
        resumeInterruptID: @escaping @Sendable (SwarmRunResume<Schema.ResumePayload>) -> InterruptID,
        runStartedEvent: @escaping @Sendable (ThreadID) -> Schema.EventKind,
        runResumedEvent: @escaping @Sendable (InterruptID) -> Schema.EventKind,
        stepStartedEvent: @escaping @Sendable (Int, Int) -> Schema.EventKind,
        stepFinishedEvent: @escaping @Sendable (Int, Int) -> Schema.EventKind,
        checkpointSavedEvent: @escaping @Sendable (CheckpointID) -> Schema.EventKind,
        runInterruptedEvent: @escaping @Sendable (InterruptID) -> Schema.EventKind,
        runFinishedEvent: @escaping @Sendable () -> Schema.EventKind,
        taskStartedEvent: @escaping @Sendable (String, String) -> Schema.EventKind,
        taskFinishedEvent: @escaping @Sendable (String, String) -> Schema.EventKind,
        finishedOutcome: @escaping @Sendable (Schema.Snapshot, CheckpointID?) -> Outcome,
        interruptedOutcome: @escaping @Sendable (InterruptID, Schema.InterruptPayload, CheckpointID) -> Outcome,
        outOfStepsOutcome: @escaping @Sendable (Int, Schema.Snapshot, CheckpointID?) -> Outcome
    ) {
        self.threadID = threadID
        self.context = context
        self.environment = environment
        self.emptySnapshot = emptySnapshot
        self.loadCheckpointByInterruptID = loadCheckpointByInterruptID
        self.saveCheckpoint = saveCheckpoint
        self.checkpointRunID = checkpointRunID
        self.checkpointStepIndex = checkpointStepIndex
        self.checkpointSnapshot = checkpointSnapshot
        self.checkpointID = checkpointID
        self.makeCheckpoint = makeCheckpoint
        self.makeInterruptedCheckpoint = makeInterruptedCheckpoint
        self.makeInterruptID = makeInterruptID
        self.noInterruptToResumeError = noInterruptToResumeError
        self.resumeMismatchError = resumeMismatchError
        self.swarmRunID = swarmRunID
        self.swarmThreadID = swarmThreadID
        self.inputWrites = inputWrites
        self.makeTaskID = makeTaskID
        self.makeRunContext = makeRunContext
        self.makeGraphInput = makeGraphInput
        self.preModel = preModel
        self.model = model
        self.shouldEndAfterModel = shouldEndAfterModel
        self.hasPendingToolCalls = hasPendingToolCalls
        self.tools = tools
        self.toolExecute = toolExecute
        self.applyWrites = applyWrites
        self.maxSteps = maxSteps
        self.maxConcurrentTasks = maxConcurrentTasks
        self.shouldCheckpoint = shouldCheckpoint
        self.resumeInterruptID = resumeInterruptID
        self.runStartedEvent = runStartedEvent
        self.runResumedEvent = runResumedEvent
        self.stepStartedEvent = stepStartedEvent
        self.stepFinishedEvent = stepFinishedEvent
        self.checkpointSavedEvent = checkpointSavedEvent
        self.runInterruptedEvent = runInterruptedEvent
        self.runFinishedEvent = runFinishedEvent
        self.taskStartedEvent = taskStartedEvent
        self.taskFinishedEvent = taskFinishedEvent
        self.finishedOutcome = finishedOutcome
        self.interruptedOutcome = interruptedOutcome
        self.outOfStepsOutcome = outOfStepsOutcome
    }
}

@_spi(ColonyInternal) public actor SwarmLoopRuntime<
    Schema: SwarmExecutionSchema,
    ThreadID: Sendable,
    RunID: Sendable,
    AttemptID: Sendable,
    InterruptID: Sendable & Equatable,
    CheckpointID: Sendable,
    Checkpoint: Sendable,
    Options: Sendable,
    Outcome: Sendable
> {
    public typealias Config = SwarmLoopRuntimeConfiguration<
        Schema,
        ThreadID,
        RunID,
        AttemptID,
        InterruptID,
        CheckpointID,
        Checkpoint,
        Options,
        Outcome
    >

    private let config: Config
    private var latestSnapshot: Schema.Snapshot
    private var pendingInterruptID: InterruptID?

    public init(configuration: Config) {
        config = configuration
        latestSnapshot = configuration.emptySnapshot()
    }

    public func currentSnapshot() -> Schema.Snapshot {
        latestSnapshot
    }

    public func takeResumeCheckpoint(interruptID: InterruptID) async throws -> Checkpoint {
        guard let currentPendingInterruptID = pendingInterruptID else {
            throw config.noInterruptToResumeError()
        }
        guard currentPendingInterruptID == interruptID else {
            throw config.resumeMismatchError(currentPendingInterruptID, interruptID)
        }
        guard let checkpoint = try await config.loadCheckpointByInterruptID(config.threadID, interruptID) else {
            throw config.noInterruptToResumeError()
        }
        pendingInterruptID = nil
        return checkpoint
    }

    public func execute(
        runID externalRunID: RunID,
        attemptID: AttemptID,
        initialInput: String?,
        resume: SwarmRunResume<Schema.ResumePayload>?,
        startingSnapshot: Schema.Snapshot,
        startingStepIndex: Int,
        emit: @escaping Config.Emit,
        streamEmit: @escaping Config.StreamEmit,
        options: Options
    ) async throws -> Outcome {
        var snapshot = startingSnapshot
        var stepIndex = startingStepIndex
        var resumePayload = resume
        let runID = config.swarmRunID(externalRunID)
        let threadID = config.swarmThreadID(config.threadID)

        await emit(config.runStartedEvent(config.threadID), [:], nil, nil)
        if let resume {
            await emit(
                config.runResumedEvent(config.resumeInterruptID(resume)),
                [:],
                nil,
                nil
            )
        }

        if let initialInput {
            let writes = try config.inputWrites(
                initialInput,
                SwarmInputContext(runID: runID, stepIndex: stepIndex)
            )
            try await apply(writes: writes, to: &snapshot, emit: emit, stepIndex: nil, taskOrdinal: nil)
        }

        while stepIndex < config.maxSteps(options) {
            try Task.checkCancellation()
            await emit(config.stepStartedEvent(stepIndex, 1), [:], stepIndex, nil)

            let mainTaskID = config.makeTaskID(runID, stepIndex, nil)
            let runContext = config.makeRunContext(
                runID,
                attemptID,
                threadID,
                mainTaskID,
                stepIndex,
                resumePayload
            )

            let isResumingPendingToolDecision = resumePayload != nil && config.hasPendingToolCalls(snapshot)

            if isResumingPendingToolDecision == false {
                let preModelOutput = try await config.preModel(
                    config.makeGraphInput(snapshot, runContext, nil, streamEmit)
                )
                try await apply(writes: preModelOutput.writes, to: &snapshot, emit: emit, stepIndex: stepIndex, taskOrdinal: nil)

                let modelOutput = try await config.model(
                    config.makeGraphInput(snapshot, runContext, nil, streamEmit)
                )
                try await apply(writes: modelOutput.writes, to: &snapshot, emit: emit, stepIndex: stepIndex, taskOrdinal: nil)

                if config.shouldEndAfterModel(snapshot) {
                    let checkpointID = try await maybeCheckpoint(
                        snapshot: snapshot,
                        runID: externalRunID,
                        attemptID: attemptID,
                        stepIndex: stepIndex,
                        options: options,
                        interrupted: false,
                        emit: emit
                    )
                    await emit(config.runFinishedEvent(), [:], nil, nil)
                    await emit(config.stepFinishedEvent(stepIndex, 0), [:], stepIndex, nil)
                    latestSnapshot = snapshot
                    return config.finishedOutcome(snapshot, checkpointID)
                }
            }

            let toolsOutput = try await config.tools(
                config.makeGraphInput(snapshot, runContext, nil, streamEmit)
            )
            try await apply(writes: toolsOutput.writes, to: &snapshot, emit: emit, stepIndex: stepIndex, taskOrdinal: nil)

            if let interrupt = toolsOutput.interrupt {
                let interruptID = config.makeInterruptID()
                let checkpoint = config.makeInterruptedCheckpoint(
                    config.threadID,
                    externalRunID,
                    attemptID,
                    stepIndex,
                    interruptID,
                    snapshot
                )
                try await config.saveCheckpoint(checkpoint)
                latestSnapshot = snapshot
                pendingInterruptID = interruptID
                let checkpointID = config.checkpointID(checkpoint)
                await emit(config.checkpointSavedEvent(checkpointID), [:], stepIndex, nil)
                await emit(config.runInterruptedEvent(interruptID), [:], stepIndex, nil)
                await emit(config.stepFinishedEvent(stepIndex, 0), [:], stepIndex, nil)
                return config.interruptedOutcome(interruptID, interrupt.payload, checkpointID)
            }

            let taskResults = try await executeSpawnedTasks(
                toolsOutput.spawn,
                snapshot: snapshot,
                runID: runID,
                attemptID: attemptID,
                stepIndex: stepIndex,
                emit: emit,
                streamEmit: streamEmit,
                maxConcurrentTasks: config.maxConcurrentTasks(options)
            )
            for taskResult in taskResults {
                try await apply(writes: taskResult.writes, to: &snapshot, emit: emit, stepIndex: stepIndex, taskOrdinal: taskResult.ordinal)
                await emit(
                    config.taskFinishedEvent(taskResult.nodeID.rawValue, taskResult.taskID.rawValue),
                    [:],
                    stepIndex,
                    taskResult.ordinal
                )
            }

            resumePayload = nil
            _ = try await maybeCheckpoint(
                snapshot: snapshot,
                runID: externalRunID,
                attemptID: attemptID,
                stepIndex: stepIndex,
                options: options,
                interrupted: false,
                emit: emit
            )
            await emit(config.stepFinishedEvent(stepIndex, 1), [:], stepIndex, nil)
            stepIndex += 1
        }

        let checkpointID = try await maybeCheckpoint(
            snapshot: snapshot,
            runID: externalRunID,
            attemptID: attemptID,
            stepIndex: stepIndex,
            options: options,
            interrupted: false,
            emit: emit
        )
        latestSnapshot = snapshot
        return config.outOfStepsOutcome(config.maxSteps(options), snapshot, checkpointID)
    }

    private func executeSpawnedTasks(
        _ seeds: [SwarmTaskSeed<Schema>],
        snapshot: Schema.Snapshot,
        runID: SwarmRunID,
        attemptID: AttemptID,
        stepIndex: Int,
        emit: @escaping Config.Emit,
        streamEmit: @escaping Config.StreamEmit,
        maxConcurrentTasks: Int
    ) async throws -> [CompletedTask<Schema>] {
        guard seeds.isEmpty == false else { return [] }

        let concurrencyLimit = max(1, maxConcurrentTasks)
        var scheduled = 0
        var nextOrdinal = 0
        var results: [CompletedTask<Schema>] = []
        results.reserveCapacity(seeds.count)
        let config = self.config
        let threadID = config.swarmThreadID(config.threadID)
        let makeTaskID = config.makeTaskID
        let makeRunContext = config.makeRunContext
        let taskStartedEvent = config.taskStartedEvent
        let taskExecutor = SpawnedTaskExecutor(toolExecute: config.toolExecute)

        return try await withThrowingTaskGroup(of: CompletedTask<Schema>.self) { group in
            func schedule(_ ordinal: Int, seed: SwarmTaskSeed<Schema>) async {
                let taskID = makeTaskID(runID, stepIndex, ordinal)
                await emit(
                    taskStartedEvent(seed.nodeID.rawValue, taskID.rawValue),
                    [:],
                    stepIndex,
                    ordinal
                )
                let taskRun = makeRunContext(
                    runID,
                    attemptID,
                    threadID,
                    taskID,
                    stepIndex,
                    nil
                )

                group.addTask {
                    try await taskExecutor.run(
                        seed: seed,
                        snapshot: snapshot,
                        taskRun: taskRun,
                        ordinal: ordinal,
                        streamEmit: streamEmit,
                        taskID: taskID
                    )
                }
            }

            while nextOrdinal < seeds.count && scheduled < concurrencyLimit {
                await schedule(nextOrdinal, seed: seeds[nextOrdinal])
                nextOrdinal += 1
                scheduled += 1
            }

            while let completed = try await group.next() {
                results.append(completed)
                scheduled -= 1

                if nextOrdinal < seeds.count {
                    await schedule(nextOrdinal, seed: seeds[nextOrdinal])
                    nextOrdinal += 1
                    scheduled += 1
                }
            }

            return results.sorted { $0.ordinal < $1.ordinal }
        }
    }

    private func apply(
        writes: [SwarmAnyWrite<Schema>],
        to snapshot: inout Schema.Snapshot,
        emit: @escaping Config.Emit,
        stepIndex: Int?,
        taskOrdinal: Int?
    ) async throws {
        try config.applyWrites(writes, &snapshot) { kind in
            await emit(kind, [:], stepIndex, taskOrdinal)
        }
    }

    private func maybeCheckpoint(
        snapshot: Schema.Snapshot,
        runID: RunID,
        attemptID: AttemptID,
        stepIndex: Int,
        options: Options,
        interrupted: Bool,
        emit: @escaping Config.Emit
    ) async throws -> CheckpointID? {
        guard config.shouldCheckpoint(options, stepIndex, interrupted) else {
            return nil
        }

        let checkpoint = config.makeCheckpoint(
            config.threadID,
            runID,
            attemptID,
            stepIndex,
            snapshot
        )
        try await config.saveCheckpoint(checkpoint)
        let checkpointID = config.checkpointID(checkpoint)
        await emit(config.checkpointSavedEvent(checkpointID), [:], stepIndex, nil)
        return checkpointID
    }

}

private struct SpawnedTaskExecutor<Schema: SwarmExecutionSchema>: Sendable {
    typealias ToolExecute = @Sendable (
        SwarmTaskSeed<Schema>,
        Schema.Snapshot,
        SwarmExecutionRun<Schema>,
        Int,
        @escaping SwarmLoopRuntimeConfiguration<Schema, Void, Void, Void, SwarmInterruptID, Void, Void, Void, Void>.StreamEmit
    ) async throws -> [SwarmAnyWrite<Schema>]

    let toolExecute: ToolExecute

    func run(
        seed: SwarmTaskSeed<Schema>,
        snapshot: Schema.Snapshot,
        taskRun: SwarmExecutionRun<Schema>,
        ordinal: Int,
        streamEmit: @escaping SwarmLoopRuntimeConfiguration<Schema, Void, Void, Void, SwarmInterruptID, Void, Void, Void, Void>.StreamEmit,
        taskID: SwarmTaskID
    ) async throws -> CompletedTask<Schema> {
        let writes = try await toolExecute(
            seed,
            snapshot,
            taskRun,
            ordinal,
            streamEmit
        )
        return CompletedTask(
            ordinal: ordinal,
            nodeID: seed.nodeID,
            taskID: taskID,
            writes: writes
        )
    }
}

private struct CompletedTask<Schema: SwarmExecutionSchema>: Sendable {
    let ordinal: Int
    let nodeID: SwarmNodeID
    let taskID: SwarmTaskID
    let writes: [SwarmAnyWrite<Schema>]
}
