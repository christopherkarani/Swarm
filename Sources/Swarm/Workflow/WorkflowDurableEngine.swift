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
/// it has terminated (`completed`, carrying the final result, or `rejected`,
/// carrying a human approval rejection). Because the
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
    /// The run ended because a human rejected a paused tool call.
    ///
    /// Terminal like ``completed(_:)``: later approval decisions and resumes
    /// report the rejection without executing.
    case rejected(toolName: String, reason: String)
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

    /// Single Integrations-engine conversion from a typed checkpoint identity to a Hive thread ID.
    /// Callers must not construct `HiveThreadID` from an arbitrary session string.
    static func hiveThreadID(for checkpointID: WorkflowCheckpointID) -> HiveThreadID {
        HiveThreadID(checkpointID.rawValue)
    }

    func run(startInput: String) async throws -> AgentResult {
        if let error = WorkflowTransition.validationError(for: workflow.workflowTransitionPolicy) {
            throw error
        }
        guard resume else { return try await runHoldingGuard(startInput: startInput) }
        return try await withResumeGuard {
            try await runHoldingGuard(startInput: startInput)
        }
    }

    private func runHoldingGuard(startInput: String) async throws -> AgentResult {
        if let controller = WorkflowDurableFaultInjection.controller {
            await controller.beginAttempt()
        }
        let components = try makeRuntimeComponents()

        if resume {
            guard try await checkpointing.containsCheckpoint(for: checkpointID) else {
                throw WorkflowError.checkpointNotFound(id: checkpointID)
            }
            try Self.throwIfRejected(
                try await components.runtime.getLatestCheckpoint(threadID: components.threadID)
            )
        } else {
            try await throwIfResumeInFlight(components: components)
        }

        let input: WorkflowDurableInput = resume ? .resume : .start(
            input: startInput,
            signature: workflow.workflowSignature
        )
        let handle = await components.runtime.run(
            threadID: components.threadID,
            input: input,
            options: runOptions(for: policy)
        )

        let outcome = try await Self.awaitOutcome(of: handle)
        return try await finish(outcome, components: components)
    }

    /// Delivers a human approval decision to a run paused on ``WorkflowApprovalRequired``.
    ///
    /// The pending interrupt is read back from the latest checkpoint, so the
    /// caller only names the checkpoint thread. `.approve` carries the approved
    /// call (plus earlier approvals in the pause chain) into the resumed step;
    /// `.reject` commits the terminal ``WorkflowDurablePhase/rejected(toolName:reason:)``
    /// phase and fails the run with
    /// ``WorkflowError/humanApprovalRejected(prompt:reason:)`` without executing.
    /// A later decision on a rejected run reports the same rejection. Concurrent
    /// resumes do not both execute: the in-process guard and the compare-and-swap
    /// claim (`claimApproval`) make the losers throw ``WorkflowResumeConflict``.
    func resumeApproval(decision: WorkflowApprovalDecision) async throws -> AgentResult {
        if let error = WorkflowTransition.validationError(for: workflow.workflowTransitionPolicy) {
            throw error
        }
        return try await withResumeGuard {
            try await resumeApprovalHoldingGuard(decision: decision)
        }
    }

    private func resumeApprovalHoldingGuard(decision: WorkflowApprovalDecision) async throws -> AgentResult {
        if let controller = WorkflowDurableFaultInjection.controller {
            await controller.beginAttempt()
        }
        let components = try makeRuntimeComponents()

        guard try await checkpointing.containsCheckpoint(for: checkpointID) else {
            throw WorkflowError.checkpointNotFound(id: checkpointID)
        }
        return try await deliver(decision, components: components)
    }

    /// Reads the pending interrupt, claims it, and resumes it. Callers hold
    /// the resume guard, and the claim keeps other processes out, so the read
    /// and the resumed commit cannot interleave with another decision.
    private func deliver(
        _ decision: WorkflowApprovalDecision,
        components: WorkflowDurableRuntimeComponents
    ) async throws -> AgentResult {
        guard let checkpoint = try await components.runtime.getLatestCheckpoint(threadID: components.threadID)
        else {
            throw WorkflowError.checkpointNotFound(id: checkpointID)
        }
        try Self.throwIfRejected(checkpoint)
        guard let interruption = checkpoint.interruption else {
            throw WorkflowError.invalidWorkflow(reason: "No paused tool approval for checkpoint '\(checkpointID)'")
        }
        let request = try WorkflowApprovalRequestEnvelope.decoded(from: interruption.payload)
        try refuseDivergentApproval(decision, request: request)
        let claimed = try await claimApproval(
            checkpoint,
            interruption: interruption,
            request: request,
            store: components.store
        )
        var approved = request.approved
        if decision == .approve {
            approved.append(WorkflowApprovedCall(toolName: request.toolName, arguments: request.arguments))
        }
        let resumePayload = try WorkflowApprovalDecisionEnvelope(
            decision: decision,
            toolName: request.toolName,
            arguments: request.arguments,
            approved: approved,
            journal: request.journal,
            divergentResumes: request.divergentResumes
        ).encoded()

        let holder = WorkflowApprovalClaimHolder(claimed)
        do {
            return try await withRenewal(of: holder, store: components.store) {
                let handle = await components.runtime.resume(
                    threadID: components.threadID,
                    interruptID: interruption.id,
                    payload: resumePayload,
                    options: runOptions(for: policy)
                )
                let outcome = try await Self.awaitOutcome(of: handle)
                return try await finish(outcome, components: components)
            }
        } catch let failure as WorkflowResumedStepFailure {
            var released = request
            released.journal = failure.journal
            released.approved = failure.approved
            await releaseClaim(await holder.current, request: released, store: components.store)
            throw failure.underlying
        } catch {
            await releaseClaim(await holder.current, request: request, store: components.store)
            throw error
        }
    }

    /// Refuses an `.approve` that would extend the divergence streak to
    /// ``WorkflowApprovalReplayDiverged/maxAttempts``, before the step runs, so
    /// a refused approve executes nothing and leaves the pause as it was.
    private func refuseDivergentApproval(
        _ decision: WorkflowApprovalDecision,
        request: WorkflowApprovalRequestEnvelope
    ) throws {
        let streak = request.divergentResumes ?? 0
        guard decision == .approve, streak + 1 >= WorkflowApprovalReplayDiverged.maxAttempts else { return }
        throw WorkflowApprovalReplayDiverged(
            checkpointID: WorkflowCheckpointID(checkpointID),
            toolName: request.toolName,
            attempts: streak + 1
        )
    }

    /// Maps a run outcome to the caller's result, persisting terminal state.
    ///
    /// A rejection is terminal state too, so it is flushed under
    /// `.onCompletion` before the rejection error propagates.
    private func finish(
        _ outcome: HiveRunOutcome<WorkflowDurableSchema>,
        components: WorkflowDurableRuntimeComponents
    ) async throws -> AgentResult {
        do {
            let result = try extractResult(from: outcome)
            try await flushIfNeeded(runtime: components.runtime, threadID: components.threadID)
            return result
        } catch WorkflowError.humanApprovalRejected(let prompt, let reason) {
            try await flushIfNeeded(runtime: components.runtime, threadID: components.threadID)
            throw WorkflowError.humanApprovalRejected(prompt: prompt, reason: reason)
        }
    }

    /// Refuses a fresh start over a run that a resume currently holds.
    ///
    /// Starting rewrites the run from step 0, so it must not overlap a resume
    /// in this process (the resume guard) or anywhere sharing the store (a
    /// live approval claim on the latest checkpoint). Other run IDs and runs
    /// with no resume in flight start normally.
    private func throwIfResumeInFlight(components: WorkflowDurableRuntimeComponents) async throws {
        let key = WorkflowDurableResumeGuard.Key(
            store: ObjectIdentifier(checkpointing.backend),
            checkpointID: checkpointID
        )
        if await WorkflowDurableResumeGuard.shared.isActive(key) {
            throw WorkflowResumeConflict(
                checkpointID: WorkflowCheckpointID(checkpointID),
                reason: "a resume of this checkpoint is in progress in this process"
            )
        }
        guard let interruption = try await components.store.loadLatest(threadID: components.threadID)?.interruption,
              let request = try? WorkflowApprovalRequestEnvelope.decoded(from: interruption.payload),
              let claim = request.claim,
              claim.isLive(at: Date())
        else { return }
        throw WorkflowResumeConflict(
            checkpointID: WorkflowCheckpointID(checkpointID),
            reason: "the paused approval is held by a resume claimed at \(claim.claimedAt)"
        )
    }

    /// Reports a checkpointed rejection before any runtime work.
    ///
    /// The rejecting step's checkpoint can still carry the original interrupt
    /// (Hive clears it in memory after the checkpoint is built), so the phase,
    /// not the interrupt, decides whether the run is terminal. Undecodable
    /// phases fall through to the runtime's own error reporting.
    private static func throwIfRejected(_ checkpoint: HiveCheckpoint<WorkflowDurableSchema>?) throws {
        guard let data = checkpoint?.globalDataByChannelID[WorkflowDurableSchema.phaseKey.id.rawValue],
              let phase = try? WorkflowCheckpointCodec<WorkflowDurablePhase>().decode(data),
              case .rejected(let toolName, let reason) = phase
        else { return }
        throw WorkflowError.humanApprovalRejected(prompt: toolName, reason: reason)
    }

    private func makeRuntimeComponents() throws -> WorkflowDurableRuntimeComponents {
        let graph = try Self.compiledGraph(for: workflow)
        let store = Self.checkpointStore(checkpointing: checkpointing, graph: graph)
        let environment = Self.environment(workflow: workflow, store: store)
        let runtime = try HiveRuntime(graph: graph, environment: environment)
        let threadID = Self.hiveThreadID(for: WorkflowCheckpointID(checkpointID))
        return WorkflowDurableRuntimeComponents(runtime: runtime, threadID: threadID, store: store)
    }

    private func flushIfNeeded(
        runtime: HiveRuntime<WorkflowDurableSchema>,
        threadID: HiveThreadID
    ) async throws {
        guard policy == .onCompletion else { return }
        let flushHandle = await runtime.applyExternalWrites(
            threadID: threadID,
            writes: [],
            options: HiveRunOptions(maxSteps: 1, checkpointPolicy: .everyStep)
        )
        // The main run already finished (and its side effects happened), so
        // the completion checkpoint must land even if the caller is cancelled
        // or times out now. Await the flush without forwarding cancellation;
        // otherwise a resume would re-run side-effecting steps.
        _ = try await flushHandle.outcome.value
    }

    /// Awaits a Hive run outcome while forwarding caller cancellation to it.
    ///
    /// `HiveRuntime` drives each attempt in an unstructured task, so cancelling
    /// the caller (or losing a `Workflow.timeout` race) would otherwise leave the
    /// run calling models, running tools, and writing checkpoints after the
    /// caller has already returned.
    private static func awaitOutcome(
        of handle: HiveRunHandle<WorkflowDurableSchema>
    ) async throws -> HiveRunOutcome<WorkflowDurableSchema> {
        try await withTaskCancellationHandler {
            try await handle.outcome.value
        } onCancel: {
            handle.outcome.cancel()
        }
    }

    static func compiledGraph(for workflow: Workflow) throws -> CompiledHiveGraph<WorkflowDurableSchema> {
        var builder = HiveGraphBuilder<WorkflowDurableSchema>(start: [WorkflowNodeID.execute])
        builder.addNode(WorkflowNodeID.execute, workflowNode)
        builder.addRouter(from: WorkflowNodeID.execute) { store in
            WorkflowDurableRouting.route(for: Result { try store.get(WorkflowDurableSchema.phaseKey) })
        }
        return try builder.compile()
    }

    static func environment(
        workflow: Workflow,
        store: AnyHiveCheckpointStore<WorkflowDurableSchema>
    ) -> HiveEnvironment<WorkflowDurableSchema> {
        let context = WorkflowDurableContext(
            workflow: workflow,
            signature: workflow.workflowSignature
        )
        return HiveEnvironment(
            context: context,
            clock: WorkflowDurableClock(),
            logger: WorkflowDurableLogger(),
            checkpointStore: store
        )
    }

    /// The runtime's checkpoint store: legacy migration plus optional fault injection.
    static func checkpointStore(
        checkpointing: WorkflowCheckpointing,
        graph: CompiledHiveGraph<WorkflowDurableSchema>
    ) -> AnyHiveCheckpointStore<WorkflowDurableSchema> {
        let migrating = AnyHiveCheckpointStore(
            WorkflowLegacyMigratingCheckpointStore(
                inner: checkpointing.runtimeStore,
                schemaVersion: graph.schemaVersion,
                graphVersion: graph.graphVersion
            )
        )
        return faultInjectingStore(wrapping: migrating)
    }

    private static func faultInjectingStore(
        wrapping store: AnyHiveCheckpointStore<WorkflowDurableSchema>
    ) -> AnyHiveCheckpointStore<WorkflowDurableSchema> {
        guard WorkflowDurableFaultInjection.controller != nil else {
            return store
        }
        return AnyHiveCheckpointStore(WorkflowFaultInjectingCheckpointStore(inner: store))
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
        case .cancelled:
            // A cancelled run's output is the last committed step (or the echoed
            // input), not a workflow result. Surfacing it would look like success.
            throw AgentError.cancelled
        case .outOfSteps:
            throw WorkflowError.invalidWorkflow(reason: "Workflow exceeded execution budget")
        case .interrupted(let interruption):
            let request = try WorkflowApprovalRequestEnvelope.decoded(from: interruption.interrupt.payload)
            throw WorkflowApprovalRequired(
                toolName: request.toolName,
                arguments: request.arguments,
                stepCursor: request.stepCursor,
                checkpointID: WorkflowCheckpointID(checkpointID),
                interruptID: interruption.interrupt.id.rawValue
            )
        }
    }

    fileprivate func extractResult(from output: HiveRunOutput<WorkflowDurableSchema>) throws -> AgentResult {
        switch output {
        case .fullStore(let store):
            let phase = try store.get(WorkflowDurableSchema.phaseKey)
            switch phase {
            case .completed(let snapshot):
                return snapshot.agentResult
            case .rejected(let toolName, let reason):
                throw WorkflowError.humanApprovalRejected(prompt: toolName, reason: reason)
            case .running(_, _, let lastResult):
                if let lastResult {
                    return lastResult.agentResult
                }
                return AgentResult(output: try store.get(WorkflowDurableSchema.currentInputKey))
            }

        case .channels(let values):
            guard let value = values.first(where: { $0.id == WorkflowDurableSchema.phaseKey.id })?.value
            else {
                throw WorkflowError.invalidWorkflow(reason: "Durable workflow finished without a phase channel")
            }
            guard let phase = value as? WorkflowDurablePhase else {
                throw WorkflowError.invalidWorkflow(reason: "Durable workflow phase channel has an invalid type")
            }
            switch phase {
            case .completed(let snapshot):
                return snapshot.agentResult
            case .rejected(let toolName, let reason):
                throw WorkflowError.humanApprovalRejected(prompt: toolName, reason: reason)
            case .running(_, _, let lastResult):
                if let lastResult {
                    return lastResult.agentResult
                }
                guard let currentInput = values.first(where: { $0.id == WorkflowDurableSchema.currentInputKey.id })?
                    .value as? String else {
                    throw WorkflowError.invalidWorkflow(
                        reason: "Durable workflow running phase is missing a current input channel"
                    )
                }
                return AgentResult(output: currentInput)
            }
        }
    }
}

/// Forks an older checkpoint of one run into a new run, then resumes the new run.
///
/// The runtime seeds the target thread from the source checkpoint (channels,
/// versions, and frontier) and persists it, so the follow-up resume is an
/// ordinary latest-checkpoint resume under the target run. The source run is
/// left untouched.
struct WorkflowDurableFork: Sendable {
    let workflow: Workflow
    let checkpointing: WorkflowCheckpointing
    let sourceRun: WorkflowCheckpointID
    let sourceCheckpointID: String
    let targetRun: WorkflowCheckpointID
    let policy: Workflow.Durable.CheckpointPolicy

    func run(startInput: String) async throws -> AgentResult {
        if let error = WorkflowTransition.validationError(for: workflow.workflowTransitionPolicy) {
            throw error
        }
        let graph = try WorkflowDurableEngine.compiledGraph(for: workflow)
        let environment = WorkflowDurableEngine.environment(
            workflow: workflow,
            store: WorkflowDurableEngine.checkpointStore(checkpointing: checkpointing, graph: graph)
        )
        let runtime = try HiveRuntime(graph: graph, environment: environment)
        _ = try await runtime.fork(
            threadID: WorkflowDurableEngine.hiveThreadID(for: sourceRun),
            to: WorkflowDurableEngine.hiveThreadID(for: targetRun),
            from: HiveCheckpointID(sourceCheckpointID),
            options: HiveRunOptions(maxSteps: 1, checkpointPolicy: .everyStep)
        )
        let engine = WorkflowDurableEngine(
            workflow: workflow,
            checkpointing: checkpointing,
            checkpointID: targetRun.rawValue,
            policy: policy,
            resume: true
        )
        return try await engine.run(startInput: startInput)
    }
}

/// Non-throwing router decision for the durable execute node.
///
/// Routers cannot throw, so the phase-channel read arrives as a `Result`. Only
/// a genuinely missing value means "no checkpoint state yet" and restarts from
/// step 0. Any other store error (type mismatch, unknown channel, scope
/// mismatch) signals corruption: routing to `.end` lets result extraction
/// re-read the phase channel on its throwing path and surface the underlying
/// error instead of silently re-running steps from the start.
enum WorkflowDurableRouting: Sendable {
    static func route(for phaseResult: Result<WorkflowDurablePhase, Error>) -> Route {
        switch phaseResult {
        case .success(let phase):
            switch phase {
            case .completed, .rejected:
                return .end
            case .running:
                return .to([WorkflowNodeID.execute])
            }
        case .failure(let error):
            if let runtimeError = error as? HiveRuntimeError,
               case .storeValueMissing = runtimeError {
                return .to([WorkflowNodeID.execute])
            }
            return .end
        }
    }
}

private struct WorkflowDurableRuntimeComponents {
    let runtime: HiveRuntime<WorkflowDurableSchema>
    let threadID: HiveThreadID
    let store: AnyHiveCheckpointStore<WorkflowDurableSchema>
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
    let currentInput = try input.store.get(WorkflowDurableSchema.currentInputKey)
    let progress = WorkflowTransition.Progress(
        stepCursor: stepCursor,
        iterationCursor: iterationCursor,
        currentInput: currentInput,
        lastResult: lastResult?.agentResult
    )
    let policy = input.context.workflow.workflowTransitionPolicy

    switch WorkflowTransition.decide(progress: progress, policy: policy) {
    case .runStep(let progress):
        let step = input.context.workflow.steps[progress.stepCursor]
        if let controller = WorkflowDurableFaultInjection.controller {
            await controller.markWorkflowStepStarted()
        }
        let replay: WorkflowStepReplay
        switch try approvalGate(resumePayload: input.run.resume?.payload) {
        case .rejected(let toolName, let reason):
            return rejectedOutput(toolName: toolName, reason: reason)
        case .allowed(let state):
            replay = state
        }
        let ledger = WorkflowApprovalLedger(approved: replay.approved, journal: replay.journal)
        do {
            let result = try await WorkflowDurableApprovalGate.$ledger.withValue(ledger) {
                try await input.context.workflow.execute(step: step, withInput: progress.currentInput)
            }
            let nextDecision = WorkflowTransition.afterStep(
                progress: progress,
                result: result,
                policy: policy
            )
            let nextProgress = try progressValue(from: nextDecision)
            return runningOutput(for: nextProgress)
        } catch let request as WorkflowToolApprovalRequest {
            return try await approvalInterruptOutput(
                progress: progress,
                request: request,
                ledger: ledger,
                replay: replay
            )
        } catch {
            guard let justApproved = replay.justApproved else { throw error }
            throw await WorkflowResumedStepFailure(
                underlying: error,
                ledger: ledger,
                offered: replay.approved,
                justApproved: justApproved
            )
        }

    case .evaluateRepeat(let progress, let result):
        guard let repeatCondition = input.context.workflow.repeatCondition else {
            throw WorkflowError.invalidWorkflow(reason: "workflow repeat predicate is missing")
        }
        let nextDecision = WorkflowTransition.afterRepeatBoundary(
            progress: progress,
            result: result,
            outcome: repeatCondition(result) ? .satisfied : .notSatisfied,
            policy: policy
        )
        return try output(for: nextDecision)

    case .complete(_, let result):
        return completedOutput(for: result)

    case .fail(let error):
        throw error
    }
}

private func progressValue(from decision: WorkflowTransition.Decision) throws -> WorkflowTransition.Progress {
    switch decision {
    case .runStep(let progress), .evaluateRepeat(let progress, _), .complete(let progress, _):
        return progress
    case .fail(let error):
        throw error
    }
}

/// Approval and replay state a step execution starts from.
private struct WorkflowStepReplay {
    /// Approvals not yet consumed in the pause chain.
    var approved: [WorkflowApprovedCall] = []
    /// Calls earlier executions of this step already ran.
    var journal: [WorkflowJournaledCall] = []
    /// Divergence streak carried from the paused request.
    var divergentResumes = 0
    /// The call the `.approve` decision this execution follows granted;
    /// `nil` for a fresh step.
    var justApproved: WorkflowApprovedCall?
}

/// An approve-resumed step failed with `underlying` (not a pause).
///
/// The step may already have executed tools, the approved call included, but
/// nothing was committed, so the engine releases the claim back to the pause.
/// This carries the step's journal and remaining approvals so the released
/// pause records them: a retried resume then replays those calls instead of
/// executing them again. The engine unwraps it before the caller sees it.
struct WorkflowResumedStepFailure: Error {
    let underlying: any Error
    let journal: [WorkflowJournaledCall]
    /// Approvals to keep in the released pause, excluding the paused call
    /// itself, which the next `.approve` grants again.
    let approved: [WorkflowApprovedCall]

    init(
        underlying: any Error,
        ledger: WorkflowApprovalLedger,
        offered: [WorkflowApprovedCall],
        justApproved: WorkflowApprovedCall
    ) async {
        self.underlying = underlying
        journal = await ledger.journal
        var unused = await ledger.unusedApprovals
        // `offered` includes the paused call; if no matching approval was
        // consumed it is still unused, so drop that copy.
        if unused.count(where: { $0 == justApproved }) == offered.count(where: { $0 == justApproved }),
           let index = unused.firstIndex(of: justApproved) {
            unused.remove(at: index)
        }
        approved = unused
    }
}

/// Approval gate state for one step execution.
private enum WorkflowApprovalGateState {
    /// Run the step with this replay state (empty for a fresh step).
    case allowed(WorkflowStepReplay)
    /// The human rejected the paused call; end the run without executing.
    case rejected(toolName: String, reason: String)
}

/// Resolves the approval gate for one step execution.
///
/// A fresh step arms the gate with no allowances. A Hive-resumed step carries
/// the human decision: `.reject` ends the run without executing (the node
/// commits a terminal rejected phase so the decision is checkpointed), and
/// `.approve` allows the calls approved so far in the pause chain, each
/// consumable once per step execution, plus the step's tool journal.
private func approvalGate(resumePayload: String?) throws -> WorkflowApprovalGateState {
    guard let resumePayload else { return .allowed(WorkflowStepReplay()) }
    let decision = try WorkflowApprovalDecisionEnvelope.decoded(from: resumePayload)
    switch decision.decision {
    case .reject:
        return .rejected(
            toolName: decision.toolName,
            reason: "Operator rejected tool '\(decision.toolName)' at durable approval resume"
        )
    case .approve:
        return .allowed(WorkflowStepReplay(
            approved: decision.approved,
            journal: decision.journal ?? [],
            divergentResumes: decision.divergentResumes ?? 0,
            justApproved: WorkflowApprovedCall(toolName: decision.toolName, arguments: decision.arguments)
        ))
    }
}

/// Terminal output for a rejected approval: commits the rejected phase and ends.
private func rejectedOutput(toolName: String, reason: String) -> HiveNodeOutput<WorkflowDurableSchema> {
    HiveNodeOutput(
        writes: [AnyHiveWrite(WorkflowDurableSchema.phaseKey, .rejected(toolName: toolName, reason: reason))],
        next: .end
    )
}

/// Builds the pause output for an approval request.
///
/// The writes preserve the incoming progress (step cursor included) rather
/// than advancing it, so the interrupt-forced checkpoint holds the paused
/// state and the resumed run replays the step from its start. The payload
/// carries the unused approvals and the step's tool journal.
///
/// An approved resume that pauses again without using the approval it was
/// resumed with diverged from that call and extends the divergence streak;
/// any other pause resets it. The resume path refuses an `.approve` that
/// would reach ``WorkflowApprovalReplayDiverged/maxAttempts`` before the step
/// runs, so the streak is checked there, not here.
private func approvalInterruptOutput(
    progress: WorkflowTransition.Progress,
    request: WorkflowToolApprovalRequest,
    ledger: WorkflowApprovalLedger,
    replay: WorkflowStepReplay
) async throws -> HiveNodeOutput<WorkflowDurableSchema> {
    let diverged = if let justApproved = replay.justApproved {
        await !ledger.hasConsumed(justApproved)
    } else {
        false
    }
    let payload = try await WorkflowApprovalRequestEnvelope(
        toolName: request.toolName,
        arguments: request.arguments,
        stepCursor: progress.stepCursor,
        approved: ledger.unusedApprovals,
        journal: ledger.journal,
        divergentResumes: diverged ? replay.divergentResumes + 1 : 0
    ).encoded()
    var output = runningOutput(for: progress)
    output.interrupt = HiveInterruptRequest(payload: payload)
    return output
}

private func runningOutput(for progress: WorkflowTransition.Progress) -> HiveNodeOutput<WorkflowDurableSchema> {
    HiveNodeOutput(
        writes: [
            AnyHiveWrite(
                WorkflowDurableSchema.phaseKey,
                .running(
                    stepCursor: progress.stepCursor,
                    iterationCursor: progress.iterationCursor,
                    lastResult: progress.lastResult.map { WorkflowResultSnapshot($0) }
                )
            ),
            AnyHiveWrite(WorkflowDurableSchema.currentInputKey, progress.currentInput),
        ]
    )
}

private func completedOutput(for result: AgentResult) -> HiveNodeOutput<WorkflowDurableSchema> {
    HiveNodeOutput(
        writes: [AnyHiveWrite(WorkflowDurableSchema.phaseKey, .completed(WorkflowResultSnapshot(result)))],
        next: .end
    )
}

private func output(for decision: WorkflowTransition.Decision) throws -> HiveNodeOutput<WorkflowDurableSchema> {
    switch decision {
    case .runStep(let progress), .evaluateRepeat(let progress, _):
        return runningOutput(for: progress)
    case .complete(_, let result):
        return completedOutput(for: result)
    case .fail(let error):
        throw error
    }
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

    func save(
        _ checkpoint: HiveCheckpoint<WorkflowDurableSchema>,
        expectedLatestID: HiveCheckpointID?
    ) async throws {
        if let controller = WorkflowDurableFaultInjection.controller {
            try await controller.consumeBeforeWrite()
        }
        try await inner.save(checkpoint, expectedLatestID: expectedLatestID)
        if let controller = WorkflowDurableFaultInjection.controller {
            try await controller.consumeAfterWrite()
        }
    }

    func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<WorkflowDurableSchema>? {
        try await inner.loadLatest(threadID: threadID)
    }
}

extension WorkflowFaultInjectingCheckpointStore: HiveCheckpointQueryableStore {
    func listCheckpoints(threadID: HiveThreadID, limit: Int?) async throws -> [HiveCheckpointSummary] {
        try await inner.listCheckpoints(threadID: threadID, limit: limit)
    }

    func loadCheckpoint(threadID: HiveThreadID, id: HiveCheckpointID) async throws -> HiveCheckpoint<Schema>? {
        try await inner.loadCheckpoint(threadID: threadID, id: id)
    }
}

enum WorkflowDurableEngineTesting {
    static func extractResult(from output: HiveRunOutput<WorkflowDurableSchema>) throws -> AgentResult {
        let engine = WorkflowDurableEngine(
            workflow: Workflow(),
            checkpointing: WorkflowCheckpointing.inMemory(),
            checkpointID: "testing",
            policy: .onCompletion,
            resume: false
        )
        return try engine.extractResult(from: output)
    }
}
#endif
