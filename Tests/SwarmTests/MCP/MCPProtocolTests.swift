// MCPProtocolTests.swift
// SwarmTests
//
// Tests for MCP protocol types: MCPRequest, MCPResponse, MCPError, MCPCapabilities, MCPResource.

import Foundation
@testable import Swarm
import Testing

// MARK: - MCPRequestTests

@Suite("MCPRequest Tests")
struct MCPRequestTests {
    @Test("request encoding includes required JSON-RPC fields")
    func requestEncoding() throws {
        let request = try MCPRequest(id: "test-123", method: "tools/list")
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["jsonrpc"] as? String == "2.0")
        #expect(json?["id"] as? String == "test-123")
        #expect(json?["method"] as? String == "tools/list")
    }

    @Test("request generates UUID by default")
    func requestDefaultId() throws {
        let request = try MCPRequest(method: "initialize")

        #expect(!request.id.isEmpty)
        #expect(UUID(uuidString: request.id) != nil)
        #expect(request.jsonrpc == "2.0")
        #expect(request.method == "initialize")
    }

    @Test("request with params encodes parameters")
    func requestWithParams() throws {
        let params: [String: SendableValue] = [
            "name": .string("calculator"),
            "arguments": .dictionary(["x": .int(10)])
        ]
        let request = try MCPRequest(method: "tools/call", params: params)

        // Verify the request has params set
        #expect(request.params != nil)
        #expect(request.params?["name"] == .string("calculator"))

        // Verify encoding doesn't throw
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        #expect(!data.isEmpty)

        // Note: SendableValue uses Swift's default enum Codable, which encodes as
        // discriminated unions (e.g., {"string": {"_0": "calculator"}}) rather than
        // raw JSON values. For MCP wire format, a custom Codable implementation
        // would be needed. The internal API works correctly; this test verifies
        // the Swift-level API behavior.
    }

    @Test("request with empty id is given a UUID fallback")
    func requestSanitizesEmptyId() throws {
        let request = try MCPRequest(id: "", method: "tools/list")

        #expect(!request.id.isEmpty)
        #expect(UUID(uuidString: request.id) != nil)
        #expect(request.method == "tools/list")
        #expect(request.jsonrpc == "2.0")
    }

    @Test("request with empty method throws")
    func requestEmptyMethodThrows() async {
        #expect(throws: MCPError.self) {
            _ = try MCPRequest(method: "")
        }
    }
}

// MARK: - MCPResponseTests

@Suite("MCPResponse Tests")
struct MCPResponseTests {
    @Test("response decodes result correctly")
    func responseWithResult() throws {
        // Note: SendableValue uses Swift's default enum Codable, which expects
        // discriminated unions. For raw JSON decoding from actual MCP servers,
        // a custom Codable implementation for SendableValue would be needed.
        // This test verifies the Swift API works correctly with properly encoded values.

        // Create response using factory method (proper internal API)
        let response = try MCPResponse.success(id: "resp-1", result: .dictionary(["tools": .array([])]))

        #expect(response.jsonrpc == "2.0")
        #expect(response.id == "resp-1")
        #expect(response.result != nil)
        #expect(response.error == nil)

        // Verify round-trip encoding/decoding works
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        let decoded = try JSONDecoder().decode(MCPResponse.self, from: data)

        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == "resp-1")
        #expect(decoded.result == response.result)
        #expect(decoded.error == nil)
    }

    @Test("response decodes error correctly")
    func responseWithError() throws {
        let jsonString = """
        {
            "jsonrpc": "2.0",
            "id": "resp-2",
            "error": {
                "code": -32601,
                "message": "Method not found"
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let response = try JSONDecoder().decode(MCPResponse.self, from: data)

        #expect(response.jsonrpc == "2.0")
        #expect(response.id == "resp-2")
        #expect(response.result == nil)
        #expect(response.error?.code == -32601)
        #expect(response.error?.message == "Method not found")
    }

    @Test("success factory creates valid response")
    func successFactory() throws {
        let response = try MCPResponse.success(id: "success-1", result: .string("done"))

        #expect(response.jsonrpc == "2.0")
        #expect(response.id == "success-1")
        #expect(response.result == .string("done"))
        #expect(response.error == nil)
    }

    @Test("failure factory creates valid error response")
    func failureFactory() throws {
        let errorObj = MCPErrorObject(code: -32600, message: "Invalid request")
        let response = try MCPResponse.failure(id: "fail-1", error: errorObj)

        #expect(response.jsonrpc == "2.0")
        #expect(response.id == "fail-1")
        #expect(response.result == nil)
        #expect(response.error?.code == -32600)
        #expect(response.error?.message == "Invalid request")
    }

    @Test("response rejects invalid jsonrpc")
    func responseRejectsInvalidJSONRPC() throws {
        let jsonString = """
        {
            "jsonrpc": "1.0",
            "id": "resp-3",
            "result": "ok"
        }
        """
        let data = jsonString.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(MCPResponse.self, from: data)
        }
    }

    @Test("response rejects empty id")
    func responseRejectsEmptyId() throws {
        let jsonString = """
        {
            "jsonrpc": "2.0",
            "id": "",
            "result": "ok"
        }
        """
        let data = jsonString.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(MCPResponse.self, from: data)
        }
    }

    @Test("response decodes numeric JSON-RPC id")
    func responseDecodesNumericID() throws {
        let jsonString = """
        {
            "jsonrpc": "2.0",
            "id": 7,
            "result": "ok"
        }
        """
        let data = jsonString.data(using: .utf8)!
        let response = try JSONDecoder().decode(MCPResponse.self, from: data)
        #expect(response.id == "7")
        #expect(response.result == .string("ok"))
    }

    @Test("success factory rejects empty id")
    func successFactoryRejectsEmptyID() {
        #expect(throws: MCPError.self) {
            _ = try MCPResponse.success(id: "", result: .string("ok"))
        }
    }

    @Test("failure factory rejects empty id")
    func failureFactoryRejectsEmptyID() {
        #expect(throws: MCPError.self) {
            _ = try MCPResponse.failure(
                id: "",
                error: MCPErrorObject(code: -32600, message: "invalid")
            )
        }
    }
}

@Suite("MCPProtocolVersion Tests")
struct MCPProtocolVersionTests {
    @Test("negotiates supported current and legacy versions")
    func negotiatesSupportedVersions() throws {
        #expect(try MCPProtocolVersion.negotiate(serverReported: MCPProtocolVersion.current) == "2025-11-25")
        #expect(try MCPProtocolVersion.negotiate(serverReported: MCPProtocolVersion.legacy) == "2024-11-05")
        #expect(try MCPProtocolVersion.negotiate(serverReported: "2025-06-18") == "2025-06-18")
    }

    @Test("unsupported or missing versions fail loudly")
    func unsupportedVersionsFail() {
        #expect(throws: MCPError.self) {
            _ = try MCPProtocolVersion.negotiate(serverReported: "1999-01-01")
        }
        #expect(throws: MCPError.self) {
            _ = try MCPProtocolVersion.negotiate(serverReported: nil)
        }
        #expect(throws: MCPError.self) {
            _ = try MCPProtocolVersion.negotiate(serverReported: "")
        }
    }
}

// MARK: - MCPErrorTests

@Suite("MCPError Tests")
struct MCPErrorTests {
    @Test("parseError has code -32700")
    func testParseError() {
        let error = MCPError.parseError()

        #expect(error.code == MCPError.parseErrorCode)
        #expect(error.code == -32700)
    }

    @Test("invalidRequest has code -32600")
    func testInvalidRequest() {
        let error = MCPError.invalidRequest()

        #expect(error.code == MCPError.invalidRequestCode)
        #expect(error.code == -32600)
    }

    @Test("methodNotFound has code -32601")
    func testMethodNotFound() {
        let error = MCPError.methodNotFound("unknown")

        #expect(error.code == MCPError.methodNotFoundCode)
        #expect(error.code == -32601)
        #expect(error.message.contains("unknown"))
    }

    @Test("invalidParams has code -32602")
    func testInvalidParams() {
        let error = MCPError.invalidParams("Missing name")

        #expect(error.code == MCPError.invalidParamsCode)
        #expect(error.code == -32602)
        #expect(error.message == "Missing name")
    }

    @Test("internalError has code -32603")
    func testInternalError() {
        let error = MCPError.internalError()

        #expect(error.code == MCPError.internalErrorCode)
        #expect(error.code == -32603)
    }

    @Test("error description conforms to LocalizedError")
    func testErrorDescription() {
        let error = MCPError(code: -32000, message: "Custom error")

        #expect(error.errorDescription?.contains("Custom error") == true)
        #expect(error.errorDescription?.contains("-32000") == true)
    }
}

// MARK: - MCPCapabilitiesTests

@Suite("MCPCapabilities Tests")
struct MCPCapabilitiesTests {
    @Test("default initializer sets all to false")
    func defaults() {
        let capabilities = MCPCapabilities()

        #expect(capabilities.tools == false)
        #expect(capabilities.resources == false)
        #expect(capabilities.prompts == false)
        #expect(capabilities.sampling == false)
    }

    @Test("empty static property has all false")
    func testEmpty() {
        let capabilities = MCPCapabilities.empty

        #expect(capabilities.tools == false)
        #expect(capabilities.resources == false)
        #expect(capabilities.prompts == false)
        #expect(capabilities.sampling == false)
        #expect(capabilities == MCPCapabilities())
    }

    @Test("capabilities encode and decode correctly")
    func encoding() throws {
        let original = MCPCapabilities(
            tools: true,
            resources: true,
            prompts: false,
            sampling: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(MCPCapabilities.self, from: data)

        #expect(decoded == original)
        #expect(decoded.tools == true)
        #expect(decoded.resources == true)
        #expect(decoded.prompts == false)
        #expect(decoded.sampling == true)
    }
}

// MARK: - MCPResourceTests

@Suite("MCPResource Tests")
struct MCPResourceTests {
    @Test("resource initializer sets properties")
    func resourceInit() {
        let resource = MCPResource(
            uri: "file:///doc.txt",
            name: "doc.txt",
            description: "A document",
            mimeType: "text/plain"
        )

        #expect(resource.uri == "file:///doc.txt")
        #expect(resource.name == "doc.txt")
        #expect(resource.description == "A document")
        #expect(resource.mimeType == "text/plain")
    }

    @Test("resource content with text has isText true")
    func resourceContentText() throws {
        let content = try MCPResourceContent(
            uri: "file:///readme.md",
            mimeType: "text/markdown",
            text: "# Hello"
        )

        #expect(content.isText == true)
        #expect(content.isBinary == false)
        #expect(content.text == "# Hello")
    }

    @Test("resource content with blob has isBinary true")
    func resourceContentBinary() throws {
        let content = try MCPResourceContent(
            uri: "file:///image.png",
            mimeType: "image/png",
            blob: "iVBORw0KGgoAAAANSUhEUg=="
        )

        #expect(content.isText == false)
        #expect(content.isBinary == true)
        #expect(content.blob == "iVBORw0KGgoAAAANSUhEUg==")
    }

    @Test("resource content throws when both text and blob are provided")
    func resourceContentBothSetThrows() async {
        #expect(throws: MCPError.self) {
            _ = try MCPResourceContent(
                uri: "file:///broken",
                mimeType: "text/plain",
                text: "hello",
                blob: "aGVsbG8="
            )
        }
    }

    @Test("resource content throws when neither text nor blob are provided")
    func resourceContentNeitherSetThrows() async {
        #expect(throws: MCPError.self) {
            _ = try MCPResourceContent(uri: "file:///broken")
        }
    }
}

@Suite("MCPWireCodec Tests")
struct MCPWireCodecTests {
    @Test("unwrapped isError envelopes throw")
    func unwrappedIsErrorThrows() {
        let envelope: SendableValue = .dictionary([
            "content": .array([.dictionary(["type": .string("text"), "text": .string("boom")])]),
            "isError": .bool(true)
        ])

        #expect(throws: MCPError.self) {
            _ = try MCPWireCodec.toolCallResult(envelope, toolName: "explode", style: .unwrappedContent)
        }
    }

    @Test("rawEnvelope returns isError envelopes")
    func rawEnvelopeReturnsIsError() throws {
        let envelope: SendableValue = .dictionary([
            "content": .array([.dictionary(["type": .string("text"), "text": .string("boom")])]),
            "isError": .bool(true)
        ])

        let raw = try MCPWireCodec.toolCallResult(envelope, toolName: "explode", style: .rawEnvelope)
        #expect(raw == envelope)
    }
}
