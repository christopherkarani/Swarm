import Foundation

/// How a caller enters a durable workflow run.
///
/// Built by the ``DurableWorkflow`` methods: ``DurableWorkflow/execute(_:)``
/// starts, ``DurableWorkflow/resume(_:from:)`` resumes, and
/// ``DurableWorkflow/resume(decision:from:)`` delivers an approval decision.
enum WorkflowDurableEntry: Sendable, Equatable {
    /// Start the run from step 0 with `input`.
    case start(input: String)
    /// Continue the run from its latest checkpoint.
    case resume
    /// Deliver a human decision to the run's paused tool approval.
    case decide(WorkflowApprovalDecision)
}

#if SWARM_INTEGRATIONS
import HiveCore

/// What the latest checkpoint of a durable run allows next.
///
/// Classified once from the latest checkpoint, before the engine acts, so
/// every entry sees the same reading of the run.
enum WorkflowDurableCheckpointStatus: Sendable, Equatable {
    /// The run has no checkpoint.
    case absent
    /// A checkpoint exists with no pending approval: mid-flight or completed.
    case resumable
    /// The run is paused on a tool approval.
    case awaitingApproval(WorkflowApprovalRequestEnvelope, interruptID: HiveInterruptID)
    /// A human rejected the paused call; the run is terminal.
    ///
    /// Takes precedence over a pending interrupt, because the rejecting
    /// step's checkpoint can still carry the original interrupt.
    case rejected(toolName: String, reason: String)

    /// Classifies the latest checkpoint of a run.
    ///
    /// An undecodable phase is not treated as rejected; it falls through to
    /// the runtime's own error reporting.
    ///
    /// - Throws: ``WorkflowError/invalidWorkflow(reason:)`` when a pending
    ///   interrupt carries an unreadable approval request.
    init(latest checkpoint: HiveCheckpoint<WorkflowDurableSchema>?) throws {
        guard let checkpoint else {
            self = .absent
            return
        }
        if let data = checkpoint.globalDataByChannelID[WorkflowDurableSchema.phaseKey.id.rawValue],
           let phase = try? WorkflowCheckpointCodec<WorkflowDurablePhase>().decode(data),
           case .rejected(let toolName, let reason) = phase {
            self = .rejected(toolName: toolName, reason: reason)
            return
        }
        guard let interruption = checkpoint.interruption else {
            self = .resumable
            return
        }
        self = try .awaitingApproval(
            WorkflowApprovalRequestEnvelope.decoded(from: interruption.payload),
            interruptID: interruption.id
        )
    }
}

/// A plan failure, carrying the public error the caller receives.
enum WorkflowDurablePlanFailure: Sendable, Equatable {
    case workflow(WorkflowError)
    case approvalRequired(WorkflowApprovalRequired)
    case resumeConflict(WorkflowResumeConflict)
    case replayDiverged(WorkflowApprovalReplayDiverged)

    /// The error thrown to the caller.
    var error: any Error {
        switch self {
        case .workflow(let error): error
        case .approvalRequired(let error): error
        case .resumeConflict(let error): error
        case .replayDiverged(let error): error
        }
    }
}

/// What the durable engine does for one entry, decided before any runtime work.
///
/// ``plan(_:_:checkpointID:now:)`` is pure: the engine reads the latest
/// checkpoint once, classifies it, and interprets the returned plan.
enum WorkflowDurablePlan: Sendable, Equatable {
    /// Run from step 0 with `input`, replacing any earlier progress.
    case startFresh(input: String)
    /// Continue from the latest checkpoint.
    case continueRun
    /// Claim the paused approval and resume its interrupt with `envelope`.
    case deliver(interruptID: HiveInterruptID, WorkflowApprovalDecisionEnvelope)
    /// Throw without running anything.
    case fail(WorkflowDurablePlanFailure)

    /// Decides what an entry does against a classified checkpoint.
    ///
    /// A paused run is never restarted or resumed past its approval: `start`
    /// and `resume` report the original ``WorkflowApprovalRequired``, and only
    /// `decide` continues it. `start` on a pause that a live resume claims
    /// reports ``WorkflowResumeConflict`` instead.
    ///
    /// - Parameters:
    ///   - entry: How the caller entered the run.
    ///   - status: The classified latest checkpoint.
    ///   - checkpointID: The run's checkpoint thread.
    ///   - now: The time claim leases are measured against.
    static func plan(
        _ entry: WorkflowDurableEntry,
        _ status: WorkflowDurableCheckpointStatus,
        checkpointID: String,
        now: Date
    ) -> WorkflowDurablePlan {
        switch (entry, status) {
        case (.start(let input), .absent), (.start(let input), .resumable), (.start(let input), .rejected):
            return .startFresh(input: input)
        case (.start, .awaitingApproval(let request, let interruptID)):
            if let claim = request.claim, claim.isLive(at: now) {
                return .fail(.resumeConflict(WorkflowResumeConflict(
                    checkpointID: WorkflowCheckpointID(checkpointID),
                    reason: "the paused approval is held by a resume claimed at \(claim.claimedAt)"
                )))
            }
            return .fail(.approvalRequired(approvalRequired(request, interruptID: interruptID, checkpointID)))
        case (.resume, .absent), (.decide, .absent):
            return .fail(.workflow(.checkpointNotFound(id: checkpointID)))
        case (.resume, .resumable):
            return .continueRun
        case (.resume, .awaitingApproval(let request, let interruptID)):
            return .fail(.approvalRequired(approvalRequired(request, interruptID: interruptID, checkpointID)))
        case (.resume, .rejected(let toolName, let reason)), (.decide, .rejected(let toolName, let reason)):
            return .fail(.workflow(.humanApprovalRejected(prompt: toolName, reason: reason)))
        case (.decide, .resumable):
            return .fail(.workflow(.invalidWorkflow(
                reason: "No paused tool approval for checkpoint '\(checkpointID)'"
            )))
        case (.decide(let decision), .awaitingApproval(let request, let interruptID)):
            return deliver(decision, request: request, interruptID: interruptID, checkpointID: checkpointID)
        }
    }

    /// The error originally thrown when the run paused on `request`.
    private static func approvalRequired(
        _ request: WorkflowApprovalRequestEnvelope,
        interruptID: HiveInterruptID,
        _ checkpointID: String
    ) -> WorkflowApprovalRequired {
        WorkflowApprovalRequired(
            toolName: request.toolName,
            arguments: request.arguments,
            stepCursor: request.stepCursor,
            checkpointID: WorkflowCheckpointID(checkpointID),
            interruptID: interruptID.rawValue
        )
    }

    /// Builds the resume payload for a decision on a paused approval.
    ///
    /// `.approve` adds the paused call to the approvals earlier in the pause
    /// chain. An `.approve` that would extend the divergence streak to
    /// ``WorkflowApprovalReplayDiverged/maxAttempts`` fails before the step
    /// runs, so a refused approve executes nothing and leaves the pause as it was.
    private static func deliver(
        _ decision: WorkflowApprovalDecision,
        request: WorkflowApprovalRequestEnvelope,
        interruptID: HiveInterruptID,
        checkpointID: String
    ) -> WorkflowDurablePlan {
        var approved = request.approved
        if decision == .approve {
            let streak = request.divergentResumes ?? 0
            guard streak + 1 < WorkflowApprovalReplayDiverged.maxAttempts else {
                return .fail(.replayDiverged(WorkflowApprovalReplayDiverged(
                    checkpointID: WorkflowCheckpointID(checkpointID),
                    toolName: request.toolName,
                    attempts: streak + 1
                )))
            }
            approved.append(WorkflowApprovedCall(toolName: request.toolName, arguments: request.arguments))
        }
        return .deliver(interruptID: interruptID, WorkflowApprovalDecisionEnvelope(
            decision: decision,
            toolName: request.toolName,
            arguments: request.arguments,
            approved: approved,
            journal: request.journal,
            divergentResumes: request.divergentResumes
        ))
    }
}
#endif
