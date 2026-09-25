import Foundation
import Testing
@testable import Swarm

@Suite("Secret redaction")
struct SecretRedactionTests {
    @Test("Sensitive names match credential carriers only")
    func sensitiveNameMatching() {
        #expect(SecretRedaction.isSensitiveName("Authorization"))
        #expect(SecretRedaction.isSensitiveName("authorization"))
        #expect(SecretRedaction.isSensitiveName("X-API-Key"))
        #expect(SecretRedaction.isSensitiveName("api_key"))
        #expect(SecretRedaction.isSensitiveName("X-Session-ID"))
        #expect(SecretRedaction.isSensitiveName("Cookie"))

        #expect(!SecretRedaction.isSensitiveName("Content-Type"))
        #expect(!SecretRedaction.isSensitiveName("HTTP-Referer"))
        #expect(!SecretRedaction.isSensitiveName("api-version"))
        #expect(!SecretRedaction.isSensitiveName("Accept"))
    }

    @Test("Redacted values keep benign entries readable")
    func redactedValuesKeepBenignEntries() {
        let redacted = SecretRedaction.redactedSensitiveValues([
            "Authorization": "credential-abc-123",
            "Content-Type": "application/json",
        ])
        #expect(redacted["Authorization"] == SecretRedaction.placeholder)
        #expect(redacted["Content-Type"] == "application/json")
    }

    @Test("Known secrets are scrubbed from free-form text")
    func knownSecretsScrubbedFromText() {
        let scrubbed = SecretRedaction.redactingKnownSecrets(
            in: "key=sk-live-9f8e7d6c5b ok",
            secrets: ["sk-live-9f8e7d6c5b", nil, ""]
        )
        #expect(scrubbed == "key=[redacted] ok")
        #expect(SecretRedaction.redactingKnownSecrets(in: "unchanged", secrets: [nil, ""]) == "unchanged")
    }

    @Test("OpenAI-compatible debug description redacts the key and sensitive headers")
    func openAICompatibleDebugDescriptionRedactsSecrets() {
        let configuration = OpenAICompatibleProviderConfiguration(
            baseURL: URL(string: "https://api.example.test/v1")!,
            apiKey: "sk-live-9f8e7d6c5b",
            model: "gpt-test",
            httpHeaders: ["Authorization": "credential-abc-123", "X-Custom": "visible-custom"],
            queryItems: ["api-version": "2024-10-21"]
        )
        let description = String(reflecting: configuration)
        #expect(!description.contains("sk-live-9f8e7d6c5b"))
        #expect(!description.contains("credential-abc-123"))
        #expect(description.contains(SecretRedaction.placeholder))
        #expect(description.contains("visible-custom"))
        #expect(description.contains("2024-10-21"))
        #expect(description.contains("gpt-test"))
    }

    @Test("WebSearch debug descriptions redact key material")
    func webSearchDebugDescriptionsRedactSecrets() {
        let configuration = WebSearchTool.Configuration(apiKey: "tavily-secret-xyz")
        let configurationDescription = String(reflecting: configuration)
        #expect(!configurationDescription.contains("tavily-secret-xyz"))
        #expect(configurationDescription.contains(SecretRedaction.placeholder))

        let tool = WebSearchTool(apiKey: "legacy-secret-xyz")
        let toolDescription = String(reflecting: tool)
        #expect(!toolDescription.contains("legacy-secret-xyz"))
        #expect(toolDescription.contains(SecretRedaction.placeholder))
    }
}
