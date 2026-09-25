#if SWARM_INTEGRATIONS
import Foundation
@testable import Swarm
import Testing

@Suite("WebSearch secret resolution")
struct WebSearchSecretResolutionTests {
    @Test("Unresolvable references return no hits without a network call")
    func unresolvableReferenceReturnsNoHits() async throws {
        let reference = SecretReference(service: "com.swarm.tests", account: "search-key")
        let backend = TavilySearchBackend(
            configuration: WebSearchTool.Configuration(apiKeyReference: reference),
            secretStore: InMemorySecretStore()
        )
        // The empty key short-circuits before any HTTP request is built.
        let hits = try await backend.search(query: "swift", maxResults: 3, domains: [], recencyDays: nil)
        #expect(hits.isEmpty)
    }

    @Test("Tool initializers accept a secret store")
    func toolInitAcceptsSecretStore() {
        let reference = SecretReference(service: "com.swarm.tests", account: "search-key")
        let tool = WebSearchTool(
            configuration: WebSearchTool.Configuration(apiKeyReference: reference),
            secretStore: InMemorySecretStore()
        )
        #expect(tool.isEnabled)
        #expect(String(reflecting: tool).contains("com.swarm.tests"))
    }
}
#endif
