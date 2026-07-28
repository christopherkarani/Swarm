#if SWARM_INTEGRATIONS
// HiveBackedAgentStreamingTests.swift
// HiveSwarm
//
// Tests for the streaming event bridge in GraphAgent.

import Foundation
import HiveCore
@_spi(ColonyInternal) @testable import Swarm
import Testing

@Suite("GraphAgent streaming event bridge")
struct HiveBackedAgentStreamingTests {

    @Test("stream yields outputToken events for model tokens")
    func stream_yieldsOutputTokens() async throws {
        let chunks: [HiveChatStreamChunk] = [
            .token("Hello"),
            .token(" world"),
            .final(HiveChatResponse(message: assistantMsg(id: "m1", content: "Hello world")))
        ]
        let agent = try makeAgent(modelChunks: chunks)

        var events: [AgentEvent] = []
        for try await event in agent.stream("test") {
            events.append(event)
        }

        let tokenEvents = events.compactMap { event -> String? in
            if case .output(.token(let token)) = event { return token }
            return nil
        }
        #expect(tokenEvents == ["Hello", " world"])
    }

    @Test("stream yields llmStarted and llmCompleted events")
    func stream_yieldsLLMLifecycleEvents() async throws {
        let chunks: [HiveChatStreamChunk] = [
            .final(HiveChatResponse(message: assistantMsg(id: "m1", content: "ok")))
        ]
        let agent = try makeAgent(modelChunks: chunks)

        var events: [AgentEvent] = []
        for try await event in agent.stream("test") {
            events.append(event)
        }

        let hasLLMStarted = events.contains { event in
            if case .observation(.llmStarted) = event { return true }
            return false
        }
        let hasLLMCompleted = events.contains { event in
            if case .observation(.llmCompleted) = event { return true }
            return false
        }
        #expect(hasLLMStarted)
        #expect(hasLLMCompleted)
    }

    @Test("stream yields toolCallStarted and toolCallCompleted for tool-using runs")
    func stream_yieldsToolCallEvents() async throws {
        let script = StreamingModelScript(chunksByInvocation: [
            [.final(HiveChatResponse(message: HiveChatMessage(
                id: "m1", role: .assistant, content: "",
                toolCalls: [HiveToolCall(id: "c1", name: "calc", argumentsJSON: "{}")]
            )))],
            [.final(HiveChatResponse(message: assistantMsg(id: "m2", content: "done")))]
        ])
        let agent = try makeScriptedAgent(script: script)

        var events: [AgentEvent] = []
        for try await event in agent.stream("test") {
            events.append(event)
        }

        let startedCall = events.compactMap { event -> ToolCall? in
            if case let .tool(.started(call: call)) = event { return call }
            return nil
        }.first
        let completed = events.compactMap { event -> (ToolCall, ToolResult)? in
            if case let .tool(.completed(call: call, result: result)) = event { return (call, result) }
            return nil
        }.first

        let start = try #require(startedCall)
        let (endCall, endResult) = try #require(completed)

        // Streaming bridge should provide stable correlation across started/completed.
        #expect(start.id == endCall.id)
        #expect(endResult.callId == endCall.id)
        #expect(endCall.providerCallId == "c1")
        #expect(endResult.output == .string("42"))
    }

    @Test("stream yields iterationStarted and iterationCompleted")
    func stream_yieldsIterationEvents() async throws {
        let chunks: [HiveChatStreamChunk] = [
            .final(HiveChatResponse(message: assistantMsg(id: "m1", content: "ok")))
        ]
        let agent = try makeAgent(modelChunks: chunks)

        var events: [AgentEvent] = []
        for try await event in agent.stream("test") {
            events.append(event)
        }

        let iterationStarted = events.contains { event in
            if case .lifecycle(.iterationStarted) = event { return true }
            return false
        }
        let iterationCompleted = events.contains { event in
            if case .lifecycle(.iterationCompleted) = event { return true }
            return false
        }
        #expect(iterationStarted)
        #expect(iterationCompleted)
    }

    @Test("stream still yields started and completed lifecycle events")
    func stream_yieldsLifecycleEvents() async throws {
        let chunks: [HiveChatStreamChunk] = [
            .final(HiveChatResponse(message: assistantMsg(id: "m1", content: "ok")))
        ]
        let agent = try makeAgent(modelChunks: chunks)

        var events: [AgentEvent] = []
        for try await event in agent.stream("test") {
            events.append(event)
        }

        let hasStarted = events.contains { event in
            if case .lifecycle(.started) = event { return true }
            return false
        }
        let hasCompleted = events.contains { event in
            if case .lifecycle(.completed) = event { return true }
            return false
        }
        #expect(hasStarted)
        #expect(hasCompleted)
    }

    @Test("stream reports completed result with correct output")
    func stream_completedResultHasOutput() async throws {
        let chunks: [HiveChatStreamChunk] = [
            .token("Hello"),
            .final(HiveChatResponse(message: assistantMsg(id: "m1", content: "Hello")))
        ]
        let agent = try makeAgent(modelChunks: chunks)

        var finalResult: AgentResult?
        for try await event in agent.stream("test") {
            if case .lifecycle(.completed(result: let result)) = event {
                finalResult = result
            }
        }

        let result = try #require(finalResult)
        #expect(result.output == "Hello")
    }

    @Test("stream events arrive in correct order: started before tokens before completed")
    func stream_eventsInCorrectOrder() async throws {
        let chunks: [HiveChatStreamChunk] = [
            .token("Hi"),
            .final(HiveChatResponse(message: assistantMsg(id: "m1", content: "Hi")))
        ]
        let agent = try makeAgent(modelChunks: chunks)

        var eventKinds: [String] = []
        for try await event in agent.stream("test") {
            switch event {
            case .lifecycle(.started): eventKinds.append("started")
            case .observation(.llmStarted): eventKinds.append("llmStarted")
            case .output(.token): eventKinds.append("outputToken")
            case .observation(.llmCompleted): eventKinds.append("llmCompleted")
            case .lifecycle(.completed): eventKinds.append("completed")
            default: break
            }
        }

        // started must come first, completed must come last
        #expect(eventKinds.first == "started")
        #expect(eventKinds.last == "completed")

        // llmStarted must come before any outputToken
        if let llmStartIdx = eventKinds.firstIndex(of: "llmStarted"),
           let tokenIdx = eventKinds.firstIndex(of: "outputToken") {
            #expect(llmStartIdx < tokenIdx)
        }
    }
}

// MARK: - Helpers

private func makeAgent(modelChunks: [HiveChatStreamChunk]) throws -> GraphAgent {
    let graph = try ChatGraph.makeToolUsingChatAgent()
    let context = RuntimeContext(modelName: "test-model", toolApprovalPolicy: .never)
    let environment = HiveEnvironment<ChatGraph.Schema>(
        context: context,
        clock: StreamingTestClock(),
        logger: StreamingTestLogger(),
        model: AnyHiveModelClient(StreamingStubModelClient(chunks: modelChunks)),
        modelRouter: nil,
        tools: AnyHiveToolRegistry(StreamingStubToolRegistry(resultContent: "ok")),
        checkpointStore: nil
    )
    let runtime = try HiveRuntime(graph: graph, environment: environment)
    let hiveRuntime = GraphRuntimeAdapter(runControl: GraphRunController(runtime: runtime))
    return GraphAgent(runtime: hiveRuntime, name: "stream-test")
}

private func makeScriptedAgent(script: StreamingModelScript) throws -> GraphAgent {
    let graph = try ChatGraph.makeToolUsingChatAgent()
    let context = RuntimeContext(modelName: "test-model", toolApprovalPolicy: .never)
    let environment = HiveEnvironment<ChatGraph.Schema>(
        context: context,
        clock: StreamingTestClock(),
        logger: StreamingTestLogger(),
        model: AnyHiveModelClient(StreamingScriptedModelClient(script: script)),
        modelRouter: nil,
        tools: AnyHiveToolRegistry(StreamingStubToolRegistry(resultContent: "42")),
        checkpointStore: nil
    )
    let runtime = try HiveRuntime(graph: graph, environment: environment)
    let hiveRuntime = GraphRuntimeAdapter(runControl: GraphRunController(runtime: runtime))
    return GraphAgent(runtime: hiveRuntime, name: "scripted-stream-test")
}

private func assistantMsg(id: String, content: String) -> HiveChatMessage {
    HiveChatMessage(id: id, role: .assistant, content: content, toolCalls: [], op: nil)
}

// MARK: - Test Doubles

private struct StreamingStubModelClient: HiveModelClient {
    let chunks: [HiveChatStreamChunk]

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        for chunk in chunks {
            if case let .final(response) = chunk { return response }
        }
        return HiveChatResponse(message: HiveChatMessage(id: "empty", role: .assistant, content: ""))
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
    }
}

private actor StreamingModelScript {
    private var chunksByInvocation: [[HiveChatStreamChunk]]

    init(chunksByInvocation: [[HiveChatStreamChunk]]) {
        self.chunksByInvocation = chunksByInvocation
    }

    func nextChunks() -> [HiveChatStreamChunk] {
        guard !chunksByInvocation.isEmpty else { return [] }
        return chunksByInvocation.removeFirst()
    }
}

private struct StreamingScriptedModelClient: HiveModelClient {
    let script: StreamingModelScript

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        let chunks = await script.nextChunks()
        for chunk in chunks {
            if case let .final(response) = chunk { return response }
        }
        throw SwarmRuntimeError.modelStreamInvalid("Missing final chunk.")
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let chunks = await script.nextChunks()
                for chunk in chunks { continuation.yield(chunk) }
                continuation.finish()
            }
        }
    }
}

private struct StreamingStubToolRegistry: HiveToolRegistry, Sendable {
    let resultContent: String
    func listTools() -> [HiveToolDefinition] { [] }
    func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        HiveToolResult(toolCallID: call.id, content: resultContent)
    }
}

private struct StreamingTestClock: HiveClock {
    func nowNanoseconds() -> UInt64 { 0 }
    func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(for: .nanoseconds(nanoseconds))
    }
}

private struct StreamingTestLogger: HiveLogger {
    func debug(_ message: String, metadata: [String: String]) {}
    func info(_ message: String, metadata: [String: String]) {}
    func error(_ message: String, metadata: [String: String]) {}
}
#endif
