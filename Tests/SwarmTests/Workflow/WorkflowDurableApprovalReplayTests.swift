import Foundation
import Testing
@testable import Swarm

#if SWARM_INTEGRATIONS

/// A tool without approval that counts its executions.
private func makeLookupTool(counter: ApprovalToolCounter) -> FunctionTool {
    FunctionTool(name: "lookup", description: "Read-only lookup without approval") { _ in
        await counter.increment()
        return .string("lookup-result")
    }
}

private func makeDurableWorkflow(
    agent: Agent,
    checkpointID: WorkflowCheckpointID
) -> DurableWorkflow {
    Workflow()
        .step(agent)
        .durable
        .configured(id: checkpointID, store: .inMemory(), policy: .everyStep)
}

@Suite("Durable approval replay idempotency", .ephemeralDefaultStores)
struct WorkflowDurableApprovalReplayTests {
    @Test("tool calls executed before a pause are not re-executed on resume")
    func executedCallsReplayFromJournal() async throws {
        let lookups = ApprovalToolCounter()
        let deletes = ApprovalToolCounter()
        let provider = await MockInferenceProvider()
        let script: () async -> Void = {
            await provider.configureToolCallingSequence(
                toolCalls: [("lookup", ["q": .string("vm-1")]), ("delete_vm", ["id": .string("vm-1")])],
                finalAnswer: "done"
            )
        }
        await script()
        let agent = try makeApprovalTestAgent(
            tools: [makeLookupTool(counter: lookups), makeApprovalCountingTool(name: "delete_vm", counter: deletes)],
            provider: provider
        )
        let checkpointID = WorkflowCheckpointID("approval-replay-journal")
        let workflow = makeDurableWorkflow(agent: agent, checkpointID: checkpointID)

        await #expect(throws: WorkflowApprovalRequired.self) {
            _ = try await workflow.execute("go")
        }
        #expect(await lookups.count == 1)

        await script()
        let result = try await workflow.resume(decision: .approve, from: checkpointID)
        #expect(result.output == "done")
        #expect(await lookups.count == 1)
        #expect(await deletes.count == 1)
        // The replayed call still appears in the step's result.
        #expect(result.toolCalls.map(\.toolName) == ["lookup", "delete_vm"])
        #expect(result.toolResults.first?.output == .string("lookup-result"))
    }

    @Test("replayed tool results are not written to memory twice")
    func replayDoesNotDuplicateMemoryWrites() async throws {
        let lookups = ApprovalToolCounter()
        let deletes = ApprovalToolCounter()
        let memory = MockAgentMemory()
        let provider = await MockInferenceProvider()
        let script: () async -> Void = {
            await provider.configureToolCallingSequence(
                toolCalls: [("lookup", ["q": .string("vm-1")]), ("delete_vm", ["id": .string("vm-1")])],
                finalAnswer: "done"
            )
        }
        await script()
        let agent = try Agent(
            tools: [makeLookupTool(counter: lookups), makeApprovalCountingTool(name: "delete_vm", counter: deletes)],
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .timeout(.seconds(30))
                .defaultTracingEnabled(false),
            memory: memory,
            inferenceProvider: provider
        )
        let checkpointID = WorkflowCheckpointID("approval-replay-memory")
        let workflow = makeDurableWorkflow(agent: agent, checkpointID: checkpointID)

        await #expect(throws: WorkflowApprovalRequired.self) {
            _ = try await workflow.execute("go")
        }
        await script()
        _ = try await workflow.resume(decision: .approve, from: checkpointID)

        let lookupWrites = await memory.addCalls.filter { $0.content.contains("lookup-result") }
        #expect(lookupWrites.count == 1)
    }

    @Test("a replay that keeps diverging from the approved call fails instead of re-asking forever")
    func divergentReplayIsBounded() async throws {
        let deletes = ApprovalToolCounter()
        let provider = await MockInferenceProvider()
        let agent = try makeApprovalTestAgent(
            tools: [makeApprovalCountingTool(name: "delete_vm", counter: deletes)],
            provider: provider
        )
        let checkpointID = WorkflowCheckpointID("approval-replay-divergent")
        let workflow = makeDurableWorkflow(agent: agent, checkpointID: checkpointID)
        // Each replay asks for a different VM than the one just approved.
        let scriptCall: (String) async -> Void = { id in
            await provider.configureToolCallingSequence(
                toolCalls: [("delete_vm", ["id": .string(id)])],
                finalAnswer: "done"
            )
        }

        await scriptCall("vm-1")
        await #expect(throws: WorkflowApprovalRequired.self) {
            _ = try await workflow.execute("go")
        }
        for id in ["vm-2", "vm-3"] {
            await scriptCall(id)
            do {
                _ = try await workflow.resume(decision: .approve, from: checkpointID)
                Issue.record("expected a renewed approval request for \(id)")
            } catch let required as WorkflowApprovalRequired {
                #expect(required.arguments == ["id": .string(id)])
            }
        }

        await scriptCall("vm-4")
        do {
            _ = try await workflow.resume(decision: .approve, from: checkpointID)
            Issue.record("expected WorkflowApprovalReplayDiverged")
        } catch let diverged as WorkflowApprovalReplayDiverged {
            #expect(diverged.checkpointID == checkpointID)
            #expect(diverged.attempts == WorkflowApprovalReplayDiverged.maxAttempts)
        }
        #expect(await deletes.count == 0)

        // The run stays paused; rejecting it still ends it cleanly.
        await #expect(throws: WorkflowError.self) {
            _ = try await workflow.resume(decision: .reject, from: checkpointID)
        }
        #expect(await deletes.count == 0)
    }
}

#endif
