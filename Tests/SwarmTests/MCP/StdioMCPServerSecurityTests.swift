// StdioMCPServerSecurityTests.swift
// SwarmTests
//
// Launch hardening for the stdio MCP transport: absolute binary paths,
// minimal environment inheritance, and working-directory sandbox limits.

import Foundation
@testable import Swarm
import Testing

@Suite("StdioMCPServer Security Tests")
struct StdioMCPServerSecurityTests {
    @Test("Bare command names are rejected")
    func bareCommandRejected() {
        #expect(throws: MCPError.self) {
            _ = try StdioMCPServer(command: "npx", name: "bare")
        }
    }

    @Test("Relative command paths are rejected")
    func relativeCommandRejected() {
        for command in ["./server", "bin/server", "../server"] {
            #expect(throws: MCPError.self, "\(command) should be rejected") {
                _ = try StdioMCPServer(command: command, name: "relative")
            }
        }
    }

    @Test("Relative commands report invalidParams mentioning absolute path")
    func relativeCommandErrorMentionsAbsolutePath() {
        do {
            _ = try StdioMCPServer(command: "npx", name: "bare")
            Issue.record("Expected init to throw for a bare command")
        } catch let error as MCPError {
            #expect(error.code == MCPError.invalidParamsCode)
            #expect(error.message.contains("absolute path"))
        } catch {
            Issue.record("Expected MCPError, got \(error)")
        }
    }

    @Test("Absolute command path is accepted")
    func absoluteCommandAccepted() throws {
        _ = try StdioMCPServer(command: "/usr/bin/true", name: "absolute")
    }

    @Test("Child environment drops unlisted host variables")
    func childEnvironmentDropsUnlistedHostVariables() {
        let host = [
            "HOME": "/Users/test",
            "PATH": "/attacker/bin:/usr/bin",
            "SWARM_SECRET_TOKEN": "super-secret",
            "AWS_SECRET_ACCESS_KEY": "hunter2",
        ]
        let child = StdioMCPServer.resolvedChildEnvironment(
            host: host,
            overlay: nil,
            additionalInheritedKeys: []
        )
        #expect(child["HOME"] == "/Users/test")
        #expect(child["SWARM_SECRET_TOKEN"] == nil)
        #expect(child["AWS_SECRET_ACCESS_KEY"] == nil)
        // Host PATH is never inherited implicitly.
        #expect(child["PATH"] == StdioMCPServer.defaultSandboxPATH)
    }

    @Test("Overlay wins and explicit inheritance opts back in")
    func overlayWinsAndExplicitInheritanceOptsIn() {
        let host = ["HOME": "/Users/test", "CUSTOM_FLAG": "host-value"]
        let child = StdioMCPServer.resolvedChildEnvironment(
            host: host,
            overlay: ["HOME": "/overlay", "API_KEY": "overlay-secret"],
            additionalInheritedKeys: ["CUSTOM_FLAG"]
        )
        #expect(child["HOME"] == "/overlay")
        #expect(child["API_KEY"] == "overlay-secret")
        #expect(child["CUSTOM_FLAG"] == "host-value")
    }

    @Test("Overlay can replace the restricted PATH")
    func overlayCanReplaceRestrictedPATH() {
        let child = StdioMCPServer.resolvedChildEnvironment(
            host: [:],
            overlay: ["PATH": "/opt/mcp/bin"],
            additionalInheritedKeys: []
        )
        #expect(child["PATH"] == "/opt/mcp/bin")
    }

    @Test("Non-absolute working directory is rejected")
    func nonAbsoluteWorkingDirectoryRejected() {
        #expect(throws: MCPError.self) {
            _ = try StdioMCPServer(
                command: "/usr/bin/true",
                workingDirectory: URL(string: "relative/dir"),
                name: "bad-workdir"
            )
        }
    }

    @Test("Working directory escaping the sandbox root is rejected")
    func workdirEscapeRejected() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-stdio-sandbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: MCPError.self) {
            _ = try StdioMCPServer(
                command: "/usr/bin/true",
                workingDirectory: URL(fileURLWithPath: "/tmp"),
                allowedWorkingDirectoryRoot: root,
                name: "escape"
            )
        }
    }

    @Test("Sandbox root defaults the working directory")
    func sandboxRootDefaultsWorkingDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-stdio-sandbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let server = try StdioMCPServer(
            command: "/usr/bin/true",
            allowedWorkingDirectoryRoot: root,
            name: "sandbox-default"
        )
        #expect(await server.resolvedWorkingDirectoryURL?.path == root.path)
    }

    #if os(macOS) || os(Linux)
        @Test("Missing working directory fails initialize")
        func missingWorkingDirectoryFailsInitialize() async throws {
            let server = try StdioMCPServer(
                command: "/usr/bin/true",
                workingDirectory: URL(
                    fileURLWithPath: "/this/path/does/not/exist-\(UUID().uuidString)"
                ),
                name: "missing-workdir"
            )
            defer { Task { try? await server.close() } }
            do {
                _ = try await server.initialize()
                Issue.record("Expected initialize() to throw for a missing working directory.")
            } catch let error as MCPError {
                #expect(error.code == MCPError.invalidParamsCode)
            }
        }

        @Test("Sandboxed initialize still completes against the fixture")
        func sandboxedInitializeCompletes() async throws {
            let python = try MCPFixtureSupport.requirePython3()
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("swarm-stdio-sandbox-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }

            let server = try StdioMCPServer(
                command: python,
                arguments: [MCPFixtureSupport.scriptURL.path],
                environment: ["SWARM_FIXTURE_MODE": "sandboxed"],
                workingDirectory: root,
                allowedWorkingDirectoryRoot: root,
                name: "sandboxed-interop",
                timeout: 10
            )
            defer { Task { try? await server.close() } }

            let capabilities = try await server.initialize()
            #expect(capabilities.tools)
            let tools = try await server.listTools()
            #expect(tools.map(\.name) == ["echo"])
        }
    #endif
}
