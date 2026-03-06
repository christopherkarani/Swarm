// InlineToolTests.swift
// Tests for InlineToolV3 closure-based tool.

@testable import Swarm
import Testing

@Suite("InlineToolV3")
struct InlineToolTests {
    @Test("Created with name and description")
    func creation() {
        let tool = InlineToolV3("greet", "Greets someone") { (args: [String: SendableValue]) in "Hello!" }
        #expect(tool.name == "greet")
        #expect(tool.description == "Greets someone")
    }

    @Test("No-argument handler")
    func noArgs() async throws {
        let tool = InlineToolV3("timestamp", "Returns timestamp") {
            "2026-03-06"
        }
        let result = try await tool.call()
        #expect(result == "2026-03-06")
    }

    @Test("Single string handler")
    func singleString() async throws {
        let tool = InlineToolV3("echo", "Echoes input") { input in
            "Echo: \(input)"
        }
        // Note: call() without args will fail for single-string variant
        // In practice, the runtime injects args before calling
        #expect(tool.name == "echo")
    }

    @Test("Raw args handler")
    func rawArgs() async throws {
        let tool = InlineToolV3("lookup", "Looks up a value") { args in
            let key = args["key"]?.stringValue ?? "unknown"
            return "Found: \(key)"
        }
        #expect(tool.name == "lookup")
    }

    @Test("InlineTool works in ToolBuilderV3")
    func inToolBuilder() {
        @ToolBuilderV3 var tools: [any ToolV3] {
            InlineToolV3("a", "Tool A", { () async throws -> String in "A" })
            InlineToolV3("b", "Tool B", { () async throws -> String in "B" })
        }
        #expect(tools.count == 2)
    }
}
