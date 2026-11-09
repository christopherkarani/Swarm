import Foundation
import Testing
@testable import Swarm

#if SWARM_INTEGRATIONS
import HiveCore

/// One cell of the durable entry plan table.
struct WorkflowDurablePlanRow: Sendable, CustomTestStringConvertible {
    let label: String
    let entry: WorkflowDurableEntry
    let status: WorkflowDurableCheckpointStatus
    let expected: WorkflowDurablePlan

    var testDescription: String {
        label
    }
}

private enum PlanFixture {
    static let checkpointID = "run-1"
    static let interruptID = HiveInterruptID("interrupt-1")
    static let now = Date(timeIntervalSince1970: 1_000_000)
    static let call = WorkflowApprovedCall(toolName: "delete_vm", arguments: ["id": .string("vm-1")])
    static let earlier = WorkflowApprovedCall(toolName: "stop_vm", arguments: ["id": .string("vm-1")])
    static let journal = [WorkflowJournaledCall(call: earlier, outcome: .success(.string("ok")), parents: nil)]

    static func request(
        claimedAt: Date? = nil,
        divergentResumes: Int? = 0
    ) -> WorkflowApprovalRequestEnvelope {
        WorkflowApprovalRequestEnvelope(
            toolName: call.toolName,
            arguments: call.arguments,
            stepCursor: 1,
            approved: [earlier],
            claim: claimedAt.map { WorkflowApprovalClaim(token: "token", claimedAt: $0) },
            journal: journal,
            divergentResumes: divergentResumes
        )
    }

    static let paused = WorkflowDurableCheckpointStatus.awaitingApproval(request(), interruptID: interruptID)
    static let rejected = WorkflowDurableCheckpointStatus.rejected(toolName: "delete_vm", reason: "no")

    static let approvalRequired = WorkflowDurablePlan.fail(.approvalRequired(WorkflowApprovalRequired(
        toolName: call.toolName,
        arguments: call.arguments,
        stepCursor: 1,
        checkpointID: WorkflowCheckpointID(checkpointID),
        interruptID: interruptID.rawValue
    )))
    static let notFound = WorkflowDurablePlan.fail(.workflow(.checkpointNotFound(id: checkpointID)))
    static let rejection = WorkflowDurablePlan.fail(.workflow(.humanApprovalRejected(prompt: "delete_vm", reason: "no")))
    static let noPausedApproval = WorkflowDurablePlan.fail(.workflow(.invalidWorkflow(
        reason: "No paused tool approval for checkpoint 'run-1'"
    )))

    static func delivered(_ decision: WorkflowApprovalDecision, approved: [WorkflowApprovedCall]) -> WorkflowDurablePlan {
        .deliver(interruptID: interruptID, WorkflowApprovalDecisionEnvelope(
            decision: decision,
            toolName: call.toolName,
            arguments: call.arguments,
            approved: approved,
            journal: journal,
            divergentResumes: 0
        ))
    }

    /// Every entry × status cell of the plan table.
    static let table: [WorkflowDurablePlanRow] = [
        WorkflowDurablePlanRow(label: "start/absent", entry: .start(input: "go"), status: .absent,
                               expected: .startFresh(input: "go")),
        WorkflowDurablePlanRow(label: "start/resumable", entry: .start(input: "go"), status: .resumable,
                               expected: .startFresh(input: "go")),
        WorkflowDurablePlanRow(label: "start/awaitingApproval", entry: .start(input: "go"), status: paused,
                               expected: approvalRequired),
        WorkflowDurablePlanRow(label: "start/rejected", entry: .start(input: "go"), status: rejected,
                               expected: .startFresh(input: "go")),
        WorkflowDurablePlanRow(label: "resume/absent", entry: .resume, status: .absent, expected: notFound),
        WorkflowDurablePlanRow(label: "resume/resumable", entry: .resume, status: .resumable, expected: .continueRun),
        WorkflowDurablePlanRow(label: "resume/awaitingApproval", entry: .resume, status: paused,
                               expected: approvalRequired),
        WorkflowDurablePlanRow(label: "resume/rejected", entry: .resume, status: rejected, expected: rejection),
        WorkflowDurablePlanRow(label: "approve/absent", entry: .decide(.approve), status: .absent, expected: notFound),
        WorkflowDurablePlanRow(label: "approve/resumable", entry: .decide(.approve), status: .resumable,
                               expected: noPausedApproval),
        WorkflowDurablePlanRow(label: "approve/awaitingApproval", entry: .decide(.approve), status: paused,
                               expected: delivered(.approve, approved: [earlier, call])),
        WorkflowDurablePlanRow(label: "approve/rejected", entry: .decide(.approve), status: rejected,
                               expected: rejection),
        WorkflowDurablePlanRow(label: "reject/absent", entry: .decide(.reject), status: .absent, expected: notFound),
        WorkflowDurablePlanRow(label: "reject/resumable", entry: .decide(.reject), status: .resumable,
                               expected: noPausedApproval),
        WorkflowDurablePlanRow(label: "reject/awaitingApproval", entry: .decide(.reject), status: paused,
                               expected: delivered(.reject, approved: [earlier])),
        WorkflowDurablePlanRow(label: "reject/rejected", entry: .decide(.reject), status: rejected,
                               expected: rejection),
    ]

    /// Claim and divergence refinements of the awaitingApproval column.
    static let refinements: [WorkflowDurablePlanRow] = [
        WorkflowDurablePlanRow(
            label: "start on a live claim conflicts",
            entry: .start(input: "go"),
            status: .awaitingApproval(request(claimedAt: now.addingTimeInterval(-10)), interruptID: interruptID),
            expected: .fail(.resumeConflict(WorkflowResumeConflict(
                checkpointID: WorkflowCheckpointID(checkpointID),
                reason: "the paused approval is held by a resume claimed at \(now.addingTimeInterval(-10))"
            )))
        ),
        WorkflowDurablePlanRow(
            label: "start on an expired claim reports the approval",
            entry: .start(input: "go"),
            status: .awaitingApproval(
                request(claimedAt: now.addingTimeInterval(-(WorkflowApprovalClaim.lease + 1))),
                interruptID: interruptID
            ),
            expected: approvalRequired
        ),
        WorkflowDurablePlanRow(
            label: "resume on a live claim reports the approval",
            entry: .resume,
            status: .awaitingApproval(request(claimedAt: now.addingTimeInterval(-10)), interruptID: interruptID),
            expected: approvalRequired
        ),
        WorkflowDurablePlanRow(
            label: "approve at the divergence limit is refused",
            entry: .decide(.approve),
            status: .awaitingApproval(
                request(divergentResumes: WorkflowApprovalReplayDiverged.maxAttempts - 1),
                interruptID: interruptID
            ),
            expected: .fail(.replayDiverged(WorkflowApprovalReplayDiverged(
                checkpointID: WorkflowCheckpointID(checkpointID),
                toolName: "delete_vm",
                attempts: WorkflowApprovalReplayDiverged.maxAttempts
            )))
        ),
        WorkflowDurablePlanRow(
            label: "reject at the divergence limit still delivers",
            entry: .decide(.reject),
            status: .awaitingApproval(
                request(divergentResumes: WorkflowApprovalReplayDiverged.maxAttempts - 1),
                interruptID: interruptID
            ),
            expected: .deliver(interruptID: interruptID, WorkflowApprovalDecisionEnvelope(
                decision: .reject,
                toolName: "delete_vm",
                arguments: call.arguments,
                approved: [earlier],
                journal: journal,
                divergentResumes: WorkflowApprovalReplayDiverged.maxAttempts - 1
            ))
        ),
    ]
}

@Suite("Durable entry plan")
struct WorkflowDurablePlanTests {
    @Test("plan table", arguments: PlanFixture.table)
    func planTable(row: WorkflowDurablePlanRow) {
        let plan = WorkflowDurablePlan.plan(
            row.entry,
            row.status,
            checkpointID: PlanFixture.checkpointID,
            now: PlanFixture.now
        )
        #expect(plan == row.expected)
    }

    @Test("claim and divergence refinements", arguments: PlanFixture.refinements)
    func refinements(row: WorkflowDurablePlanRow) {
        let plan = WorkflowDurablePlan.plan(
            row.entry,
            row.status,
            checkpointID: PlanFixture.checkpointID,
            now: PlanFixture.now
        )
        #expect(plan == row.expected)
    }

    @Test("the table covers every entry and status")
    func tableIsComplete() {
        #expect(PlanFixture.table.count == 16)
        #expect(Set(PlanFixture.table.map(\.label)).count == 16)
    }
}
#endif
