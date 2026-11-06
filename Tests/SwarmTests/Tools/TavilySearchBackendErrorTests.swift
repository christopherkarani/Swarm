#if SWARM_INTEGRATIONS && !os(Linux)
import Foundation
@testable import Swarm
import Testing

/// `TavilySearchBackend` posts through `URLSession.shared`; a globally
/// registered protocol that only claims `api.tavily.com` stubs it.
@Suite("Tavily backend error redaction", .serialized)
struct TavilySearchBackendErrorTests {
    @Test("Failed Tavily responses surface a status-only message to the model")
    func failureMessageOmitsBody() async throws {
        TavilyStubURLProtocol.respond(
            status: 401,
            body: #"{"detail":{"error":"Invalid API key tvly-SECRETSECRET for query 'my medical records'"}}"#
        )
        URLProtocol.registerClass(TavilyStubURLProtocol.self)
        defer { URLProtocol.unregisterClass(TavilyStubURLProtocol.self) }

        let backend = TavilySearchBackend(
            configuration: WebSearchTool.Configuration(apiKey: "tvly-SECRETSECRET"),
            secretStore: nil
        )

        do {
            _ = try await backend.search(query: "my medical records", maxResults: 3, domains: [], recencyDays: nil)
            Issue.record("Expected a Tavily failure")
        } catch let AgentError.toolFailure(_, message, _) {
            let text = try #require(message)
            #expect(text == "Tavily request failed (HTTP 401: authentication failed)")
            #expect(!text.contains("tvly-"))
            #expect(!text.contains("medical"))
        }
    }

    @Test("Logged Tavily error bodies are redacted and truncated")
    func sanitizedErrorBodyRedactsAndTruncates() {
        let body = Data(("api key tvly-SECRETSECRET rejected\n" + String(repeating: "x", count: 1000)).utf8)
        let sanitized = TavilySearchBackend.sanitizedErrorBody(body, apiKey: "tvly-SECRETSECRET")

        #expect(!sanitized.contains("SECRETSECRET"))
        #expect(!sanitized.contains("\n"))
        #expect(sanitized.count <= TavilySearchBackend.maxLoggedErrorBodyLength + 1)
    }

    @Test("Undecodable bodies are summarized by size")
    func sanitizedErrorBodyHandlesBinary() {
        let sanitized = TavilySearchBackend.sanitizedErrorBody(Data([0xFF, 0xFE, 0x00]), apiKey: "k")
        #expect(sanitized == "(3-byte non-UTF-8 body)")
    }
}

private final class TavilyStubURLProtocol: URLProtocol {
    private struct Response: Sendable {
        let status: Int
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var response = Response(status: 500, body: Data())

    static func respond(status: Int, body: String) {
        lock.withLock { response = Response(status: status, body: Data(body.utf8)) }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.tavily.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let stub = Self.lock.withLock { Self.response }
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
