import Conduit
import Foundation
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
        #expect(config.dataCollection == Conduit.OpenRouterDataCollection.deny)
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
}
