// ToolBridgeTests.swift
// Tests for the ToolV3 → AnyJSONTool bridge.

@testable import Swarm
import Testing

@Suite("ToolV3Bridge")
struct ToolBridgeTests {
    struct AddTool: ToolV3 {
        let name = "add"
        let description = "Adds two numbers"
        @ParameterV3("First number") var a: Int
        @ParameterV3("Second number") var b: Int
        func call() async throws -> String { "\(a + b)" }
    }

    @Test("Bridge preserves name and description")
    func bridgeProperties() {
        let bridged = ToolV3Bridge(AddTool())
        #expect(bridged.name == "add")
        #expect(bridged.description == "Adds two numbers")
    }

    @Test("Bridge extracts parameters from @ParameterV3")
    func bridgeParameters() {
        let bridged = ToolV3Bridge(AddTool())
        let params = bridged.parameters
        #expect(params.count == 2)
        #expect(params[0].name == "a")
        #expect(params[0].description == "First number")
        #expect(params[0].isRequired == true)
        #expect(params[1].name == "b")
    }

    @Test("Bridge has no guardrails")
    func bridgeGuardrails() {
        let bridged = ToolV3Bridge(AddTool())
        #expect(bridged.inputGuardrails.isEmpty)
        #expect(bridged.outputGuardrails.isEmpty)
    }

    @Test("asAnyJSONTool() convenience")
    func asAnyJSONToolConvenience() {
        let tool = AddTool()
        let bridged = tool.asAnyJSONTool()
        #expect(bridged.name == "add")
    }
}
