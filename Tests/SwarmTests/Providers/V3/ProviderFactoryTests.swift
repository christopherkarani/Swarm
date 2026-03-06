// ProviderFactoryTests.swift
// Tests for V3 provider dot-syntax factories.

@testable import Swarm
import Testing

@Suite("V3 Provider Factories")
struct ProviderFactoryTests {
    @Test("Anthropic dot-syntax via LLM")
    func anthropicFactory() {
        // Verifies the factory compiles and returns InferenceProvider
        let provider: any InferenceProvider = LLM.anthropic(key: "test-key")
        #expect(provider is LLM)
    }

    @Test("OpenAI dot-syntax via LLM")
    func openAIFactory() {
        let provider: any InferenceProvider = LLM.openAI(key: "test-key")
        #expect(provider is LLM)
    }

    @Test("OpenRouter dot-syntax via LLM")
    func openRouterFactory() {
        let provider: any InferenceProvider = LLM.openRouter(key: "test-key")
        #expect(provider is LLM)
    }

    @Test("Ollama dot-syntax via ConduitProviderSelection")
    func ollamaFactory() {
        let provider: any InferenceProvider = ConduitProviderSelection.ollama(model: "llama3.2")
        #expect(provider is ConduitProviderSelection)
    }
}
