import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Swarm
import Testing

@Suite("HTTPMCPServer Retry Tests", .serialized)
struct HTTPMCPServerRetryTests {
    @Test("Does not retry on HTTP 4xx responses")
    func doesNotRetryOnClientErrors() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://mcp.example.com/api")!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("bad request".utf8))
        }

        let server = try HTTPMCPServer(
            url: URL(string: "https://mcp.example.com/api")!,
            name: "retry-test",
            maxRetries: 3,
            session: session
        )

        await #expect(throws: MCPError.self) {
            _ = try await server.listTools()
        }

        #expect(MockURLProtocol.requestCount == 1)
    }

    @Test("List tools preserves nested input schema fidelity")
    func listToolsPreservesNestedInputSchemaFidelity() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://mcp.example.com/api")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let body: [String: Any] = [
                "jsonrpc": "2.0",
                "id": "tools-list",
                "result": [
                    "tools": [
                        [
                            "name": "search",
                            "description": "Search documents",
                            "inputSchema": [
                                "type": "object",
                                "required": ["payload"],
                                "properties": [
                                    "payload": [
                                        "type": "object",
                                        "description": "Search payload",
                                        "required": ["query", "filters"],
                                        "properties": [
                                            "query": [
                                                "type": "string",
                                                "description": "Query source",
                                                "enum": ["docs", "news"]
                                            ],
                                            "category": [
                                                "type": "string",
                                                "description": "Content category",
                                                "oneOf": [
                                                    ["enum": ["guide", "api"]],
                                                    ["const": "blog"],
                                                    ["enum": ["release", "example"]]
                                                ]
                                            ],
                                            "limit": [
                                                "type": "integer",
                                                "description": "Maximum results",
                                                "default": 10
                                            ],
                                            "filters": [
                                                "type": "array",
                                                "description": "Structured filters",
                                                "items": [
                                                    "type": "object",
                                                    "required": ["field"],
                                                    "properties": [
                                                        "field": [
                                                            "type": "string",
                                                            "description": "Field name"
                                                        ],
                                                        "values": [
                                                            "type": "array",
                                                            "description": "Allowed values",
                                                            "items": ["type": "string"]
                                                        ]
                                                    ]
                                                ]
                                            ]
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
            return (response, try JSONSerialization.data(withJSONObject: body))
        }

        let server = try HTTPMCPServer(
            url: URL(string: "https://mcp.example.com/api")!,
            name: "schema-test",
            maxRetries: 0,
            session: session
        )

        let tools = try await server.listTools()
        let tool = try #require(tools.first)
        let payload = try #require(tool.parameters.first { $0.name == "payload" })
        #expect(payload.isRequired)

        guard case let .object(payloadProperties) = payload.type else {
            Issue.record("Expected payload to remain an object schema")
            return
        }

        let query = try #require(payloadProperties.first { $0.name == "query" })
        #expect(query.isRequired)
        #expect(query.type == .oneOf(["docs", "news"]))

        let category = try #require(payloadProperties.first { $0.name == "category" })
        #expect(!category.isRequired)
        #expect(category.type == .oneOf(["guide", "api", "blog", "release", "example"]))

        let limit = try #require(payloadProperties.first { $0.name == "limit" })
        #expect(!limit.isRequired)
        #expect(limit.defaultValue == .int(10))

        let filters = try #require(payloadProperties.first { $0.name == "filters" })
        #expect(filters.isRequired)
        guard case let .array(elementType) = filters.type,
              case let .object(filterProperties) = elementType else {
            Issue.record("Expected filters to preserve array object item schema")
            return
        }

        let field = try #require(filterProperties.first { $0.name == "field" })
        #expect(field.isRequired)
        #expect(field.type == .string)

        let values = try #require(filterProperties.first { $0.name == "values" })
        #expect(!values.isRequired)
        #expect(values.type == .array(elementType: .string))
    }

    @Test("Call tool treats MCP isError result as execution failure")
    func callToolTreatsIsErrorResultAsExecutionFailure() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://mcp.example.com/api")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let body: [String: Any] = [
                "jsonrpc": "2.0",
                "id": "tool-call",
                "result": [
                    "content": [
                        [
                            "type": "text",
                            "text": "remote tool failed"
                        ]
                    ],
                    "isError": true
                ]
            ]
            return (response, try JSONSerialization.data(withJSONObject: body))
        }

        let server = try HTTPMCPServer(
            url: URL(string: "https://mcp.example.com/api")!,
            name: "tool-error-test",
            maxRetries: 0,
            session: session
        )

        do {
            _ = try await server.callTool(name: "explode", arguments: [:])
            Issue.record("Expected remote isError tool result to throw")
        } catch let error as MCPError {
            #expect(error.code == MCPError.internalErrorCode)
            #expect(error.message.contains("explode"))
            #expect(error.message.contains("remote tool failed"))
            #expect(error.data?.dictionaryValue?["isError"]?.boolValue == true)
        } catch {
            Issue.record("Expected MCPError, got \(error)")
        }
    }

    @Test(
        "tools/call is never resent after the request may have reached the server",
        arguments: [
            ToolCallFailure.httpStatus(500),
            ToolCallFailure.httpStatus(503),
            ToolCallFailure.transport(.timedOut),
            ToolCallFailure.transport(.networkConnectionLost),
        ]
    )
    func toolsCallIsNotRetriedOnAmbiguousFailure(_ failure: ToolCallFailure) async throws {
        let session = Self.makeSession()
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        MockURLProtocol.handler = { request in try failure.respond(to: request) }

        let server = try HTTPMCPServer(
            url: URL(string: "https://mcp.example.com/api")!,
            name: "no-retry-tools-call",
            maxRetries: 3,
            session: session
        )

        await #expect(throws: MCPError.self) {
            _ = try await server.callTool(name: "transfer_funds", arguments: [:])
        }
        #expect(MockURLProtocol.requestCount == 1)
    }

    @Test("tools/call is retried when the connection never opened")
    func toolsCallIsRetriedOnPreSendFailure() async throws {
        let session = Self.makeSession()
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        MockURLProtocol.handler = { request in
            if MockURLProtocol.requestCount == 1 {
                throw URLError(.cannotConnectToHost)
            }
            return try Self.toolCallSuccess(for: request)
        }

        let server = try HTTPMCPServer(
            url: URL(string: "https://mcp.example.com/api")!,
            name: "retry-pre-send",
            maxRetries: 1,
            session: session
        )

        _ = try await server.callTool(name: "echo", arguments: [:])
        #expect(MockURLProtocol.requestCount == 2)
    }

    @Test("Read-only methods still retry transient server failures")
    func listToolsRetriesServerErrors() async throws {
        let session = Self.makeSession()
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        MockURLProtocol.handler = { request in try ToolCallFailure.httpStatus(503).respond(to: request) }

        let server = try HTTPMCPServer(
            url: URL(string: "https://mcp.example.com/api")!,
            name: "retry-list",
            maxRetries: 1,
            session: session
        )

        await #expect(throws: MCPError.self) {
            _ = try await server.listTools()
        }
        #expect(MockURLProtocol.requestCount == 2)
    }

    @Test("5xx twice then success backs off 1s then 2s without waiting on the clock")
    func serverErrorsBackOffThroughInjectedSleep() async throws {
        let session = Self.makeSession()
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        MockURLProtocol.handler = { request in
            if MockURLProtocol.requestCount <= 2 {
                return try ToolCallFailure.httpStatus(503).respond(to: request)
            }
            return try Self.toolsListSuccess(for: request)
        }
        let recorder = SleepRecorder()

        let server = try HTTPMCPServer(
            url: URL(string: "https://mcp.example.com/api")!,
            name: "retry-backoff",
            apiKey: nil,
            timeout: 30,
            maxRetries: 3,
            session: session,
            sleep: { await recorder.record($0) }
        )

        let elapsed = try await ContinuousClock().measure {
            _ = try await server.listTools()
        }

        #expect(MockURLProtocol.requestCount == 3)
        #expect(await recorder.durations == [.seconds(1), .seconds(2)])
        // A real backoff would take at least 1s + 2s; the injected sleep returns at once.
        #expect(elapsed < .seconds(3))
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func toolCallSuccess(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://mcp.example.com/api")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "call",
            "result": ["content": [["type": "text", "text": "ok"]]],
        ]
        return (response, try JSONSerialization.data(withJSONObject: body))
    }

    private static func toolsListSuccess(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://mcp.example.com/api")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "tools-list",
            "result": ["tools": [] as [Any]],
        ]
        return (response, try JSONSerialization.data(withJSONObject: body))
    }
}

/// Records backoff durations instead of sleeping.
private actor SleepRecorder {
    private(set) var durations: [Duration] = []

    func record(_ duration: Duration) {
        durations.append(duration)
    }
}

// MARK: - MCPRetryDecision

@Suite("MCPRetryDecision")
struct MCPRetryDecisionTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let error: any Error
        let attempt: Int
        let maxRetries: Int
        let scope: HTTPMCPServer.RetryScope
        let expected: MCPRetryDecision
    }

    static let rows: [Row] = [
        // Client errors never retry, whatever the scope or attempt.
        Row(testDescription: "HTTP 400", error: MCPError(code: 400, message: "bad"), attempt: 0, maxRetries: 3, scope: .transientFailures, expected: .fail),
        Row(testDescription: "HTTP 404", error: MCPError(code: 404, message: "missing"), attempt: 0, maxRetries: 3, scope: .transientFailures, expected: .fail),
        Row(testDescription: "HTTP 499", error: MCPError(code: 499, message: "closed"), attempt: 1, maxRetries: 3, scope: .transientFailures, expected: .fail),
        Row(testDescription: "JSON-RPC invalid request", error: MCPError.invalidRequest("x"), attempt: 0, maxRetries: 3, scope: .transientFailures, expected: .fail),
        Row(testDescription: "JSON-RPC invalid params", error: MCPError.invalidParams("x"), attempt: 0, maxRetries: 3, scope: .transientFailures, expected: .fail),
        Row(testDescription: "JSON-RPC method not found", error: MCPError.methodNotFound("x"), attempt: 0, maxRetries: 3, scope: .transientFailures, expected: .fail),
        // 5xx and other MCP errors retry idempotent methods with 1s, 2s, 4s backoff.
        Row(testDescription: "HTTP 500 attempt 0", error: MCPError(code: 500, message: "boom"), attempt: 0, maxRetries: 3, scope: .transientFailures, expected: .retry(after: .seconds(1))),
        Row(testDescription: "HTTP 503 attempt 1", error: MCPError(code: 503, message: "busy"), attempt: 1, maxRetries: 3, scope: .transientFailures, expected: .retry(after: .seconds(2))),
        Row(testDescription: "HTTP 502 attempt 2", error: MCPError(code: 502, message: "gateway"), attempt: 2, maxRetries: 3, scope: .transientFailures, expected: .retry(after: .seconds(4))),
        Row(testDescription: "JSON-RPC internal error", error: MCPError.internalError("x"), attempt: 0, maxRetries: 3, scope: .transientFailures, expected: .retry(after: .seconds(1))),
        Row(testDescription: "HTTP 500 non-idempotent", error: MCPError(code: 500, message: "boom"), attempt: 0, maxRetries: 3, scope: .connectionNotEstablished, expected: .fail),
        Row(testDescription: "HTTP 500 attempt == maxRetries", error: MCPError(code: 500, message: "boom"), attempt: 3, maxRetries: 3, scope: .transientFailures, expected: .fail),
        Row(testDescription: "HTTP 500 maxRetries 0", error: MCPError(code: 500, message: "boom"), attempt: 0, maxRetries: 0, scope: .transientFailures, expected: .fail),
        // Transport errors retry idempotent methods; others only when the connection never opened.
        Row(testDescription: "timeout idempotent", error: URLError(.timedOut), attempt: 0, maxRetries: 3, scope: .transientFailures, expected: .retry(after: .seconds(1))),
        Row(testDescription: "timeout non-idempotent", error: URLError(.timedOut), attempt: 0, maxRetries: 3, scope: .connectionNotEstablished, expected: .fail),
        Row(testDescription: "connection lost non-idempotent", error: URLError(.networkConnectionLost), attempt: 0, maxRetries: 3, scope: .connectionNotEstablished, expected: .fail),
        Row(testDescription: "cannot connect non-idempotent", error: URLError(.cannotConnectToHost), attempt: 1, maxRetries: 3, scope: .connectionNotEstablished, expected: .retry(after: .seconds(2))),
        Row(testDescription: "DNS failure non-idempotent", error: URLError(.dnsLookupFailed), attempt: 0, maxRetries: 3, scope: .connectionNotEstablished, expected: .retry(after: .seconds(1))),
        Row(testDescription: "cannot connect attempt == maxRetries", error: URLError(.cannotConnectToHost), attempt: 2, maxRetries: 2, scope: .connectionNotEstablished, expected: .fail),
        Row(testDescription: "timeout maxRetries 0", error: URLError(.timedOut), attempt: 0, maxRetries: 0, scope: .transientFailures, expected: .fail),
        // Cancellation is classified like any transport error; the shell's
        // `Task.checkCancellation()` before sleeping is what stops a cancelled task.
        Row(testDescription: "cancellation idempotent", error: CancellationError(), attempt: 0, maxRetries: 3, scope: .transientFailures, expected: .retry(after: .seconds(1))),
        Row(testDescription: "cancellation non-idempotent", error: CancellationError(), attempt: 0, maxRetries: 3, scope: .connectionNotEstablished, expected: .fail),
        Row(testDescription: "cancellation attempt == maxRetries", error: CancellationError(), attempt: 3, maxRetries: 3, scope: .transientFailures, expected: .fail),
    ]

    @Test("decide follows the HTTP MCP retry policy", arguments: rows)
    func decide(_ row: Row) {
        let decision = MCPRetryDecision.decide(
            error: row.error,
            attempt: row.attempt,
            maxRetries: row.maxRetries,
            scope: row.scope
        )
        #expect(decision == row.expected)
    }
}

enum ToolCallFailure: Sendable, CustomTestStringConvertible {
    case httpStatus(Int)
    case transport(URLError.Code)

    var testDescription: String {
        switch self {
        case let .httpStatus(code): "HTTP \(code)"
        case let .transport(code): "URLError \(code.rawValue)"
        }
    }

    func respond(to request: URLRequest) throws -> (HTTPURLResponse, Data) {
        switch self {
        case let .httpStatus(status):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://mcp.example.com/api")!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("server error".utf8))
        case let .transport(code):
            throw URLError(code)
        }
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestCount: Int = 0
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        requestCount = 0
        handler = nil
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            fatalError("MockURLProtocol.handler not set")
        }

        Self.requestCount += 1

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
