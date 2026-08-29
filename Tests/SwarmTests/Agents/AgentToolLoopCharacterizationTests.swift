// AgentToolLoopCharacterizationTests.swift
// SwarmTests
//
// Characterization tests for the Agent tool-calling loop (spec T1 AC-001).
// They pin public `executeToolCallingLoop` behavior: one admission per inference
// attempt, including after host tools without a handoff.

import Foundation
@testable import Swarm
import Testing

@Suite("Tool-calling loop characterization (T1 AC-001)")
struct AgentToolLoopCharacterizationTests {
    private static let loopConfiguration = AgentConfiguration.default
        .enableStreaming(false)
        .timeout(.seconds(30))
        .defaultTracingEnabled(false)

    @Test("Host loop executes tool calls and continues to a final answer")
    func hostLoopExecutesToolsThenFinishes() async throws {
        let tool = SpyTool(name: "weather", result: .string("72F"))
        let provider = await MockInferenceProvider()
        await provider.configureToolCallingSequence(
            toolCalls: [("weather", [:])],
            finalAnswer: "It is 72F"
        )
        let agent = try Agent(
            tools: [tool],
            configuration: Self.loopConfiguration,
            inferenceProvider: provider
        )

        let result = try await agent.run("What is the weather?")

        #expect(result.output == "It is 72F")
        #expect(await tool.callCount == 1)
        // One tool-calling turn plus one final turn.
        #expect(await provider.recordedInferenceCallCount == 2)
        #expect(result.iterationCount == 2)
        #expect(result.toolCalls.map(\.toolName) == ["weather"])
    }

    @Test("Two host-tool rounds under a tight cap admit once per inference")
    func twoHostToolRoundsUnderTightCapDoNotDoubleAdmit() async throws {
        let tool = SpyTool(name: "step", result: .string("ok"))
        let provider = await MockInferenceProvider()
        await provider.configureToolCallingSequence(
            toolCalls: [("step", [:]), ("step", [:])],
            finalAnswer: "done"
        )
        let agent = try Agent(
            tools: [tool],
            configuration: Self.loopConfiguration.maxIterations(3),
            inferenceProvider: provider
        )

        let result = try await agent.run("two steps")

        #expect(result.output == "done")
        #expect(await tool.callCount == 2)
        #expect(await provider.recordedInferenceCallCount == 3)
        #expect(result.iterationCount == 3)
    }

    @Test("Iteration cap throws maxIterationsExceeded with the configured count")
    func iterationCapThrowsMaxIterationsExceeded() async throws {
        let tool = SpyTool(name: "noop", result: .string("ok"))
        let provider = await MockInferenceProvider()
        // Every response requests the same tool; the model never finishes.
        let loopingToolCall = InferenceResponse(
            content: nil,
            toolCalls: [
                InferenceResponse.ParsedToolCall(id: "call_loop", name: "noop", arguments: [:]),
            ],
            finishReason: .toolCall,
            usage: nil
        )
        await provider.setToolCallResponses(Array(repeating: loopingToolCall, count: 5))
        let agent = try Agent(
            tools: [tool],
            configuration: Self.loopConfiguration.maxIterations(2),
            inferenceProvider: provider
        )

        do {
            _ = try await agent.run("loop forever")
            Issue.record("Expected AgentError.maxIterationsExceeded")
        } catch let error as AgentError {
            guard case let .maxIterationsExceeded(iterations) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(iterations == 2)
        }

        #expect(await tool.callCount == 2)
        #expect(await provider.recordedInferenceCallCount == 2)
    }

    @Test("Provider-owned loop executes tools inside inference and finishes in one turn")
    func providerOwnedLoopFinishesInSingleInferenceCall() async throws {
        let tool = SpyTool(name: "ping", result: .string("pong"))
        let provider = OwnedLoopCharacterizationProvider(toolName: "ping")
        let agent = try Agent(
            tools: [tool],
            configuration: Self.loopConfiguration,
            inferenceProvider: provider
        )

        let result = try await agent.run("use ping")

        #expect(result.output == "owned done")
        #expect(await tool.callCount == 1)
        let inferenceCalls = await provider.inferenceCallCount
        #expect(inferenceCalls == 1)
        #expect(result.iterationCount == 1)
    }

    @Test("Streaming tool calls drive the loop through the streaming path")
    func streamingToolCallPath() async throws {
        let tool = SpyTool(name: "echo", result: .string("hi"))
        let provider = await MockInferenceProvider(capabilities: [.streamingToolCalls])
        await provider.configureToolCallingSequence(
            toolCalls: [("echo", [:])],
            finalAnswer: "done streaming"
        )
        let agent = try Agent(
            tools: [tool],
            configuration: AgentConfiguration.default
                .maxIterations(3)
                .timeout(.seconds(30))
                .defaultTracingEnabled(false),
            inferenceProvider: provider
        )

        var events: [AgentEvent] = []
        for try await event in agent.stream("hi") {
            events.append(event)
        }

        // Streaming path emits output events while consuming the update stream.
        #expect(events.contains { event in
            if case .output = event { return true }
            return false
        })

        guard let completed = events.last(where: { event in
            if case .lifecycle(.completed) = event { return true }
            return false
        }), case let .lifecycle(.completed(result: result)) = completed else {
            Issue.record("Missing lifecycle(.completed) event")
            return
        }
        #expect(result.output == "done streaming")
        #expect(await tool.callCount == 1)
    }
}

/// Owned-loop provider that runs one tool through the executor handed to it by
/// the agent, then finishes the turn with a completed response.
private actor OwnedLoopCharacterizationProvider: InferenceProvider {
    nonisolated let capabilities: InferenceProviderCapabilities = [
        .conversationMessages,
        .nativeToolCalling,
        .providerOwnedToolLoop,
    ]

    let toolName: String
    private(set) var inferenceCallCount = 0

    init(toolName: String) {
        self.toolName = toolName
    }

    func generate(messages _: [InferenceMessage], options _: InferenceOptions) async throws -> String {
        throw AgentError.generationFailed(reason: "expected generateWithToolCalls")
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        inferenceCallCount += 1
        guard let toolExecutor else {
            throw AgentError.providerOwnedToolLoopRequiresExecutor
        }
        _ = try await toolExecutor.executeTool(named: toolName, arguments: [:])
        return InferenceResponse(content: "owned done", finishReason: .completed)
    }
}
