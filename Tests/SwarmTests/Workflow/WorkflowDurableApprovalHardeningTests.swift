import Foundation
import Testing
@testable import Swarm

// MARK: - Owned-loop provider stub

/// Provider-owned tool loop stub: calls the Agent-supplied executor for one
/// scripted tool, then answers `"done"`.
private actor ApprovalOwnedLoopProvider: InferenceProvider, MessagesFromPromptInference {
    nonisolated let capabilities: InferenceProviderCapabilities = [
        .conversationMessages,
        .nativeToolCalling,
        .providerOwnedToolLoop,
    ]

    let toolName: String
    let arguments: [String: SendableValue]

    init(toolName: String, arguments: [String: SendableValue] = [:]) {
        self.toolName = toolName
        self.arguments = arguments
    }

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        throw AgentError.generationFailed(reason: "expected generateWithToolCalls")
    }

    nonisolated func stream(
        prompt _: String,
        options _: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt _: String,
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        throw AgentError.generationFailed(reason: "expected messages seam")
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        guard let toolExecutor else {
            throw AgentError.providerOwnedToolLoopRequiresExecutor
        }
        let output = try await toolExecutor.executeTool(named: toolName, arguments: arguments)
        let toolText = Agent.toolOutputText(for: output)
        return InferenceResponse(
            content: "done",
            finishReason: .completed,
            transcriptMessages: [
                .assistant("", toolCalls: [
                    InferenceMessage.ToolCall(id: "call_owned", name: toolName, arguments: arguments),
                ]),
                .tool(name: toolName, content: toolText, toolCallID: "call_owned"),
                .assistant("done"),
            ]
        )
    }
}

#if canImport(FoundationModels)
@Suite("Foundation Models native tool runtime approval passthrough")
struct FoundationModelsNativeToolRuntimeApprovalTests {
    @Test("native tool runtime rethrows the durable approval request")
    func nativeRuntimeRethrowsApprovalRequest() async throws {
        guard #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) else { return }
        let runtime = FoundationModelsNativeToolRuntime(
            executor: ToolCallExecutor { name, arguments in
                throw WorkflowToolApprovalRequest(toolName: name, arguments: arguments)
            }
        )

        await #expect(throws: WorkflowToolApprovalRequest.self) {
            _ = try await runtime.execute(name: "delete_vm", arguments: ["id": .string("vm-1")])
        }
    }
}
#endif

#if SWARM_INTEGRATIONS

@Suite("Durable workflow tool approval hardening", .ephemeralDefaultStores)
struct WorkflowDurableApprovalHardeningTests {
    private static func makeDirectory(_ prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func expectPause(
        _ body: () async throws -> AgentResult,
        toolName: String,
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) async -> WorkflowApprovalRequired? {
        do {
            let result = try await body()
            Issue.record("expected WorkflowApprovalRequired, got result \(result.output)", sourceLocation: sourceLocation)
            return nil
        } catch let required as WorkflowApprovalRequired {
            #expect(required.toolName == toolName, sourceLocation: sourceLocation)
            return required
        } catch {
            Issue.record("expected WorkflowApprovalRequired, got \(error)", sourceLocation: sourceLocation)
            return nil
        }
    }

    // MARK: Fork composition

    @Test("fork from a checkpoint before an approval pause, then approve, completes")
    func forkBeforePauseThenApproveCompletes() async throws {
        let directory = try Self.makeDirectory("swarm-approval-fork")
        defer { try? FileManager.default.removeItem(at: directory) }

        let counter = ApprovalToolCounter()
        let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
        let provider = await MockInferenceProvider()
        await provider.configureToolCallingSequence(
            toolCalls: [("delete_vm", ["id": .string("vm-1")])],
            finalAnswer: "done"
        )
        let agent = try makeApprovalTestAgent(tools: [tool], provider: provider)
        let store = WorkflowCheckpointing.fileSystem(directory: directory)
        let source = WorkflowCheckpointID("approval-fork-source")
        let durable = Workflow()
            .step(MockAgentRuntime(response: "prepared"))
            .step(agent)
            .durable
            .configured(id: source, store: store, policy: .everyStep)

        _ = await Self.expectPause({ try await durable.execute("go") }, toolName: "delete_vm")

        let history = try await durable.inspect()
        let forkPoint = try #require(history.checkpoints.first(where: { $0.stepCursor == 1 }))
        let target = WorkflowCheckpointID("approval-fork-target")

        await provider.configureToolCallingSequence(
            toolCalls: [("delete_vm", ["id": .string("vm-1")])],
            finalAnswer: "done"
        )
        let required = await Self.expectPause(
            { try await durable.resume("go", from: target, forkingFrom: forkPoint.checkpointID) },
            toolName: "delete_vm"
        )
        #expect(required?.checkpointID == target)
        #expect(await counter.count == 0)

        await provider.configureToolCallingSequence(
            toolCalls: [("delete_vm", ["id": .string("vm-1")])],
            finalAnswer: "done"
        )
        let result = try await durable.resume(decision: .approve, from: target)
        #expect(result.output == "done")
        #expect(await counter.count == 1)
    }

    // MARK: Reject is terminal

    @Test(
        "reject is terminal: a later approve on the same checkpoint does not execute",
        arguments: [Workflow.Durable.CheckpointPolicy.everyStep, .onCompletion]
    )
    func rejectIsTerminalAndLaterApproveFails(policy: Workflow.Durable.CheckpointPolicy) async throws {
        let counter = ApprovalToolCounter()
        let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
        let provider = await MockInferenceProvider()
        await provider.configureToolCallingSequence(
            toolCalls: [("delete_vm", ["id": .string("vm-1")])],
            finalAnswer: "done"
        )
        let agent = try makeApprovalTestAgent(tools: [tool], provider: provider)
        let checkpointID = WorkflowCheckpointID("approval-reject-terminal")
        let workflow = Workflow()
            .step(agent)
            .durable
            .configured(id: checkpointID, store: .inMemory(), policy: policy)

        _ = await Self.expectPause({ try await workflow.execute("go") }, toolName: "delete_vm")
        try await Self.expectRejected { try await workflow.resume(decision: .reject, from: checkpointID) }

        await provider.configureToolCallingSequence(
            toolCalls: [("delete_vm", ["id": .string("vm-1")])],
            finalAnswer: "done"
        )
        try await Self.expectRejected { try await workflow.resume(decision: .approve, from: checkpointID) }
        #expect(await counter.count == 0)

        await provider.configureToolCallingSequence(
            toolCalls: [("delete_vm", ["id": .string("vm-1")])],
            finalAnswer: "done"
        )
        try await Self.expectRejected { try await workflow.resume("go", from: checkpointID) }
        #expect(await counter.count == 0)
    }

    @Test("reject survives a restart over the file store")
    func rejectSurvivesRestart() async throws {
        let directory = try Self.makeDirectory("swarm-approval-reject-restart")
        defer { try? FileManager.default.removeItem(at: directory) }

        let counter = ApprovalToolCounter()
        let checkpointID = WorkflowCheckpointID("approval-reject-restart")
        func makeWorkflow() async throws -> DurableWorkflow {
            let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
            let provider = await MockInferenceProvider()
            await provider.configureToolCallingSequence(
                toolCalls: [("delete_vm", ["id": .string("vm-1")])],
                finalAnswer: "done"
            )
            let agent = try makeApprovalTestAgent(tools: [tool], provider: provider)
            return Workflow()
                .step(agent)
                .durable
                .configured(id: checkpointID, store: .fileSystem(directory: directory), policy: .everyStep)
        }

        let first = try await makeWorkflow()
        _ = await Self.expectPause({ try await first.execute("go") }, toolName: "delete_vm")
        let second = try await makeWorkflow()
        try await Self.expectRejected { try await second.resume(decision: .reject, from: checkpointID) }

        let third = try await makeWorkflow()
        try await Self.expectRejected { try await third.resume(decision: .approve, from: checkpointID) }
        #expect(await counter.count == 0)
    }

    private static func expectRejected(
        sourceLocation: Testing.SourceLocation = #_sourceLocation,
        _ body: () async throws -> AgentResult
    ) async throws {
        do {
            let result = try await body()
            Issue.record("expected humanApprovalRejected, got result \(result.output)", sourceLocation: sourceLocation)
        } catch let error as WorkflowError {
            guard case .humanApprovalRejected(let prompt, _) = error else {
                Issue.record("expected humanApprovalRejected, got \(error)", sourceLocation: sourceLocation)
                return
            }
            #expect(prompt == "delete_vm", sourceLocation: sourceLocation)
        }
    }

    // MARK: Concurrent decisions

    @Test("concurrent approves on one checkpoint execute the tool once")
    func concurrentApprovesExecuteOnce() async throws {
        let counter = ApprovalToolCounter()
        let store = WorkflowCheckpointing.inMemory()
        let checkpointID = WorkflowCheckpointID("approval-concurrent")
        func makeWorkflow() async throws -> DurableWorkflow {
            let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
            let provider = await MockInferenceProvider()
            await provider.configureToolCallingSequence(
                toolCalls: [("delete_vm", ["id": .string("vm-1")])],
                finalAnswer: "done"
            )
            let agent = try makeApprovalTestAgent(tools: [tool], provider: provider)
            return Workflow()
                .step(agent)
                .durable
                .configured(id: checkpointID, store: store, policy: .everyStep)
        }

        let initial = try await makeWorkflow()
        _ = await Self.expectPause({ try await initial.execute("go") }, toolName: "delete_vm")

        let first = try await makeWorkflow()
        let second = try await makeWorkflow()
        async let firstOutcome = Self.succeeded { try await first.resume(decision: .approve, from: checkpointID) }
        async let secondOutcome = Self.succeeded { try await second.resume(decision: .approve, from: checkpointID) }
        let outcomes = await [firstOutcome, secondOutcome]

        #expect(await counter.count == 1)
        #expect(outcomes.filter(\.self).count == 1)
    }

    private static func succeeded(_ body: () async throws -> AgentResult) async -> Bool {
        do {
            _ = try await body()
            return true
        } catch {
            return false
        }
    }

    // MARK: Argument matching

    @Test("approve runs a call whose arguments carry integral doubles")
    func integralDoubleArgumentsApproveRunsOnce() async throws {
        let counter = ApprovalToolCounter()
        let tool = makeApprovalCountingTool(name: "transfer", counter: counter)
        let provider = await MockInferenceProvider()
        let script: () async -> Void = {
            await provider.configureToolCallingSequence(
                toolCalls: [("transfer", ["amount": .double(2.0)])],
                finalAnswer: "done"
            )
        }
        await script()
        let agent = try makeApprovalTestAgent(tools: [tool], provider: provider)
        let checkpointID = WorkflowCheckpointID("approval-double")
        let workflow = Workflow()
            .step(agent)
            .durable
            .configured(id: checkpointID, store: .inMemory(), policy: .everyStep)

        _ = await Self.expectPause({ try await workflow.execute("go") }, toolName: "transfer")

        await script()
        let result = try await workflow.resume(decision: .approve, from: checkpointID)
        #expect(result.output == "done")
        #expect(await counter.count == 1)
    }

    @Test("approve re-pauses when the replayed step regenerates different arguments")
    func driftingArgumentsRepauseWithNewArguments() async throws {
        let counter = ApprovalToolCounter()
        let tool = makeApprovalCountingTool(name: "transfer", counter: counter)
        let provider = await MockInferenceProvider()
        await provider.configureToolCallingSequence(
            toolCalls: [("transfer", ["amount": .int(100), "to": .string("acct-1")])],
            finalAnswer: "done"
        )
        let agent = try makeApprovalTestAgent(tools: [tool], provider: provider)
        let checkpointID = WorkflowCheckpointID("approval-drift")
        let workflow = Workflow()
            .step(agent)
            .durable
            .configured(id: checkpointID, store: .inMemory(), policy: .everyStep)

        _ = await Self.expectPause({ try await workflow.execute("go") }, toolName: "transfer")

        let drifted: [String: SendableValue] = [
            "amount": .int(100), "to": .string("acct-1"), "memo": .string("rent"),
        ]
        await provider.configureToolCallingSequence(toolCalls: [("transfer", drifted)], finalAnswer: "done")
        let required = await Self.expectPause(
            { try await workflow.resume(decision: .approve, from: checkpointID) },
            toolName: "transfer"
        )
        #expect(required?.arguments == drifted)
        #expect(await counter.count == 0)
    }

    // MARK: Catch-all wrappers

    @Test("fallback step pauses instead of retrying or falling back")
    func fallbackStepPausesInsteadOfFallingBack() async throws {
        let counter = ApprovalToolCounter()
        let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
        let provider = await MockInferenceProvider()
        let script: () async -> Void = {
            await provider.configureToolCallingSequence(
                toolCalls: [("delete_vm", ["id": .string("vm-1")])],
                finalAnswer: "primary done"
            )
        }
        await script()
        let primary = try makeApprovalTestAgent(tools: [tool], provider: provider)
        let backupProvider = await MockInferenceProvider()
        await backupProvider.configureToolCallingSequence(finalAnswer: "backup")
        let backup = try makeApprovalTestAgent(tools: [], provider: backupProvider)
        let observer = ApprovalRecordingObserver()
        let checkpointID = WorkflowCheckpointID("approval-fallback")
        let workflow = Workflow()
            .fallback(primary: primary, to: backup, retries: 2)
            .observed(by: observer)
            .durable
            .configured(id: checkpointID, store: .inMemory(), policy: .everyStep)

        _ = await Self.expectPause({ try await workflow.execute("go") }, toolName: "delete_vm")
        #expect(await backupProvider.recordedInferenceCallCount == 0)
        #expect(await observer.recorded.count == 1)
        #expect(await counter.count == 0)

        await script()
        let result = try await workflow.resume(decision: .approve, from: checkpointID)
        #expect(result.output == "primary done")
        #expect(await counter.count == 1)
        #expect(await backupProvider.recordedInferenceCallCount == 0)
    }

    @Test("nested agent tool pauses the outer durable step", arguments: [false, true])
    func nestedAgentToolPauses(stopOnToolError: Bool) async throws {
        let counter = ApprovalToolCounter()
        let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
        let innerProvider = await MockInferenceProvider()
        let outerProvider = await MockInferenceProvider()
        let script: () async -> Void = {
            await innerProvider.configureToolCallingSequence(
                toolCalls: [("delete_vm", ["id": .string("vm-1")])],
                finalAnswer: "inner done"
            )
            await outerProvider.configureToolCallingSequence(
                toolCalls: [("inner_agent", ["input": .string("tear down")])],
                finalAnswer: "outer done"
            )
        }
        await script()
        let inner = try makeApprovalTestAgent(tools: [tool], provider: innerProvider)
        let outer = try Agent(
            tools: [inner.asTool(name: "inner_agent")],
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .timeout(.seconds(30))
                .stopOnToolError(stopOnToolError)
                .defaultTracingEnabled(false),
            inferenceProvider: outerProvider
        )
        let checkpointID = WorkflowCheckpointID("approval-nested-\(stopOnToolError)")
        let workflow = Workflow()
            .step(outer)
            .durable
            .configured(id: checkpointID, store: .inMemory(), policy: .everyStep)

        _ = await Self.expectPause({ try await workflow.execute("go") }, toolName: "delete_vm")
        #expect(await counter.count == 0)

        await script()
        let result = try await workflow.resume(decision: .approve, from: checkpointID)
        #expect(result.output == "outer done")
        #expect(await counter.count == 1)
    }

    // MARK: Provider-owned tool loop

    @Test("provider-owned tool loop pauses and approve runs the tool once")
    func ownedLoopProviderPauses() async throws {
        let counter = ApprovalToolCounter()
        let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
        let provider = ApprovalOwnedLoopProvider(toolName: "delete_vm", arguments: ["id": .string("vm-1")])
        let agent = try Agent(
            tools: [tool],
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .timeout(.seconds(30))
                .defaultTracingEnabled(false),
            inferenceProvider: provider
        )
        let checkpointID = WorkflowCheckpointID("approval-owned-loop")
        let workflow = Workflow()
            .step(agent)
            .durable
            .configured(id: checkpointID, store: .inMemory(), policy: .everyStep)

        _ = await Self.expectPause({ try await workflow.execute("go") }, toolName: "delete_vm")
        #expect(await counter.count == 0)

        let result = try await workflow.resume(decision: .approve, from: checkpointID)
        #expect(result.output == "done")
        #expect(await counter.count == 1)
    }
}

#endif
