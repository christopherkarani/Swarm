#if SWARM_INTEGRATIONS
import Dispatch
import Foundation
import HiveCore

struct WorkflowDurableContext: Sendable {
    let workflow: Workflow
    let signature: String
}

enum WorkflowDurableInput: Sendable {
    case start(input: String, signature: String)
    case resume
}

struct WorkflowDurableSchema: HiveSchema {
    typealias Context = WorkflowDurableContext
    typealias Input = WorkflowDurableInput
    typealias InterruptPayload = String
    typealias ResumePayload = String

    static let currentInputSpec = HiveChannelSpec<Self, String>(
        id: HiveChannelID("workflow.currentInput"),
        scope: .global,
        reducer: .lastWriteWins(),
        updatePolicy: .single,
        initial: { "" },
        codec: HiveAnyCodec(WorkflowCheckpointCodec<String>()),
        persistence: .checkpointed
    )
    static let lastResultSpec = HiveChannelSpec<Self, WorkflowResultSnapshot?>(
        id: HiveChannelID("workflow.lastResult"),
        scope: .global,
        reducer: .lastWriteWins(),
        updatePolicy: .single,
        initial: { Optional<WorkflowResultSnapshot>.none },
        codec: HiveAnyCodec(WorkflowCheckpointCodec<WorkflowResultSnapshot?>()),
        persistence: .checkpointed
    )
    static let stepCursorSpec = HiveChannelSpec<Self, Int>(
        id: HiveChannelID("workflow.stepCursor"),
        scope: .global,
        reducer: .lastWriteWins(),
        updatePolicy: .single,
        initial: { 0 },
        codec: HiveAnyCodec(WorkflowCheckpointCodec<Int>()),
        persistence: .checkpointed
    )
    static let iterationCursorSpec = HiveChannelSpec<Self, Int>(
        id: HiveChannelID("workflow.iterationCursor"),
        scope: .global,
        reducer: .lastWriteWins(),
        updatePolicy: .single,
        initial: { 0 },
        codec: HiveAnyCodec(WorkflowCheckpointCodec<Int>()),
        persistence: .checkpointed
    )
    static let completedSpec = HiveChannelSpec<Self, Bool>(
        id: HiveChannelID("workflow.completed"),
        scope: .global,
        reducer: .lastWriteWins(),
        updatePolicy: .single,
        initial: { false },
        codec: HiveAnyCodec(WorkflowCheckpointCodec<Bool>()),
        persistence: .checkpointed
    )
    static let signatureSpec = HiveChannelSpec<Self, String>(
        id: HiveChannelID("workflow.signature"),
        scope: .global,
        reducer: .lastWriteWins(),
        updatePolicy: .single,
        initial: { "" },
        codec: HiveAnyCodec(WorkflowCheckpointCodec<String>()),
        persistence: .checkpointed
    )

    static let currentInputKey = currentInputSpec.key
    static let lastResultKey = lastResultSpec.key
    static let stepCursorKey = stepCursorSpec.key
    static let iterationCursorKey = iterationCursorSpec.key
    static let completedKey = completedSpec.key
    static let signatureKey = signatureSpec.key

    static var channelSpecs: [AnyHiveChannelSpec<Self>] {
        [
            AnyHiveChannelSpec(currentInputSpec),
            AnyHiveChannelSpec(lastResultSpec),
            AnyHiveChannelSpec(stepCursorSpec),
            AnyHiveChannelSpec(iterationCursorSpec),
            AnyHiveChannelSpec(completedSpec),
            AnyHiveChannelSpec(signatureSpec),
        ]
    }

    static func inputWrites(_ input: Input, inputContext _: HiveInputContext) throws -> [AnyHiveWrite<Self>] {
        switch input {
        case .start(let input, let signature):
            return [
                AnyHiveWrite(currentInputKey, input),
                AnyHiveWrite(lastResultKey, Optional<WorkflowResultSnapshot>.none),
                AnyHiveWrite(stepCursorKey, 0),
                AnyHiveWrite(iterationCursorKey, 0),
                AnyHiveWrite(completedKey, false),
                AnyHiveWrite(signatureKey, signature),
            ]

        case .resume:
            return []
        }
    }
}

struct WorkflowDurableEngine: Sendable {
    let workflow: Workflow
    let checkpointing: WorkflowCheckpointing
    let checkpointID: String
    let policy: Workflow.Durable.CheckpointPolicy
    let resume: Bool

    func run(startInput: String) async throws -> AgentResult {
        if let controller = WorkflowDurableFaultInjection.controller {
            await controller.beginAttempt()
        }
        let graph = try makeGraph()
        let context = WorkflowDurableContext(
            workflow: workflow,
            signature: workflow.workflowSignature
        )

        let environment = HiveEnvironment<WorkflowDurableSchema>(
            context: context,
            clock: WorkflowDurableClock(),
            logger: WorkflowDurableLogger(),
            checkpointStore: faultInjectingStore(wrapping: checkpointing.runtimeStore)
        )

        let runtime = try HiveRuntime(graph: graph, environment: environment)
        let threadID = HiveThreadID(checkpointID)

        if resume {
            guard try await checkpointing.containsCheckpoint(for: checkpointID) else {
                throw WorkflowError.checkpointNotFound(id: checkpointID)
            }
        }

        let input: WorkflowDurableInput = resume ? .resume : .start(
            input: startInput,
            signature: workflow.workflowSignature
        )
        let handle = await runtime.run(
            threadID: threadID,
            input: input,
            options: runOptions(for: policy)
        )

        let outcome = try await handle.outcome.value
        let result = try extractResult(from: outcome)

        if policy == .onCompletion {
            let flushHandle = await runtime.applyExternalWrites(
                threadID: threadID,
                writes: [],
                options: HiveRunOptions(maxSteps: 1, checkpointPolicy: .everyStep)
            )
            _ = try await flushHandle.outcome.value
        }

        return result
    }

    private func faultInjectingStore(
        wrapping store: AnyHiveCheckpointStore<WorkflowDurableSchema>
    ) -> AnyHiveCheckpointStore<WorkflowDurableSchema> {
        guard WorkflowDurableFaultInjection.controller != nil else {
            return store
        }
        return AnyHiveCheckpointStore(WorkflowFaultInjectingCheckpointStore(inner: store))
    }

    private func makeGraph() throws -> CompiledHiveGraph<WorkflowDurableSchema> {
        var builder = HiveGraphBuilder<WorkflowDurableSchema>(start: [WorkflowNodeID.execute])
        builder.addNode(WorkflowNodeID.execute, workflowNode)
        builder.addRouter(from: WorkflowNodeID.execute) { store in
            let completed = (try? store.get(WorkflowDurableSchema.completedKey)) ?? false
            return completed ? .end : .to([WorkflowNodeID.execute])
        }
        return try builder.compile()
    }

    private func runOptions(for policy: Workflow.Durable.CheckpointPolicy) -> HiveRunOptions {
        let checkpointPolicy: HiveCheckpointPolicy = switch policy {
        case .everyStep: .everyStep
        case .onCompletion: .disabled
        }

        return HiveRunOptions(
            maxSteps: maxStepBudget(),
            maxConcurrentTasks: 1,
            checkpointPolicy: checkpointPolicy,
            deterministicStreamBuffering: true
        )
    }

    private func maxStepBudget() -> Int {
        let baseSteps = max(1, workflow.steps.count)

        if workflow.repeatCondition != nil {
            let loopSpan = baseSteps + 1
            let bounded = max(1, workflow.maxRepeatIterations)
            if loopSpan > (Int.max - 4) / bounded {
                return Int.max - 1
            }
            return (loopSpan * bounded) + 4
        }

        return baseSteps + 4
    }

    private func extractResult(from outcome: HiveRunOutcome<WorkflowDurableSchema>) throws -> AgentResult {
        switch outcome {
        case .finished(let output, _):
            return try extractResult(from: output)
        case .cancelled(let output, _):
            return try extractResult(from: output)
        case .outOfSteps:
            throw WorkflowError.invalidWorkflow(reason: "Workflow exceeded execution budget")
        case .interrupted:
            throw WorkflowError.invalidWorkflow(reason: "Workflow runtime interrupted unexpectedly")
        }
    }

    private func extractResult(from output: HiveRunOutput<WorkflowDurableSchema>) throws -> AgentResult {
        switch output {
        case .fullStore(let store):
            if let snapshot = try store.get(WorkflowDurableSchema.lastResultKey) {
                return snapshot.agentResult
            }
            let currentInput = try store.get(WorkflowDurableSchema.currentInputKey)
            return AgentResult(output: currentInput)

        case .channels(let projection):
            if let snapshot = try projection.get(WorkflowDurableSchema.lastResultKey) {
                return snapshot.agentResult
            }
            return AgentResult(output: try projection.get(WorkflowDurableSchema.currentInputKey))
        }
    }
}

private enum WorkflowNodeID {
    static let execute = HiveNodeID("workflow.execute")
}

private func workflowNode(_ input: HiveNodeInput<WorkflowDurableSchema>) async throws -> HiveNodeOutput<WorkflowDurableSchema> {
    let checkpointSignature = try input.store.get(WorkflowDurableSchema.signatureKey)
    if let mismatch = workflowDurableSignatureMismatch(
        checkpointSignature: checkpointSignature,
        currentSignature: input.context.signature
    ) {
        throw mismatch
    }

    let completed = try input.store.get(WorkflowDurableSchema.completedKey)
    if completed {
        return HiveNodeOutput(next: .end)
    }

    let currentInput = try input.store.get(WorkflowDurableSchema.currentInputKey)
    let lastResultSnapshot = try input.store.get(WorkflowDurableSchema.lastResultKey)
    var stepCursor = try input.store.get(WorkflowDurableSchema.stepCursorKey)
    var iterationCursor = try input.store.get(WorkflowDurableSchema.iterationCursorKey)

    if stepCursor >= input.context.workflow.steps.count {
        if let repeatCondition = input.context.workflow.repeatCondition {
            let lastResult = lastResultSnapshot?.agentResult ?? AgentResult(output: currentInput)
            if repeatCondition(lastResult) {
                return HiveNodeOutput(
                    writes: [AnyHiveWrite(WorkflowDurableSchema.completedKey, true)],
                    next: .end
                )
            }

            let nextIteration = iterationCursor + 1
            if nextIteration >= input.context.workflow.maxRepeatIterations {
                return HiveNodeOutput(
                    writes: [AnyHiveWrite(WorkflowDurableSchema.completedKey, true)],
                    next: .end
                )
            }

            stepCursor = 0
            iterationCursor = nextIteration

            return HiveNodeOutput(
                writes: [
                    AnyHiveWrite(WorkflowDurableSchema.stepCursorKey, stepCursor),
                    AnyHiveWrite(WorkflowDurableSchema.iterationCursorKey, iterationCursor),
                    AnyHiveWrite(WorkflowDurableSchema.currentInputKey, lastResult.output),
                ]
            )
        }

        return HiveNodeOutput(
            writes: [AnyHiveWrite(WorkflowDurableSchema.completedKey, true)],
            next: .end
        )
    }

    let step = input.context.workflow.steps[stepCursor]
    if let controller = WorkflowDurableFaultInjection.controller {
        await controller.markWorkflowStepStarted()
    }
    let result = try await input.context.workflow.execute(step: step, withInput: currentInput)
    let snapshot = WorkflowResultSnapshot(result)

    return HiveNodeOutput(
        writes: [
            AnyHiveWrite(WorkflowDurableSchema.lastResultKey, Optional(snapshot)),
            AnyHiveWrite(WorkflowDurableSchema.currentInputKey, result.output),
            AnyHiveWrite(WorkflowDurableSchema.stepCursorKey, stepCursor + 1),
        ]
    )
}

private struct WorkflowDurableClock: HiveClock {
    func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

private struct WorkflowDurableLogger: HiveLogger {
    func debug(_ message: String, metadata: [String: String]) {}
    func info(_ message: String, metadata: [String: String]) {}
    func error(_ message: String, metadata: [String: String]) {}
}

enum WorkflowDurableFaultPoint: Sendable, Equatable {
    case beforeCheckpointWrite
    case afterCheckpointWrite
    case midStep
}

struct WorkflowDurableInjectedFault: Error, Sendable, Equatable {
    let point: WorkflowDurableFaultPoint
}

enum WorkflowDurableFaultInjection {
    @TaskLocal static var controller: WorkflowDurableFaultController?
}

actor WorkflowDurableFaultController {
    private var queue: [WorkflowDurableFaultPoint]
    private(set) var injected: [WorkflowDurableFaultPoint] = []
    private var workflowStepStarted = false
    private var injectedThisAttempt = false

    init(queue: [WorkflowDurableFaultPoint]) {
        self.queue = queue
    }

    func beginAttempt() {
        workflowStepStarted = false
        injectedThisAttempt = false
    }

    func markWorkflowStepStarted() {
        workflowStepStarted = true
    }

    func consumeMidStep() throws {
        try consume(.midStep, requireWorkflowStep: false)
    }

    func consumeBeforeWrite() throws {
        try consume(.beforeCheckpointWrite, requireWorkflowStep: true)
    }

    func consumeAfterWrite() throws {
        try consume(.afterCheckpointWrite, requireWorkflowStep: true)
    }

    private func consume(_ point: WorkflowDurableFaultPoint, requireWorkflowStep: Bool) throws {
        guard !injectedThisAttempt, queue.first == point else { return }
        if requireWorkflowStep, !workflowStepStarted { return }
        queue.removeFirst()
        injected.append(point)
        injectedThisAttempt = true
        throw WorkflowDurableInjectedFault(point: point)
    }
}

actor WorkflowFaultInjectingCheckpointStore: HiveCheckpointStore {
    typealias Schema = WorkflowDurableSchema

    private let inner: AnyHiveCheckpointStore<WorkflowDurableSchema>

    init(inner: AnyHiveCheckpointStore<WorkflowDurableSchema>) {
        self.inner = inner
    }

    func save(_ checkpoint: HiveCheckpoint<WorkflowDurableSchema>) async throws {
        if let controller = WorkflowDurableFaultInjection.controller {
            try await controller.consumeBeforeWrite()
        }
        try await inner.save(checkpoint)
        if let controller = WorkflowDurableFaultInjection.controller {
            try await controller.consumeAfterWrite()
        }
    }

    func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<WorkflowDurableSchema>? {
        try await inner.loadLatest(threadID: threadID)
    }
}
#endif
