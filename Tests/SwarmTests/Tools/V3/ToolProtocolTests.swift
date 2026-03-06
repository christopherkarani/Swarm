// ToolProtocolTests.swift
// Tests for the V3 ToolV3 protocol.

@testable import Swarm
import Testing

// MARK: - Fixtures

private struct GreetingTool: ToolV3 {
    let name = "greeting"
    let description = "Returns a greeting message"
    func call() async throws -> String { "Hello, Swarm!" }
}

private struct ThrowingTool: ToolV3 {
    let name = "thrower"
    let description = "Always throws"
    func call() async throws -> String { throw TestToolError.intentional }
}

private enum TestToolError: Error { case intentional }

// MARK: - Suite

@Suite("ToolV3 Protocol")
struct ToolProtocolTests {
    @Test("struct conforms with name and description")
    func conformanceProperties() {
        let tool = GreetingTool()
        #expect(tool.name == "greeting")
        #expect(tool.description == "Returns a greeting message")
    }

    @Test("call() returns expected string result")
    func callReturnsResult() async throws {
        let tool = GreetingTool()
        let result = try await tool.call()
        #expect(result == "Hello, Swarm!")
    }

    @Test("call() propagates thrown errors")
    func callPropagatesErrors() async {
        let tool = ThrowingTool()
        do {
            _ = try await tool.call()
            Issue.record("Expected error")
        } catch {
            #expect(error is TestToolError)
        }
    }

    @Test("ToolV3 satisfies Sendable")
    func sendableConformance() {
        let tool: any ToolV3 & Sendable = GreetingTool()
        #expect(tool.name == "greeting")
    }

    @Test("ToolV3 stored as existential array")
    func existentialStorage() {
        let tools: [any ToolV3] = [GreetingTool(), ThrowingTool()]
        #expect(tools.count == 2)
        #expect(tools[0].name == "greeting")
        #expect(tools[1].name == "thrower")
    }
}
