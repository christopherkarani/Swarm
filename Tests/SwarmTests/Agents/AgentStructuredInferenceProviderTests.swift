import Testing
@testable import Swarm

@Suite("Agent Structured Inference Providers")
struct AgentStructuredInferenceProviderTests {
    @Test("Prefers structured conversation generation when provider supports it")
    func prefersStructuredConversationGeneration() async throws {
        let provider = MockInferenceProvider(responses: ["structured reply"])
        let agent = try Agent(
            instructions: "You are a structured assistant.",
            inferenceProvider: provider
        )

        let result = try await agent.run("Hello")

        #expect(result.output == "structured reply")

        let promptCalls = await provider.generateCalls
        let messageCalls = await provider.generateMessageCalls

        #expect(promptCalls.isEmpty)
        #expect(messageCalls.count == 1)

        let messages = messageCalls[0].messages
        #expect(messages.count == 2)
        #expect(messages[0].role == .system)
        #expect(messages[0].content.contains("You are a structured assistant."))
        #expect(messages[1] == .user("Hello"))
    }

    @Test("Carries assistant tool calls and tool result ids through structured history")
    func preservesStructuredToolHistory() async throws {
        struct EchoTool: AnyJSONTool, Sendable {
            let name = "echo"
            let description = "Echoes the provided text"
            let parameters: [ToolParameter] = [
                ToolParameter(name: "text", description: "Text to echo", type: .string)
            ]

            func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
                .string(arguments["text"]?.stringValue ?? "")
            }
        }

        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: "Checking the echo tool",
                toolCalls: [
                    .init(id: "call_1", name: "echo", arguments: ["text": "hi"])
                ],
                finishReason: .toolCall
            ),
            InferenceResponse(content: "All done", finishReason: .completed),
        ])

        let agent = try Agent(
            tools: [EchoTool()],
            configuration: .default.maxIterations(3),
            inferenceProvider: provider
        )

        let result = try await agent.run("Say hi")

        #expect(result.output == "All done")

        let promptCalls = await provider.toolCallCalls
        let messageCalls = await provider.toolCallMessageCalls

        #expect(promptCalls.isEmpty)
        #expect(messageCalls.count == 2)

        let followupMessages = messageCalls[1].messages

        let assistantMessage = followupMessages.first { message in
            message.role == .assistant && !message.toolCalls.isEmpty
        }
        #expect(assistantMessage != nil)
        #expect(assistantMessage?.toolCalls.first?.id == "call_1")
        #expect(assistantMessage?.toolCalls.first?.name == "echo")

        let toolMessage = followupMessages.first { $0.role == .tool }
        #expect(toolMessage != nil)
        #expect(toolMessage?.name == "echo")
        #expect(toolMessage?.toolCallID == "call_1")
        #expect(toolMessage?.content == "hi")
    }
}
