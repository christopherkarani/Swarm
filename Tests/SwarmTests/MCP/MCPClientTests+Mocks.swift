// MCPClientTests+Mocks.swift
// SwarmTests
//
// Mock types for MCPClient tests.

import Foundation
@testable import Swarm

// MARK: - MockMCPServer

/// A mock MCP server for testing MCPClient behavior.
actor MockMCPServer: MCPServerConnection {
    let name: String
    var capabilitiesToReturn: MCPCapabilities
    var toolsToReturn: [ToolSchema]
    var resourcesToReturn: [MCPResource]
    var resourceContentToReturn: MCPResourceContent?
    var errorToThrow: Error?

    // Track method calls
    private(set) var initializeCalled = false
    private(set) var listToolsCalled = false
    private(set) var listResourcesCalled = false
    private(set) var listResourcesCallCount = 0
    private(set) var closeCalled = false
    private(set) var callToolHistory: [(name: String, arguments: [String: SendableValue])] = []
    private(set) var readResourceHistory: [String] = []

    // MARK: - MCPServerConnection Protocol

    nonisolated var capabilities: MCPCapabilities {
        get async {
            await capabilitiesToReturn
        }
    }

    // MARK: - Initialization

    init(
        name: String,
        capabilities: MCPCapabilities = MCPCapabilities(tools: true, resources: true),
        tools: [ToolSchema] = [],
        resources: [MCPResource] = [],
        resourceContent: MCPResourceContent? = nil,
        errorToThrow: Error? = nil
    ) {
        self.name = name
        capabilitiesToReturn = capabilities
        toolsToReturn = tools
        resourcesToReturn = resources
        resourceContentToReturn = resourceContent
        self.errorToThrow = errorToThrow
    }

    func initialize() async throws -> MCPCapabilities {
        if let error = errorToThrow {
            throw error
        }
        initializeCalled = true
        return capabilitiesToReturn
    }

    func close() async throws {
        if let error = errorToThrow {
            throw error
        }
        closeCalled = true
    }

    func listTools() async throws -> [ToolSchema] {
        if let error = errorToThrow {
            throw error
        }
        listToolsCalled = true
        return toolsToReturn
    }

    func callTool(name: String, arguments: [String: SendableValue]) async throws -> SendableValue {
        if let error = errorToThrow {
            throw error
        }
        callToolHistory.append((name: name, arguments: arguments))
        return .string("Result from \(self.name):\(name)")
    }

    func listResources() async throws -> [MCPResource] {
        if let error = errorToThrow {
            throw error
        }
        listResourcesCalled = true
        listResourcesCallCount += 1
        return resourcesToReturn
    }

    func resetListResourcesCalled() {
        listResourcesCalled = false
    }

    func resetListResourcesCallCount() {
        listResourcesCallCount = 0
    }

    func readResource(uri: String) async throws -> MCPResourceContent {
        if let error = errorToThrow {
            throw error
        }
        readResourceHistory.append(uri)
        if let content = resourceContentToReturn, content.uri == uri {
            return content
        }
        throw MCPError.invalidParams("Resource not found: \(uri)")
    }

    // MARK: - Test Helpers

    func setError(_ error: Error?) {
        errorToThrow = error
    }

    func setCapabilities(_ capabilities: MCPCapabilities) {
        capabilitiesToReturn = capabilities
    }

    func setTools(_ tools: [ToolSchema]) {
        toolsToReturn = tools
    }

    func setResources(_ resources: [MCPResource]) {
        resourcesToReturn = resources
    }

    func setResourceContent(_ content: MCPResourceContent?) {
        resourceContentToReturn = content
    }
}
