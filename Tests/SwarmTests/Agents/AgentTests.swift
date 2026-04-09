// AgentTests.swift
// SwarmTests
//
// Tests for agent implementations.

import Foundation
@testable import Swarm
import Testing

// MARK: - ReActAgentTests

@Suite("Agent Tests")
struct ReActAgentTests {
    @Test("Simple query returns final answer")
    func simpleQuery() async throws {
        // Create a mock provider that immediately returns a response
        let mockProvider = MockInferenceProvider(responses: [
            "42"
        ])

        // Create agent with the mock provider
        let agent = try Agent(
            tools: [],
            instructions: "You are a helpful assistant.",
            inferenceProvider: mockProvider
        )

        // Run the agent
        let result = try await agent.run("What is the answer?")

        // Verify the output — Agent returns the raw model response
        #expect(result.output == "42")
        #expect(result.iterationCount == 1)
        let promptCalls = await mockProvider.generateCalls
        let messageCalls = await mockProvider.generateMessageCalls
        #expect(promptCalls.isEmpty)
        #expect(messageCalls.count == 1)
    }

    @Test("Native tool calling executes provider tool calls")
    func nativeToolCallingExecutesToolCalls() async throws {
        let spyTool = SpyTool(
            name: "test_tool",
            result: .string("Tool result")
        )

        let mockProvider = MockInferenceProvider()
        await mockProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_123",
                        name: "test_tool",
                        arguments: ["location": .string("NYC")]
                    )
                ],
                finishReason: .toolCall,
                usage: nil
            ),
            InferenceResponse(
                content: "Done",
                toolCalls: [],
                finishReason: .completed,
                usage: nil
            )
        ])

        let config = AgentConfiguration.default
            .modelSettings(ModelSettings.default.toolChoice(.required))

        let agent = try Agent(
            tools: [spyTool],
            instructions: "You are a helpful assistant.",
            configuration: config,
            inferenceProvider: mockProvider
        )

        let result = try await agent.run("Use the tool")

        #expect(result.output == "Done")
        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].providerCallId == "call_123")

        #expect(await spyTool.callCount == 1)
        #expect(await spyTool.wasCalledWith(argument: "location", value: .string("NYC")))

        let recordedToolCalls = await allRecordedToolCallRounds(from: mockProvider)
        #expect(recordedToolCalls.count == 2)
        #expect(recordedToolCalls.first?.options.toolChoice == .required)
        #expect(recordedToolCalls.first?.tools.contains { $0.name == "test_tool" } == true)
    }

    @Test("Max iterations exceeded")
    func maxIterationsExceeded() async throws {
        // Create mock provider that always returns tool calls (never a final text response)
        let mockProvider = MockInferenceProvider()
        await mockProvider.configureInfiniteToolCalling(toolName: "noop")

        // A no-op tool so the agent enters the tool-calling path
        let noopTool = MockTool(name: "noop", description: "Does nothing")

        // Create agent with maxIterations=1
        let config = AgentConfiguration.default.maxIterations(1)
        let agent = try Agent(
            tools: [noopTool],
            instructions: "You are a helpful assistant.",
            configuration: config,
            inferenceProvider: mockProvider
        )

        // Verify that maxIterationsExceeded error is thrown
        do {
            _ = try await agent.run("Think forever")
            Issue.record("Expected maxIterationsExceeded error but succeeded")
        } catch let error as AgentError {
            switch error {
            case let .maxIterationsExceeded(iterations):
                #expect(iterations == 1)
            default:
                Issue.record("Expected maxIterationsExceeded but got: \(error)")
            }
        } catch {
            Issue.record("Expected AgentError but got: \(error)")
        }
    }

    @Test("Duplicate tool calls are suppressed after the first identical request")
    func duplicateToolCallsAreSuppressed() async throws {
        let spyTool = SpyTool(
            name: "websearch",
            result: .string("First search result")
        )

        let mockProvider = MockInferenceProvider()
        await mockProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_1",
                        name: "websearch",
                        arguments: ["query": .string("same query"), "maxResults": .int(1)]
                    )
                ],
                finishReason: .toolCall,
                usage: nil
            ),
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_2",
                        name: "websearch",
                        arguments: ["query": .string("same query")]
                    )
                ],
                finishReason: .toolCall,
                usage: nil
            ),
            InferenceResponse(
                content: "Done",
                toolCalls: [],
                finishReason: .completed,
                usage: nil
            )
        ])

        let agent = try Agent(
            tools: [spyTool],
            instructions: "Use tools when needed.",
            inferenceProvider: mockProvider
        )

        let result = try await agent.run("Search once")

        #expect(result.output == "Done")
        #expect(await spyTool.callCount == 1)
        #expect(result.toolCalls.count == 1)
        #expect(result.toolResults.count == 1)
    }

    @Test("Weak repeated websearch calls collapse to one semantic invalid signature")
    func weakRepeatedWebsearchCallsAreSuppressed() async throws {
        let spyTool = SpyTool(
            name: "websearch",
            result: .string("Search result")
        )

        let mockProvider = MockInferenceProvider()
        await mockProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_1",
                        name: "websearch",
                        arguments: ["goal": .string("compact")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_2",
                        name: "websearch",
                        arguments: ["domains": .array([.string("apple.com")])]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
            InferenceResponse(
                content: "Done",
                toolCalls: [],
                finishReason: .completed,
                usage: nil
            ),
        ])

        let agent = try Agent(
            tools: [spyTool],
            instructions: "Use tools when needed.",
            inferenceProvider: mockProvider
        )

        let result = try await agent.run("Search once")

        #expect(result.output == "Done")
        #expect(await spyTool.callCount == 1)
        #expect(result.toolCalls.count == 1)
        #expect(result.toolResults.count == 1)
    }

    @Test("Agent retries once when model ignores an existing tool result")
    func agentRetriesWhenModelIgnoresToolResult() async throws {
        let spyTool = SpyTool(
            name: "websearch",
            result: .string("Found 1 ranked result for 'Foundation Models'.")
        )

        let mockProvider = MockInferenceProvider()
        await mockProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_1",
                        name: "websearch",
                        arguments: ["query": .string("Foundation Models")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
            InferenceResponse(
                content: "I cannot access external information or perform web searches.",
                toolCalls: [],
                finishReason: .completed,
                usage: nil
            ),
            InferenceResponse(
                content: "The retrieved result says Foundation Models information was found, but the limitation is that the source snippet is incomplete.",
                toolCalls: [],
                finishReason: .completed,
                usage: nil
            ),
        ])

        let agent = try Agent(
            tools: [spyTool],
            instructions: "Use tools when needed.",
            inferenceProvider: mockProvider
        )

        let result = try await agent.run("Search and answer")

        #expect(result.output.contains("retrieved result"))
        #expect(await spyTool.callCount == 1)
        let toolCallRounds = await allRecordedToolCallRounds(from: mockProvider)
        #expect(toolCallRounds.count == 3)
    }

    @Test("Agent retries once when model returns placeholder tool JSON after a real tool result")
    func agentRetriesWhenModelReturnsPlaceholderToolJSON() async throws {
        let spyTool = SpyTool(
            name: "websearch",
            result: .string("Found 1 ranked result for 'Swarm websearch'.")
        )

        let mockProvider = MockInferenceProvider()
        await mockProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_1",
                        name: "websearch",
                        arguments: ["query": .string("Swarm websearch")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
            InferenceResponse(
                content: #"{"swarm_tool_call":{"nonce":"nonce","tool":"tool_name","arguments":{"param1":"value1"}}}"#,
                toolCalls: [],
                finishReason: .completed,
                usage: nil
            ),
            InferenceResponse(
                content: "The retrieved result mentions Swarm websearch, but the source quality is limited.",
                toolCalls: [],
                finishReason: .completed,
                usage: nil
            ),
        ])

        let agent = try Agent(
            tools: [spyTool],
            instructions: "Use tools when needed.",
            inferenceProvider: mockProvider
        )

        let result = try await agent.run("Search and answer")

        #expect(result.output.contains("retrieved result"))
        #expect(await spyTool.callCount == 1)
        let toolCallRounds = await allRecordedToolCallRounds(from: mockProvider)
        #expect(toolCallRounds.count == 3)
    }

    @Test("Agent falls back to tool-result synthesis after repeated refusal")
    func agentFallsBackToToolResultSynthesis() async throws {
        let spyTool = SpyTool(
            name: "websearch",
            result: .string("""
            Found 1 ranked results for 'Foundation Models'.

            1. [Apple Developer](https://developer.apple.com/machine-learning/)
               Apple provides on-device Foundation Models APIs and related documentation.
            """)
        )

        let mockProvider = MockInferenceProvider()
        await mockProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_1",
                        name: "websearch",
                        arguments: ["query": .string("Foundation Models")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
            InferenceResponse(
                content: "I can't access external information.",
                toolCalls: [],
                finishReason: .completed,
                usage: nil
            ),
            InferenceResponse(
                content: "Sorry, I can't assist with that.",
                toolCalls: [],
                finishReason: .completed,
                usage: nil
            ),
        ])

        let agent = try Agent(
            tools: [spyTool],
            instructions: "Use tools when needed.",
            inferenceProvider: mockProvider
        )

        let result = try await agent.run("Search and answer")

        #expect(result.output.contains("Apple Developer"))
        #expect(result.output.contains("limited to the retrieved search snippet") || result.output.contains("successfully retrieved evidence"))
        #expect(await spyTool.callCount == 1)
    }

    @Test("Agent executes explicit websearch plan when model refuses to call tools")
    func agentExecutesExplicitWebsearchPlanFallback() async throws {
        actor PlannedWebSearchTool: AnyJSONTool {
            nonisolated let name = "websearch"
            nonisolated let description = "Searches the web"
            nonisolated let parameters: [ToolParameter] = [
                ToolParameter(name: "query", description: "Search query", type: .string, isRequired: true),
                ToolParameter(name: "mode", description: "Search mode", type: .string, isRequired: false),
                ToolParameter(name: "maxResults", description: "Maximum search results", type: .int, isRequired: false),
                ToolParameter(name: "detail", description: "Search detail level", type: .string, isRequired: false),
                ToolParameter(name: "preferCached", description: "Prefer cached artifacts", type: .bool, isRequired: false),
                ToolParameter(name: "domains", description: "Domain filters", type: .array(elementType: .string), isRequired: false),
            ]
            nonisolated let inputGuardrails: [any ToolInputGuardrail] = []
            nonisolated let outputGuardrails: [any ToolOutputGuardrail] = []

            private(set) var calls: [(query: String, maxResults: Int?, detail: String?, preferCached: Bool?, domains: [String])] = []

            func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
                let query = arguments["query"]?.stringValue ?? "missing"
                calls.append((
                    query: query,
                    maxResults: arguments["maxResults"]?.intValue,
                    detail: arguments["detail"]?.stringValue,
                    preferCached: arguments["preferCached"]?.boolValue,
                    domains: arguments["domains"]?.arrayValue?.compactMap(\.stringValue) ?? []
                ))
                return .string("""
                Found 1 ranked results for '\(query)'.

                1. [\(query)](https://example.com/\(calls.count))
                   Evidence for \(query).
                """)
            }
        }

        let websearch = PlannedWebSearchTool()
        let mockProvider = MockInferenceProvider()
        await mockProvider.setToolCallResponses([
            InferenceResponse(content: "I cannot browse the web.", toolCalls: [], finishReason: .completed, usage: nil),
            InferenceResponse(content: "I cannot browse the web.", toolCalls: [], finishReason: .completed, usage: nil),
            InferenceResponse(content: "I cannot browse the web.", toolCalls: [], finishReason: .completed, usage: nil),
            InferenceResponse(content: "I cannot browse the web.", toolCalls: [], finishReason: .completed, usage: nil),
            InferenceResponse(content: "I cannot browse the web.", toolCalls: [], finishReason: .completed, usage: nil),
        ])

        let agent = try Agent(
            tools: [websearch],
            instructions: "Use tools when needed.",
            configuration: .default.maxIterations(6),
            inferenceProvider: mockProvider
        )

        let prompt = """
        Use the websearch tool exactly three times.
        1. Search for Apple Foundation Models context window.
        2. Search for whether Apple Foundation Models supports streaming tool calls.
        3. Search for one current source about Apple Foundation Models tool calling limitations.
        Then answer in 4 short bullets with the findings and cite the URLs you used.
        """

        let result = try await agent.run(prompt)

        let calls = await websearch.calls
        #expect(calls.count == 3)
        #expect(calls[0].query == "Apple Foundation Models context window")
        #expect(calls[1].query == "whether Apple Foundation Models supports streaming tool calls")
        #expect(calls[2].query == "one current source about Apple Foundation Models tool calling limitations")
        #expect(calls[0].maxResults == 2)
        #expect(calls[1].maxResults == 2)
        #expect(calls[2].maxResults == 2)
        #expect(calls.allSatisfy { $0.detail == "compact" })
        #expect(calls.allSatisfy { $0.preferCached == true })
        #expect(calls[0].domains.contains("developer.apple.com"))
        #expect(calls[1].domains.contains("developer.apple.com"))
        #expect(calls[2].domains.contains("developer.apple.com"))
        #expect(result.output.contains("https://example.com/1"))
        #expect(result.output.contains("https://example.com/2"))
        #expect(result.output.contains("https://example.com/3"))
    }

    @Test("Deterministic websearch fallback prefers diverse supporting hits over repeated generic primaries")
    func deterministicWebsearchFallbackPrefersDiverseSupportingHits() async throws {
        actor SupportingWebSearchTool: AnyJSONTool {
            nonisolated let name = "websearch"
            nonisolated let description = "Searches the web"
            nonisolated let parameters: [ToolParameter] = [
                ToolParameter(name: "query", description: "Search query", type: .string, isRequired: true),
                ToolParameter(name: "mode", description: "Search mode", type: .string, isRequired: false),
                ToolParameter(name: "maxResults", description: "Maximum search results", type: .int, isRequired: false),
                ToolParameter(name: "detail", description: "Search detail level", type: .string, isRequired: false),
                ToolParameter(name: "preferCached", description: "Prefer cached artifacts", type: .bool, isRequired: false),
            ]
            nonisolated let inputGuardrails: [any ToolInputGuardrail] = []
            nonisolated let outputGuardrails: [any ToolOutputGuardrail] = []

            private(set) var calls: [String] = []

            func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
                let query = arguments["query"]?.stringValue ?? "missing"
                calls.append(query)
                let supportURL = switch calls.count {
                case 1: "https://developer.apple.com/documentation/FoundationModels"
                case 2: "https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window"
                default: "https://machinelearning.apple.com/research/introducing-apple-foundation-models"
                }

                return .string("""
                [Websearch Evidence]
                Query: \(query)
                Best: [What’s New - Machine Learning - Apple Developer](https://developer.apple.com/machine-learning/whats-new/)
                Snippet: Generic overview page.
                Support 1: [Specific Result](\(supportURL))
                Summary: Better supporting evidence exists for \(query).
                """)
            }
        }

        let websearch = SupportingWebSearchTool()
        let mockProvider = MockInferenceProvider()
        await mockProvider.setToolCallResponses([
            InferenceResponse(content: "I cannot browse the web.", toolCalls: [], finishReason: .completed, usage: nil),
            InferenceResponse(content: "I cannot browse the web.", toolCalls: [], finishReason: .completed, usage: nil),
            InferenceResponse(content: "I cannot browse the web.", toolCalls: [], finishReason: .completed, usage: nil),
            InferenceResponse(content: "I cannot browse the web.", toolCalls: [], finishReason: .completed, usage: nil),
        ])

        let agent = try Agent(
            tools: [websearch],
            instructions: "Use tools when needed.",
            configuration: .default.maxIterations(6),
            inferenceProvider: mockProvider
        )

        let prompt = """
        Use the websearch tool exactly three times.
        1. Search for Apple Foundation Models overview.
        2. Search for Apple Foundation Models context limit docs.
        3. Search for Apple Foundation Models research article.
        Then answer in 3 short bullets with the findings and cite the URLs you used.
        """

        let result = try await agent.run(prompt)

        #expect(result.output.contains("https://developer.apple.com/documentation/FoundationModels"))
        #expect(result.output.contains("https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window"))
        #expect(result.output.contains("https://machinelearning.apple.com/research/introducing-apple-foundation-models"))
        #expect(result.output.contains("https://developer.apple.com/machine-learning/whats-new/") == false)
    }
}

// MARK: - BuiltInToolsTests

@Suite("Built-in Tools Tests")
struct BuiltInToolsTests {
    #if canImport(Darwin)
        @Test("Calculator tool")
        func calculatorTool() async throws {
            let calculator = CalculatorTool()

            // Test basic arithmetic with operator precedence
            let result = try await calculator.execute(arguments: [
                "expression": .string("2+3*4")
            ])

            // Verify result (3*4=12, 12+2=14)
            #expect(result == .double(14.0))
        }
    #endif

    @Test("DateTime tool")
    func dateTimeTool() async throws {
        let dateTime = DateTimeTool()

        // Test unix timestamp format
        let result = try await dateTime.execute(arguments: [
            "format": .string("unix")
        ])

        // Verify we get a double (unix timestamp)
        switch result {
        case let .double(timestamp):
            // Verify it's a reasonable timestamp (not zero, not too far in the past/future)
            #expect(timestamp > 0)
            #expect(timestamp < Date.distantFuture.timeIntervalSince1970)
        default:
            Issue.record("Expected double result but got: \(result)")
        }
    }

    @Test("String tool")
    func stringTool() async throws {
        let stringTool = StringTool()

        // Test uppercase operation
        let result = try await stringTool.execute(arguments: [
            "operation": .string("uppercase"),
            "input": .string("hello")
        ])

        // Verify result
        #expect(result == .string("HELLO"))
    }
}

// MARK: - ToolRegistryTests

@Suite("Tool Registry Tests")
struct ToolRegistryTests {
    @Test("Register and lookup tools")
    func registerAndLookup() async throws {
        // Create an empty registry
        let registry = ToolRegistry()

        // Verify it's empty
        let initialCount = await registry.count
        #expect(initialCount == 0)

        // Create and register a mock tool
        let mockTool = MockTool(name: "test_tool", description: "A test tool")
        try await registry.register(mockTool)

        // Verify the tool was registered
        let afterRegisterCount = await registry.count
        #expect(afterRegisterCount == 1)

        // Lookup the tool
        let lookedUpTool = await registry.tool(named: "test_tool")
        #expect(lookedUpTool != nil)
        #expect(lookedUpTool?.name == "test_tool")

        // Verify contains
        let contains = await registry.contains(named: "test_tool")
        #expect(contains == true)

        // Unregister the tool
        await registry.unregister(named: "test_tool")

        // Verify it was removed
        let afterUnregisterCount = await registry.count
        #expect(afterUnregisterCount == 0)

        let notFound = await registry.tool(named: "test_tool")
        #expect(notFound == nil)
    }
}

private struct RecordedToolCallRound {
    let tools: [ToolSchema]
    let options: InferenceOptions
}

private func allRecordedToolCallRounds(from provider: MockInferenceProvider) async -> [RecordedToolCallRound] {
    let promptRounds = await provider.toolCallCalls.map {
        RecordedToolCallRound(tools: $0.tools, options: $0.options)
    }
    let messageRounds = await provider.toolCallMessageCalls.map {
        RecordedToolCallRound(tools: $0.tools, options: $0.options)
    }
    return promptRounds + messageRounds
}
