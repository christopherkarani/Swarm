import Foundation
import Testing
@testable import Swarm

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("OpenAI-compatible error mapping")
struct OpenAICompatibleErrorMappingTests {
    private let endpoint = URL(string: "https://api.example.test/v1")!

    @Test("HTTP 429 maps to retryable rateLimitExceeded")
    func status429IsRetryableRateLimit() async throws {
        let error = try await failure(status: 429, body: #"{"error":{"message":"slow down"}}"#, headers: ["Retry-After": "2"])
        guard case let .rateLimitExceeded(retryAfter) = error else {
            Issue.record("expected rateLimitExceeded, got \(error)")
            return
        }
        #expect(retryAfter == 2)
        #expect(error.isRetryable)
        #expect(InferenceRetryability.isRetryable(error))
    }

    @Test("HTTP 500 maps to retryable generationFailed")
    func status500IsRetryableGenerationFailed() async throws {
        let error = try await failure(status: 500, body: #"{"error":{"message":"boom"}}"#)
        guard case .generationFailed = error else {
            Issue.record("expected generationFailed, got \(error)")
            return
        }
        #expect(error.isRetryable)
        #expect(InferenceRetryability.isRetryable(error))
    }

    @Test("HTTP 503 maps to retryable generationFailed")
    func status503IsRetryableGenerationFailed() async throws {
        let error = try await failure(status: 503, body: "unavailable")
        guard case .generationFailed = error else {
            Issue.record("expected generationFailed, got \(error)")
            return
        }
        #expect(InferenceRetryability.isRetryable(error))
    }

    @Test("HTTP 400 is not retryable")
    func status400IsNotRetryable() async throws {
        let error = try await failure(status: 400, body: #"{"error":{"message":"bad schema"}}"#)
        guard case .invalidInput = error else {
            Issue.record("expected invalidInput, got \(error)")
            return
        }
        #expect(error.isRetryable == false)
        #expect(InferenceRetryability.isRetryable(error) == false)
    }

    @Test("HTTP 401 is not retryable")
    func status401IsNotRetryable() async throws {
        let error = try await failure(status: 401, body: #"{"error":{"message":"nope"}}"#)
        guard case .invalidInput = error else {
            Issue.record("expected invalidInput, got \(error)")
            return
        }
        #expect(InferenceRetryability.isRetryable(error) == false)
    }

    @Test("HTTP 403 is not retryable")
    func status403IsNotRetryable() async throws {
        let error = try await failure(status: 403, body: #"{"error":{"message":"forbidden"}}"#)
        guard case .invalidInput = error else {
            Issue.record("expected invalidInput, got \(error)")
            return
        }
        #expect(InferenceRetryability.isRetryable(error) == false)
    }

    @Test("Network URLError remains retryable without wrapping")
    func networkURLErrorStaysRetryable() {
        let error = URLError(.cannotConnectToHost)
        let mapped = OpenAICompatibleErrorMapper.mapTransport(error)
        #expect(mapped is URLError)
        #expect(InferenceRetryability.isRetryable(mapped))
    }

    @Test("Streaming HTTP 400 is not retryable")
    func streamingStatus400IsNotRetryable() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        OpenAICompatibleURLProtocol.enqueue(
            status: 400,
            json: #"{"error":{"message":"bad stream"}}"#
        )
        let provider = makeProvider()
        do {
            for try await _ in provider.stream(messages: [.user("hi")], options: .default) {}
            Issue.record("expected stream to throw")
        } catch let error as AgentError {
            guard case .invalidInput = error else {
                Issue.record("expected invalidInput, got \(error)")
                return
            }
            #expect(InferenceRetryability.isRetryable(error) == false)
        }
    }

    private func failure(
        status: Int,
        body: String,
        headers: [String: String] = [:]
    ) async throws -> AgentError {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        var responseHeaders = ["Content-Type": "application/json"]
        for (key, value) in headers {
            responseHeaders[key] = value
        }
        OpenAICompatibleURLProtocol.enqueue(status: status, headers: responseHeaders, json: body)
        do {
            _ = try await makeProvider().generate(messages: [.user("hi")], options: .default)
            Issue.record("expected provider to throw")
            throw AgentError.internalError(reason: "expected throw")
        } catch let error as AgentError {
            return error
        }
    }

    private func makeProvider() -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            configuration: .init(baseURL: endpoint, apiKey: "sk-test", model: "gpt-test"),
            session: OpenAICompatibleURLProtocol.makeSession()
        )
    }
}
