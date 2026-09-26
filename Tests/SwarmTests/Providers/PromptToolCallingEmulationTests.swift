// PromptToolCallingEmulationTests.swift
// SwarmTests
//
// Tests for prompt-envelope tool calling used by text-only inference backends.
// Apple Foundation Models tool calling is covered by FoundationModels* tests.

import Foundation
@testable import Swarm
import Testing

// MARK: - Tool Prompt Builder Tests

@Suite("Prompt tool prompt builder")
struct PromptToolPromptTests {
    @Test("Tool prompt includes tool definitions")
    func toolPromptIncludesDefinitions() throws {
        let tool = ToolSchema(
            name: "calculator",
            description: "Performs mathematical calculations",
            parameters: [
                ToolParameter(name: "expression", description: "Math expression", type: .string)
            ]
        )
        
        let basePrompt = "What is 2+2?"
        let prompt = PromptToolPromptBuilder.buildToolPrompt(
            basePrompt: basePrompt,
            tools: [tool],
            context: PromptToolCallingContext(nonce: "nonce-123")
        )
        
        #expect(prompt.contains("Available tools:"))
        #expect(prompt.contains("calculator:"))
        #expect(prompt.contains("Performs mathematical calculations"))
        #expect(prompt.contains("expression"))
        #expect(prompt.contains("string (required)"))
        #expect(prompt.contains("Math expression"))
    }
    
    @Test("Tool prompt includes JSON format instructions")
    func toolPromptIncludesJSONFormat() throws {
        let tool = ToolSchema(name: "test", description: "Test tool", parameters: [])
        let prompt = PromptToolPromptBuilder.buildToolPrompt(
            basePrompt: "Hello",
            tools: [tool],
            context: PromptToolCallingContext(nonce: "nonce-123")
        )

        #expect(prompt.contains(#""swarm_tool_call""#))
        #expect(prompt.contains(#""nonce": "nonce-123""#))
        #expect(prompt.contains(#""tool": "tool_name""#))
        #expect(prompt.contains(#""arguments": {"param1": "value1"}"#))
        #expect(prompt.contains("\"tool\":"))
        #expect(prompt.contains("only a single JSON object"))
    }
    
    @Test("Tool prompt with multiple tools")
    func toolPromptWithMultipleTools() throws {
        let calculator = ToolSchema(
            name: "calculator",
            description: "Calculate",
            parameters: [
                ToolParameter(name: "expr", description: "Expression", type: .string)
            ]
        )
        let weather = ToolSchema(
            name: "weather",
            description: "Get weather",
            parameters: [
                ToolParameter(name: "city", description: "City name", type: .string),
                ToolParameter(name: "units", description: "Temperature units", type: .string, isRequired: false)
            ]
        )
        
        let prompt = PromptToolPromptBuilder.buildToolPrompt(
            basePrompt: "What is the weather in London?",
            tools: [calculator, weather],
            context: PromptToolCallingContext(nonce: "nonce-123")
        )
        
        #expect(prompt.contains("calculator:"))
        #expect(prompt.contains("weather:"))
        #expect(prompt.contains("city: string (required)"))
        #expect(prompt.contains("units: string - Temperature units"))
    }
    
    @Test("Tool prompt with no tools returns base prompt")
    func toolPromptWithNoTools() throws {
        let basePrompt = "Hello, how are you?"
        let prompt = PromptToolPromptBuilder.buildToolPrompt(
            basePrompt: basePrompt,
            tools: [],
            context: PromptToolCallingContext(nonce: "nonce-123")
        )
        
        #expect(prompt == basePrompt)
    }
    
    @Test("Tool prompt with complex parameter types")
    func toolPromptWithComplexTypes() throws {
        let tool = ToolSchema(
            name: "complex",
            description: "Complex tool",
            parameters: [
                ToolParameter(name: "count", description: "Count", type: .int),
                ToolParameter(name: "ratio", description: "Ratio", type: .double),
                ToolParameter(name: "enabled", description: "Enabled", type: .bool),
                ToolParameter(name: "tags", description: "Tags", type: .array(elementType: .string)),
                ToolParameter(name: "options", description: "Options", type: .oneOf(["a", "b", "c"]))
            ]
        )
        
        let prompt = PromptToolPromptBuilder.buildToolPrompt(
            basePrompt: "Test",
            tools: [tool],
            context: PromptToolCallingContext(nonce: "nonce-123")
        )
        
        #expect(prompt.contains("integer"))
        #expect(prompt.contains("number"))
        #expect(prompt.contains("boolean"))
        #expect(prompt.contains("array of string"))
        #expect(prompt.contains("one of: a, b, c"))
    }
}

// MARK: - Tool Calling Emulation Tests

@Suite("Prompt tool calling emulation")
struct PromptToolCallingEmulationTests {
    @Test("No-tool emulation preserves the original prompt and returns completed content")
    func noToolEmulationPreservesPrompt() async throws {
        let basePrompt = "Say hi"

        let response = try await PromptToolCallingEmulation.generateResponse(
            prompt: basePrompt,
            tools: [],
            options: .default
        ) { prompt, _ in
            #expect(prompt == basePrompt)
            return "hi"
        }

        #expect(response.content == "hi")
        #expect(response.toolCalls.isEmpty)
        #expect(response.finishReason == .completed)
    }

    @Test("Valid tool output maps to tool calls with toolCall finish reason")
    func validToolOutputMapsToToolCalls() throws {
        let tools = [
            ToolSchema(name: "lookup", description: "Look up information", parameters: []),
        ]
        let context = PromptToolCallingContext(nonce: "nonce-123")

        let response = try PromptToolCallingEmulation.makeInferenceResponse(
            from: #"{"swarm_tool_call":{"nonce":"nonce-123","tool":"lookup","arguments":{"query":"swift"}}}"#,
            availableTools: tools,
            context: context
        )

        #expect(response.content == nil)
        #expect(response.finishReason == .toolCall)
        #expect(response.toolCalls.count == 1)
        #expect(response.toolCalls.first?.name == "lookup")
        #expect(response.toolCalls.first?.arguments["query"] == .string("swift"))
    }

    @Test("Malformed tool output fails safely as plain content")
    func malformedToolOutputFailsSafely() throws {
        let tools = [
            ToolSchema(name: "lookup", description: "Look up information", parameters: []),
        ]
        let context = PromptToolCallingContext(nonce: "nonce-123")

        let response = try PromptToolCallingEmulation.makeInferenceResponse(
            from: #"{"tool":"lookup","arguments":{"query":"swift""#,
            availableTools: tools,
            context: context
        )

        #expect(response.content == #"{"tool":"lookup","arguments":{"query":"swift""#)
        #expect(response.toolCalls.isEmpty)
        #expect(response.finishReason == .completed)
    }

    @Test("Plain non-tool output fails safely as completed content")
    func plainOutputFailsSafely() throws {
        let tools = [
            ToolSchema(name: "lookup", description: "Look up information", parameters: []),
        ]
        let context = PromptToolCallingContext(nonce: "nonce-123")

        let response = try PromptToolCallingEmulation.makeInferenceResponse(
            from: "Here is the answer without a tool.",
            availableTools: tools,
            context: context
        )

        #expect(response.content == "Here is the answer without a tool.")
        #expect(response.toolCalls.isEmpty)
        #expect(response.finishReason == .completed)
    }
}

// MARK: - Tool Call Parser Tests

@Suite("Prompt tool call parser")
struct PromptToolParserTests {
    private let context = PromptToolCallingContext(nonce: "nonce-123")

    @Test("Parse valid JSON tool call")
    func parseValidJSONToolCall() throws {
        let response = #"{"swarm_tool_call":{"nonce":"nonce-123","tool":"calculator","arguments":{"expression":"2+2"}}}"#
        
        let availableTools = [
            ToolSchema(name: "calculator", description: "Calc", parameters: [])
        ]
        
        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: availableTools,
            context: context
        )
        
        #expect(toolCalls != nil)
        #expect(toolCalls?.count == 1)
        #expect(toolCalls?[0].name == "calculator")
        #expect(toolCalls?[0].arguments["expression"] == .string("2+2"))
    }
    
    @Test("Return nil for plain JSON without Swarm envelope")
    func plainJSONWithoutEnvelopeIsRejected() throws {
        let response = #"{"tool":"weather","arguments":{"city":"London"}}"#
        
        let availableTools = [
            ToolSchema(name: "weather", description: "Weather", parameters: [])
        ]
        
        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: availableTools,
            context: context
        )

        #expect(toolCalls == nil)
    }
    
    @Test("Parse tool call with call ID")
    func parseToolCallWithCallId() throws {
        let response = #"{"swarm_tool_call":{"nonce":"nonce-123","id":"call_123","tool":"search","arguments":{"query":"Swift"}}}"#
        
        let availableTools = [
            ToolSchema(name: "search", description: "Search", parameters: [])
        ]
        
        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: availableTools,
            context: context
        )
        
        #expect(toolCalls?.first?.id == "call_123")
    }

    @Test("Parse wrapped tool call with surrounding prose")
    func parseWrappedToolCallWithProse() throws {
        let response = """
        I'll use the lookup tool.
        {"swarm_tool_call":{"nonce":"nonce-123","tool":"lookup","arguments":{"query":"Swift"}}}
        """

        let availableTools = [
            ToolSchema(name: "lookup", description: "Lookup", parameters: [])
        ]

        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: availableTools,
            context: context
        )

        #expect(toolCalls?.count == 1)
        #expect(toolCalls?.first?.name == "lookup")
        #expect(toolCalls?.first?.arguments["query"] == .string("Swift"))
    }

    @Test("Parse wrapped tool call inside markdown fence")
    func parseWrappedToolCallInsideMarkdownFence() throws {
        let response = """
        ```json
        {"swarm_tool_call":{"nonce":"nonce-123","tool":"lookup","arguments":{"query":"Swift"}}}
        ```
        """

        let availableTools = [
            ToolSchema(name: "lookup", description: "Lookup", parameters: [])
        ]

        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: availableTools,
            context: context
        )

        #expect(toolCalls?.count == 1)
        #expect(toolCalls?.first?.name == "lookup")
    }
    
    @Test("Parse tool call with various argument types")
    func parseToolCallWithVariousTypes() throws {
        let response = #"{"swarm_tool_call":{"nonce":"nonce-123","tool":"test","arguments":{"str":"hello","num":42,"float":3.14,"bool":true,"null":null}}}"#
        
        let availableTools = [
            ToolSchema(name: "test", description: "Test", parameters: [])
        ]
        
        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: availableTools,
            context: context
        )
        
        #expect(toolCalls?.first?.arguments["str"] == .string("hello"))
        #expect(toolCalls?.first?.arguments["num"] == .int(42))
        #expect(toolCalls?.first?.arguments["bool"] == .bool(true))
    }
    
    @Test("Parse tool call with nested arguments")
    func parseToolCallWithNestedArguments() throws {
        let response = #"{"swarm_tool_call":{"nonce":"nonce-123","tool":"createUser","arguments":{"user":{"name":"Alice","age":30}}}}"#
        
        let availableTools = [
            ToolSchema(name: "createUser", description: "Create user", parameters: [])
        ]
        
        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: availableTools,
            context: context
        )
        
        let userDict = toolCalls?.first?.arguments["user"]?.dictionaryValue
        #expect(userDict?["name"] == .string("Alice"))
        #expect(userDict?["age"] == .int(30))
    }
    
    @Test("Parse tool call with array arguments")
    func parseToolCallWithArrayArguments() throws {
        let response = #"{"swarm_tool_call":{"nonce":"nonce-123","tool":"search","arguments":{"tags":["swift","ai","ios"]}}}"#
        
        let availableTools = [
            ToolSchema(name: "search", description: "Search", parameters: [])
        ]
        
        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: availableTools,
            context: context
        )
        
        let tags = toolCalls?.first?.arguments["tags"]?.arrayValue
        #expect(tags?.count == 3)
        #expect(tags?[0] == .string("swift"))
    }
    
    @Test("Return nil for response without JSON")
    func returnNilForResponseWithoutJSON() throws {
        let response = "This is just a regular response without any tool calls."
        
        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: [ToolSchema(name: "tool", description: "Tool", parameters: [])],
            context: context
        )
        
        #expect(toolCalls == nil)
    }
    
    @Test("Return nil for unknown tool name")
    func returnNilForUnknownToolName() throws {
        let response = #"{"swarm_tool_call":{"nonce":"nonce-123","tool":"unknownTool","arguments":{}}}"#
        
        let availableTools = [
            ToolSchema(name: "knownTool", description: "Known", parameters: [])
        ]
        
        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: availableTools,
            context: context
        )
        
        #expect(toolCalls == nil)
    }
    
    @Test("Return nil for invalid JSON")
    func returnNilForInvalidJSON() throws {
        let response = """
        {"tool": "test", "arguments": {invalid json
        """
        
        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: [ToolSchema(name: "test", description: "Test", parameters: [])],
            context: context
        )
        
        #expect(toolCalls == nil)
    }
    
    @Test("Return nil for JSON without tool name")
    func returnNilForJSONWithoutToolName() throws {
        let response = #"{"swarm_tool_call":{"nonce":"nonce-123","arguments":{"x":1}}}"#
        
        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: [ToolSchema(name: "test", description: "Test", parameters: [])],
            context: context
        )
        
        #expect(toolCalls == nil)
    }
    
    @Test("Return nil for envelope with wrong nonce")
    func returnNilForWrongNonce() throws {
        let response = #"{"swarm_tool_call":{"nonce":"different","tool":"getTime","arguments":{}}}"#

        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: [ToolSchema(name: "getTime", description: "Get time", parameters: [])],
            context: context
        )

        #expect(toolCalls == nil)
    }

    @Test("Return nil for multiple wrapped tool envelopes")
    func returnNilForMultipleWrappedToolEnvelopes() throws {
        let response = """
        First:
        {"swarm_tool_call":{"nonce":"nonce-123","tool":"getTime","arguments":{}}}
        Second:
        {"swarm_tool_call":{"nonce":"nonce-123","tool":"getTime","arguments":{}}}
        """

        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: [ToolSchema(name: "getTime", description: "Get time", parameters: [])],
            context: context
        )

        #expect(toolCalls == nil)
    }

    @Test("Parse tool call with empty arguments")
    func parseToolCallWithEmptyArguments() throws {
        let response = #"{"swarm_tool_call":{"nonce":"nonce-123","tool":"getTime","arguments":{}}}"#
        
        let availableTools = [
            ToolSchema(name: "getTime", description: "Get time", parameters: [])
        ]
        
        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: availableTools,
            context: context
        )
        
        #expect(toolCalls?.first?.name == "getTime")
        #expect(toolCalls?.first?.arguments.isEmpty == true)
    }
}

// MARK: - Integration Tests (No Foundation Models Required)

@Suite("Prompt tool calling integration")
struct PromptToolCallingIntegrationTests {
    @Test("generateWithToolCalls returns content when no tools provided")
    func generateWithToolCallsNoTools() async throws {
        // Parser-only check: text-only backends do not use Apple's session.
        let toolCalls = try PromptToolParser.parseToolCalls(
            from: "Just a normal response",
            availableTools: [],
            context: PromptToolCallingContext(nonce: "nonce-123")
        )
        
        #expect(toolCalls == nil)
    }
}

// MARK: - Fail-Closed Envelope Tests (AC-005)

@Suite("Prompt tool call parser fail-closed")
struct PromptToolParserFailClosedTests {
    private let context = PromptToolCallingContext(nonce: "nonce-123")
    private let tools = [ToolSchema(name: "lookup", description: "Lookup", parameters: [])]

    @Test("Mistyped tool field throws naming the field")
    func mistypedToolFieldThrows() throws {
        let response = #"{"swarm_tool_call":{"nonce":"nonce-123","tool":123,"arguments":{}}}"#

        #expect(throws: PromptToolParseError.malformedEnvelopeField(
            field: "tool",
            detail: "expected a string tool name"
        )) {
            _ = try PromptToolParser.parseToolCalls(
                from: response,
                availableTools: tools,
                context: context
            )
        }
    }

    @Test("Mistyped arguments field throws naming the field")
    func mistypedArgumentsFieldThrows() throws {
        let response = #"{"swarm_tool_call":{"nonce":"nonce-123","tool":"lookup","arguments":"oops"}}"#

        #expect(throws: PromptToolParseError.malformedEnvelopeField(
            field: "arguments",
            detail: "expected an object mapping argument names to values"
        )) {
            _ = try PromptToolParser.parseToolCalls(
                from: response,
                availableTools: tools,
                context: context
            )
        }
    }

    @Test("Mistyped id field throws naming the field")
    func mistypedIDFieldThrows() throws {
        let response = #"{"swarm_tool_call":{"nonce":"nonce-123","id":42,"tool":"lookup","arguments":{}}}"#

        #expect(throws: PromptToolParseError.malformedEnvelopeField(
            field: "id",
            detail: "expected a string call id"
        )) {
            _ = try PromptToolParser.parseToolCalls(
                from: response,
                availableTools: tools,
                context: context
            )
        }
    }

    @Test("Prose-wrapped malformed envelope throws")
    func wrappedMalformedEnvelopeThrows() throws {
        let response = """
        Using the tool now.
        {"swarm_tool_call":{"nonce":"nonce-123","tool":["lookup"],"arguments":{}}}
        """

        #expect(throws: PromptToolParseError.self) {
            _ = try PromptToolParser.parseToolCalls(
                from: response,
                availableTools: tools,
                context: context
            )
        }
    }

    @Test("Valid envelope alongside malformed envelope throws instead of dropping the broken one")
    func validPlusMalformedThrows() throws {
        let valid = #"{"swarm_tool_call":{"nonce":"nonce-123","tool":"lookup","arguments":{}}}"#
        let malformed = #"{"swarm_tool_call":{"nonce":"nonce-123","tool":123,"arguments":{}}}"#

        for response in ["\(valid)\n\(malformed)", "\(malformed)\n\(valid)"] {
            #expect(throws: PromptToolParseError.self) {
                _ = try PromptToolParser.parseToolCalls(
                    from: response,
                    availableTools: tools,
                    context: context
                )
            }
        }
    }

    @Test("Mistyped nonce yields nil as unauthenticated text")
    func mistypedNonceYieldsNil() throws {
        let response = #"{"swarm_tool_call":{"nonce":123,"tool":"lookup","arguments":{}}}"#

        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: tools,
            context: context
        )
        #expect(toolCalls == nil)
    }

    @Test("Non-object envelope value yields nil")
    func nonObjectEnvelopeYieldsNil() throws {
        let response = #"{"swarm_tool_call":"lookup"}"#

        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: tools,
            context: context
        )
        #expect(toolCalls == nil)
    }

    @Test("Null tool reads as absent and yields nil")
    func nullToolYieldsNil() throws {
        let response = #"{"swarm_tool_call":{"nonce":"nonce-123","tool":null,"arguments":{}}}"#

        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: tools,
            context: context
        )
        #expect(toolCalls == nil)
    }

    @Test("Null arguments read as absent and parse with empty arguments")
    func nullArgumentsParseAsEmpty() throws {
        let response = #"{"swarm_tool_call":{"nonce":"nonce-123","tool":"lookup","arguments":null}}"#

        let toolCalls = try PromptToolParser.parseToolCalls(
            from: response,
            availableTools: tools,
            context: context
        )
        #expect(toolCalls?.first?.name == "lookup")
        #expect(toolCalls?.first?.arguments.isEmpty == true)
    }

    @Test("makeInferenceResponse propagates envelope field errors")
    func responseMappingPropagatesFieldErrors() throws {
        #expect(throws: PromptToolParseError.self) {
            _ = try PromptToolCallingEmulation.makeInferenceResponse(
                from: #"{"swarm_tool_call":{"nonce":"nonce-123","tool":123}}"#,
                availableTools: tools,
                context: context
            )
        }
    }
}

// The PromptToolPromptBuilder and PromptToolParser types
// are defined in Sources/Swarm/Providers/PromptToolCallingEmulation.swift and are
// available here via @testable import Swarm.
