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
            id: WorkflowApprovalClaimCheckpointID.claim(after: checkpoint.id),
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

    /// Runs `body` while renewing the claim recorded in `holder`.
    ///
    /// A resumed step can outlive ``WorkflowApprovalClaim/lease`` (a slow
    /// approved tool), and Hive's later commits are plain saves, so an expired
    /// claim would let another resume execute the approved call too. Every
    /// third of the lease the claim is re-saved with a fresh timestamp,
    /// compare-and-swapped against the claim checkpoint last written; renewal
    /// stops once the resumed run commits (the swap fails). The renewal task
    /// has finished when this returns or throws, so `holder.current` is the
    /// claim checkpoint written last.
    func withRenewal<T: Sendable>(
        of holder: WorkflowApprovalClaimHolder,
        store: AnyHiveCheckpointStore<WorkflowDurableSchema>,
        _ body: () async throws -> T
    ) async throws -> T {
        let interval = UInt64(WorkflowApprovalClaim.lease / 3 * 1_000_000_000)
        let renewal = Task {
            while true {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }
                guard await holder.renew(store: store) else { return }
            }
        }
        do {
            let result = try await body()
            renewal.cancel()
            await renewal.value
            return result
        } catch {
            renewal.cancel()
            await renewal.value
            throw error
        }
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
            id: WorkflowApprovalClaimCheckpointID.release(of: claimed.id),
            interruption: HiveInterrupt(id: interruption.id, payload: payload)
        )
        do {
            try await store.save(released, expectedLatestID: claimed.id)
        } catch {
            Log.orchestration.warning(
                "Could not release durable approval claim on '\(checkpointID)'; it expires after its lease: \(error)"
            )
        }
    }
}

/// Fixed-length checkpoint IDs for approval claims and their releases.
///
/// Every ID is derived from the paused Hive checkpoint ID (the part before the
/// first `:`) plus a zero-padded claim sequence, so repeated failed resumes
/// never grow the ID (file stores put it in the file name). At one step index
/// the IDs sort in save order: `base` < `base:c00000001` <
/// `base:c00000001r` < `base:c00000002`.
enum WorkflowApprovalClaimCheckpointID {
    private static let sequenceDigits = 8

    /// The ID for the next claim after `current` (a pause, claim, or release).
    static func claim(after current: HiveCheckpointID) -> HiveCheckpointID {
        let parsed = parse(current)
        return HiveCheckpointID("\(parsed.base):c\(padded(parsed.sequence + 1))")
    }

    /// The ID for releasing the claim saved as `claimed`.
    static func release(of claimed: HiveCheckpointID) -> HiveCheckpointID {
        let parsed = parse(claimed)
        return HiveCheckpointID("\(parsed.base):c\(padded(parsed.sequence))r")
    }

    private static func parse(_ id: HiveCheckpointID) -> (base: Substring, sequence: Int) {
        let raw = id.rawValue
        guard let separator = raw.firstIndex(of: ":") else { return (raw[...], 0) }
        var suffix = raw[raw.index(after: separator)...]
        guard suffix.first == "c" else { return (raw[..<separator], 0) }
        suffix = suffix.dropFirst()
        if suffix.last == "r" { suffix = suffix.dropLast() }
        return (raw[..<separator], Int(suffix) ?? 0)
    }

    private static func padded(_ sequence: Int) -> String {
        let digits = String(sequence)
        return String(repeating: "0", count: max(0, sequenceDigits - digits.count)) + digits
    }
}

/// The latest claim checkpoint a resume wrote, renewed while the resume runs.
actor WorkflowApprovalClaimHolder {
    private(set) var current: HiveCheckpoint<WorkflowDurableSchema>

    init(_ claimed: HiveCheckpoint<WorkflowDurableSchema>) {
        current = claimed
    }

    /// Re-saves the claim with a fresh timestamp. Returns `false` once a
    /// commit superseded the claim or another writer took the run.
    func renew(store: AnyHiveCheckpointStore<WorkflowDurableSchema>) async -> Bool {
        guard let interruption = current.interruption,
              var request = try? WorkflowApprovalRequestEnvelope.decoded(from: interruption.payload),
              request.claim != nil else { return false }
        request.claim?.claimedAt = Date()
        guard let payload = try? request.encoded() else { return false }
        let renewed = current.replacing(
            id: WorkflowApprovalClaimCheckpointID.claim(after: current.id),
            interruption: HiveInterrupt(id: interruption.id, payload: payload)
        )
        do {
            try await store.save(renewed, expectedLatestID: current.id)
        } catch {
            return false
        }
        current = renewed
        return true
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

    /// Whether a resume of `key` is running in this process.
    func isActive(_ key: Key) -> Bool {
        active.contains(key)
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
