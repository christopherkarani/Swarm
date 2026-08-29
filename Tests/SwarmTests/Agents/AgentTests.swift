// AgentTests.swift
// SwarmTests
//
// Tests for agent implementations.

import Foundation
@testable import Swarm
import Testing

// MARK: - ReActAgentTests

@Suite("Agent Tests", .ephemeralDefaultStores)
struct ReActAgentTests {

    @Test("makeDefaultMemory matches Integrations trait")
    func makeDefaultMemoryMatchesIntegrationsTrait() throws {
        let memory = try Agent.makeDefaultMemory()
        #if SWARM_INTEGRATIONS && canImport(ContextCore)
        #expect(memory is DefaultAgentMemory)
        #else
        #expect(memory is SlidingWindowMemory)
        #endif
    }

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

        let recordedToolCalls = await mockProvider.toolCallMessageCalls
        #expect(recordedToolCalls.count == 2)
        #expect(recordedToolCalls.first?.options.toolChoice == .required)
        #expect(recordedToolCalls.first?.tools.contains { $0.name == "test_tool" } == true)
    }

    @Test("Multiple tool calls in one turn preserve result order")
    func multipleToolCallsPreserveResultOrder() async throws {
        let firstTool = MockTool(name: "first") { _ in
            .string("first result")
        }
        let secondTool = MockTool(name: "second") { _ in
            .string("second result")
        }

        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(id: "call_first", name: "first", arguments: [:]),
                    InferenceResponse.ParsedToolCall(id: "call_second", name: "second", arguments: [:]),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
            InferenceResponse(content: "Done", toolCalls: [], finishReason: .completed, usage: nil),
        ])

        let agent = try Agent(
            tools: [firstTool, secondTool],
            instructions: "Use both tools.",
            configuration: .default.parallelToolCalls(true),
            inferenceProvider: provider
        )

        let result = try await agent.run("Use both tools")

        #expect(result.toolCalls.map(\.toolName) == ["first", "second"])
        #expect(result.toolResults.map(\.output) == [.string("first result"), .string("second result")])
        #expect(result.output == "Done")
    }

    @Test("Multiple tool-call failures keep input order and continue the run")
    func multipleToolCallFailuresKeepOrder() async throws {
        let failing = MockTool(name: "first") { _ in
            throw AgentError.toolFailure(toolName: "first", message: "boom", cause: nil)
        }
        let succeeding = MockTool(name: "second") { _ in
            .string("ok")
        }

        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(id: "call_first", name: "first", arguments: [:]),
                    InferenceResponse.ParsedToolCall(id: "call_second", name: "second", arguments: [:]),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
            InferenceResponse(content: "Recovered", toolCalls: [], finishReason: .completed, usage: nil),
        ])

        let agent = try Agent(
            tools: [failing, succeeding],
            instructions: "Use both tools.",
            configuration: .default.parallelToolCalls(true),
            inferenceProvider: provider
        )

        let result = try await agent.run("Use both tools")

        #expect(result.toolCalls.map(\.toolName) == ["first", "second"])
        #expect(result.toolResults.map(\.isSuccess) == [false, true])
        #expect(result.toolResults[0].errorMessage != nil)
        #expect(result.toolResults[1].output == .string("ok"))
        #expect(result.output == "Recovered")
    }

    @Test("stopOnToolError throws after committing the first failed call")
    func stopOnToolErrorThrowsFirstFailure() async throws {
        let failing = MockTool(name: "first") { _ in
            throw AgentError.toolFailure(toolName: "first", message: "boom", cause: nil)
        }
        let succeeding = MockTool(name: "second") { _ in
            .string("ok")
        }

        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(id: "call_first", name: "first", arguments: [:]),
                    InferenceResponse.ParsedToolCall(id: "call_second", name: "second", arguments: [:]),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
            InferenceResponse(content: "should not run", toolCalls: [], finishReason: .completed, usage: nil),
        ])

        let agent = try Agent(
            tools: [failing, succeeding],
            instructions: "Use both tools.",
            configuration: .default.parallelToolCalls(true).stopOnToolError(true),
            inferenceProvider: provider
        )

        do {
            _ = try await agent.run("Use both tools")
            Issue.record("Expected stopOnToolError to throw")
        } catch let error as AgentError {
            switch error {
            case let .toolFailure(toolName, message, _):
                #expect(toolName == "first")
                #expect(message?.contains("boom") == true)
            default:
                Issue.record("Expected toolFailure, got \(error)")
            }
        } catch {
            Issue.record("Expected AgentError, got \(error)")
        }
    }

    @Test("Parallel tool timeout cancels in-flight tool work")
    func parallelToolTimeoutCancelsInflightWork() async throws {
        let hanging = MockTool(name: "slow") { _ in
            try await Task.sleep(for: .seconds(2))
            return .string("late")
        }
        let alsoHanging = MockTool(name: "slower") { _ in
            try await Task.sleep(for: .seconds(2))
            return .string("later")
        }

        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(id: "call_slow", name: "slow", arguments: [:]),
                    InferenceResponse.ParsedToolCall(id: "call_slower", name: "slower", arguments: [:]),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
        ])

        let agent = try Agent(
            tools: [hanging, alsoHanging],
            instructions: "Use both tools.",
            configuration: .default.parallelToolCalls(true).timeout(.milliseconds(80)),
            inferenceProvider: provider
        )

        let runTask = Task {
            try await agent.run("Use both tools")
        }
        let completion = await awaitParallelTaskResult(runTask, timeout: .milliseconds(800))
        guard let completion else {
            runTask.cancel()
            Issue.record("Parallel tool run did not stop promptly after timeout")
            return
        }

        switch completion {
        case .success:
            Issue.record("Expected timeout error but run succeeded")
        case let .failure(error as AgentError):
            #expect(error == .timeout(duration: .milliseconds(80)))
        case let .failure(error):
            Issue.record("Expected AgentError.timeout, got \(error)")
        }
    }

    @Test("Parallel tool cancellation stops in-flight tool work")
    func parallelToolCancellationStopsInflightWork() async throws {
        let hanging = MockTool(name: "slow") { _ in
            try await Task.sleep(for: .seconds(2))
            return .string("late")
        }
        let alsoHanging = MockTool(name: "slower") { _ in
            try await Task.sleep(for: .seconds(2))
            return .string("later")
        }

        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(id: "call_slow", name: "slow", arguments: [:]),
                    InferenceResponse.ParsedToolCall(id: "call_slower", name: "slower", arguments: [:]),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
        ])

        let agent = try Agent(
            tools: [hanging, alsoHanging],
            instructions: "Use both tools.",
            configuration: .default.parallelToolCalls(true).timeout(.seconds(15)),
            inferenceProvider: provider
        )

        let runTask = Task {
            try await agent.run("Use both tools")
        }
        try await Task.sleep(for: .milliseconds(40))
        await agent.cancel()

        let completion = await awaitParallelTaskResult(runTask, timeout: .milliseconds(800))
        guard let completion else {
            runTask.cancel()
            Issue.record("Parallel tool run did not stop promptly after agent.cancel()")
            return
        }

        switch completion {
        case .success:
            Issue.record("Expected cancellation error but run succeeded")
        case let .failure(error as AgentError):
            #expect(error == .cancelled)
        case let .failure(error):
            Issue.record("Expected AgentError.cancelled, got \(error)")
        }
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

private func awaitParallelTaskResult<T: Sendable>(
    _ task: Task<T, Error>,
    timeout: Duration
) async -> Result<T, Error>? {
    await withTaskGroup(of: Result<T, Error>?.self) { group in
        group.addTask {
            do {
                return .success(try await task.value)
            } catch {
                return .failure(error)
            }
        }

        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }

        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
