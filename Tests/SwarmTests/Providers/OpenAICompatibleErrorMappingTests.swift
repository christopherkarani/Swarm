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

    @Test("HTTP 401 maps to non-retryable authenticationFailed")
    func status401IsAuthenticationFailed() async throws {
        let error = try await failure(status: 401, body: #"{"error":{"message":"nope"}}"#)
        guard case let .authenticationFailed(reason) = error else {
            Issue.record("expected authenticationFailed, got \(error)")
            return
        }
        #expect(reason.contains("401"))
        #expect(reason.contains("nope"))
        #expect(error.isRetryable == false)
        #expect(InferenceRetryability.isRetryable(error) == false)
    }

    @Test("HTTP 403 maps to non-retryable authenticationFailed")
    func status403IsAuthenticationFailed() async throws {
        let error = try await failure(status: 403, body: #"{"error":{"message":"forbidden"}}"#)
        guard case .authenticationFailed = error else {
            Issue.record("expected authenticationFailed, got \(error)")
            return
        }
        #expect(InferenceRetryability.isRetryable(error) == false)
    }

    @Test("HTTP 402 mentions billing and is not retryable")
    func status402MentionsBilling() async throws {
        let error = try await failure(status: 402, body: #"{"error":{"message":"quota hit"}}"#)
        guard case let .invalidInput(reason) = error else {
            Issue.record("expected invalidInput, got \(error)")
            return
        }
        #expect(reason.localizedCaseInsensitiveContains("billing"))
        #expect(InferenceRetryability.isRetryable(error) == false)
    }

    @Test("HTTP 429 with insufficient_quota is not retryable")
    func status429InsufficientQuotaIsNotRetryable() async throws {
        let error = try await failure(
            status: 429,
            body: #"{"error":{"message":"check your plan","code":"insufficient_quota"}}"#
        )
        guard case .invalidInput = error else {
            Issue.record("expected invalidInput, got \(error)")
            return
        }
        #expect(InferenceRetryability.isRetryable(error) == false)
    }

    @Test("String error bodies are extracted")
    func stringErrorBodyIsExtracted() async throws {
        let error = try await failure(status: 400, body: #"{"error":"plain failure"}"#)
        guard case let .invalidInput(reason) = error else {
            Issue.record("expected invalidInput, got \(error)")
            return
        }
        #expect(reason.contains("plain failure"))
    }

    @Test("Google nested errors array message is extracted")
    func googleNestedErrorsAreExtracted() async throws {
        let error = try await failure(
            status: 400,
            body: #"{"error":{"errors":[{"message":"nested boom"}],"status":"INVALID_ARGUMENT"}}"#
        )
        guard case let .invalidInput(reason) = error else {
            Issue.record("expected invalidInput, got \(error)")
            return
        }
        #expect(reason.contains("nested boom"))
    }

    @Test("FastAPI detail message is extracted")
    func fastAPIDetailIsExtracted() async throws {
        let error = try await failure(status: 400, body: #"{"detail":"fast failure"}"#)
        guard case let .invalidInput(reason) = error else {
            Issue.record("expected invalidInput, got \(error)")
            return
        }
        #expect(reason.contains("fast failure"))
    }

    @Test("Top-level array error message is extracted")
    func topLevelArrayErrorIsExtracted() async throws {
        let error = try await failure(status: 400, body: #"[{"message":"array failure"}]"#)
        guard case let .invalidInput(reason) = error else {
            Issue.record("expected invalidInput, got \(error)")
            return
        }
        #expect(reason.contains("array failure"))
    }

    @Test("Numeric error codes do not break mapping")
    func numericErrorCodeIsTolerated() async throws {
        let error = try await failure(
            status: 400,
            body: #"{"error":{"message":"numeric code","code":400}}"#
        )
        guard case let .invalidInput(reason) = error else {
            Issue.record("expected invalidInput, got \(error)")
            return
        }
        #expect(reason.contains("numeric code"))
    }

    @Test("Retry-After HTTP date maps to delay")
    func retryAfterHTTPDateMapsToDelay() {
        let fireDate = Date().addingTimeInterval(30)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let error = OpenAICompatibleErrorMapper.map(
            statusCode: 429,
            body: Data(#"{"error":{"message":"slow"}}"#.utf8),
            headers: ["Retry-After": formatter.string(from: fireDate)],
            model: "gpt-test"
        )
        guard case let .rateLimitExceeded(retryAfter) = error else {
            Issue.record("expected rateLimitExceeded, got \(error)")
            return
        }
        #expect(retryAfter != nil)
        #expect(retryAfter ?? -1 > 0)
        #expect(retryAfter ?? 999 <= 30)
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
