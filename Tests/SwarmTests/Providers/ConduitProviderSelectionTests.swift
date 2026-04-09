#if canImport(ConduitAdvanced)
import ConduitAdvanced
#else
import Conduit
#endif
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import Testing
@testable import Swarm

@Suite("Conduit Provider Selection")
struct ConduitProviderSelectionTests {
    @Test("Builds Anthropic Conduit provider")
    func buildsAnthropicProvider() {
        let provider = ConduitProviderSelection
            .anthropic(apiKey: "test-key", model: "claude-3-opus-20240229")
            .makeProvider()

        #expect(provider is ConduitInferenceProvider<AnthropicProvider>)
    }

    @Test("Builds OpenRouter Conduit provider")
    func buildsOpenRouterProvider() {
        let provider = ConduitProviderSelection
            .openRouter(apiKey: "test-key", model: "anthropic/claude-3-opus")
            .makeProvider()

        #expect(provider is ConduitInferenceProvider<OpenAIProvider>)
    }

    #if canImport(FoundationModels)
    @Test("Builds Foundation Models Conduit provider without streaming tool-call capability")
    func buildsFoundationModelsProvider() {
        guard #available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *) else {
            return
        }

        let selection = ConduitProviderSelection.foundationModels()
        let provider = selection.makeProvider()
        let capabilities = InferenceProviderCapabilities.resolved(for: selection)

        #expect(capabilities.contains(.conversationMessages))
        #expect(capabilities.contains(.nativeToolCalling))
        #expect(capabilities.contains(.structuredOutputs))
        #expect(capabilities.contains(.streamingToolCalls) == false)
        #expect(provider is ConduitInferenceProvider<FoundationModelsProvider>)
    }
    #endif

    @Test("Builds MiniMax Conduit provider")
    func buildsMiniMaxProvider() {
        let provider = ConduitProviderSelection
            .minimax(apiKey: "test-key", model: "minimax-01")
            .makeProvider()

        #if CONDUIT_TRAIT_MINIMAX
            #expect(provider is ConduitInferenceProvider<MiniMaxProvider>)
        #else
            #expect(provider is ConduitInferenceProvider<OpenAIProvider>)
        #endif
    }

    @Test("Builds Ollama Conduit provider")
    func buildsOllamaProvider() {
        let provider = ConduitProviderSelection
            .ollama(model: "llama3.2")
            .makeProvider()

        #expect(provider is ConduitInferenceProvider<OpenAIProvider>)
    }

    @Test("Maps OpenRouter routing to Conduit config")
    func mapsOpenRouterRouting() throws {
        let url = try #require(URL(string: "https://example.com"))
        let routing = OpenRouterRouting(
            providers: [.anthropic, .openai],
            fallbacks: false,
            routeByLatency: true,
            siteURL: url,
            appName: "Swarm",
            dataCollection: .deny
        )

        let config = routing.toConduit()
        #expect(config.providers?.map(\.slug) == ["anthropic", "openai"])
        #expect(config.fallbacks == false)
        #expect(config.routeByLatency == true)
        #expect(config.siteURL == url)
        #expect(config.appName == "Swarm")
        #expect(config.dataCollection == OpenRouterDataCollection.deny)
    }

    @Test("Closure-based Ollama configuration")
    func closureBasedOllama() {
        let provider = ConduitProviderSelection
            .ollama(model: "llama3.2") { settings in
                settings.host = "192.168.1.100"
                settings.port = 11435
            }
            .makeProvider()

        #expect(provider is ConduitInferenceProvider<OpenAIProvider>)
    }

    @Test("Closure-based OpenRouter configuration")
    func closureBasedOpenRouter() {
        let provider = ConduitProviderSelection
            .openRouter(apiKey: "test-key", model: "anthropic/claude-3-opus") { routing in
                routing.providers = [.anthropic]
                routing.fallbacks = false
            }
            .makeProvider()

        #expect(provider is ConduitInferenceProvider<OpenAIProvider>)
    }

    @Test("OpenRouter provider selection preserves routing metadata")
    func openRouterSelectionPreservesRoutingMetadata() throws {
        let url = try #require(URL(string: "https://swarm.dev"))
        let provider = ConduitProviderSelection
            .openRouter(apiKey: "test-key", model: "anthropic/claude-3-opus") { routing in
                routing.providers = [.anthropic]
                routing.siteURL = url
                routing.appName = "Swarm"
                routing.dataCollection = .deny
            }
            .makeProvider()

        let metadata = try #require(mirroredOpenRouterMetadata(from: provider))
        #expect(metadata.siteURL == url)
        #expect(metadata.appName == "Swarm")
        #expect(metadata.dataCollectionDescription?.contains("deny") == true)
    }

    @Test("Ollama provider selection preserves advanced settings")
    func ollamaSelectionPreservesAdvancedSettings() throws {
        let provider = ConduitProviderSelection
            .ollama(model: "llama3.2") { settings in
                settings.host = "127.0.0.1"
                settings.port = 11435
                settings.keepAlive = "10m"
                settings.pullOnMissing = true
                settings.numGPU = 2
                settings.lowVRAM = true
                settings.numCtx = 4096
                settings.healthCheck = false
            }
            .makeProvider()

        let configuration = try #require(mirroredOllamaConfiguration(from: provider))
        #expect(configuration.keepAlive == "10m")
        #expect(configuration.pullOnMissing == true)
        #expect(configuration.numGPU == 2)
        #expect(configuration.lowVRAM == true)
        #expect(configuration.numCtx == 4096)
        #expect(configuration.healthCheck == false)
    }

    @Test("Maps Ollama settings to Conduit config")
    func mapsOllamaSettings() {
        let settings = OllamaSettings(
            host: "127.0.0.1",
            port: 11435,
            keepAlive: "10m",
            pullOnMissing: true,
            numGPU: 2,
            lowVRAM: true,
            numCtx: 4096,
            healthCheck: false
        )

        let config = settings.toConduit()
        #expect(config.keepAlive == "10m")
        #expect(config.pullOnMissing == true)
        #expect(config.numGPU == 2)
        #expect(config.lowVRAM == true)
        #expect(config.numCtx == 4096)
        #expect(config.healthCheck == false)
    }

#if canImport(MLX)
    @Test("Builds MLX text-only provider")
    func buildsMLXProvider() {
        let provider = ConduitProviderSelection
            .mlx(model: "mlx-community/Llama-3.2-1B-Instruct-4bit")
            .makeProvider()

        #expect(provider is TextOnlyConversationInferenceProviderAdapter)
        let capabilities = InferenceProviderCapabilities.resolved(for: provider)
        #expect(capabilities.contains(.conversationMessages))
    }

    @Test("Builds MLX local text-only provider")
    func buildsMLXLocalProvider() {
        let provider = ConduitProviderSelection
            .mlxLocal(path: "/Users/me/models/Qwen3-8B-MLX-bf16")
            .makeProvider()

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
