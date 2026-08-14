// MCPIntegrationTests.swift
// SwarmTests
//
// Integration tests for MCP tool bridging, client discovery, model settings, and AgentBuilder.

import Foundation
@testable import Swarm
import Testing

// MARK: - IntegrationTestMCPServer

/// A mock MCP server for integration testing.
actor IntegrationTestMCPServer: MCPServerConnection {
    // MARK: Internal

    let name: String
    var toolsToReturn: [ToolSchema] = []
    private(set) var initializeCalled = false
    private(set) var callToolHistory: [(name: String, arguments: [String: SendableValue])] = []

    nonisolated var capabilities: MCPCapabilities {
        get async { await _capabilities }
    }

    init(name: String, capabilities: MCPCapabilities = MCPCapabilities(tools: true, resources: true)) {
        self.name = name
        _capabilities = capabilities
    }

    func setCapabilities(_ caps: MCPCapabilities) {
        _capabilities = caps
    }

    func initialize() async throws -> MCPCapabilities {
        initializeCalled = true
        return _capabilities
    }

    func listTools() async throws -> [ToolSchema] {
        toolsToReturn
    }

    func callTool(name: String, arguments: [String: SendableValue]) async throws -> SendableValue {
        callToolHistory.append((name: name, arguments: arguments))
        return .string("result-from-\(self.name):\(name)")
    }

    func listResources() async throws -> [MCPResource] { [] }

    func readResource(uri: String) async throws -> MCPResourceContent {
        try MCPResourceContent(uri: uri, text: "")
    }

    func close() async throws {}

    func setTools(_ tools: [ToolSchema]) {
        toolsToReturn = tools
    }

    // MARK: Private

    private var _capabilities: MCPCapabilities
}

// MARK: - MCPToolBridgeIntegrationTests

@Suite("MCP Tool Bridge Integration")
struct MCPToolBridgeIntegrationTests {
    @Test("Bridge tools from server correctly")
    func bridgeToolsFromServer() async throws {
        let server = IntegrationTestMCPServer(name: "test-server")
        await server.setTools([
            ToolSchema(name: "read_file", description: "Read a file", parameters: []),
            ToolSchema(name: "write_file", description: "Write a file", parameters: [])
        ])

        let bridge = MCPToolBridge(server: server)
        let tools = try await bridge.bridgeTools()

        #expect(tools.count == 2)
        #expect(tools.map(\.name).contains("read_file"))
        #expect(tools.map(\.name).contains("write_file"))
    }

    @Test("Bridged tool execution calls server")
    func bridgedToolExecution() async throws {
        let server = IntegrationTestMCPServer(name: "exec-server")
        await server.setTools([
            ToolSchema(name: "search", description: "Search", parameters: [])
        ])

        let bridge = MCPToolBridge(server: server)
        let tools = try await bridge.bridgeTools()

        #expect(tools.count == 1)
        let searchTool = tools[0]

        let result = try await searchTool.execute(arguments: ["query": .string("swift")])

        #expect(result == .string("result-from-exec-server:search"))
        let history = await server.callToolHistory
        #expect(history.count == 1)
        #expect(history[0].name == "search")
        #expect(history[0].arguments["query"] == .string("swift"))
    }
}

// MARK: - MCPClientToolDiscoveryTests

@Suite("MCP Client Tool Discovery")
struct MCPClientToolDiscoveryTests {
    @Test("Client discovers tools from server")
    func clientDiscoverTools() async throws {
        let client = MCPClient()
        let server = MockMCPServer(name: "discovery-server")
        await server.setTools([
            ToolSchema(name: "tool_a", description: "Tool A", parameters: []),
            ToolSchema(name: "tool_b", description: "Tool B", parameters: [])
        ])

        try await client.addServer(server)
        let tools = try await client.getAllTools()

        #expect(tools.count == 2)
        #expect(tools.map(\.name).contains("tool_a"))
        #expect(tools.map(\.name).contains("tool_b"))
    }

    @Test("Client tool caching works correctly")
    func clientToolCaching() async throws {
        let client = MCPClient()
        let server = MockMCPServer(name: "cache-server")
        await server.setTools([
            ToolSchema(name: "cached_tool", description: "Cached", parameters: [])
        ])

        try await client.addServer(server)

        // First call populates cache
        let tools1 = try await client.getAllTools()
        #expect(tools1.count == 1)

        // Modify server tools
        await server.setTools([
            ToolSchema(name: "new_tool", description: "New", parameters: [])
        ])

        // Second call returns cached result
        let tools2 = try await client.getAllTools()
        #expect(tools2.count == 1)
        #expect(tools2[0].name == "cached_tool")

        // Refresh forces new fetch
        let tools3 = try await client.refreshTools()
        #expect(tools3.count == 1)
        #expect(tools3[0].name == "new_tool")
    }
}

// MARK: - ModelSettingsIntegrationTests

@Suite("Model Settings Integration")
struct ModelSettingsIntegrationTests {
    @Test("Model settings apply to agent configuration")
    func modelSettingsWithAgentConfiguration() throws {
        let settings = ModelSettings.creative
            .maxTokens(2048)
            .toolChoice(.required)

        let config = AgentConfiguration.default
            .modelSettings(settings)

        #expect(config.modelSettings?.temperature == 1.2)
        #expect(config.modelSettings?.topP == 0.95)
        #expect(config.modelSettings?.maxTokens == 2048)
        #expect(config.modelSettings?.toolChoice == .required)
    }

    @Test("Model settings validation works in context")
    func modelSettingsValidation() throws {
        let validSettings = ModelSettings()
            .temperature(0.8)
            .topP(0.9)
            .maxTokens(1024)

        try validSettings.validate()

        let invalidSettings = ModelSettings().temperature(3.0)
        #expect(throws: ModelSettingsValidationError.self) {
            try invalidSettings.validate()
        }
    }

    @Test("Model settings presets work correctly")
    func modelSettingsPresets() {
        let creative = ModelSettings.creative
        #expect(creative.temperature == 1.2)
        #expect(creative.topP == 0.95)

        let precise = ModelSettings.precise
        #expect(precise.temperature == 0.2)
        #expect(precise.topP == 0.9)

        let balanced = ModelSettings.balanced
        #expect(balanced.temperature == 0.7)
        #expect(balanced.topP == 0.9)
    }
}

// MARK: - AgentModelSettingsIntegrationTests

@Suite("Agent Model Settings Integration")
struct AgentModelSettingsIntegrationTests {
    @Test("Agent with ModelSettings works via direct init")
    func agentWithModelSettings() async throws {
        let config = AgentConfiguration.default.modelSettings(.precise.maxTokens(1500))
        let agent = try Agent(
            instructions: "Precise agent.",
            configuration: config
        )

        #expect(agent.configuration.modelSettings?.temperature == 0.2)
        #expect(agent.configuration.modelSettings?.topP == 0.9)
        #expect(agent.configuration.modelSettings?.maxTokens == 1500)
    }

    @Test("Agent configuration merge works correctly via direct init")
    func agentConfigurationMerge() async throws {
        let config = AgentConfiguration.default
            .maxIterations(15)
            .modelSettings(.balanced.parallelToolCalls(true))
        let agent = try Agent(
            instructions: "Merged settings agent.",
            configuration: config
        )

        #expect(agent.configuration.maxIterations == 15)
        #expect(agent.configuration.modelSettings?.temperature == 0.7)
        #expect(agent.configuration.modelSettings?.parallelToolCalls == true)
    }
}
