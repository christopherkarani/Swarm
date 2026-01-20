// ToolArgumentNormalizationTests.swift
// SwiftAgentsTests
//
// Tests for ToolArgumentProcessor normalization logic.

import Testing
@testable import SwiftAgents

@Suite("Tool Argument Normalization Tests")
struct ToolArgumentNormalizationTests {
    
    private struct TestTool: AnyJSONTool {
        let name = "test_tool"
        let description = "A test tool"
        let parameters: [ToolParameter]
        
        init(parameters: [ToolParameter]) {
            self.parameters = parameters
        }
        
        func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
            return .string("ok")
        }
    }
    
    @Test("Coerces string to integer")
    func coerceStringToInt() throws {
        let param = ToolParameter(name: "count", description: "Count", type: .int)
        let tool = TestTool(parameters: [param])
        
        let args: [String: SendableValue] = ["count": .string("42")]
        let normalized = try tool.normalizeArguments(args)
        
        #expect(normalized["count"] == .int(42))
    }
    
    @Test("Coerces string to boolean")
    func coerceStringToBool() throws {
        let param = ToolParameter(name: "flag", description: "Flag", type: .bool)
        let tool = TestTool(parameters: [param])
        
        let argsTrue: [String: SendableValue] = ["flag": .string("true")]
        let normalizedTrue = try tool.normalizeArguments(argsTrue)
        #expect(normalizedTrue["flag"] == .bool(true))
        
        let argsFalse: [String: SendableValue] = ["flag": .string("FALSE")]
        let normalizedFalse = try tool.normalizeArguments(argsFalse)
        #expect(normalizedFalse["flag"] == .bool(false))
    }
    
    @Test("Coerces string to double")
    func coerceStringToDouble() throws {
        let param = ToolParameter(name: "score", description: "Score", type: .double)
        let tool = TestTool(parameters: [param])
        
        let args: [String: SendableValue] = ["score": .string("3.14")]
        let normalized = try tool.normalizeArguments(args)
        
        #expect(normalized["score"] == .double(3.14))
    }
    
    @Test("Applies default values")
    func appliesDefaultValues() throws {
        let param = ToolParameter(
            name: "mode", 
            description: "Mode", 
            type: .string, 
            isRequired: false, 
            defaultValue: .string("auto")
        )
        let tool = TestTool(parameters: [param])
        
        let args: [String: SendableValue] = [:]
        let normalized = try tool.normalizeArguments(args)
        
        #expect(normalized["mode"] == .string("auto"))
    }
    
    @Test("Recursively coerces array elements")
    func coercesArrayElements() throws {
        let param = ToolParameter(
            name: "numbers", 
            description: "Numbers", 
            type: .array(elementType: .int)
        )
        let tool = TestTool(parameters: [param])
        
        let args: [String: SendableValue] = ["numbers": .array([.string("1"), .string("2"), .int(3)])]
        let normalized = try tool.normalizeArguments(args)
        
        if case let .array(elements) = normalized["numbers"] {
            #expect(elements == [.int(1), .int(2), .int(3)])
        } else {
            Issue.record("Expected array")
        }
    }
    
    @Test("Recursively coerces object properties")
    func coercesObjectProperties() throws {
        let innerParam = ToolParameter(name: "age", description: "Age", type: .int)
        let param = ToolParameter(
            name: "person", 
            description: "Person", 
            type: .object(properties: [innerParam])
        )
        let tool = TestTool(parameters: [param])
        
        let args: [String: SendableValue] = ["person": .dictionary(["age": .string("30")])]
        let normalized = try tool.normalizeArguments(args)
        
        if case let .dictionary(dict) = normalized["person"],
           let age = dict["age"] {
            #expect(age == .int(30))
        } else {
            Issue.record("Expected object with property")
        }
    }
}
