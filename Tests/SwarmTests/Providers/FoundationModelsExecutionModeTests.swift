// FoundationModelsExecutionModeTests.swift
//
// Flag defaulting and non-FM providers ignoring native session mode.

import Foundation
@testable import Swarm
import Testing

@Suite("FoundationModels Execution Mode")
struct FoundationModelsExecutionModeTests {
    @Test("Capture remains the AgentConfiguration default")
    func captureIsDefault() {
        #expect(AgentConfiguration.default.foundationModelsExecution == .capture)
        #expect(AgentConfiguration().foundationModelsExecution == .capture)
    }

    @Test("Non-FM providers ignore nativeSession and keep the Swarm tool loop")
    func nonFMProvidersIgnoreNativeFlag() async throws {
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

        let config = AgentConfiguration.default
            .foundationModelsExecution(.nativeSession)
            .defaultTracingEnabled(false)
        let agent = try Agent(
            tools: [spy],
            instructions: "You are a helpful assistant.",
            configuration: config,
            inferenceProvider: mockProvider
        )

        let result = try await agent.run("Use the tool")
        #expect(result.output == "Done")
        #expect(result.toolCalls.count == 1)

        let recorded = await mockProvider.toolCallMessageCalls
        #expect(recorded.count == 2)
    }

    @Test("Native session uses the envelope prompt when structured messages are nil")
    func nativeSessionUsesEnvelopeWhenStructuredMessagesNil() {
        let envelope = """
        [Retrieved Context]
        windowed-memory
        [Current Conversation]
        User: needle-user-input
        """
        let history = [
            InferenceMessage.user("stale-turn-1"),
            InferenceMessage.assistant("stale-turn-2"),
            InferenceMessage.user("needle-user-input"),
        ]

        let messages = FoundationModelsNativePrompt.messages(
            structuredMessages: nil,
            envelopePrompt: envelope
        )

        #expect(messages == [.user(envelope)])
        #expect(!messages.contains(where: { $0.content == history[0].content }))
    }

    @Test("Native session keeps structured messages when the envelope was not rewritten")
    func nativeSessionKeepsStructuredMessages() {
        let structured = [
            InferenceMessage.user("hello"),
            InferenceMessage.assistant("hi"),
        ]
        let messages = FoundationModelsNativePrompt.messages(
            structuredMessages: structured,
            envelopePrompt: "STUFFED SHOULD BE IGNORED"
        )
        #expect(messages == structured)
    }
}
