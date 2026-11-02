#if SWARM_INTEGRATIONS
import Foundation
import HiveCore

// Concurrency control for durable resumes: an in-process guard plus a
// store-level compare-and-swap claim on paused approvals.

extension WorkflowDurableEngine {
    /// Runs `body` while this process holds the run's resume guard.
    func withResumeGuard(
        _ body: () async throws -> AgentResult
    ) async throws -> AgentResult {
        let key = WorkflowDurableResumeGuard.Key(
            store: ObjectIdentifier(checkpointing.backend),
            checkpointID: checkpointID
        )
        guard await WorkflowDurableResumeGuard.shared.acquire(key) else {
            throw WorkflowResumeConflict(
                checkpointID: WorkflowCheckpointID(checkpointID),
                reason: "another resume of this checkpoint is in progress in this process"
            )
        }
        do {
            let result = try await body()
            await WorkflowDurableResumeGuard.shared.release(key)
            return result
        } catch {
            await WorkflowDurableResumeGuard.shared.release(key)
            throw error
        }
    }

    /// Claims the paused approval with a compare-and-swap save.
    ///
    /// The claim rewrites the latest checkpoint under a new ID with the claim
    /// recorded in the interrupt payload, expecting the checkpoint just read
    /// to still be latest. A concurrent resume (any process) that read the
    /// same checkpoint loses the swap; one that reads the claimed checkpoint
    /// sees a live claim. Either way it throws ``WorkflowResumeConflict``
    /// before executing anything.
    func claimApproval(
        _ checkpoint: HiveCheckpoint<WorkflowDurableSchema>,
        interruption: HiveInterrupt<WorkflowDurableSchema>,
        request: WorkflowApprovalRequestEnvelope,
        store: AnyHiveCheckpointStore<WorkflowDurableSchema>
    ) async throws -> HiveCheckpoint<WorkflowDurableSchema> {
        let now = Date()
        if let existing = request.claim, existing.isLive(at: now) {
            throw WorkflowResumeConflict(
                checkpointID: WorkflowCheckpointID(checkpointID),
                reason: "the paused approval was claimed by another resume at \(existing.claimedAt); "
                    + "the claim expires after \(Int(WorkflowApprovalClaim.lease)) seconds"
            )
        }
        var claimedRequest = request
        let claim = WorkflowApprovalClaim(token: UUID().uuidString, claimedAt: now)
        claimedRequest.claim = claim
        let claimed = checkpoint.replacing(
            id: HiveCheckpointID("\(checkpoint.id.rawValue):claim:\(claim.token)"),
            interruption: HiveInterrupt(id: interruption.id, payload: try claimedRequest.encoded())
        )
        do {
            try await store.save(claimed, expectedLatestID: checkpoint.id)
        } catch is HiveCheckpointConflict {
            throw WorkflowResumeConflict(
                checkpointID: WorkflowCheckpointID(checkpointID),
                reason: "another resume claimed the paused approval first"
            )
        }
        return claimed
    }

    /// Best-effort release of a claim after a resume failed before committing.
    ///
    /// Only applies while the claimed checkpoint is still latest; once the
    /// resumed run committed anything the claim is already superseded.
    func releaseClaim(
        _ claimed: HiveCheckpoint<WorkflowDurableSchema>,
        request: WorkflowApprovalRequestEnvelope,
        store: AnyHiveCheckpointStore<WorkflowDurableSchema>
    ) async {
        guard let interruption = claimed.interruption,
              let payload = try? request.encoded() else { return }
        let released = claimed.replacing(
            id: HiveCheckpointID("\(claimed.id.rawValue):released"),
            interruption: HiveInterrupt(id: interruption.id, payload: payload)
        )
        try? await store.save(released, expectedLatestID: claimed.id)
    }
}

/// Process-wide guard that keeps two resumes of one run from overlapping.
///
/// Keyed by checkpoint-store identity plus checkpoint ID: handles sharing a
/// ``WorkflowCheckpointing`` value contend here, while separate store
/// instances (as in separate processes) are serialized by the store-level
/// claim instead.
actor WorkflowDurableResumeGuard {
    struct Key: Hashable {
        let store: ObjectIdentifier
        let checkpointID: String
    }

    static let shared = WorkflowDurableResumeGuard()

    private var active: Set<Key> = []

    /// Returns `false` when a resume of `key` is already running.
    func acquire(_ key: Key) -> Bool {
        active.insert(key).inserted
    }

    func release(_ key: Key) {
        active.remove(key)
    }
}

extension HiveCheckpoint where Schema == WorkflowDurableSchema {
    /// Copy of this checkpoint under a new ID with a different interruption.
    func replacing(id: HiveCheckpointID, interruption: HiveInterrupt<Schema>?) -> Self {
        HiveCheckpoint(
            id: id,
            threadID: threadID,
            runID: runID,
            stepIndex: stepIndex,
            schemaVersion: schemaVersion,
            graphVersion: graphVersion,
            checkpointFormatVersion: checkpointFormatVersion,
            channelVersionsByChannelID: channelVersionsByChannelID,
            versionsSeenByNodeID: versionsSeenByNodeID,
            updatedChannelsLastCommit: updatedChannelsLastCommit,
            globalDataByChannelID: globalDataByChannelID,
            frontier: frontier,
            deferredFrontier: deferredFrontier,
            joinBarrierSeenByJoinID: joinBarrierSeenByJoinID,
            interruption: interruption,
            lineage: lineage
        )
    }
}
#endif
