import Foundation
import Testing
@testable import Swarm

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("OpenAI-compatible provider secret references")
struct OpenAICompatibleSecretReferenceTests {
    private let endpoint = URL(string: "https://api.example.test/v1")!
    private let reference = SecretReference(service: "com.swarm.tests", account: "provider-key")

    @Test("Referenced keys are sent as the Bearer credential")
    func referencedKeySentAsBearerCredential() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        OpenAICompatibleURLProtocol.enqueue(json: completionJSON(content: "hello"))

        let store = InMemorySecretStore(secrets: [reference: "resolved-reference-value"])
        let configuration = OpenAICompatibleProviderConfiguration(
            baseURL: endpoint,
            apiKeyReference: reference,
            model: "gpt-test"
        )
        let provider = OpenAICompatibleProvider(
            configuration: configuration,
            secretStore: store,
            session: OpenAICompatibleURLProtocol.makeSession()
        )

        let response = try await provider.generateWithToolCalls(
            messages: [.user("hi")],
            tools: [],
            options: .default
        )
        #expect(response.content == "hello")

        let recorded = try #require(OpenAICompatibleURLProtocol.requests.first)
        #expect(recorded.headers["Authorization"] == "Bearer resolved-reference-value")
    }

    @Test("Inline keys win over references on the wire")
    func inlineKeyWinsOverReference() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        OpenAICompatibleURLProtocol.enqueue(json: completionJSON(content: "hello"))

        let store = InMemorySecretStore(secrets: [reference: "resolved-reference-value"])
        let provider: OpenAICompatibleProvider = .openAICompatible(
            OpenAICompatibleProviderConfiguration(
                baseURL: endpoint,
                apiKey: "inline-wire-value",
                apiKeyReference: reference,
                model: "gpt-test"
            ),
            secretStore: store,
            session: OpenAICompatibleURLProtocol.makeSession()
        )

        _ = try await provider.generateWithToolCalls(
            messages: [.user("hi")],
            tools: [],
            options: .default
        )

        let recorded = try #require(OpenAICompatibleURLProtocol.requests.first)
        #expect(recorded.headers["Authorization"] == "Bearer inline-wire-value")
    }

    @Test("Unresolvable references send no Authorization header")
    func unresolvableReferenceSendsNoAuthHeader() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        OpenAICompatibleURLProtocol.enqueue(json: completionJSON(content: "hello"))

        let provider = OpenAICompatibleProvider(
            configuration: OpenAICompatibleProviderConfiguration(
                baseURL: endpoint,
                apiKeyReference: reference,
                model: "gpt-test"
            ),
            secretStore: InMemorySecretStore(),
            session: OpenAICompatibleURLProtocol.makeSession()
        )

        _ = try await provider.generateWithToolCalls(
            messages: [.user("hi")],
            tools: [],
            options: .default
        )

        let recorded = try #require(OpenAICompatibleURLProtocol.requests.first)
        #expect(recorded.headers["Authorization"] == nil)
    }

    private func completionJSON(content: String) -> String {
        """
        {
          "choices": [
            { "index": 0, "message": { "role": "assistant", "content": "\(content)" }, "finish_reason": "stop" }
          ],
          "usage": { "prompt_tokens": 1, "completion_tokens": 1 }
        }
        """
    }
}
