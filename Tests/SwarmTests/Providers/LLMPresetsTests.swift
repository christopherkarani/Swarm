import Conduit
import Foundation
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

    @Test("LLM OpenRouter preset preserves routing metadata")
    func llmOpenRouterPresetPreservesRoutingMetadata() throws {
        let url = try #require(URL(string: "https://swarm.dev"))
        let preset = LLM.openRouter(apiKey: "test-key", model: "anthropic/claude-3-opus") { routing in
            routing.providers = [.anthropic]
            routing.siteURL = url
            routing.appName = "Swarm"
            routing.dataCollection = .deny
        }

        let provider = preset._makeProviderForTesting()
        let metadata = try #require(mirroredOpenRouterMetadata(from: provider))
        #expect(metadata.siteURL == url)
        #expect(metadata.appName == "Swarm")
        #expect(metadata.dataCollectionDescription?.contains("deny") == true)
    }

    @Test("LLM Ollama preset preserves advanced settings")
    func llmOllamaPresetPreservesAdvancedSettings() throws {
        let preset = LLM.ollama("llama3.2") { settings in
            settings.host = "127.0.0.1"
            settings.port = 11435
            settings.keepAlive = "10m"
            settings.pullOnMissing = true
            settings.numGPU = 2
            settings.lowVRAM = true
            settings.numCtx = 4096
            settings.healthCheck = false
        }

        let provider = preset._makeProviderForTesting()
        let configuration = try #require(mirroredOllamaConfiguration(from: provider))
        #expect(configuration.keepAlive == "10m")
        #expect(configuration.pullOnMissing == true)
        #expect(configuration.numGPU == 2)
        #expect(configuration.lowVRAM == true)
        #expect(configuration.numCtx == 4096)
        #expect(configuration.healthCheck == false)
    }

#if canImport(MLX)
    @Test("MLX preset builds a text-only conversation adapter")
    func mlxPresetBuildsTextOnlyConversationAdapter() throws {
        let preset = LLM.mlx("mlx-community/Llama-3.2-1B-Instruct-4bit")
        let provider = preset._makeProviderForTesting()

        #expect(provider is TextOnlyConversationInferenceProviderAdapter)

        let capabilities = InferenceProviderCapabilities.resolved(for: provider)
        #expect(capabilities.contains(.conversationMessages))
        #expect(!capabilities.contains(.nativeToolCalling))
    }

    @Test("MLX local preset builds a text-only conversation adapter")
    func mlxLocalPresetBuildsTextOnlyConversationAdapter() throws {
        let preset = LLM.mlxLocal("/Users/me/models/Qwen3-8B-MLX-bf16")
        let provider = preset._makeProviderForTesting()

        #expect(provider is TextOnlyConversationInferenceProviderAdapter)
        let capabilities = InferenceProviderCapabilities.resolved(for: provider)
        #expect(capabilities.contains(.conversationMessages))
    }
#endif
}

private func mirroredOpenRouterMetadata(from provider: Any) -> (siteURL: URL?, appName: String?, dataCollectionDescription: String?)? {
    guard let rawProvider = unwrapMirrorOptional(Mirror(reflecting: provider).descendant("provider")),
          let configuration = unwrapMirrorOptional(Mirror(reflecting: rawProvider).descendant("configuration")),
          let openRouterConfig = unwrapMirrorOptional(Mirror(reflecting: configuration).descendant("openRouterConfig"))
    else {
        return nil
    }

    let mirror = Mirror(reflecting: openRouterConfig)
    let siteURL = unwrapMirrorOptional(mirror.descendant("siteURL")) as? URL
    let appName = unwrapMirrorOptional(mirror.descendant("appName")) as? String
    let dataCollection = unwrapMirrorOptional(mirror.descendant("dataCollection"))
    return (siteURL, appName, dataCollection.map { String(describing: $0) })
}

private func mirroredOllamaConfiguration(from provider: Any) -> (
    keepAlive: String?,
    pullOnMissing: Bool?,
    numGPU: Int?,
    lowVRAM: Bool?,
    numCtx: Int?,
    healthCheck: Bool?
)? {
    guard let rawProvider = unwrapMirrorOptional(Mirror(reflecting: provider).descendant("provider")),
          let configuration = unwrapMirrorOptional(Mirror(reflecting: rawProvider).descendant("configuration")),
          let ollamaConfig = unwrapMirrorOptional(Mirror(reflecting: configuration).descendant("ollamaConfig"))
    else {
        return nil
    }

    let mirror = Mirror(reflecting: ollamaConfig)
    return (
        unwrapMirrorOptional(mirror.descendant("keepAlive")) as? String,
        unwrapMirrorOptional(mirror.descendant("pullOnMissing")) as? Bool,
        unwrapMirrorOptional(mirror.descendant("numGPU")) as? Int,
        unwrapMirrorOptional(mirror.descendant("lowVRAM")) as? Bool,
        unwrapMirrorOptional(mirror.descendant("numCtx")) as? Int,
        unwrapMirrorOptional(mirror.descendant("healthCheck")) as? Bool
    )
}

private func unwrapMirrorOptional(_ value: Any?) -> Any? {
    guard let value else { return nil }
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else { return value }
    return mirror.children.first?.value
}
