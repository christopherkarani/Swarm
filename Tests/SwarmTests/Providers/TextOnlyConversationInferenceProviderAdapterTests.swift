import Foundation
@testable import Swarm
import Testing

@Suite("Text-Only Inference Provider Adapter")
struct TextOnlyConversationInferenceProviderAdapterTests {
    @Test("Default tool-calling emulation works for plain inference providers")
    func defaultToolCallingEmulationWorksForPlainProviders() async throws {
        let provider = CertifiedTextOnlyProvider(mode: .alwaysToolEnvelope)

        let response = try await provider.generateWithToolCalls(
            prompt: "Use the string tool to uppercase hello.",
            tools: [StringTool().schema],
            options: .default
        )

        #expect(response.finishReason == .toolCall)
        let toolCall = try #require(response.toolCalls.first)
        #expect(toolCall.name == "string")
        #expect(toolCall.arguments["operation"] == .string("uppercase"))
        #expect(toolCall.arguments["input"] == .string("hello"))
    }

    @Test("Text-only conversation adapter flattens structured history for plain providers")
    func textOnlyConversationAdapterFlattensStructuredHistory() async throws {
        let provider = CertifiedTextOnlyProvider(mode: .finalAnswer("ok"))
        let adapter = TextOnlyConversationInferenceProviderAdapter(base: provider)

        let output = try await adapter.generate(
            messages: [
                .system("system instructions"),
                .user("hello")
            ],
            options: .default
        )

        #expect(output == "ok")
        let prompts = await provider.recordedPrompts()
        #expect(prompts.count == 1)
        #expect(prompts[0].contains("[System]: system instructions"))
        #expect(prompts[0].contains("[User]: hello"))
    }

    @Test("Agent completes tool loops with text-only providers")
    func agentCompletesToolLoopsWithTextOnlyProviders() async throws {
        let provider = CertifiedTextOnlyProvider(mode: .toolThenAnswer)
        let agent = try Agent(
            tools: [StringTool()],
            instructions: "Use tools when helpful.",
            inferenceProvider: provider
        )

        let result = try await agent.run("Uppercase hello.")

        #expect(result.output == "Final answer: HELLO")
        let prompts = await provider.recordedPrompts()
        #expect(prompts.count == 2)
        #expect(prompts[0].contains("\"swarm_tool_call\""))
        #expect(prompts[1].contains("[Tool Result - string]: HELLO"))
    }
}
