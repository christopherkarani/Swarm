// ToolBuilderTests.swift
// Tests for the @ToolBuilderV3 result builder.

@testable import Swarm
import Testing

// MARK: - Fixtures

private struct MockToolA: ToolV3 {
    let name = "mock_a"
    let description = "Mock tool A"
    func call() async throws -> String { "A" }
}

private struct MockToolB: ToolV3 {
    let name = "mock_b"
    let description = "Mock tool B"
    func call() async throws -> String { "B" }
}

// MARK: - Suite

@Suite("@ToolBuilderV3 result builder")
struct ToolBuilderTests {
    @Test("Collects multiple tools")
    func buildBlock() {
        @ToolBuilderV3 var tools: [any ToolV3] {
            MockToolA()
            MockToolB()
        }
        #expect(tools.count == 2)
        #expect(tools[0].name == "mock_a")
        #expect(tools[1].name == "mock_b")
    }

    @Test("Supports if-else conditionals")
    func buildEither() {
        let useA = true
        @ToolBuilderV3 var tools: [any ToolV3] {
            if useA {
                MockToolA()
            } else {
                MockToolB()
            }
        }
        #expect(tools.count == 1)
        #expect(tools[0].name == "mock_a")
    }

    @Test("Supports optional (if without else)")
    func buildOptional() {
        let includeB = false
        @ToolBuilderV3 var tools: [any ToolV3] {
            MockToolA()
            if includeB {
                MockToolB()
            }
        }
        #expect(tools.count == 1)
        #expect(tools[0].name == "mock_a")
    }

    @Test("Empty builder produces empty array")
    func emptyBuilder() {
        @ToolBuilderV3 var tools: [any ToolV3] {}
        #expect(tools.isEmpty)
    }
}
