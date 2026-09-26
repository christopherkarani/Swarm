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

    /// Delivers a human approval decision to a run paused on ``WorkflowApprovalRequired``.
    ///
    /// The pending approval is read back from the checkpoint thread, so the
    /// call works from a fresh process as long as the checkpoint store is
    /// shared. `.approve` executes the paused tool call and continues the run
    /// (pausing again if the step reaches another approval-required tool);
    /// `.reject` fails with
    /// ``WorkflowError/humanApprovalRejected(prompt:reason:)`` without executing.
    ///
    /// There is no timeout on the approval wait itself: the run stays paused
    /// until this method is called.
    ///
    /// - Parameters:
    ///   - decision: The human decision for the paused tool call.
    ///   - checkpointID: The checkpoint thread holding the paused state.
    /// - Returns: The workflow's final ``AgentResult``.
    /// - Throws: ``WorkflowError/checkpointNotFound(id:)`` when no checkpoint exists,
    ///   ``WorkflowError/invalidWorkflow(reason:)`` when no approval is paused,
    ///   ``WorkflowError/humanApprovalRejected(prompt:reason:)`` on `.reject`,
    ///   ``WorkflowApprovalRequired`` when the resumed run pauses again,
    ///   or ``WorkflowError/durableRuntimeUnavailable(reason:)`` on lean builds.
    public func resume(
        decision: WorkflowApprovalDecision,
        from checkpointID: WorkflowCheckpointID
    ) async throws -> AgentResult {
        try await workflow.executeDurableApprovalConfigured(
            decision: decision,
            checkpointID: checkpointID,
            checkpointing: checkpointing,
            policy: policy
        )
    }
}
