// ParameterTests.swift
// Tests for the @ParameterV3 property wrapper.

@testable import Swarm
import Testing

@Suite("@ParameterV3 property wrapper")
struct ParameterTests {
    @Test("String parameter stores description and value")
    func stringParameter() {
        @ParameterV3("A name") var name: String
        name = "Alice"
        #expect(name == "Alice")
        #expect($name.description == "A name")
        #expect($name.isRequired == true)
    }

    @Test("Int parameter")
    func intParameter() {
        @ParameterV3("A number") var x: Int
        x = 42
        #expect(x == 42)
        #expect($x.description == "A number")
    }

    @Test("Double parameter")
    func doubleParameter() {
        @ParameterV3("A ratio") var ratio: Double
        ratio = 3.14
        #expect(ratio == 3.14)
    }

    @Test("Bool parameter")
    func boolParameter() {
        @ParameterV3("A flag") var flag: Bool
        flag = true
        #expect(flag == true)
    }

    @Test("Optional parameter defaults to nil and is not required")
    func optionalParameter() {
        @ParameterV3("Optional input") var y: String?
        #expect(y == nil)
        #expect($y.isRequired == false)
        y = "hello"
        #expect(y == "hello")
    }

    @Test("Parameter with default value")
    func defaultValue() {
        @ParameterV3("Count", default: 10) var count: Int
        #expect(count == 10)
        #expect($count.isRequired == false)
    }

    @Test("Parameter used in a ToolV3 struct")
    func inToolStruct() async throws {
        struct AddTool: ToolV3 {
            let name = "add"
            let description = "Adds two numbers"
            @ParameterV3("First number") var a: Int
            @ParameterV3("Second number") var b: Int
            func call() async throws -> String { "\(a + b)" }
        }

        var tool = AddTool()
        tool.a = 3
        tool.b = 7
        let result = try await tool.call()
        #expect(result == "10")
    }
}
