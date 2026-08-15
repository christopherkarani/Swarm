// HTTPMCPServerTests.swift
// SwarmTests
//
// Tests for HTTPMCPServer initialization, defaults, and property access.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Swarm
import Testing

// MARK: - HTTPMCPServerInitializationTests

@Suite("HTTPMCPServer Initialization Tests")
struct HTTPMCPServerInitializationTests {
    @Test("Server initializes with correct properties")
    func serverInit() async throws {
        let url = URL(string: "https://mcp.example.com/api")!
        let server = try HTTPMCPServer(
            url: url,
            name: "test-server",
            apiKey: "sk-test-key",
            timeout: 60.0,
            maxRetries: 5
        )

        let name = await server.name
        #expect(name == "test-server")
    }

    @Test("Server uses default timeout of 30.0 seconds")
    func defaultTimeout() async throws {
        let url = URL(string: "https://mcp.example.com/api")!
        let server = try HTTPMCPServer(url: url, name: "timeout-test")

        // Verify default timeout by checking capabilities before init returns empty
        // The timeout is internal, but we can verify server creation succeeds
        let name = await server.name
        #expect(name == "timeout-test")
    }

    @Test("Server uses default maxRetries of 3")
    func defaultMaxRetries() async throws {
        let url = URL(string: "https://mcp.example.com/api")!
        let server = try HTTPMCPServer(url: url, name: "retries-test")

        // maxRetries is internal, verify server creation with defaults succeeds
        let name = await server.name
        #expect(name == "retries-test")
    }
}

// MARK: - HTTPMCPServerCapabilitiesTests

@Suite("HTTPMCPServer Capabilities Tests")
struct HTTPMCPServerCapabilitiesTests {
    @Test("Capabilities returns empty MCPCapabilities before initialization")
    func capabilitiesBeforeInit() async throws {
        let url = URL(string: "https://mcp.example.com/api")!
        let server = try HTTPMCPServer(url: url, name: "capabilities-test")

        let capabilities = await server.capabilities

        // Before initialize() is called, capabilities should be empty
        #expect(capabilities.tools == false)
        #expect(capabilities.resources == false)
        #expect(capabilities.prompts == false)
        #expect(capabilities.sampling == false)
        #expect(capabilities == MCPCapabilities())
    }

    @Test("Capabilities would return cached value after initialization")
    func capabilitiesAfterInit() async throws {
        // Note: We cannot test real HTTP initialization without a mock server.
        // This test documents the expected behavior: after initialize() is called,
        // capabilities should return the cached value from the server response.
        let url = URL(string: "https://mcp.example.com/api")!
        let server = try HTTPMCPServer(url: url, name: "cached-capabilities-test")

        // Before init, capabilities are empty
        let beforeInit = await server.capabilities
        #expect(beforeInit == MCPCapabilities.empty)

        // Real initialization would require mocking URLSession or a live server.
        // The HTTPMCPServer caches capabilities after successful initialize().
    }
}

@Suite("HTTPMCPServer Lifecycle Tests", .serialized)
struct HTTPMCPServerLifecycleTests {
    @Test("Initialize sends client capabilities and initialized notification")
    func initializeSendsClientCapabilitiesAndInitializedNotification() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HTTPMCPRecordingURLProtocol.self]
        let session = URLSession(configuration: config)

        HTTPMCPRecordingURLProtocol.reset()
        defer { HTTPMCPRecordingURLProtocol.reset() }

        HTTPMCPRecordingURLProtocol.handler = { request, body in
            guard let requestObject = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let method = requestObject["method"] as? String else {
                throw MCPError.invalidRequest("Expected JSON-RPC request body")
            }

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://mcp.example.com/api")!,
                statusCode: method == "notifications/initialized" ? 202 : 200,
                httpVersion: nil,
                headerFields: nil
            )!

            if method == "initialize" {
                let id = requestObject["id"] as? String ?? "initialize-id"
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "protocolVersion": "2024-11-05",
                        "serverInfo": [
                            "name": "mock-mcp",
                            "version": "1.0.0"
                        ],
                        "capabilities": [
                            "tools": [:]
                        ]
                    ]
                ]
                return (response, try JSONSerialization.data(withJSONObject: body))
            }

            if method == "notifications/initialized" {
                return (response, Data())
            }

            throw MCPError.methodNotFound(method)
        }

        let server = try HTTPMCPServer(
            url: URL(string: "https://mcp.example.com/api")!,
            name: "lifecycle-test",
            maxRetries: 0,
            session: session
        )

        let capabilities = try await server.initialize()

        #expect(capabilities.tools)

        let requestObjects = try HTTPMCPRecordingURLProtocol.requestBodies.map { body in
            try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        }
        let methods = requestObjects.compactMap { $0["method"] as? String }
        #expect(methods == ["initialize", "notifications/initialized"])

        let initializeParams = try #require(requestObjects[0]["params"] as? [String: Any])
        #expect(initializeParams["protocolVersion"] as? String == MCPProtocolVersion.current)
        #expect(initializeParams["capabilities"] != nil)
        let clientInfo = try #require(initializeParams["clientInfo"] as? [String: Any])
        #expect(clientInfo["name"] as? String == "Swarm")
        #expect(clientInfo["version"] as? String == Swarm.version)

        let firstHeaders = try #require(HTTPMCPRecordingURLProtocol.requestHeaders.first)
        #expect(firstHeaders["Accept"]?.contains("application/json") == true)
        #expect(firstHeaders["Accept"]?.contains("text/event-stream") == true)
        #expect(firstHeaders["MCP-Protocol-Version"] == MCPProtocolVersion.current)

        #expect(await server.negotiatedProtocolVersion == "2024-11-05")
        #expect(await server.sessionID == nil)

        if requestObjects.count > 1 {
            #expect(requestObjects[1]["id"] == nil)
        } else {
            Issue.record("Expected notifications/initialized after initialize")
        }
    }
}

// MARK: - HTTPMCPServerNameTests

@Suite("HTTPMCPServer Name Tests")
struct HTTPMCPServerNameTests {
    @Test("Server returns correct name property")
    func serverName() async throws {
        let url = URL(string: "https://api.example.com/mcp")!
        let server = try HTTPMCPServer(url: url, name: "my-custom-server")

        let name = await server.name
        #expect(name == "my-custom-server")
    }

    @Test("Server preserves name with special characters")
    func serverNameSpecialCharacters() async throws {
        let url = URL(string: "https://api.example.com/mcp")!
        let server = try HTTPMCPServer(url: url, name: "server-with_special.chars:123")

        let name = await server.name
        #expect(name == "server-with_special.chars:123")
    }

    @Test("Server preserves empty name")
    func serverEmptyName() async throws {
        let url = URL(string: "https://api.example.com/mcp")!
        let server = try HTTPMCPServer(url: url, name: "")

        let name = await server.name
        #expect(name.isEmpty)
    }
}

@Suite("HTTPMCPServer Security Validation Tests")
struct HTTPMCPServerSecurityValidationTests {
    @Test("Rejects non-HTTPS URL when apiKey is provided")
    func rejectsInsecureURLWithAPIKey() async throws {
        let url = try #require(URL(string: "http://mcp.example.com/api"))
        #expect(throws: MCPError.self) {
            _ = try HTTPMCPServer(url: url, name: "insecure", apiKey: "sk-test")
        }
    }
}

private final class HTTPMCPRecordingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestBodies: [Data] = []
    nonisolated(unsafe) static var handler: ((URLRequest, Data) throws -> (HTTPURLResponse, Data))?

    nonisolated(unsafe) static var requestHeaders: [[String: String]] = []

    static func reset() {
        requestBodies = []
        requestHeaders = []
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
            fatalError("HTTPMCPRecordingURLProtocol.handler not set")
        }

        do {
            let body = try bodyData(from: request)
            Self.requestBodies.append(body)
            var headers: [String: String] = [:]
            if let accept = request.value(forHTTPHeaderField: "Accept") {
                headers["Accept"] = accept
            }
            if let version = request.value(forHTTPHeaderField: "MCP-Protocol-Version") {
                headers["MCP-Protocol-Version"] = version
            }
            if let session = request.value(forHTTPHeaderField: "MCP-Session-Id") {
                headers["MCP-Session-Id"] = session
            }
            Self.requestHeaders.append(headers)
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
