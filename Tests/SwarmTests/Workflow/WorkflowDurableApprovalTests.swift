import Foundation
import Testing
@testable import Swarm

// MARK: - Shared helpers (all builds)

/// Counts tool executions across task boundaries.
actor ApprovalToolCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

func makeApprovalCountingTool(
    name: String,
    counter: ApprovalToolCounter,
    output: String = "ok"
) -> FunctionTool {
    FunctionTool(
        name: name,
        description: "Approval-gated test tool",
        executionSemantics: ToolExecutionSemantics(approvalRequirement: .always)
    ) { _ in
        await counter.increment()
        return .string(output)
    }
}

func makeApprovalTestAgent(
    tools: [any AnyJSONTool],
    provider: MockInferenceProvider
) throws -> Agent {
    try Agent(
        tools: tools,
        configuration: AgentConfiguration.default
            .enableStreaming(false)
            .timeout(.seconds(30))
            .defaultTracingEnabled(false),
        inferenceProvider: provider
    )
}

/// Records `onToolApprovalRequested` callbacks.
final class ApprovalRecordingObserver: AgentObserver, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [ToolCall] = []

    var recorded: [ToolCall] {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func onToolApprovalRequested(
        context _: AgentContext?,
        agent _: any AgentRuntime,
        call: ToolCall
    ) async {
        lock.lock()
        defer { lock.unlock() }
        calls.append(call)
    }
}

@Suite("Durable approval event surface")
struct WorkflowDurableApprovalEventTests {
    @Test("approval request maps onto the AgentEvent tool stream")
    func approvalRequestedMapsToAgentEventStream() async throws {
        let (stream, continuation) = AsyncThrowingStream<AgentEvent, Error>.makeStream()
        let observer = EventStreamObserver(continuation: continuation)
        let call = ToolCall(toolName: "delete_vm", arguments: ["id": .string("vm-1")])

        await observer.onToolApprovalRequested(context: nil, agent: MockAgentRuntime(response: "ok"), call: call)
        continuation.finish()

        var events: [AgentEvent] = []
        for try await event in stream {
            events.append(event)
        }
        #expect(events == [.tool(.approvalRequested(call: call))])
    }

    @Test("direct agent runs do not gate approval-required tools")
    func directAgentRunDoesNotGateApprovalTools() async throws {
        // The durable gate lives below Agent.run on the durable path only;
        // direct runs execute approval-required tools without throwing.
        let counter = ApprovalToolCounter()
        let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
        let provider = await MockInferenceProvider()
        await provider.configureToolCallingSequence(
            toolCalls: [("delete_vm", ["id": .string("vm-1")])],
            finalAnswer: "done"
        )
        let agent = try makeApprovalTestAgent(tools: [tool], provider: provider)

        let result = try await agent.run("go")

        #expect(result.output == "done")
        #expect(await counter.count == 1)
    }
}

#if SWARM_INTEGRATIONS

@Suite("Durable workflow tool approvals")
struct WorkflowDurableApprovalTests {
    @Test("approve resumes and executes the tool exactly once")
    func approveResumesAndExecutesExactlyOnce() async throws {
        let counter = ApprovalToolCounter()
        let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
        let provider = await MockInferenceProvider()
        await provider.configureToolCallingSequence(
            toolCalls: [("delete_vm", ["id": .string("vm-1")])],
            finalAnswer: "done"
        )
        let agent = try makeApprovalTestAgent(tools: [tool], provider: provider)
        let checkpointID = WorkflowCheckpointID("approval-once")
        let workflow = Workflow()
            .step(agent)
            .durable
            .configured(id: checkpointID, store: .inMemory(), policy: .everyStep)

        do {
            _ = try await workflow.execute("go")
            Issue.record("expected WorkflowApprovalRequired")
        } catch let required as WorkflowApprovalRequired {
            #expect(required.toolName == "delete_vm")
            #expect(required.arguments == ["id": .string("vm-1")])
            #expect(required.stepCursor == 0)
            #expect(required.checkpointID == checkpointID)
            #expect(!required.interruptID.isEmpty)
        }
        #expect(await counter.count == 0)

        await provider.configureToolCallingSequence(
            toolCalls: [("delete_vm", ["id": .string("vm-1")])],
            finalAnswer: "done"
        )
        let result = try await workflow.resume(decision: .approve, from: checkpointID)

        #expect(result.output == "done")
        #expect(await counter.count == 1)
    }

    @Test("reject fails without executing the tool")
    func rejectFailsWithoutExecuting() async throws {
        let counter = ApprovalToolCounter()
        let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
        let provider = await MockInferenceProvider()
        await provider.configureToolCallingSequence(
            toolCalls: [("delete_vm", ["id": .string("vm-1")])],
            finalAnswer: "done"
        )
        let agent = try makeApprovalTestAgent(tools: [tool], provider: provider)
        let checkpointID = WorkflowCheckpointID("approval-reject")
        let workflow = Workflow()
            .step(agent)
            .durable
            .configured(id: checkpointID, store: .inMemory(), policy: .everyStep)

        do {
            _ = try await workflow.execute("go")
            Issue.record("expected WorkflowApprovalRequired")
        } catch is WorkflowApprovalRequired {
        }

        do {
            _ = try await workflow.resume(decision: .reject, from: checkpointID)
            Issue.record("expected humanApprovalRejected")
        } catch let error as WorkflowError {
            guard case .humanApprovalRejected(let prompt, _) = error else {
                Issue.record("expected humanApprovalRejected, got \(error)")
                return
            }
            #expect(prompt == "delete_vm")
        }
        #expect(await counter.count == 0)
    }

    @Test("restart while paused resumes from disk and executes once")
    func restartWhilePausedResumesFromDisk() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-approval-restart-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let counter = ApprovalToolCounter()
        let checkpointID = WorkflowCheckpointID("approval-restart")

        // First handle pauses and is dropped; only the directory survives.
        do {
            let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
            let provider = await MockInferenceProvider()
            await provider.configureToolCallingSequence(
                toolCalls: [("delete_vm", ["id": .string("vm-1")])],
                finalAnswer: "done"
            )
            let agent = try makeApprovalTestAgent(tools: [tool], provider: provider)
            let workflow = Workflow()
                .step(agent)
                .durable
                .configured(id: checkpointID, store: .fileSystem(directory: directory), policy: .everyStep)
            do {
                _ = try await workflow.execute("go")
                Issue.record("expected WorkflowApprovalRequired")
            } catch is WorkflowApprovalRequired {
            }
        }
        #expect(await counter.count == 0)

        // Fresh handles over the same directory approve and complete.
        let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
        let provider = await MockInferenceProvider()
        await provider.configureToolCallingSequence(
            toolCalls: [("delete_vm", ["id": .string("vm-1")])],
            finalAnswer: "done"
        )
        let agent = try makeApprovalTestAgent(tools: [tool], provider: provider)
        let workflow = Workflow()
            .step(agent)
            .durable
            .configured(id: checkpointID, store: .fileSystem(directory: directory), policy: .everyStep)
        let result = try await workflow.resume(decision: .approve, from: checkpointID)

        #expect(result.output == "done")
        #expect(await counter.count == 1)
    }

    @Test("resumed step pauses again for a different approval-required tool")
    func resumedStepPausesAgainForDifferentTool() async throws {
        let counterA = ApprovalToolCounter()
        let counterB = ApprovalToolCounter()
        let toolA = makeApprovalCountingTool(name: "tool_a", counter: counterA, output: "a-ok")
        let toolB = makeApprovalCountingTool(name: "tool_b", counter: counterB, output: "b-ok")
        let provider = await MockInferenceProvider()
        let script: () async -> Void = {
            await provider.configureToolCallingSequence(
                toolCalls: [("tool_a", [:]), ("tool_b", [:])],
                finalAnswer: "done"
            )
        }
        await script()
        let agent = try makeApprovalTestAgent(tools: [toolA, toolB], provider: provider)
        let checkpointID = WorkflowCheckpointID("approval-chain")
        let workflow = Workflow()
            .step(agent)
            .durable
            .configured(id: checkpointID, store: .inMemory(), policy: .everyStep)

        do {
            _ = try await workflow.execute("go")
            Issue.record("expected WorkflowApprovalRequired")
        } catch let required as WorkflowApprovalRequired {
            #expect(required.toolName == "tool_a")
        }

        await script()
        do {
            _ = try await workflow.resume(decision: .approve, from: checkpointID)
            Issue.record("expected second WorkflowApprovalRequired")
        } catch let required as WorkflowApprovalRequired {
            #expect(required.toolName == "tool_b")
        }
        #expect(await counterA.count == 1)
        #expect(await counterB.count == 0)

        // Step-granularity replay re-executes already-approved tools; B still runs once.
        await script()
        let result = try await workflow.resume(decision: .approve, from: checkpointID)
        #expect(result.output == "done")
        #expect(await counterA.count == 2)
        #expect(await counterB.count == 1)
    }

    @Test("approval request notifies the workflow observer")
    func approvalRequestNotifiesObserver() async throws {
        let counter = ApprovalToolCounter()
        let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
        let provider = await MockInferenceProvider()
        await provider.configureToolCallingSequence(
            toolCalls: [("delete_vm", ["id": .string("vm-1")])],
            finalAnswer: "done"
        )
        let agent = try makeApprovalTestAgent(tools: [tool], provider: provider)
        let observer = ApprovalRecordingObserver()
        let checkpointID = WorkflowCheckpointID("approval-observer")
        let workflow = Workflow()
            .step(agent)
            .observed(by: observer)
            .durable
            .configured(id: checkpointID, store: .inMemory(), policy: .everyStep)

        do {
            _ = try await workflow.execute("go")
            Issue.record("expected WorkflowApprovalRequired")
        } catch is WorkflowApprovalRequired {
        }

        let recorded = observer.recorded
        #expect(recorded.count == 1)
        #expect(recorded.first?.toolName == "delete_vm")
        #expect(recorded.first?.arguments == ["id": .string("vm-1")])
    }

    @Test("approval envelopes round-trip and reject unknown versions")
    func approvalEnvelopesRoundTrip() throws {
        let request = WorkflowApprovalRequestEnvelope(
            toolName: "delete_vm",
            arguments: ["id": .string("vm-1")],
            stepCursor: 2,
            approved: [WorkflowApprovedCall(toolName: "earlier", arguments: [:])]
        )
        let requestString = try request.encoded()
        let decodedRequest = try WorkflowApprovalRequestEnvelope.decoded(from: requestString)
        #expect(decodedRequest == request)

        let decision = WorkflowApprovalDecisionEnvelope(
            decision: .approve,
            toolName: "delete_vm",
            arguments: ["id": .string("vm-1")],
            approved: [WorkflowApprovedCall(toolName: "delete_vm", arguments: ["id": .string("vm-1")])]
        )
        let decisionString = try decision.encoded()
        let decodedDecision = try WorkflowApprovalDecisionEnvelope.decoded(from: decisionString)
        #expect(decodedDecision == decision)

        #expect(throws: WorkflowError.self) {
            _ = try WorkflowApprovalRequestEnvelope.decoded(from: #"{"version":99,"kind":"swarm.toolApprovalRequest"}"#)
        }
        #expect(throws: WorkflowError.self) {
            _ = try WorkflowApprovalDecisionEnvelope.decoded(from: #"{"version":1,"kind":"swarm.somethingElse"}"#)
        }
        #expect(throws: WorkflowError.self) {
            _ = try WorkflowApprovalRequestEnvelope.decoded(from: "not json")
        }
    }

    @Test("approval resume without a checkpoint throws checkpointNotFound")
    func approvalResumeWithoutCheckpointThrows() async throws {
        let agent = MockAgentRuntime(response: "ok")
        let workflow = Workflow()
            .step(agent)
            .durable
            .configured(id: WorkflowCheckpointID("approval-missing"), store: .inMemory())

        await #expect(throws: WorkflowError.checkpointNotFound(id: "approval-missing")) {
            _ = try await workflow.resume(
                decision: .approve,
                from: WorkflowCheckpointID("approval-missing")
            )
        }
    }
}

/// Real process-kill/restart E2E hook, driven by an external script (never CI).
///
/// Phase 1 pauses on approval, writes a marker, then sleeps until the driver
/// SIGKILLs the process. Phase 2 runs in a fresh process and approves.
/// The tool handler appends to a file so exactly-once is observable across
/// processes. Enabled only when `SWARM_APPROVAL_E2E_PHASE` is set.
@Suite(
    "Durable approval kill/restart E2E",
    .enabled(if: ProcessInfo.processInfo.environment["SWARM_APPROVAL_E2E_PHASE"] != nil)
)
struct WorkflowDurableApprovalKillRestartTests {
    @Test("kill/restart phase")
    func killRestartPhase() async throws {
        let environment = ProcessInfo.processInfo.environment
        let phase = try #require(environment["SWARM_APPROVAL_E2E_PHASE"])
        let directory = try #require(environment["SWARM_APPROVAL_E2E_DIR"])
        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        let logURL = directoryURL.appendingPathComponent("tool-calls.log")
        let checkpointID = WorkflowCheckpointID("approval-kill-restart")

        let tool = FunctionTool(
            name: "delete_vm",
            description: "Approval-gated kill-restart tool",
            executionSemantics: ToolExecutionSemantics(approvalRequirement: .always)
        ) { _ in
            let line = "executed\n"
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try Data(line.utf8).write(to: logURL)
            }
            return .string("ok")
        }
        let provider = await MockInferenceProvider()
        await provider.configureToolCallingSequence(
            toolCalls: [("delete_vm", ["id": .string("vm-1")])],
            finalAnswer: "done"
        )
        let agent = try makeApprovalTestAgent(tools: [tool], provider: provider)
        let workflow = Workflow()
            .step(agent)
            .durable
            .configured(id: checkpointID, store: .fileSystem(directory: directoryURL), policy: .everyStep)

        if phase == "1" {
            do {
                _ = try await workflow.execute("go")
                Issue.record("expected WorkflowApprovalRequired")
            } catch is WorkflowApprovalRequired {
            }
            try Data("paused".utf8).write(to: directoryURL.appendingPathComponent("paused.marker"))
            try await Task.sleep(for: .seconds(180))
        } else if phase == "2" {
            let result = try await workflow.resume(decision: .approve, from: checkpointID)
            #expect(result.output == "done")
            let log = try String(contentsOf: logURL, encoding: .utf8)
            #expect(log.components(separatedBy: "\n").filter { !$0.isEmpty }.count == 1)
        } else {
            Issue.record("unknown SWARM_APPROVAL_E2E_PHASE: \(phase)")
        }
    }
}

#else

@Suite("Durable approval lean gating")
struct WorkflowDurableApprovalLeanTests {
    @Test("approval resume throws durableRuntimeUnavailable on lean builds")
    func approvalResumeThrowsOnLean() async throws {
        let agent = MockAgentRuntime(response: "ok")
        let workflow = Workflow()
            .step(agent)
            .durable
            .configured(id: WorkflowCheckpointID("approval-lean"), store: .inMemory())

        do {
            _ = try await workflow.resume(decision: .approve, from: WorkflowCheckpointID("approval-lean"))
            Issue.record("expected durableRuntimeUnavailable")
        } catch let error as WorkflowError {
            guard case .durableRuntimeUnavailable = error else {
                Issue.record("expected durableRuntimeUnavailable, got \(error)")
                return
            }
        }
    }
}

#endif
