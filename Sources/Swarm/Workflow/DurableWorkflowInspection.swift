import Foundation

/// Phase of a single durable workflow checkpoint.
///
/// Mirrors the checkpointed run state: either the run is mid-flight
/// (`running`, with its cursors and most recent step result) or it has
/// terminated (`completed`, carrying the final result).
public enum DurableWorkflowPhase: Sendable, Equatable {
    /// The run is still executing. `stepCursor` indexes the next step to run;
    /// `iterationCursor` counts completed passes of a repeating workflow;
    /// `lastResult` is the most recent step result, or `nil` before the first
    /// step commits.
    case running(stepCursor: Int, iterationCursor: Int, lastResult: AgentResult?)
    /// The run has finished. Carries the workflow's final result.
    case completed(AgentResult)
}

/// Point-in-time view of one checkpoint in a durable run's history.
///
/// Obtain histories with ``DurableWorkflow/inspect()`` or
/// ``DurableWorkflow/inspect(run:)``. Snapshots never expose Hive runtime
/// types; identifiers are plain strings.
public struct DurableWorkflowCheckpointSnapshot: Sendable, Equatable {
    /// Identifier of this checkpoint, as assigned by the checkpoint store.
    ///
    /// Pass this to ``DurableWorkflow/resume(_:from:forkingFrom:)`` to fork a
    /// new run from this point in history.
    public let checkpointID: String
    /// Runtime step index of this checkpoint. Histories are ordered oldest
    /// first, so these ascend within
    /// ``DurableWorkflowRunInspection/checkpoints``.
    public let stepIndex: Int
    /// Run-state phase captured by this checkpoint.
    public let phase: DurableWorkflowPhase
    /// Whether this checkpoint's workflow signature matches the inspecting
    /// workflow's current signature. `false` means resuming would throw a
    /// definition-mismatch error.
    public let signatureMatches: Bool

    /// Creates a checkpoint snapshot.
    public init(
        checkpointID: String,
        stepIndex: Int,
        phase: DurableWorkflowPhase,
        signatureMatches: Bool
    ) {
        self.checkpointID = checkpointID
        self.stepIndex = stepIndex
        self.phase = phase
        self.signatureMatches = signatureMatches
    }

    /// Whether this checkpoint captures a finished run.
    public var isCompleted: Bool {
        if case .completed = phase { return true }
        return false
    }

    /// Next-step cursor when `phase` is `running`, otherwise `nil`.
    public var stepCursor: Int? {
        if case .running(let stepCursor, _, _) = phase { return stepCursor }
        return nil
    }

    /// Completed-repeat-pass count when `phase` is `running`, otherwise `nil`.
    public var iterationCursor: Int? {
        if case .running(_, let iterationCursor, _) = phase { return iterationCursor }
        return nil
    }

    /// Most recent step result, or the final result when the run completed.
    ///
    /// `nil` only before the first step of a running workflow commits.
    public var lastResult: AgentResult? {
        switch phase {
        case .running(_, _, let lastResult):
            return lastResult
        case .completed(let result):
            return result
        }
    }
}

/// Newest-last checkpoint history of one durable run.
///
/// Returned by ``DurableWorkflow/inspect()`` and
/// ``DurableWorkflow/inspect(run:)``.
public struct DurableWorkflowRunInspection: Sendable, Equatable {
    /// The inspected run.
    public let run: WorkflowCheckpointID
    /// Checkpoint snapshots ordered oldest first (newest last).
    public let checkpoints: [DurableWorkflowCheckpointSnapshot]

    /// Creates a run inspection.
    public init(run: WorkflowCheckpointID, checkpoints: [DurableWorkflowCheckpointSnapshot]) {
        self.run = run
        self.checkpoints = checkpoints
    }

    /// The newest checkpoint snapshot, if the run has any checkpoints.
    public var latest: DurableWorkflowCheckpointSnapshot? {
        checkpoints.last
    }

    /// Whether the newest checkpoint captures a finished run.
    public var isCompleted: Bool {
        latest?.isCompleted ?? false
    }

    /// Whether the newest checkpoint's workflow signature matches the
    /// inspecting workflow's current signature.
    public var signatureMatches: Bool {
        latest?.signatureMatches ?? true
    }
}

#if SWARM_INTEGRATIONS
import HiveCore

/// Maps stored Hive checkpoints to public inspection snapshots.
enum DurableWorkflowInspector {
    /// Reads `run`'s history and maps every decodable checkpoint.
    ///
    /// Checkpoints whose run-state payload cannot be decoded are skipped with
    /// a warning, matching store-level corrupt-file tolerance.
    ///
    /// - Throws: ``WorkflowError/checkpointNotFound(id:)`` when the run has no
    ///   decodable checkpoints.
    static func inspect(
        workflow: Workflow,
        run: WorkflowCheckpointID,
        checkpointing: WorkflowCheckpointing
    ) async throws -> DurableWorkflowRunInspection {
        let history = try await checkpointing.history(for: run.rawValue)
        let currentSignature = workflow.workflowSignature
        var snapshots: [DurableWorkflowCheckpointSnapshot] = []
        snapshots.reserveCapacity(history.count)
        for checkpoint in history {
            do {
                snapshots.append(
                    try snapshot(from: checkpoint, currentSignature: currentSignature)
                )
            } catch {
                Log.orchestration.warning(
                    "Skipping undecodable workflow checkpoint \(checkpoint.id.rawValue): \(error)"
                )
            }
        }
        guard !snapshots.isEmpty else {
            throw WorkflowError.checkpointNotFound(id: run.rawValue)
        }
        return DurableWorkflowRunInspection(run: run, checkpoints: snapshots)
    }

    private static func snapshot(
        from checkpoint: HiveCheckpoint<WorkflowDurableSchema>,
        currentSignature: String
    ) throws -> DurableWorkflowCheckpointSnapshot {
        let native = try WorkflowLegacyCheckpointMigrator.migrate(
            checkpoint,
            schemaVersion: checkpoint.schemaVersion,
            graphVersion: checkpoint.graphVersion
        )
        let data = native.globalDataByChannelID
        guard let phaseData = data[WorkflowDurableSchema.phaseKey.id.rawValue],
              let signatureData = data[WorkflowDurableSchema.signatureKey.id.rawValue]
        else {
            throw WorkflowError.invalidWorkflow(reason: "Durable checkpoint is missing run-state channels")
        }
        let phase = try WorkflowCheckpointCodec<WorkflowDurablePhase>().decode(phaseData)
        let signature = try WorkflowCheckpointCodec<String>().decode(signatureData)
        let matches = workflowDurableSignatureMismatch(
            checkpointSignature: signature,
            currentSignature: currentSignature
        ) == nil
        return DurableWorkflowCheckpointSnapshot(
            checkpointID: checkpoint.id.rawValue,
            stepIndex: checkpoint.stepIndex,
            phase: publicPhase(from: phase),
            signatureMatches: matches
        )
    }

    private static func publicPhase(from phase: WorkflowDurablePhase) -> DurableWorkflowPhase {
        switch phase {
        case .running(let stepCursor, let iterationCursor, let lastResult):
            return .running(
                stepCursor: stepCursor,
                iterationCursor: iterationCursor,
                lastResult: lastResult?.agentResult
            )
        case .completed(let snapshot):
            return .completed(snapshot.agentResult)
        }
    }
}
#endif
