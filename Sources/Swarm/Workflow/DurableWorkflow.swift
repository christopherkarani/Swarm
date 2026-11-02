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
    /// Decisions are durable and one-shot. A rejection is committed as a
    /// terminal checkpoint state, so approving the same checkpoint afterwards
    /// throws instead of running the rejected call. An approval covers one
    /// execution of the exact call; an identical second call in the same step
    /// pauses again.
    ///
    /// Only one concurrent resume of a checkpoint executes. Others, in this
    /// process or in another process sharing the checkpoint store, throw
    /// ``WorkflowResumeConflict`` without executing.
    ///
    /// The paused step replays from its start, but tool calls do not run twice.
    /// Each tool call that executed in the step is journaled in the checkpoint.
    /// On replay, a call with the same tool name and arguments returns its
    /// recorded result, does not notify observers or tracing again, and does
    /// not write to memory again. If the replay keeps pausing on other calls
    /// without reaching the approved one, the approve after
    /// ``WorkflowApprovalReplayDiverged/maxAttempts`` such resumes throws
    /// ``WorkflowApprovalReplayDiverged``.
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
    ///   ``WorkflowResumeConflict`` when another resume holds the run,
    ///   ``WorkflowApprovalReplayDiverged`` when replays keep missing the approved call,
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
