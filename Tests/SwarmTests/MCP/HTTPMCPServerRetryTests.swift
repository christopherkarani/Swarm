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
