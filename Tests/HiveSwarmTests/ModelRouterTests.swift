#if SWARM_INTEGRATIONS
// ModelRouterTests.swift
// HiveSwarm
//
// Tests for model router wiring through OrchestrationHiveEngine and GraphAgent.

import Foundation
import Testing
import HiveCore
@_spi(ColonyInternal) @testable import Swarm

@Suite("Model Router Wiring")
struct ModelRouterTests {

    // MARK: - Model Router Routes Requests via HiveEnvironment

    @Test("Model router is used when set on HiveEnvironment")
    func modelRouter_isUsed_whenSetOnEnvironment() async throws {
        let graph = try ChatGraph.makeToolUsingChatAgent()
        let context = RuntimeContext(modelName: "test-model", toolApprovalPolicy: .never)

        let routedClient = CapturingModelClient(
            chunks: [.final(HiveChatResponse(message: assistantMessage(id: "m1", content: "routed")))]
        )
        let router = StaticModelRouter(client: AnyHiveModelClient(routedClient))

        let environment = HiveEnvironment<ChatGraph.Schema>(
            context: context,
            clock: TestClock(),
            logger: TestLogger(),
            model: nil,
            modelRouter: router,
            tools: AnyHiveToolRegistry(EmptyToolRegistry()),
            checkpointStore: nil
        )

        let runtime = try HiveRuntime(graph: graph, environment: environment)
        let handle = await runtime.run(
            threadID: HiveThreadID("router-test"),
            input: "Hello",
            options: HiveRunOptions(maxSteps: 5, checkpointPolicy: .disabled)
        )

        let outcome = try await handle.outcome.value
        let store = try extractFullStore(outcome: outcome)
        let finalAnswer = try store.get(ChatGraph.Schema.finalAnswerKey)

        #expect(finalAnswer == "routed")
        #expect(await routedClient.streamCallCount == 1, "Router-provided client should have been called")
    }

    @Test("Model router takes precedence over direct model client")
    func modelRouter_takesPrecedence_overDirectModel() async throws {
        let graph = try ChatGraph.makeToolUsingChatAgent()
        let context = RuntimeContext(modelName: "test-model", toolApprovalPolicy: .never)

        let routedClient = CapturingModelClient(
            chunks: [.final(HiveChatResponse(message: assistantMessage(id: "m1", content: "from-router")))]
        )
        let directClient = CapturingModelClient(
            chunks: [.final(HiveChatResponse(message: assistantMessage(id: "m2", content: "from-direct")))]
        )
        let router = StaticModelRouter(client: AnyHiveModelClient(routedClient))

        let environment = HiveEnvironment<ChatGraph.Schema>(
            context: context,
            clock: TestClock(),
            logger: TestLogger(),
            model: AnyHiveModelClient(directClient),
            modelRouter: router,
            tools: AnyHiveToolRegistry(EmptyToolRegistry()),
            checkpointStore: nil
        )

        let runtime = try HiveRuntime(graph: graph, environment: environment)
        let handle = await runtime.run(
            threadID: HiveThreadID("precedence-test"),
            input: "Hello",
            options: HiveRunOptions(maxSteps: 5, checkpointPolicy: .disabled)
        )

        let outcome = try await handle.outcome.value
        let store = try extractFullStore(outcome: outcome)
        let finalAnswer = try store.get(ChatGraph.Schema.finalAnswerKey)

        #expect(finalAnswer == "from-router")
        #expect(await routedClient.streamCallCount == 1, "Router client should be used")
        #expect(await directClient.streamCallCount == 0, "Direct client should NOT be used when router is present")
    }

    // MARK: - OrchestrationHiveEngine Wiring (removed — OrchestrationHiveEngine deleted in API redesign)

    // MARK: - GraphAgent with Model Router

    @Test("GraphAgent works when environment has modelRouter but no direct model")
    func hiveBackedAgent_worksWithModelRouterOnly() async throws {
        let graph = try ChatGraph.makeToolUsingChatAgent()
        let context = RuntimeContext(modelName: "test-model", toolApprovalPolicy: .never)

        let routedClient = CapturingModelClient(
            chunks: [.final(HiveChatResponse(message: assistantMessage(id: "m1", content: "agent-routed")))]
        )
        let router = StaticModelRouter(client: AnyHiveModelClient(routedClient))

        let environment = HiveEnvironment<ChatGraph.Schema>(
            context: context,
            clock: TestClock(),
            logger: TestLogger(),
            model: nil,
            modelRouter: router,
            tools: AnyHiveToolRegistry(EmptyToolRegistry()),
            checkpointStore: nil
        )

        let runtime = try HiveRuntime(graph: graph, environment: environment)
        let hiveRuntime = GraphRuntimeAdapter(runControl: GraphRunController(runtime: runtime))
        let agent = GraphAgent(runtime: hiveRuntime, name: "router-agent")

        let result = try await agent.run("Hello")
        #expect(result.output == "agent-routed")
        #expect(await routedClient.streamCallCount == 1)
    }

    // MARK: - Preflight Validation

    @Test("Preflight passes when modelRouter is set but model is nil")
    func preflight_passes_withModelRouterOnly() async throws {
        let graph = try ChatGraph.makeToolUsingChatAgent()
        let context = RuntimeContext(modelName: "test-model", toolApprovalPolicy: .never)

        let routedClient = CapturingModelClient(
            chunks: [.final(HiveChatResponse(message: assistantMessage(id: "m1", content: "ok")))]
        )
        let router = StaticModelRouter(client: AnyHiveModelClient(routedClient))

        let environment = HiveEnvironment<ChatGraph.Schema>(
            context: context,
            clock: TestClock(),
            logger: TestLogger(),
            model: nil,
            modelRouter: router,
            tools: AnyHiveToolRegistry(EmptyToolRegistry()),
            checkpointStore: nil
        )

        let runtime = try HiveRuntime(graph: graph, environment: environment)
        let runControl = GraphRunController(runtime: runtime)

        // Should not throw — modelRouter satisfies the model requirement
        let handle = try await runControl.start(
            threadID: HiveThreadID("preflight-test"),
            input: "Hello",
            options: HiveRunOptions(maxSteps: 5, checkpointPolicy: .disabled)
        )
        let outcome = try await handle.outcome.value

        switch outcome {
        case .finished:
            break // Success path
        default:
            Issue.record("Expected finished outcome, got \(outcome)")
        }
    }
}

// MARK: - Test Doubles

/// A model client that captures invocations for verification.
private actor CapturingModelClient: HiveModelClient {
    let chunks: [HiveChatStreamChunk]
    private(set) var streamCallCount: Int = 0
    private(set) var completeCallCount: Int = 0

    init(chunks: [HiveChatStreamChunk]) {
        self.chunks = chunks
    }

    nonisolated func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        await incrementCompleteCount()
        for chunk in await getChunks() {
            if case let .final(response) = chunk { return response }
        }
        throw SwarmRuntimeError.modelStreamInvalid("Missing final chunk.")
    }

    nonisolated func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { [self] continuation in
            Task {
                await self.incrementStreamCount()
                let chunks = await self.getChunks()
                for chunk in chunks { continuation.yield(chunk) }
                continuation.finish()
            }
        }
    }

    private func incrementStreamCount() { streamCallCount += 1 }
    private func incrementCompleteCount() { completeCallCount += 1 }
    private func getChunks() -> [HiveChatStreamChunk] { chunks }
}

/// A model router that always returns the same client.
private struct StaticModelRouter: HiveModelRouter {
    let client: AnyHiveModelClient

    func route(_ request: HiveChatRequest, hints: HiveInferenceHints?) -> AnyHiveModelClient {
        client
    }
}

/// A tool registry with no tools.
private struct EmptyToolRegistry: HiveToolRegistry, Sendable {
    func listTools() -> [HiveToolDefinition] { [] }
    func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        HiveToolResult(toolCallID: call.id, content: "")
    }
}

// TransformStep removed — OrchestrationStep protocol deleted in API redesign.

private struct TestClock: HiveClock {
    func nowNanoseconds() -> UInt64 { 0 }
    func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(for: .nanoseconds(nanoseconds))
    }
}

private struct TestLogger: HiveLogger {
    func debug(_ message: String, metadata: [String: String]) {}
    func info(_ message: String, metadata: [String: String]) {}
    func error(_ message: String, metadata: [String: String]) {}
}

// MARK: - Helpers

private func assistantMessage(id: String, content: String) -> HiveChatMessage {
    HiveChatMessage(
        id: id,
        role: .assistant,
        content: content,
        toolCalls: [],
        op: nil
    )
}

private func extractFullStore<Schema: HiveSchema>(
    outcome: HiveRunOutcome<Schema>
) throws -> HiveGlobalStore<Schema> {
    switch outcome {
    case let .finished(output, _),
         let .cancelled(output, _),
         let .outOfSteps(_, output, _):
        switch output {
        case let .fullStore(store):
            return store
        case .channels:
            throw TestError("Expected full store output.")
        }
    case .interrupted:
        throw TestError("Expected finished/cancelled/outOfSteps, got interrupted.")
    }
}

private struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
#endif
