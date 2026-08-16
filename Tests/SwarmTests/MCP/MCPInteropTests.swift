// MCPInteropTests.swift
// SwarmTests
//
// Wire-protocol tests against a real MCP server fixture over stdio and HTTP.

import Foundation
@testable import Swarm
import Testing

#if os(Linux)
@Suite(
    "MCP Interop Tests",
    .disabled("stdio MCP fixture hangs the Linux GitHub Actions process; python3 never leaves stdin")
)
#else
@Suite("MCP Interop Tests", .serialized, .timeLimit(.minutes(1)))
#endif
struct MCPInteropTests {
    @Test("Stdio transport completes initialize, tools/list, and tools/call")
    func stdioHandshakeListAndCall() async throws {
        let python = try MCPFixtureSupport.requirePython3()
        let script = MCPFixtureSupport.scriptURL
        #expect(FileManager.default.fileExists(atPath: script.path))

        let server = StdioMCPServer(
            command: python,
            arguments: [script.path],
            name: "stdio-interop",
            timeout: 10
        )
        defer {
            Task { try? await server.close() }
        }

        let capabilities = try await server.initialize()
        #expect(capabilities.tools)
        #expect(!capabilities.prompts)
        #expect(!capabilities.sampling)
        #expect(await server.negotiatedProtocolVersion == MCPProtocolVersion.current)

        let tools = try await server.listTools()
        #expect(tools.map(\.name) == ["echo"])

        let result = try await server.callTool(
            name: "echo",
            arguments: ["text": .string("stdio-wire")]
        )
        #expect(result == .string("stdio-wire"))

        let raw = try await server.callToolRaw(
            name: "echo",
            arguments: ["text": .string("raw")]
        )
        #expect(raw.dictionaryValue?["content"] != nil)
    }

    @Test("HTTP transport completes initialize, tools/list, and tools/call")
    func httpHandshakeListAndCall() async throws {
        let python = try MCPFixtureSupport.requirePython3()
        let script = MCPFixtureSupport.scriptURL
        let portFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-mcp-http-\(UUID().uuidString).port")
        defer { try? FileManager.default.removeItem(at: portFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [script.path, "--http", "0", "--port-file", portFile.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        defer {
            process.terminate()
            process.waitUntilExit()
        }

        let port = try MCPFixtureSupport.waitForPortFile(portFile)
        let url = try #require(URL(string: "http://127.0.0.1:\(port)/"))
        let server = try HTTPMCPServer(
            url: url,
            name: "http-interop",
            maxRetries: 0
        )
        defer {
            Task { try? await server.close() }
        }

        let capabilities = try await server.initialize()
        #expect(capabilities.tools)
        #expect(await server.negotiatedProtocolVersion == MCPProtocolVersion.current)
        #expect(await server.sessionID == "swarm-fixture-session")

        let tools = try await server.listTools()
        #expect(tools.map(\.name) == ["echo"])

        let result = try await server.callTool(
            name: "echo",
            arguments: ["text": .string("http-wire")]
        )
        #expect(result == .string("http-wire"))
    }

    @Test("Stdio empty tool name returns an error")
    func stdioEmptyToolName() async throws {
        let python = try MCPFixtureSupport.requirePython3()
        let server = StdioMCPServer(
            command: python,
            arguments: [MCPFixtureSupport.scriptURL.path],
            name: "stdio-empty-name",
            timeout: 10
        )
        defer {
            Task { try? await server.close() }
        }

        _ = try await server.initialize()
        do {
            _ = try await server.callTool(name: "", arguments: [:])
            Issue.record("Expected empty tool name to throw")
        } catch let error as MCPError {
            #expect(error.code == MCPError.invalidParamsCode)
        }
    }
}
