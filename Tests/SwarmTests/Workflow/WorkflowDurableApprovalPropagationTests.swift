import Foundation
import Testing
@testable import Swarm

// Durable approval pauses travel as `WorkflowToolApprovalRequest` errors from
// the tool gate up to the durable node. Every catch-all between the two must
// rethrow them untouched; otherwise the human is never asked and the run
// continues down a recovery path (backup agent, retry, tool failure).

@Suite("Durable approval pause propagation through resilience wrappers")
struct WorkflowDurableApprovalResiliencePropagationTests {
    @Test("RetryPolicy rethrows an approval pause without retrying")
    func retryPolicyDoesNotRetryApprovalPause() async throws {
        let counter = ApprovalToolCounter()
        let policy = RetryPolicy(maxAttempts: 3, backoff: .immediate)

        await #expect(throws: WorkflowToolApprovalRequest.self) {
            try await policy.execute { () async throws -> String in
                await counter.increment()
                throw WorkflowToolApprovalRequest(toolName: "delete_vm", arguments: [:])
            }
        }
        #expect(await counter.count == 1)
    }

    @Test("FallbackChain rethrows an approval pause without running later steps")
    func fallbackChainDoesNotFallBackOnApprovalPause() async throws {
        let counter = ApprovalToolCounter()
        let chain = FallbackChain<String>()
            .attempt(name: "primary") {
                throw WorkflowToolApprovalRequest(toolName: "delete_vm", arguments: [:])
            }
            .attempt(name: "backup") {
                await counter.increment()
                return "backup"
            }

        await #expect(throws: WorkflowToolApprovalRequest.self) {
            _ = try await chain.execute()
        }
        #expect(await counter.count == 0)
    }
}

/// Records tool lifecycle callbacks in arrival order.
private actor ToolLifecycleRecorder: AgentObserver {
    enum Entry: Equatable {
        case started(String)
        case ended(String, isSuccess: Bool)
        case approvalRequested(String)
    }

    private(set) var entries: [Entry] = []

    func onToolStart(context _: AgentContext?, agent _: any AgentRuntime, call: ToolCall) async {
        entries.append(.started(call.toolName))
    }

    func onToolEnd(context _: AgentContext?, agent _: any AgentRuntime, invocation: ToolInvocation) async {
        entries.append(.ended(invocation.call.toolName, isSuccess: invocation.result.isSuccess))
    }

    func onToolApprovalRequested(context _: AgentContext?, agent _: any AgentRuntime, call: ToolCall) async {
        entries.append(.approvalRequested(call.toolName))
    }
}

@Suite("Durable approval pause through agent-as-tool observability")
struct WorkflowDurableApprovalAgentToolObservabilityTests {
    @Test("agent-as-tool pause pairs the outer tool start with a non-failure end and closes its span")
    func agentToolPauseClosesOuterToolCall() async throws {
        let counter = ApprovalToolCounter()
        let innerProvider = await MockInferenceProvider()
        await innerProvider.configureToolCallingSequence(
            toolCalls: [("delete_vm", ["id": .string("vm-1")])],
            finalAnswer: "inner-done"
        )
        let inner = try makeApprovalTestAgent(
            tools: [makeApprovalCountingTool(name: "delete_vm", counter: counter)],
            provider: innerProvider
        )
        let registry = ToolRegistry()
        try await registry.register(inner.asTool(name: "operator", description: "Runs operations"))
        let recorder = ToolLifecycleRecorder()
        let tracer = SpyTracer()

        await #expect(throws: WorkflowToolApprovalRequest.self) {
            try await WorkflowDurableApprovalGate.$ledger.withValue(WorkflowApprovalLedger(approved: [])) {
                _ = try await ToolExecutionEngine().execute(
                    toolName: "operator",
                    arguments: ["input": .string("delete vm-1")],
                    registry: registry,
                    agent: MockAgentRuntime(response: "outer"),
                    context: nil,
                    resultBuilder: AgentResult.Builder(),
                    observer: recorder,
                    tracing: TracingHelper(tracer: tracer, agentName: "outer"),
                    stopOnToolError: false
                )
            }
        }

        #expect(await counter.count == 0)
        #expect(await recorder.entries == [
            .started("operator"),
            .approvalRequested("delete_vm"),
            .ended("operator", isSuccess: true)
        ])
        let events = await tracer.tracedEvents
        let started = try #require(events.first { $0.kind == .toolCall && $0.toolName == "operator" })
        #expect(events.contains { $0.kind == .toolResult && $0.spanId == started.spanId })
        #expect(!events.contains { $0.kind == .toolError })
    }
}

#if SWARM_INTEGRATIONS

@Suite("Durable approval pause propagation through workflow combinators", .ephemeralDefaultStores)
struct WorkflowDurableApprovalPropagationTests {
    @Test(".fallback pauses for approval instead of retrying or running the backup")
    func fallbackPausesInsteadOfRunningBackup() async throws {
        let counter = ApprovalToolCounter()
        let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
        let provider = await MockInferenceProvider()
        await provider.configureToolCallingSequence(
            toolCalls: [("delete_vm", ["id": .string("vm-1")])],
            finalAnswer: "primary-done"
        )
        let primary = try makeApprovalTestAgent(tools: [tool], provider: provider)
        let backup = MockAgentRuntime(response: "backup-done")
        let checkpointID = WorkflowCheckpointID("approval-fallback")
        let workflow = Workflow()
            .fallback(primary: primary, to: backup, retries: 2)
            .durable
            .configured(id: checkpointID, store: .inMemory(), policy: .everyStep)

        do {
            let result = try await workflow.execute("go")
            Issue.record("expected WorkflowApprovalRequired, got output \(result.output)")
        } catch let required as WorkflowApprovalRequired {
            #expect(required.toolName == "delete_vm")
        }
        #expect(await counter.count == 0)

        await provider.configureToolCallingSequence(
            toolCalls: [("delete_vm", ["id": .string("vm-1")])],
            finalAnswer: "primary-done"
        )
        let result = try await workflow.resume(decision: .approve, from: checkpointID)
        #expect(result.output == "primary-done")
        #expect(result.metadata[.fallbackUsed] == nil)
        #expect(await counter.count == 1)
    }

    @Test("agent-as-tool surfaces the nested approval instead of a tool failure")
    func agentToolSurfacesNestedApproval() async throws {
        let counter = ApprovalToolCounter()
        let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
        let innerProvider = await MockInferenceProvider()
        let outerProvider = await MockInferenceProvider()
        let script: () async -> Void = {
            await innerProvider.configureToolCallingSequence(
                toolCalls: [("delete_vm", ["id": .string("vm-1")])],
                finalAnswer: "inner-done"
            )
            await outerProvider.configureToolCallingSequence(
                toolCalls: [("operator", ["input": .string("delete vm-1")])],
                finalAnswer: "outer-done"
            )
        }
        await script()
        let inner = try makeApprovalTestAgent(tools: [tool], provider: innerProvider)
        let outer = try makeApprovalTestAgent(
            tools: [inner.asTool(name: "operator", description: "Runs operations")],
            provider: outerProvider
        )
        let checkpointID = WorkflowCheckpointID("approval-agent-tool")
        let workflow = Workflow()
            .step(outer)
            .durable
            .configured(id: checkpointID, store: .inMemory(), policy: .everyStep)

        do {
            let result = try await workflow.execute("go")
            Issue.record("expected WorkflowApprovalRequired, got output \(result.output)")
        } catch let required as WorkflowApprovalRequired {
            #expect(required.toolName == "delete_vm")
        }
        #expect(await counter.count == 0)

        await script()
        let result = try await workflow.resume(decision: .approve, from: checkpointID)
        #expect(result.output == "outer-done")
        #expect(await counter.count == 1)
    }

    @Test("handoff surfaces the target's approval instead of a tool failure")
    func handoffSurfacesTargetApproval() async throws {
        let counter = ApprovalToolCounter()
        let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
        let targetProvider = await MockInferenceProvider()
        let sourceProvider = await MockInferenceProvider()
        let script: () async -> Void = {
            await targetProvider.configureToolCallingSequence(
                toolCalls: [("delete_vm", ["id": .string("vm-1")])],
                finalAnswer: "target-done"
            )
            await sourceProvider.configureToolCallingSequence(
                toolCalls: [("handoff_to_ops", ["reason": .string("needs ops")])],
                finalAnswer: "source-done"
            )
        }
        await script()
        let target = try makeApprovalTestAgent(tools: [tool], provider: targetProvider)
        let source = try Agent(
            tools: [],
            instructions: "Hand off operations.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            inferenceProvider: sourceProvider,
            handoffs: [AnyHandoffConfiguration(HandoffConfiguration(
                targetAgent: target,
                toolNameOverride: "handoff_to_ops"
            ))]
        )
        let checkpointID = WorkflowCheckpointID("approval-handoff")
        let workflow = Workflow()
            .step(source)
            .durable
            .configured(id: checkpointID, store: .inMemory(), policy: .everyStep)

        do {
            let result = try await workflow.execute("go")
            Issue.record("expected WorkflowApprovalRequired, got output \(result.output)")
        } catch let required as WorkflowApprovalRequired {
            #expect(required.toolName == "delete_vm")
        }
        #expect(await counter.count == 0)

        await script()
        let result = try await workflow.resume(decision: .approve, from: checkpointID)
        #expect(result.output == "target-done")
        #expect(await counter.count == 1)
    }
}

#endif
