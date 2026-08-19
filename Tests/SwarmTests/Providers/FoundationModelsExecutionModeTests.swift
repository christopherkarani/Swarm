// FoundationModelsExecutionModeTests.swift
//
// Deprecated flag is a no-op. Non-FM adapters keep the Agent tool loop.

import Foundation
@testable import Swarm
import Testing

@Suite("FoundationModels Execution Mode")
struct FoundationModelsExecutionModeTests {
    @Test("Capture remains the stored AgentConfiguration default")
    func captureIsDefault() {
        #expect(AgentConfiguration.default.foundationModelsExecution == .capture)
        #expect(AgentConfiguration().foundationModelsExecution == .capture)
    }

    @Test("Non-FM providers keep the Swarm tool loop")
    func nonFMProvidersKeepSwarmToolLoop() async throws {
        let spy = MockTool(
            name: "test_tool",
            description: "Test tool",
            parameters: [ToolParameter(name: "location", description: "Location", type: .string)],
            result: .string("Tool result")
        )
        let mockProvider = MockInferenceProvider()
        await mockProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_123",
                        name: "test_tool",
                        arguments: ["location": .string("NYC")]
                    ),
                ],
                finishReason: .toolCall
            ),
            InferenceResponse(
                content: "Done",
                toolCalls: [],
                finishReason: .completed
            ),
        ])

        let agent = try Agent(
            tools: [spy],
            instructions: "You are a helpful assistant.",
            configuration: AgentConfiguration.default.defaultTracingEnabled(false),
            inferenceProvider: mockProvider
        )

        let result = try await agent.run("Use the tool")
        #expect(result.output == "Done")
        #expect(result.toolCalls.count == 1)

        let recorded = await mockProvider.toolCallMessageCalls
        #expect(recorded.count == 2)
    }
}
