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

/// Closed run-state phase for durable workflows.
///
/// The phase is the single checkpointed carrier of workflow progress: either the
/// run is mid-flight (`running`, with its cursors and most recent step result) or
/// it has terminated (`completed`, carrying the final result). Because the
/// cursors live inside `running`'s payload, a completed run can never coexist
/// with pending cursor state — the illegal combination is unrepresentable by
/// construction rather than guarded at runtime.
///
/// Note: `lastResult` rides inside `running` (instead of a parallel result
/// channel) because completion and repeat-boundary evaluation happen in later
/// supersteps than the last step write; the snapshot must survive the store
/// round-trip so resumed runs return and evaluate the full ``AgentResult``.
///
/// Cursor *values* cannot be forbidden structurally (`Int` associated values),
/// so the non-negative invariant is enforced once at the domain-read boundary
/// in ``workflowNode(_:)-swift.func``, where every resume — migrated legacy or
/// native — crosses back into engine logic.
enum WorkflowDurablePhase: Codable, Sendable, Equatable {
    /// The run is still executing. `stepCursor` indexes the next step to run;
    /// `iterationCursor` counts completed passes of a repeating workflow;
    /// `lastResult` is the most recent step result, or nil before the first
    /// step commits.
    case running(stepCursor: Int, iterationCursor: Int, lastResult: WorkflowResultSnapshot?)
    /// The run has finished. Carries the workflow's final result.
    case completed(WorkflowResultSnapshot)
}

struct WorkflowDurableSchema: HiveSchema {
    typealias Context = WorkflowDurableContext
    typealias Input = WorkflowDurableInput
    typealias InterruptPayload = String
    typealias ResumePayload = String

    static let currentInputKey = HiveChannelKey<Self, String>(HiveChannelID("workflow.currentInput"))
    static let signatureKey = HiveChannelKey<Self, String>(HiveChannelID("workflow.signature"))
    static let phaseKey = HiveChannelKey<Self, WorkflowDurablePhase>(HiveChannelID("workflow.phase"))

    static var channelSpecs: [AnyHiveChannelSpec<Self>] {
        [
            AnyHiveChannelSpec(
                HiveChannelSpec(
                    key: currentInputKey,
                    scope: .global,
                    reducer: .lastWriteWins(),
                    updatePolicy: .single,
                    initial: { "" },
                    codec: HiveAnyCodec(WorkflowCheckpointCodec<String>()),
                    persistence: .checkpointed
                )
            ),
            AnyHiveChannelSpec(
                HiveChannelSpec(
                    key: signatureKey,
                    scope: .global,
                    reducer: .lastWriteWins(),
                    updatePolicy: .single,
                    initial: { "" },
                    codec: HiveAnyCodec(WorkflowCheckpointCodec<String>()),
                    persistence: .checkpointed
                )
            ),
            AnyHiveChannelSpec(
                HiveChannelSpec(
                    key: phaseKey,
                    scope: .global,
                    reducer: .lastWriteWins(),
                    updatePolicy: .single,
                    initial: { WorkflowDurablePhase.running(stepCursor: 0, iterationCursor: 0, lastResult: nil) },
                    codec: HiveAnyCodec(WorkflowCheckpointCodec<WorkflowDurablePhase>()),
                    persistence: .checkpointed
                )
            ),
        ]
    }

    static func inputWrites(_ input: Input, inputContext _: HiveInputContext) throws -> [AnyHiveWrite<Self>] {
        switch input {
        case .start(let input, let signature):
            return [
                AnyHiveWrite(currentInputKey, input),
                AnyHiveWrite(signatureKey, signature),
                AnyHiveWrite(phaseKey, WorkflowDurablePhase.running(stepCursor: 0, iterationCursor: 0, lastResult: nil)),
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
            checkpointStore: faultInjectingStore(wrapping: AnyHiveCheckpointStore(
                WorkflowLegacyMigratingCheckpointStore(
                    inner: checkpointing.runtimeStore,
                    schemaVersion: graph.schemaVersion,
                    graphVersion: graph.graphVersion
                )
            ))
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
            let phase = (try? store.get(WorkflowDurableSchema.phaseKey))
                ?? .running(stepCursor: 0, iterationCursor: 0, lastResult: nil)
            if case .completed = phase {
                return .end
            }
            return .to([WorkflowNodeID.execute])
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
            let phase = try store.get(WorkflowDurableSchema.phaseKey)
            switch phase {
            case .completed(let snapshot):
                return snapshot.agentResult
            case .running(_, _, let lastResult):
                if let lastResult {
                    return lastResult.agentResult
                }
                return AgentResult(output: try store.get(WorkflowDurableSchema.currentInputKey))
            }

        case .channels(let values):
            guard let value = values.first(where: { $0.id == WorkflowDurableSchema.phaseKey.id })?.value
            else {
                return AgentResult(output: "")
            }
            guard let phase = value as? WorkflowDurablePhase else {
                return AgentResult(output: "")
            }
            switch phase {
            case .completed(let snapshot):
                return snapshot.agentResult
            case .running(_, _, let lastResult):
                if let lastResult {
                    return lastResult.agentResult
                }
                if let currentInput = values.first(where: { $0.id == WorkflowDurableSchema.currentInputKey.id })?
                    .value as? String {
                    return AgentResult(output: currentInput)
                }
                return AgentResult(output: "")
            }
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

    let phase = try input.store.get(WorkflowDurableSchema.phaseKey)
    guard case .running(let stepCursor, let iterationCursor, let lastResult) = phase else {
        return HiveNodeOutput(next: .end)
    }

    // Cursors are untrusted persisted state: every engine-written cursor is
    // non-negative by construction, so a negative value can only come from a
    // tampered or truncated checkpoint. Fail the resume with a typed error
    // instead of trapping on `steps[stepCursor]` below.
    guard stepCursor >= 0, iterationCursor >= 0 else {
        throw WorkflowError.invalidWorkflow(
            reason: "durable checkpoint carries negative cursors "
                + "(stepCursor: \(stepCursor), iterationCursor: \(iterationCursor))"
        )
    }

    let currentInput = try input.store.get(WorkflowDurableSchema.currentInputKey)
    // The final result of a pass: the last committed step result, or the
    // original input for workflows that complete before running any step.
    let finalSnapshot = { lastResult ?? WorkflowResultSnapshot(AgentResult(output: currentInput)) }

    if stepCursor >= input.context.workflow.steps.count {
        if let repeatCondition = input.context.workflow.repeatCondition {
            let lastResultValue = lastResult?.agentResult ?? AgentResult(output: currentInput)
            if repeatCondition(lastResultValue) {
                return HiveNodeOutput(
                    writes: [AnyHiveWrite(WorkflowDurableSchema.phaseKey, .completed(finalSnapshot()))],
                    next: .end
                )
            }

            let nextIteration = iterationCursor + 1
            if nextIteration >= input.context.workflow.maxRepeatIterations {
                return HiveNodeOutput(
                    writes: [AnyHiveWrite(WorkflowDurableSchema.phaseKey, .completed(finalSnapshot()))],
                    next: .end
                )
            }

            return HiveNodeOutput(
                writes: [
                    AnyHiveWrite(
                        WorkflowDurableSchema.phaseKey,
                        .running(stepCursor: 0, iterationCursor: nextIteration, lastResult: lastResult)
                    ),
                    AnyHiveWrite(WorkflowDurableSchema.currentInputKey, lastResultValue.output),
                ]
            )
        }

        return HiveNodeOutput(
            writes: [AnyHiveWrite(WorkflowDurableSchema.phaseKey, .completed(finalSnapshot()))],
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
            AnyHiveWrite(
                WorkflowDurableSchema.phaseKey,
                .running(stepCursor: stepCursor + 1, iterationCursor: iterationCursor, lastResult: Optional(snapshot))
            ),
            AnyHiveWrite(WorkflowDurableSchema.currentInputKey, result.output),
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

/// Checkpoint store wrapper that migrates pre-phase-enum checkpoints on load.
///
/// Loads matching the current schema version pass through untouched; anything
/// else is offered to ``WorkflowLegacyCheckpointMigrator`` so durable runs
/// checkpointed by earlier Swarm releases resume instead of failing with a
/// version mismatch.
private struct WorkflowLegacyMigratingCheckpointStore: HiveCheckpointStore {
    typealias Schema = WorkflowDurableSchema

    private let inner: AnyHiveCheckpointStore<Schema>
    private let schemaVersion: String
    private let graphVersion: String

    init(
        inner: AnyHiveCheckpointStore<Schema>,
        schemaVersion: String,
        graphVersion: String
    ) {
        self.inner = inner
        self.schemaVersion = schemaVersion
        self.graphVersion = graphVersion
    }

    func save(_ checkpoint: HiveCheckpoint<Schema>) async throws {
        try await inner.save(checkpoint)
    }

    func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<Schema>? {
        guard let checkpoint = try await inner.loadLatest(threadID: threadID) else { return nil }
        guard checkpoint.schemaVersion != schemaVersion else { return checkpoint }
        return try WorkflowLegacyCheckpointMigrator.migrate(
            checkpoint,
            schemaVersion: schemaVersion,
            graphVersion: graphVersion
        )
    }
}

/// Rewrites checkpoints persisted in the pre-phase-enum six-channel layout into
/// the current three-channel phase-enum layout.
///
/// The legacy channels (`workflow.currentInput`, `workflow.lastResult`,
/// `workflow.stepCursor`, `workflow.iterationCursor`, `workflow.completed`,
/// `workflow.signature`) are decoded with the same deterministic JSON codecs
/// that wrote them, then folded into one ``WorkflowDurablePhase``:
/// `completed == true` becomes `.completed` (synthesizing the result from the
/// current input when no step ever committed), otherwise `.running` carries the
/// cursors and snapshot forward. A synthesized completion cannot leave pending
/// cursors behind because the cursors are dropped with the legacy layout.
///
/// Version bookkeeping (`channelVersionsByChannelID`, `versionsSeenByNodeID`,
/// `updatedChannelsLastCommit`) is pruned to channel IDs the current schema
/// still registers: legacy checkpoints carry the removed channel IDs in these
/// maps, and the runtime rejects any unknown ID there as corrupt. Surviving
/// channels keep their write history; the phase channel starts at version 0
/// like any newly registered channel.
///
/// Checkpoints without the legacy discriminator channel are returned untouched
/// so the runtime raises its regular version-mismatch error rather than
/// guessing at an unknown format.
enum WorkflowLegacyCheckpointMigrator {
    static func migrate(
        _ checkpoint: HiveCheckpoint<WorkflowDurableSchema>,
        schemaVersion: String,
        graphVersion: String
    ) throws -> HiveCheckpoint<WorkflowDurableSchema> {
        let legacyData = checkpoint.globalDataByChannelID
        guard legacyData[LegacyRunState.completedChannelID] != nil else {
            return checkpoint
        }

        let legacy = try LegacyRunState(globalDataByChannelID: legacyData)
        let phase: WorkflowDurablePhase
        if legacy.completed {
            phase = .completed(legacy.lastResult ?? WorkflowResultSnapshot(AgentResult(output: legacy.currentInput)))
        } else {
            phase = .running(
                stepCursor: legacy.stepCursor,
                iterationCursor: legacy.iterationCursor,
                lastResult: legacy.lastResult
            )
        }

        var migratedData: [String: Data] = [:]
        migratedData[WorkflowDurableSchema.phaseKey.id.rawValue] =
            try WorkflowCheckpointCodec<WorkflowDurablePhase>().encode(phase)
        migratedData[WorkflowDurableSchema.currentInputKey.id.rawValue] =
            try WorkflowCheckpointCodec<String>().encode(legacy.currentInput)
        migratedData[WorkflowDurableSchema.signatureKey.id.rawValue] =
            try WorkflowCheckpointCodec<String>().encode(legacy.signature)

        let registeredGlobalIDs = Set(
            WorkflowDurableSchema.channelSpecs
                .filter { $0.scope == .global }
                .map { $0.id.rawValue }
        )

        return HiveCheckpoint(
            id: checkpoint.id,
            threadID: checkpoint.threadID,
            runID: checkpoint.runID,
            stepIndex: checkpoint.stepIndex,
            schemaVersion: schemaVersion,
            graphVersion: graphVersion,
            checkpointFormatVersion: checkpoint.checkpointFormatVersion,
            channelVersionsByChannelID: checkpoint.channelVersionsByChannelID
                .filter { registeredGlobalIDs.contains($0.key) },
            versionsSeenByNodeID: checkpoint.versionsSeenByNodeID.mapValues { versions in
                versions.filter { registeredGlobalIDs.contains($0.key) }
            },
            updatedChannelsLastCommit: checkpoint.updatedChannelsLastCommit
                .filter { registeredGlobalIDs.contains($0) },
            globalDataByChannelID: migratedData,
            frontier: checkpoint.frontier,
            deferredFrontier: checkpoint.deferredFrontier,
            joinBarrierSeenByJoinID: checkpoint.joinBarrierSeenByJoinID,
            interruption: checkpoint.interruption,
            lineage: checkpoint.lineage
        )
    }
}

/// Channel identifiers and decoded values of the pre-phase-enum durable layout.
private struct LegacyRunState {
    static let currentInputChannelID = "workflow.currentInput"
    static let signatureChannelID = "workflow.signature"
    static let stepCursorChannelID = "workflow.stepCursor"
    static let iterationCursorChannelID = "workflow.iterationCursor"
    static let completedChannelID = "workflow.completed"
    static let lastResultChannelID = "workflow.lastResult"

    let currentInput: String
    let signature: String
    let stepCursor: Int
    let iterationCursor: Int
    let completed: Bool
    let lastResult: WorkflowResultSnapshot?

    init(globalDataByChannelID data: [String: Data]) throws {
        // Missing entries fall back to start-of-run values; entries that are
        // present but undecodable fail loudly instead of fabricating state.
        currentInput = try Self.decoded(data[Self.currentInputChannelID], as: String.self) ?? ""
        signature = try Self.decoded(data[Self.signatureChannelID], as: String.self) ?? ""
        stepCursor = try Self.decoded(data[Self.stepCursorChannelID], as: Int.self) ?? 0
        iterationCursor = try Self.decoded(data[Self.iterationCursorChannelID], as: Int.self) ?? 0
        completed = try Self.decoded(data[Self.completedChannelID], as: Bool.self) ?? false
        lastResult = try Self.decoded(data[Self.lastResultChannelID], as: WorkflowResultSnapshot?.self) ?? nil
    }

    private static func decoded<Value: Codable & Sendable>(_ data: Data?, as _: Value.Type) throws -> Value? {
        guard let data else { return nil }
        return try WorkflowCheckpointCodec<Value>().decode(data)
    }
}
#endif
