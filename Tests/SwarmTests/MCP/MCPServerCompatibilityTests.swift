// MCPServerCompatibilityTests.swift
// SwarmTests
//
// Source-compatibility coverage for the deprecated MCPServer alias.

import Testing
@testable import Swarm

@Suite("MCPServer Compatibility Tests")
struct MCPServerCompatibilityTests {
    @Test("Deprecated MCPServer remains an alias for MCPServerConnection")
    @available(*, deprecated, message: "Compatibility witness for MCPServer.")
    func deprecatedAliasRemainsAvailable() async {
        let legacyServer: MCPServer = MockMCPServer(name: "legacy-server")
        let canonicalServer: any MCPServerConnection = legacyServer

        #expect(await canonicalServer.name == "legacy-server")
    }
}
