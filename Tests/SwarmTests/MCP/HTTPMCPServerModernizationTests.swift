// HTTPMCPServerModernizationTests.swift
// SwarmTests
//
// Version negotiation, envelope unwrap, empty tool names, and streamable HTTP.

import Foundation
@testable import Swarm
import Testing

@Suite("HTTPMCPServer Modernization Tests", .serialized)
struct HTTPMCPServerModernizationTests {
    @Test("Unsupported protocol version fails loudly")
    func unsupportedProtocolVersionFails() async throws {
        let session = try makeSession { _, body in
            let request = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let id = request["id"] as? String ?? "1"
            return try jsonResponse(
                id: id,
                result: [
                    "protocolVersion": "1999-01-01",
                    "capabilities": ["tools": [:]]
                ]
            )
        }
        defer { ModernizationURLProtocol.reset() }

        let server = try HTTPMCPServer(
            url: URL(string: "https://mcp.example.com/api")!,
            name: "version-test",
            maxRetries: 0,
            session: session
        )

        do {
            _ = try await server.initialize()
            Issue.record("Expected unsupported protocol version to throw")
        } catch let error as MCPError {
            #expect(error.code == MCPError.invalidRequestCode)
            #expect(error.message.contains("1999-01-01"))
            #expect(error.message.contains("2024-11-05"))
        }
    }

    @Test("callTool unwraps a single text content block")
    func callToolUnwrapsTextContent() async throws {
        let session = try makeSession { _, body in
            let request = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let id = request["id"] as? String ?? "1"
            return try jsonResponse(
                id: id,
                result: [
                    "content": [
                        ["type": "text", "text": "hello from envelope"]
                    ],
                    "isError": false
                ]
            )
        }
        defer { ModernizationURLProtocol.reset() }

        let server = try HTTPMCPServer(
            url: URL(string: "https://mcp.example.com/api")!,
            name: "unwrap-test",
            maxRetries: 0,
            session: session
        )

        let unwrapped = try await server.callTool(name: "echo", arguments: [:])
        #expect(unwrapped == .string("hello from envelope"))

        let raw = try await server.callToolRaw(name: "echo", arguments: [:])
        #expect(raw.dictionaryValue?["isError"]?.boolValue == false)
        #expect(raw.dictionaryValue?["content"]?.arrayValue?.isEmpty == false)
    }

    @Test("Empty tool name returns an error instead of trapping")
    func emptyToolNameReturnsError() async throws {
        let server = try HTTPMCPServer(
            url: URL(string: "https://mcp.example.com/api")!,
            name: "empty-name",
            maxRetries: 0
        )

        do {
            _ = try await server.callTool(name: "   ", arguments: [:])
            Issue.record("Expected empty tool name to throw")
        } catch let error as MCPError {
            #expect(error.code == MCPError.invalidParamsCode)
            #expect(error.message.contains("non-empty"))
        }
    }

    @Test("Prompts and sampling advertised by the server are not surfaced")
    func promptsAndSamplingAreDeadvertised() async throws {
        let session = try makeSession { _, body in
            let request = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let id = request["id"] as? String ?? "1"
            if request["method"] as? String == "notifications/initialized" {
                return emptyAccepted()
            }
            return try jsonResponse(
                id: id,
                result: [
                    "protocolVersion": MCPProtocolVersion.current,
                    "capabilities": [
                        "tools": [:],
                        "prompts": [:],
                        "sampling": [:]
                    ]
                ]
            )
        }
        defer { ModernizationURLProtocol.reset() }

        let server = try HTTPMCPServer(
            url: URL(string: "https://mcp.example.com/api")!,
            name: "caps-test",
            maxRetries: 0,
            session: session
        )

        let capabilities = try await server.initialize()
        #expect(capabilities.tools)
        #expect(!capabilities.prompts)
        #expect(!capabilities.sampling)
    }

    @Test("Session id from initialize is forwarded on the next request")
    func sessionIDIsForwarded() async throws {
        let session = try makeSession { request, body in
            let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let method = object["method"] as? String
            let id = object["id"] as? String ?? "1"
            if method == "initialize" {
                return try jsonResponse(
                    id: id,
                    result: [
                        "protocolVersion": MCPProtocolVersion.legacy,
                        "capabilities": ["tools": [:]]
                    ],
                    headers: ["MCP-Session-Id": "abc-session"]
                )
            }
            if method == "notifications/initialized" {
                return emptyAccepted()
            }
            #expect(request.value(forHTTPHeaderField: "MCP-Session-Id") == "abc-session")
            return try jsonResponse(id: id, result: ["tools": []])
        }
        defer { ModernizationURLProtocol.reset() }

        let server = try HTTPMCPServer(
            url: URL(string: "https://mcp.example.com/api")!,
            name: "session-test",
            maxRetries: 0,
            session: session
        )

        _ = try await server.initialize()
        #expect(await server.sessionID == "abc-session")
        _ = try await server.listTools()
    }

    @Test("SSE JSON-RPC responses are decoded")
    func sseResponsesAreDecoded() async throws {
        let session = try makeSession { _, body in
            let request = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let id = request["id"] as? String ?? "1"
            let payload = """
            event: message
            data: {"jsonrpc":"2.0","id":"\(id)","result":{"tools":[]}}

            """
            let response = HTTPURLResponse(
                url: URL(string: "https://mcp.example.com/api")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data(payload.utf8))
        }
        defer { ModernizationURLProtocol.reset() }

        let server = try HTTPMCPServer(
            url: URL(string: "https://mcp.example.com/api")!,
            name: "sse-test",
            maxRetries: 0,
            session: session
        )

        let tools = try await server.listTools()
        #expect(tools.isEmpty)
    }

    private func makeSession(
        _ handler: @escaping @Sendable (URLRequest, Data) throws -> (HTTPURLResponse, Data)
    ) throws -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ModernizationURLProtocol.self]
        ModernizationURLProtocol.reset()
        ModernizationURLProtocol.handler = handler
        return URLSession(configuration: config)
    }

    private func jsonResponse(
        id: String,
        result: [String: Any],
        headers: [String: String] = [:]
    ) throws -> (HTTPURLResponse, Data) {
        var headerFields = headers
        headerFields["Content-Type"] = "application/json"
        let response = HTTPURLResponse(
            url: URL(string: "https://mcp.example.com/api")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: headerFields
        )!
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ]
        return (response, try JSONSerialization.data(withJSONObject: body))
    }

    private func emptyAccepted() -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "https://mcp.example.com/api")!,
            statusCode: 202,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data())
    }
}

private final class ModernizationURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest, Data) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        handler = nil
    }

    override class func canInit(with _: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            fatalError("ModernizationURLProtocol.handler not set")
        }
        do {
            let body = try bodyData(from: request)
            let (response, data) = try handler(request, body)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read < 0 {
                throw stream.streamError ?? MCPError.internalError("Failed to read HTTP body stream")
            }
            if read == 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}
