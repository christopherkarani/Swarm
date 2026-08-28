// StreamingEventTests.swift
// SwarmTests
//
// Tests for streaming events in agents.

import Foundation
@testable import Swarm
import Testing

@Suite("Streaming Event Tests", .ephemeralDefaultStores)
struct StreamingEventTests {

    
    @Test("Agent stream emits tool call events")
    func reactAgentStreamEvents() async throws {
        // 1. Setup mock provider with native tool call responses
        let mockProvider = MockInferenceProvider()
        await mockProvider.setToolCallResponses([
            // First response: model requests a tool call
            InferenceResponse(
                content: nil,
                toolCalls: [
                    .init(id: "call_1", name: "test_tool", arguments: ["arg": .string("1")])
                ],
                finishReason: .toolCall
            ),
            // Second response: model returns final answer after tool result
            InferenceResponse(
                content: "Done",
                toolCalls: [],
                finishReason: .completed
            )
        ])

        // 2. Setup agent with a mock tool
        let tool = MockTool(name: "test_tool", description: "Test tool")
        let agent = try Agent(
            tools: [tool],
            instructions: "You are a test assistant.",
            inferenceProvider: mockProvider
        )

        // 3. Collect events from stream
        var events: [AgentEvent] = []
        for try await event in agent.stream("Start") {
            events.append(event)
        }

        // 4. Verify events
        // Expected sequence:
        // .started
        // .iterationStarted(1)
        // .llmStarted
        // .llmCompleted
        // .toolCallStarted(test_tool)
        // .toolCallCompleted(test_tool)
        // .iterationCompleted(1)
        // .iterationStarted(2)
        // .llmStarted
        // .llmCompleted
        // .iterationCompleted(2)
        // .completed

        #expect(events.contains { if case .lifecycle(.started) = $0 { return true }; return false })
        #expect(events.contains { if case .lifecycle(.iterationStarted(let n)) = $0 { return n == 1 }; return false })
        #expect(events.contains { if case .tool(.started(call: let call)) = $0 { return call.toolName == "test_tool" }; return false })
        #expect(events.contains { if case .tool(.completed(call: let call, result: _)) = $0 { return call.toolName == "test_tool" }; return false })
        #expect(events.contains { if case .lifecycle(.completed) = $0 { return true }; return false })
    }
    
    @Test("Agent stream emits iteration events")
    func agentStreamEvents() async throws {
        // 1. Setup mock provider (Agent uses generateWithToolCalls)
        let mockProvider = MockInferenceProvider()
        await mockProvider.setResponses(["Final answer directly"])
        
        // 2. Setup agent
        let agent = try Agent(
            tools: [],
            instructions: "You are a test assistant.",
            inferenceProvider: mockProvider
        )
        
        // 3. Collect events from stream
        var events: [AgentEvent] = []
        for try await event in agent.stream("Start") {
            events.append(event)
        }
        
        // 4. Verify events
        #expect(events.contains { if case .lifecycle(.started) = $0 { return true }; return false })
        #expect(events.contains { if case .lifecycle(.iterationStarted(let n)) = $0 { return n == 1 }; return false })
        #expect(events.contains { if case .lifecycle(.completed) = $0 { return true }; return false })
    }

    @Test("Agent streaming avoids second request without tool-call streaming")
    func agentStreamingAvoidsSecondRequest() async throws {
        let mockProvider = MockInferenceProvider()
        await mockProvider.setToolCallResponses([
            InferenceResponse(content: "Final answer directly", toolCalls: [], finishReason: .completed)
        ])

        let tool = MockTool(name: "test_tool", description: "Test tool")
        let agent = try Agent(
            tools: [tool],
            instructions: "You are a test assistant.",
            inferenceProvider: mockProvider
        )

        for try await _ in agent.stream("Start") {}

        let toolCallCount = await mockProvider.toolCallMessageCalls.count
        let streamCount = await mockProvider.streamCalls.count
        let generateCount = await mockProvider.generateMessageCalls.count

        #expect(toolCallCount == 1)
        #expect(streamCount == 0)
        #expect(generateCount == 0)
    }

    @Test("Agent streaming uses tool-call generation when tools are available")
    func reactAgentStreamingUsesToolCallGeneration() async throws {
        let mockProvider = MockInferenceProvider()
        await mockProvider.setToolCallResponses([
            InferenceResponse(content: "Final Answer: Done", toolCalls: [], finishReason: .completed)
        ])

        let tool = MockTool(name: "test_tool", description: "Test tool")
        let agent = try Agent(
            tools: [tool],
            instructions: "You are a test assistant.",
            inferenceProvider: mockProvider
        )

        for try await _ in agent.stream("Start") {}

        let toolCallCount = await mockProvider.toolCallMessageCalls.count
        let streamCount = await mockProvider.streamCalls.count
        let generateCount = await mockProvider.generateMessageCalls.count

        #expect(toolCallCount == 1)
        #expect(streamCount == 0)
        #expect(generateCount == 0)
    }

    @Test("Agent streaming honors providers that opt out of streaming tool calls")
    func agentStreamingHonorsToolCallStreamingCapabilityOptOut() async throws {
        let provider = CapabilityOptOutToolStreamingProvider()
        let tool = MockTool(name: "test_tool", description: "Test tool")
        let agent = try Agent(
            tools: [tool],
            instructions: "You are a test assistant.",
            inferenceProvider: provider
        )

        for try await _ in agent.stream("Start") {}

        #expect(provider.generateWithToolCallsCount == 1)
        #expect(provider.streamWithToolCallsCount == 0)
    }

    @Test("Agent streaming uses providers that advertise streaming tool calls")
    func agentStreamingUsesAdvertisedToolCallStreamingCapability() async throws {
        let provider = CapabilityOptInToolStreamingProvider()
        let tool = MockTool(name: "test_tool", description: "Test tool")
        let agent = try Agent(
            tools: [tool],
            instructions: "You are a test assistant.",
            inferenceProvider: provider
        )

        var sawOutput = false
        for try await event in agent.stream("Start") {
            if case .output(.token("Done")) = event {
                sawOutput = true
            }
        }

        #expect(sawOutput)
        #expect(provider.generateWithToolCallsCount == 0)
        #expect(provider.streamWithToolCallsCount == 1)
    }
}

private final class CapabilityOptOutToolStreamingProvider:
    InferenceProvider,
    @unchecked Sendable
{
    var capabilities: InferenceProviderCapabilities {
        [.nativeToolCalling]
    }

    var generateWithToolCallsCount: Int {
        withLock { generateWithToolCallsCountStorage }
    }

    var streamWithToolCallsCount: Int {
        withLock { streamWithToolCallsCountStorage }
    }

    private let lock = NSLock()
    private var generateWithToolCallsCountStorage = 0
    private var streamWithToolCallsCountStorage = 0

    func generate(messages _: [InferenceMessage], options _: InferenceOptions) async throws -> String {
        "Done"
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions,
        toolExecutor _: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        withLock {
            generateWithToolCallsCountStorage += 1
        }
        return InferenceResponse(content: "Done", toolCalls: [], finishReason: .completed)
    }

    func streamWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions,
        toolExecutor _: ToolCallExecutor?
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        withLock {
            streamWithToolCallsCountStorage += 1
        }
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: AgentError.generationFailed(reason: "streaming tool calls were not advertised"))
        }
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

private final class CapabilityOptInToolStreamingProvider:
    InferenceProvider,
    @unchecked Sendable
{
    var capabilities: InferenceProviderCapabilities {
        [.nativeToolCalling, .streamingToolCalls]
    }

    var generateWithToolCallsCount: Int {
        withLock { generateWithToolCallsCountStorage }
    }

    var streamWithToolCallsCount: Int {
        withLock { streamWithToolCallsCountStorage }
    }

    private let lock = NSLock()
    private var generateWithToolCallsCountStorage = 0
    private var streamWithToolCallsCountStorage = 0

    func generate(messages _: [InferenceMessage], options _: InferenceOptions) async throws -> String {
        "Done"
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions,
        toolExecutor _: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        withLock {
            generateWithToolCallsCountStorage += 1
        }
        return InferenceResponse(content: "Done", toolCalls: [], finishReason: .completed)
    }

    func streamWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions,
        toolExecutor _: ToolCallExecutor?
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        withLock {
            streamWithToolCallsCountStorage += 1
        }
        return AsyncThrowingStream { continuation in
            continuation.yield(.outputChunk("Done"))
            continuation.finish()
        }
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
