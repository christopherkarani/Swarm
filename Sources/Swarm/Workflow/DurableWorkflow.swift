import Foundation

/// A workflow configured for durable checkpointing with a required identity and store.
///
/// Construct with ``Workflow/Durable/configured(id:store:policy:)``. Both the checkpoint
/// ID and checkpoint store are required; there is no partial durable configuration.
public struct DurableWorkflow: Sendable {
    fileprivate let workflow: Workflow
    fileprivate let checkpointID: WorkflowCheckpointID
    fileprivate let checkpointing: WorkflowCheckpointing
    fileprivate let policy: Workflow.Durable.CheckpointPolicy

    init(
        workflow: Workflow,
        checkpointID: WorkflowCheckpointID,
        checkpointing: WorkflowCheckpointing,
        policy: Workflow.Durable.CheckpointPolicy
    ) {
        self.workflow = workflow
        self.checkpointID = checkpointID
        self.checkpointing = checkpointing
        self.policy = policy
    }

    /// Starts a durable workflow run.
    ///
    /// - Parameter input: Initial workflow input.
    /// - Returns: The workflow's final ``AgentResult``.
    /// - Throws: ``WorkflowError/durableRuntimeUnavailable(reason:)`` on lean builds.
    public func execute(_ input: String) async throws -> AgentResult {
        try await workflow.executeDurableConfigured(
            input: input,
            checkpointID: checkpointID,
            checkpointing: checkpointing,
            policy: policy,
            resume: false
        )
    }

    /// Resumes a durable workflow from a saved checkpoint.
    ///
    /// - Parameters:
    ///   - input: Input passed to the resumed run (may be ignored when the checkpoint already
    ///     carries progress).
    ///   - checkpointID: The checkpoint thread to resume.
    /// - Returns: The workflow's final ``AgentResult``.
    /// - Throws: ``WorkflowError/checkpointNotFound(id:)`` when no checkpoint exists,
    ///   or ``WorkflowError/durableRuntimeUnavailable(reason:)`` on lean builds.
    public func resume(_ input: String, from checkpointID: WorkflowCheckpointID) async throws -> AgentResult {
        try await workflow.executeDurableConfigured(
            input: input,
            checkpointID: checkpointID,
            checkpointing: checkpointing,
            policy: policy,
            resume: true
        )
    }

    /// Inspects this run's checkpoint history without executing.
    ///
    /// - Returns: The run's checkpoints ordered oldest first (newest last),
    ///   with step cursors, results, and per-checkpoint signature-match flags.
    /// - Throws: ``WorkflowError/checkpointNotFound(id:)`` when the run has no
    ///   decodable checkpoints, or
    ///   ``WorkflowError/durableRuntimeUnavailable(reason:)`` on lean builds.
    public func inspect() async throws -> DurableWorkflowRunInspection {
        #if SWARM_INTEGRATIONS
        return try await DurableWorkflowInspector.inspect(
            workflow: workflow,
            run: checkpointID,
            checkpointing: checkpointing
        )
        #else
        throw WorkflowError.durableRuntimeUnavailable(
            reason: IntegrationsTrait.requirementMessage(for: "Durable workflow inspection")
        )
        #endif
    }

    /// Inspects another run's checkpoint history with this workflow's signature.
    ///
    /// Signature-match flags compare the stored checkpoints against this
    /// workflow's current definition, so inspecting an older run after changing
    /// the workflow surfaces `false` instead of failing at resume time.
    ///
    /// - Parameter run: The checkpoint thread to inspect.
    /// - Returns: The run's checkpoints ordered oldest first (newest last).
    /// - Throws: ``WorkflowError/checkpointNotFound(id:)`` when the run has no
    ///   decodable checkpoints, or
    ///   ``WorkflowError/durableRuntimeUnavailable(reason:)`` on lean builds.
    public func inspect(run: WorkflowCheckpointID) async throws -> DurableWorkflowRunInspection {
        #if SWARM_INTEGRATIONS
        return try await DurableWorkflowInspector.inspect(
            workflow: workflow,
            run: run,
            checkpointing: checkpointing
        )
        #else
        throw WorkflowError.durableRuntimeUnavailable(
            reason: IntegrationsTrait.requirementMessage(for: "Durable workflow inspection")
        )
        #endif
    }

    /// Forks an older checkpoint of this run into a new run, then resumes it.
    ///
    /// The source checkpoint is selected from ``inspect()`` history. The
    /// source run is left untouched; progress continues under `checkpointID`.
    ///
    /// - Parameters:
    ///   - input: Input passed to the resumed run (may be ignored when the
    ///     forked checkpoint already carries progress).
    ///   - checkpointID: The new run to create. Must not have checkpoints yet.
    ///   - sourceCheckpointID: A checkpoint ID from this run's history.
    /// - Returns: The forked run's final ``AgentResult``.
    /// - Throws: ``WorkflowError/checkpointNotFound(id:)`` when the source
    ///   checkpoint does not exist, ``WorkflowError/invalidWorkflow(reason:)``
    ///   when the target run already has checkpoints, or
    ///   ``WorkflowError/durableRuntimeUnavailable(reason:)`` on lean builds.
    public func resume(
        _ input: String,
        from checkpointID: WorkflowCheckpointID,
        forkingFrom sourceCheckpointID: String
    ) async throws -> AgentResult {
        try await workflow.executeDurableFork(
            input: input,
            sourceRun: self.checkpointID,
            sourceCheckpointID: sourceCheckpointID,
            targetRun: checkpointID,
            checkpointing: checkpointing,
            policy: policy
        )
    }
}
