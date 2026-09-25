import Foundation
import Testing
@testable import Swarm

@Suite("API key reference resolution")
struct SecretResolutionTests {
    private let endpoint = URL(string: "https://api.example.test/v1")!
    private let reference = SecretReference(service: "com.swarm.tests", account: "provider-key")

    @Test("OpenAI-compatible configuration prefers the inline key over the reference")
    func openAICompatiblePrefersInlineKey() async throws {
        let store = InMemorySecretStore(secrets: [reference: "referenced-value"])
        let configuration = OpenAICompatibleProviderConfiguration(
            baseURL: endpoint,
            apiKey: "  inline-value  ",
            apiKeyReference: reference,
            model: "gpt-test"
        )
        #expect(try await configuration.resolveAPIKey(using: store) == "inline-value")
    }

    @Test("OpenAI-compatible configuration resolves the reference from the store")
    func openAICompatibleResolvesReference() async throws {
        let store = InMemorySecretStore(secrets: [reference: "referenced-value"])
        let configuration = OpenAICompatibleProviderConfiguration(
            baseURL: endpoint,
            apiKeyReference: reference,
            model: "gpt-test"
        )
        #expect(try await configuration.resolveAPIKey(using: store) == "referenced-value")
    }

    @Test("OpenAI-compatible resolve returns nil without a key, reference, or store")
    func openAICompatibleResolveReturnsNilWhenUnavailable() async throws {
        let emptyStore = InMemorySecretStore()
        let referenceOnly = OpenAICompatibleProviderConfiguration(
            baseURL: endpoint,
            apiKeyReference: reference,
            model: "gpt-test"
        )
        // Reference set but no store.
        #expect(try await referenceOnly.resolveAPIKey(using: nil) == nil)
        // Store has no matching secret.
        #expect(try await referenceOnly.resolveAPIKey(using: emptyStore) == nil)
        // Neither key nor reference.
        let bare = OpenAICompatibleProviderConfiguration(baseURL: endpoint, model: "gpt-test")
        #expect(try await bare.resolveAPIKey(using: emptyStore) == nil)
    }

    @Test("WebSearch configuration resolves the reference from the store")
    func webSearchResolvesReference() async throws {
        let store = InMemorySecretStore(secrets: [reference: "search-value"])
        var configuration = WebSearchTool.Configuration(apiKeyReference: reference)
        #expect(try await configuration.resolveAPIKey(using: store) == "search-value")
        configuration.apiKey = "inline-search-value"
        #expect(try await configuration.resolveAPIKey(using: store) == "inline-search-value")
        #expect(try await configuration.resolveAPIKey(using: nil) == "inline-search-value")
    }

    @Test("WebSearch hasLiveSearchBackend counts references as configured")
    func webSearchBackendPresenceCountsReferences() {
        #expect(WebSearchTool.Configuration().hasLiveSearchBackend == false)
        #expect(WebSearchTool.Configuration(apiKey: "key").hasLiveSearchBackend == true)
        #expect(WebSearchTool.Configuration(apiKeyReference: reference).hasLiveSearchBackend == true)
    }
}
