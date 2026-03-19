@testable import Swarm
import Testing

@Suite("Agent Defaults")
struct AgentDefaultInferenceProviderTests {
    @Test("Throws if no inference provider is set and Foundation Models are unavailable")
    func throwsIfNoProviderAndFoundationModelsUnavailable() async {
        await withSwarmConfigurationIsolation {
            // Keep this deterministic across environments: if Foundation Models are available at runtime,
            // Agent may run without an explicit provider.
            if DefaultInferenceProviderFactory.makeFoundationModelsProviderIfAvailable() != nil {
                return
            }

            do {
                _ = try await Agent().run("hi")
                Issue.record("Expected inference provider unavailable error")
            } catch let error as AgentError {
                switch error {
                case let .inferenceProviderUnavailable(reason):
                    #expect(reason.contains("Foundation Models"))
                    #expect(reason.contains("inference provider"))
                default:
                    Issue.record("Unexpected AgentError: \(error)")
                }
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test("Foundation Models provider accepts tool-call requests without explicit rejection")
    func foundationModelsProviderAcceptsToolCalls() async throws {
        guard let provider = DefaultInferenceProviderFactory.makeFoundationModelsProviderIfAvailable() else {
            return
        }

        let tools = [
            ToolSchema(
                name: "weather",
                description: "weather lookup",
                parameters: [
                    ToolParameter(name: "city", description: "City name", type: .string),
                ]
            ),
        ]

        let response = try await provider.generateWithToolCalls(
            prompt: "Check weather in Nairobi. If you call a tool, reply with JSON only.",
            tools: tools,
            options: .default
        )

        #expect(response.finishReason == .toolCall || response.finishReason == .completed)
        #expect(!response.toolCalls.isEmpty || response.content != nil)
    }
}
