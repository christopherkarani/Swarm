import Foundation
import Testing
@testable import Swarm

#if SWARM_INTEGRATIONS

/// Decision durability and approval consumption for durable tool approvals.
@Suite("Durable approval decisions are durable and one-shot")
struct WorkflowDurableApprovalDecisionTests {
    @Test(
        "reject resolves the pause durably so a later approve cannot run the tool",
        arguments: [Workflow.Durable.CheckpointPolicy.everyStep, .onCompletion]
    )
    func rejectIsDurable(policy: Workflow.Durable.CheckpointPolicy) async throws {
        let counter = ApprovalToolCounter()
        let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
        let provider = await MockInferenceProvider()
        let script: () async -> Void = {
            await provider.configureToolCallingSequence(
                toolCalls: [("delete_vm", ["id": .string("vm-1")])],
                finalAnswer: "done"
            )
        }
        await script()
        let agent = try makeApprovalTestAgent(tools: [tool], provider: provider)
        let checkpointID = WorkflowCheckpointID("approval-reject-durable")
        let workflow = Workflow()
            .step(agent)
            .durable
            .configured(id: checkpointID, store: .inMemory(), policy: policy)

        await #expect(throws: WorkflowApprovalRequired.self) {
            _ = try await workflow.execute("go")
        }

        await script()
        await #expect(throws: WorkflowError.self) {
            _ = try await workflow.resume(decision: .reject, from: checkpointID)
        }

        // The rejected pause is gone: approving the same checkpoint must fail
        // instead of executing the rejected call.
        await script()
        do {
            let result = try await workflow.resume(decision: .approve, from: checkpointID)
            Issue.record("approve after reject must fail, got output \(result.output)")
        } catch let error as WorkflowError {
            guard case .invalidWorkflow = error else {
                Issue.record("expected invalidWorkflow (no paused approval), got \(error)")
                return
            }
        }

        // A plain resume reports the terminal rejection rather than re-running.
        await script()
        do {
            let result = try await workflow.resume("go", from: checkpointID)
            Issue.record("resume after reject must fail, got output \(result.output)")
        } catch let error as WorkflowError {
            guard case .humanApprovalRejected(let prompt, _) = error else {
                Issue.record("expected humanApprovalRejected, got \(error)")
                return
            }
            #expect(prompt == "delete_vm")
        }
        #expect(await counter.count == 0)
    }

    @Test("an approval is consumed by one call; a repeated identical call pauses again")
    func approvalIsOneShot() async throws {
        let counter = ApprovalToolCounter()
        let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
        let provider = await MockInferenceProvider()
        let script: () async -> Void = {
            await provider.configureToolCallingSequence(
                toolCalls: [
                    ("delete_vm", ["id": .string("vm-1")]),
                    ("delete_vm", ["id": .string("vm-1")]),
                ],
                finalAnswer: "done"
            )
        }
        await script()
        let agent = try makeApprovalTestAgent(tools: [tool], provider: provider)
        let checkpointID = WorkflowCheckpointID("approval-one-shot")
        let workflow = Workflow()
            .step(agent)
            .durable
            .configured(id: checkpointID, store: .inMemory(), policy: .everyStep)

        await #expect(throws: WorkflowApprovalRequired.self) {
            _ = try await workflow.execute("go")
        }

        await script()
        do {
            let result = try await workflow.resume(decision: .approve, from: checkpointID)
            Issue.record("second identical call must pause again, got output \(result.output)")
        } catch let required as WorkflowApprovalRequired {
            #expect(required.toolName == "delete_vm")
        }
        #expect(await counter.count == 1)

        await script()
        let result = try await workflow.resume(decision: .approve, from: checkpointID)
        #expect(result.output == "done")
    }
}

#endif
