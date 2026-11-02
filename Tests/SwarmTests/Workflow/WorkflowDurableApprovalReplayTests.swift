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

/// A side-effecting tool without approval that counts its executions.
private func makeUngatedCountingTool(name: String, counter: ApprovalToolCounter) -> FunctionTool {
    FunctionTool(name: name, description: "Side-effecting tool without approval") { _ in
        await counter.increment()
        return .string("\(name)-ok")
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

    @Test("a replay that keeps diverging from the approved call fails before running the step")
    func divergentReplayIsBounded() async throws {
        let deletes = ApprovalToolCounter()
        let notifies = ApprovalToolCounter()
        let provider = await MockInferenceProvider()
        let agent = try makeApprovalTestAgent(
            tools: [
                makeApprovalCountingTool(name: "delete_vm", counter: deletes),
                makeUngatedCountingTool(name: "notify", counter: notifies),
            ],
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

        // The capped replay would notify before diverging again; it must not run,
        // including when the operator retries the approve.
        for _ in 0 ..< 2 {
            await provider.configureToolCallingSequence(
                toolCalls: [("notify", ["id": .string("vm-4")]), ("delete_vm", ["id": .string("vm-4")])],
                finalAnswer: "done"
            )
            do {
                _ = try await workflow.resume(decision: .approve, from: checkpointID)
                Issue.record("expected WorkflowApprovalReplayDiverged")
            } catch let diverged as WorkflowApprovalReplayDiverged {
                #expect(diverged.checkpointID == checkpointID)
                #expect(diverged.attempts == WorkflowApprovalReplayDiverged.maxAttempts)
            }
        }
        #expect(await deletes.count == 0)
        #expect(await notifies.count == 0)

        // The run stays paused; rejecting it still ends it cleanly.
        await #expect(throws: WorkflowError.self) {
            _ = try await workflow.resume(decision: .reject, from: checkpointID)
        }
        #expect(await deletes.count == 0)
        #expect(await notifies.count == 0)
    }

    @Test("an approve-resume that runs the call just approved resets the divergence streak")
    func progressAfterDivergenceResetsStreak() async throws {
        let deletes = ApprovalToolCounter()
        let provider = await MockInferenceProvider()
        let agent = try makeApprovalTestAgent(
            tools: [makeApprovalCountingTool(name: "delete_vm", counter: deletes)],
            provider: provider
        )
        let checkpointID = WorkflowCheckpointID("approval-replay-progress")
        let workflow = makeDurableWorkflow(agent: agent, checkpointID: checkpointID)
        let script: ([String]) async -> Void = { ids in
            await provider.configureToolCallingSequence(
                toolCalls: ids.map { ("delete_vm", ["id": .string($0)]) },
                finalAnswer: "done"
            )
        }

        await script(["vm-1"])
        await #expect(throws: WorkflowApprovalRequired.self) {
            _ = try await workflow.execute("go")
        }
        // vm-1 is approved but the replay asks for vm-2 (one divergence). After
        // that, every resume runs the call just approved and asks for the next.
        let chain: [([String], String)] = [
            (["vm-2"], "vm-2"),
            (["vm-2", "vm-3"], "vm-3"),
            (["vm-2", "vm-3", "vm-4"], "vm-4"),
        ]
        for (ids, pausedOn) in chain {
            await script(ids)
            do {
                _ = try await workflow.resume(decision: .approve, from: checkpointID)
                Issue.record("expected a renewed approval request for \(pausedOn)")
            } catch let required as WorkflowApprovalRequired {
                #expect(required.arguments == ["id": .string(pausedOn)])
            }
        }

        await script(["vm-2", "vm-3", "vm-4"])
        let result = try await workflow.resume(decision: .approve, from: checkpointID)
        #expect(result.output == "done")
        // vm-2, vm-3, and vm-4 each run once; vm-1 never runs.
        #expect(await deletes.count == 3)
    }

    @Test("a journaled call matches its replay after the checkpoint JSON round-trip")
    func journalMatchesNormalizedArguments() async throws {
        let lookups = ApprovalToolCounter()
        let deletes = ApprovalToolCounter()
        let provider = await MockInferenceProvider()
        let script: () async -> Void = {
            await provider.configureToolCallingSequence(
                toolCalls: [("lookup", ["n": .double(2.0)]), ("delete_vm", ["id": .string("vm-1")])],
                finalAnswer: "done"
            )
        }
        await script()
        let agent = try makeApprovalTestAgent(
            tools: [makeLookupTool(counter: lookups), makeApprovalCountingTool(name: "delete_vm", counter: deletes)],
            provider: provider
        )
        let checkpointID = WorkflowCheckpointID("approval-replay-normalized")
        let workflow = makeDurableWorkflow(agent: agent, checkpointID: checkpointID)

        await #expect(throws: WorkflowApprovalRequired.self) {
            _ = try await workflow.execute("go")
        }
        await script()
        _ = try await workflow.resume(decision: .approve, from: checkpointID)
        #expect(await lookups.count == 1)
        #expect(await deletes.count == 1)
    }

    @Test("an approved call cancelled by a sibling's pause keeps its approval")
    func cancelledApprovedCallKeepsApproval() async throws {
        let slowRuns = ApprovalToolCounter()
        let fastRuns = ApprovalToolCounter()
        let provider = await MockInferenceProvider()
        let script: () async -> Void = {
            await provider.setToolCallResponses([
                InferenceResponse(
                    content: nil,
                    toolCalls: [
                        InferenceResponse.ParsedToolCall(id: "call_a", name: "slow_a", arguments: ["x": .string("x")]),
                        InferenceResponse.ParsedToolCall(id: "call_b", name: "fast_b", arguments: ["y": .string("y")]),
                    ],
                    finishReason: .toolCall,
                    usage: nil
                ),
                InferenceResponse(content: "done", toolCalls: [], finishReason: .completed, usage: nil),
            ])
        }
        let slow = FunctionTool(
            name: "slow_a",
            description: "Slow approval-gated tool",
            executionSemantics: ToolExecutionSemantics(approvalRequirement: .always)
        ) { _ in
            try await Task.sleep(for: .milliseconds(200))
            await slowRuns.increment()
            return .string("a-ok")
        }
        let agent = try Agent(
            tools: [slow, makeApprovalCountingTool(name: "fast_b", counter: fastRuns)],
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .timeout(.seconds(30))
                .defaultTracingEnabled(false)
                .parallelToolCalls(true),
            inferenceProvider: provider
        )
        let checkpointID = WorkflowCheckpointID("approval-replay-cancelled-sibling")
        let workflow = makeDurableWorkflow(agent: agent, checkpointID: checkpointID)

        await script()
        await #expect(throws: WorkflowApprovalRequired.self) {
            _ = try await workflow.execute("go")
        }
        var output: String?
        var resumes = 0
        while output == nil, resumes < 4 {
            resumes += 1
            await script()
            do {
                output = try await workflow.resume(decision: .approve, from: checkpointID).output
            } catch is WorkflowApprovalRequired {}
        }
        #expect(output == "done")
        #expect(resumes == 2)
        #expect(await slowRuns.count == 1)
        #expect(await fastRuns.count == 1)
    }

    @Test("calls made inside an agent used as a tool do not answer later top-level calls")
    func nestedAgentCallsStayScopedToTheirOuterCall() async throws {
        let sends = ApprovalToolCounter()
        let deletes = ApprovalToolCounter()
        let innerProvider = await MockInferenceProvider()
        let outerProvider = await MockInferenceProvider()
        let script: () async -> Void = {
            await innerProvider.configureToolCallingSequence(
                toolCalls: [("send_email", ["to": .string("a")])],
                finalAnswer: "researched"
            )
            await outerProvider.configureToolCallingSequence(
                toolCalls: [
                    ("research", ["input": .string("q")]),
                    ("delete_vm", ["id": .string("vm-1")]),
                    ("send_email", ["to": .string("a")]),
                ],
                finalAnswer: "done"
            )
        }
        let inner = try makeApprovalTestAgent(
            tools: [makeUngatedCountingTool(name: "send_email", counter: sends)],
            provider: innerProvider
        )
        let outer = try makeApprovalTestAgent(
            tools: [
                inner.asTool(name: "research", description: "Researches a question"),
                makeApprovalCountingTool(name: "delete_vm", counter: deletes),
                makeUngatedCountingTool(name: "send_email", counter: sends),
            ],
            provider: outerProvider
        )
        let checkpointID = WorkflowCheckpointID("approval-replay-nested-scope")
        let workflow = makeDurableWorkflow(agent: outer, checkpointID: checkpointID)

        await script()
        await #expect(throws: WorkflowApprovalRequired.self) {
            _ = try await workflow.execute("go")
        }
        #expect(await sends.count == 1)

        await script()
        let result = try await workflow.resume(decision: .approve, from: checkpointID)
        #expect(result.output == "done")
        #expect(await deletes.count == 1)
        // The nested send ran once; the later top-level send is a new call.
        #expect(await sends.count == 2)
    }
}

@Suite("Durable approval ledger")
struct WorkflowApprovalLedgerTests {
    @Test("a restored approval is unused again")
    func restoreReturnsApproval() async {
        let call = WorkflowApprovedCall(toolName: "delete_vm", arguments: ["id": .string("vm-1")])
        let ledger = WorkflowApprovalLedger(approved: [call])
        #expect(await ledger.consume(call))
        #expect(await ledger.unusedApprovals.isEmpty)
        await ledger.restore(call)
        #expect(await ledger.unusedApprovals == [call])
    }
}

#endif
