import Conduit
import Testing
@testable import Swarm

@Suite("LLM Presets")
struct LLMPresetsTests {
    @Test("OpenAI preset builds Conduit OpenAI provider")
    func openAIPresetBuildsProvider() throws {
        let agent = try Agent(.openAI(key: "test-key", model: "gpt-4o-mini"))

        let provider = agent.inferenceProvider
        #expect(provider != nil)
        if let provider {
            #expect(provider is LLM)
            if let preset = provider as? LLM {
                #expect(preset._makeProviderForTesting() is ConduitInferenceProvider<OpenAIProvider>)
            }
        }
    }

    @Test("Anthropic preset builds Conduit Anthropic provider")
    func anthropicPresetBuildsProvider() throws {
        let agent = try Agent(.anthropic(key: "test-key", model: "claude-3-opus-20240229"))

        let provider = agent.inferenceProvider
        #expect(provider != nil)
        if let provider {
            #expect(provider is LLM)
            if let preset = provider as? LLM {
                #expect(preset._makeProviderForTesting() is ConduitInferenceProvider<AnthropicProvider>)
            }
        }
    }

    @Test("OpenRouter preset builds Conduit OpenAI-compatible provider")
    func openRouterPresetBuildsProvider() throws {
        let agent = try Agent(.openRouter(key: "test-key", model: "anthropic/claude-3-opus"))

        let provider = agent.inferenceProvider
        #expect(provider != nil)
        if let provider {
            #expect(provider is LLM)
            if let preset = provider as? LLM {
                #expect(preset._makeProviderForTesting() is ConduitInferenceProvider<OpenAIProvider>)
            }
        }
    }

    @Test("MiniMax preset builds Conduit OpenAI-compatible provider")
    func minimaxPresetBuildsProvider() throws {
        let agent = try Agent(.minimax(key: "test-key", model: "minimax-01"))

        let provider = agent.inferenceProvider
        #expect(provider != nil)
        if let provider {
            #expect(provider is LLM)
            if let preset = provider as? LLM {
                #if CONDUIT_TRAIT_MINIMAX
                    #expect(preset._makeProviderForTesting() is ConduitInferenceProvider<MiniMaxProvider>)
                #else
                    #expect(preset._makeProviderForTesting() is ConduitInferenceProvider<OpenAIProvider>)
                #endif
            }
        }
    }

    @Test("Ollama preset with custom settings builds Conduit provider")
    func ollamaPresetBuildsProviderWithSettings() throws {
        let agent = try Agent(LLM.ollama("llama3.2") { settings in
            settings.host = "127.0.0.1"
            settings.port = 11435
            settings.keepAlive = "10m"
            settings.pullOnMissing = true
            settings.numGPU = 2
            settings.lowVRAM = true
            settings.numCtx = 4096
            settings.healthCheck = false
        })

        let provider = agent.inferenceProvider
        #expect(provider != nil)
        if let provider {
            #expect(provider is LLM)
            if let preset = provider as? LLM {
                #expect(preset._makeProviderForTesting() is ConduitInferenceProvider<OpenAIProvider>)
            }
        }
    }
}
