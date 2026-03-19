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
        let spyTool = await SpyTool(
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

        let recordedToolCalls = await mockProvider.toolCallMessageCalls
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
}

// MARK: - BuiltInToolsTests

@Suite("Built-in Tools Tests")
struct BuiltInToolsTests {
    #if canImport(Darwin)
        @Test("Calculator tool")
        func calculatorTool() async throws {
            var calculator = CalculatorTool()

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
        var dateTime = DateTimeTool()

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
        var stringTool = StringTool()

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
