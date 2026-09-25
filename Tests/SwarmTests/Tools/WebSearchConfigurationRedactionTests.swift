import Foundation
@testable import Swarm
import Testing

@Suite("WebSearch Configuration Redaction Tests")
struct WebSearchConfigurationRedactionTests {
    @Test("configuration descriptions never include the API key value")
    func configurationDescriptionsRedactAPIKey() {
        let secret = "[REDACTED] websearch key value"
        let configured = WebSearchTool.Configuration(apiKey: secret)

        #expect(configured.hasLiveSearchBackend)
        #expect(configured.description.contains(secret) == false)
        #expect(configured.debugDescription.contains(secret) == false)
        #expect(String(describing: configured).contains(secret) == false)
        #expect(String(reflecting: configured).contains(secret) == false)
        #expect(configured.description.contains("<configured>"))
    }

    @Test("configuration descriptions report an absent key")
    func configurationDescriptionsReportAbsentKey() {
        let unconfigured = WebSearchTool.Configuration(apiKey: nil)

        #expect(!unconfigured.hasLiveSearchBackend)
        #expect(unconfigured.description.contains("<absent>"))
        #expect(unconfigured.debugDescription.contains("<absent>"))
    }
}
