import Foundation
@testable import Swarm
import Testing

@Suite("Agent Defaults", .ephemeralDefaultStores)
struct AgentDefaultInferenceProviderTests {

    @Test("privacyRequired does not route through an explicit non-private provider")
    func privacyRequiredSkipsExplicitNonPrivateProvider() async throws {
        let nonPrivateProvider = MockInferenceProvider(responses: ["non-private response"])
        let configuration = AgentConfiguration.default
            .inferencePolicy(InferencePolicy(privacyRequired: true))
        let agent = try Agent(
            instructions: "Keep this private.",
            configuration: configuration,
            inferenceProvider: nonPrivateProvider,
            runEnvironment: AgentRunEnvironment(defaultProvider: { nil })
        )

        do {
            _ = try await agent.run("secret")
        } catch {
            // Foundation Models may be unavailable or unavailable for the test prompt.
            // The privacy invariant is that the explicit non-private provider is not called.
        }

        #expect(await nonPrivateProvider.generateCallCount == 0)
        #expect(await nonPrivateProvider.toolCallCalls.isEmpty)
        #expect(await nonPrivateProvider.generateMessageCalls.isEmpty)
        #expect(await nonPrivateProvider.toolCallMessageCalls.isEmpty)
    }

    @Test("Throws if no inference provider is set and Foundation Models are unavailable")
    func throwsIfNoProviderAndFoundationModelsUnavailable() async {
        // Keep this deterministic across environments: if Foundation Models are available at runtime,
        // Agent may run without an explicit provider.
        if DefaultInferenceProviderFactory.makeFoundationModelsProviderIfAvailable() != nil {
            return
        }

        do {
            let agent = try Agent(runEnvironment: AgentRunEnvironment(
                defaultProvider: { nil },
                webConfiguration: { nil }
            ))
            _ = try await agent.run("hi")
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

    @Test("Foundation Models provider accepts tool-call requests without explicit rejection")
    func foundationModelsProviderAcceptsToolCalls() async throws {
        guard ProcessInfo.processInfo.environment["SWARM_RUN_LIVE_FOUNDATION_MODELS_TESTS"] == "1" else {
            return
        }
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

        let capabilities = InferenceProviderCapabilities.resolved(for: provider)
        #expect(response.finishReason == .toolCall || response.finishReason == .completed)
        #expect(!response.toolCalls.isEmpty || response.content != nil)
        #expect(capabilities.contains(.nativeToolCalling))
        #expect(capabilities.contains(.streamingToolCalls) == false)
    }
}
