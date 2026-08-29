// ParallelToolExecutorTests.swift
// SwarmTests
//
// Comprehensive unit tests for ParallelToolExecutor.
// Mock types are defined in ParallelToolExecutorTests+Mocks.swift

import Foundation
@testable import Swarm
import Testing

// MARK: - ParallelToolExecutorTests

@Suite("ParallelToolExecutor Tests")
struct ParallelToolExecutorTests {
    // MARK: Internal

    // MARK: - Order Preservation Tests

    @Test("Parallel execution maintains order regardless of completion time")
    func parallelExecutionMaintainsOrder() async throws {
        // Create tools with different delays - tool3 finishes first, tool1 last
        let tool1 = MockDelayTool(name: "slow_tool", delay: .milliseconds(50), resultValue: .string("first"))
        let tool2 = MockDelayTool(name: "medium_tool", delay: .milliseconds(25), resultValue: .string("second"))
        let tool3 = MockDelayTool(name: "fast_tool", delay: .milliseconds(5), resultValue: .string("third"))

        let registry = try await createRegistry(tools: [tool1, tool2, tool3])
        let executor = ParallelToolExecutor()
        let agent = createMockAgent()

        // Create calls in specific order: slow, medium, fast
        let calls = [
            ToolCall(toolName: "slow_tool", arguments: [:]),
            ToolCall(toolName: "medium_tool", arguments: [:]),
            ToolCall(toolName: "fast_tool", arguments: [:])
        ]

        // Execute in parallel
        let results = try await executor.executeInParallel(
            calls,
            using: registry,
            agent: agent,
            context: nil
        )

        // Verify results are in the SAME order as input, not completion order
        #expect(results.count == 3)
        #expect(results[0].toolName == "slow_tool")
        #expect(results[0].value == SendableValue.string("first"))
        #expect(results[1].toolName == "medium_tool")
        #expect(results[1].value == SendableValue.string("second"))
        #expect(results[2].toolName == "fast_tool")
        #expect(results[2].value == SendableValue.string("third"))
    }

    @Test("Order is maintained with many tools")
    func orderWithManyTools() async throws {
        // Create 10 tools with random-ish delays
        var tools: [MockDelayTool] = []
        for i in 0 ..< 10 {
            let delay = Duration.milliseconds((10 - i) * 5) // Reverse order delays
            tools.append(MockDelayTool(
                name: "tool_\(i)",
                delay: delay,
                resultValue: .int(i)
            ))
        }

        let registry = try await createRegistry(tools: tools)
        let executor = ParallelToolExecutor()
        let agent = createMockAgent()

        let calls = tools.map { ToolCall(toolName: $0.name, arguments: [:]) }

        let results = try await executor.executeInParallel(
            calls,
            using: registry,
            agent: agent,
            context: nil
        )

        // Verify order matches input
        #expect(results.count == 10)
        for i in 0 ..< 10 {
            #expect(results[i].toolName == "tool_\(i)")
            #expect(results[i].value == SendableValue.int(i))
        }
    }

    // MARK: - Error Handling Tests

    @Test("Parallel execution handles errors gracefully with default behavior")
    func parallelExecutionHandlesErrors() async throws {
        let successTool = MockDelayTool(name: "success_tool", delay: .zero, resultValue: .string("success"))
        let errorTool = MockErrorTool(name: "error_tool")

        let registry = try await createRegistry(tools: [successTool, errorTool])
        let executor = ParallelToolExecutor()
        let agent = createMockAgent()

        let calls = [
            ToolCall(toolName: "success_tool", arguments: [:]),
            ToolCall(toolName: "error_tool", arguments: [:])
        ]

        // Default behavior captures errors in results
        let results = try await executor.executeInParallel(
            calls,
            using: registry,
            agent: agent,
            context: nil
        )

        #expect(results.count == 2)

        // First result should be success
        #expect(results[0].isSuccess == true)
        #expect(results[0].toolName == "success_tool")
        #expect(results[0].value == SendableValue.string("success"))

        // Second result should be failure
        #expect(results[1].isSuccess == false)
        #expect(results[1].toolName == "error_tool")
        #expect(results[1].error != nil)
    }

    @Test("Disabled tools fail validation before execution")
    func disabledToolFailsValidationBeforeExecution() async throws {
        let counter = ToolExecutionCounter()
        let enabledTool = CountingTool(name: "enabled_tool", counter: counter)
        let disabledTool = DisabledTestTool(name: "disabled_tool")

        let registry = try await createRegistry(tools: [enabledTool, disabledTool])
        let executor = ParallelToolExecutor()
        let agent = createMockAgent()

        let calls = [
            ToolCall(toolName: "enabled_tool", arguments: [:]),
            ToolCall(toolName: "disabled_tool", arguments: [:])
        ]

        await #expect(throws: AgentError.self) {
            _ = try await executor.executeInParallel(
                calls,
                using: registry,
                agent: agent,
                context: nil
            )
        }

        let executionCount = await counter.snapshot()
        #expect(executionCount == 0)
    }

    @Test("Fail-fast strategy rejects disabled tools before execution")
    func failFastRejectsDisabledToolBeforeExecution() async throws {
        let counter = ToolExecutionCounter()
        let enabledTool = CountingTool(name: "enabled_tool", counter: counter)
        let disabledTool = DisabledTestTool(name: "disabled_tool")

        let registry = try await createRegistry(tools: [enabledTool, disabledTool])
        let executor = ParallelToolExecutor()
        let agent = createMockAgent()

        let calls = [
            ToolCall(toolName: "enabled_tool", arguments: [:]),
            ToolCall(toolName: "disabled_tool", arguments: [:])
        ]

        await #expect(throws: AgentError.self) {
            _ = try await executor.executeInParallel(
                calls,
                using: registry,
                agent: agent,
                context: nil,
                errorStrategy: .failFast
            )
        }

        let executionCount = await counter.snapshot()
        #expect(executionCount == 0)
    }

    @Test("Error strategy .failFast throws on first error")
    func errorStrategyFailFast() async throws {
        let successTool1 = MockDelayTool(name: "success1", delay: .zero, resultValue: .string("ok1"))
        let errorTool = MockErrorTool(
            name: "error_tool",
            error: AgentError.toolFailure(toolName: "error_tool", message: "Test failure", cause: nil)
        )
        let successTool2 = MockDelayTool(name: "success2", delay: .zero, resultValue: .string("ok2"))

        let registry = try await createRegistry(tools: [successTool1, errorTool, successTool2])
        let executor = ParallelToolExecutor()
        let agent = createMockAgent()

        let calls = [
            ToolCall(toolName: "success1", arguments: [:]),
            ToolCall(toolName: "error_tool", arguments: [:]),
            ToolCall(toolName: "success2", arguments: [:])
        ]

        // Should throw the error from the first failing tool
        var thrownError: Error?
        do {
            _ = try await executor.executeInParallel(
                calls,
                using: registry,
                agent: agent,
                context: nil,
                errorStrategy: .failFast
            )
        } catch {
            thrownError = error
        }

        #expect(thrownError != nil)
        if let agentError = thrownError as? AgentError {
            if case let .toolFailure(toolName, _, _) = agentError {
                #expect(toolName == "error_tool")
            } else {
                Issue.record("Expected toolFailure error")
            }
        }
    }

    @Test("Error strategy .collectErrors throws composite error")
    func errorStrategyCollectErrors() async throws {
        let errorTool1 = MockErrorTool(
            name: "error1",
            error: AgentError.toolFailure(toolName: "error1", message: "First failure", cause: nil)
        )
        let errorTool2 = MockErrorTool(
            name: "error2",
            error: AgentError.toolFailure(toolName: "error2", message: "Second failure", cause: nil)
        )
        let successTool = MockDelayTool(name: "success", delay: .zero, resultValue: .string("ok"))

        let registry = try await createRegistry(tools: [errorTool1, errorTool2, successTool])
        let executor = ParallelToolExecutor()
        let agent = createMockAgent()

        let calls = [
            ToolCall(toolName: "error1", arguments: [:]),
            ToolCall(toolName: "success", arguments: [:]),
            ToolCall(toolName: "error2", arguments: [:])
        ]

        var thrownError: Error?
        do {
            _ = try await executor.executeInParallel(
                calls,
                using: registry,
                agent: agent,
                context: nil,
                errorStrategy: .collectErrors
            )
        } catch {
            thrownError = error
        }

        #expect(thrownError != nil)
        if let agentError = thrownError as? AgentError {
            if case let .toolFailure(toolName, message, _) = agentError {
                #expect(toolName == "parallel_execution")
                #expect(message?.contains("Multiple tools failed") == true)
            } else {
                Issue.record("Expected toolFailure with parallel_execution")
            }
        }
    }

    @Test("Error strategy .continueOnError returns all results")
    func errorStrategyContinueOnError() async throws {
        let successTool1 = MockDelayTool(name: "success1", delay: .zero, resultValue: .string("result1"))
        let errorTool = MockErrorTool(name: "error_tool")
        let successTool2 = MockDelayTool(name: "success2", delay: .zero, resultValue: .string("result2"))

        let registry = try await createRegistry(tools: [successTool1, errorTool, successTool2])
        let executor = ParallelToolExecutor()
        let agent = createMockAgent()

        let calls = [
            ToolCall(toolName: "success1", arguments: [:]),
            ToolCall(toolName: "error_tool", arguments: [:]),
            ToolCall(toolName: "success2", arguments: [:])
        ]

        // Should NOT throw, returns results with failures included
        let results = try await executor.executeInParallel(
            calls,
            using: registry,
            agent: agent,
            context: nil,
            errorStrategy: .continueOnError
        )

        #expect(results.count == 3)

        // Check each result
        #expect(results[0].isSuccess == true)
        #expect(results[0].value == SendableValue.string("result1"))

        #expect(results[1].isSuccess == false)
        #expect(results[1].error != nil)

        #expect(results[2].isSuccess == true)
        #expect(results[2].value == SendableValue.string("result2"))
    }

    // MARK: - Tool Validation Tests

    @Test("Validates tools exist before execution")
    func validatesToolsExist() async throws {
        let existingTool = MockDelayTool(name: "existing", delay: .zero, resultValue: .string("ok"))
        let registry = try await createRegistry(tools: [existingTool])
        let executor = ParallelToolExecutor()
        let agent = createMockAgent()

        let calls = [
            ToolCall(toolName: "existing", arguments: [:]),
            ToolCall(toolName: "nonexistent", arguments: [:])
        ]

        var thrownError: AgentError?
        do {
            _ = try await executor.executeInParallel(
                calls,
                using: registry,
                agent: agent,
                context: nil
            )
        } catch let error as AgentError {
            thrownError = error
        }

        #expect(thrownError == .toolNotFound(name: "nonexistent"))
    }

    @Test("Tool validation fails fast before any execution")
    func toolValidationFailsFast() async throws {
        // Use a spy tool to verify it was NOT called
        let spyTool = SpyTool(name: "spy_tool", result: .string("should not execute"))
        let registry = try await createRegistry(tools: [spyTool])
        let executor = ParallelToolExecutor()
        let agent = createMockAgent()

        let calls = [
            ToolCall(toolName: "spy_tool", arguments: [:]),
            ToolCall(toolName: "missing_tool", arguments: [:])
        ]

        do {
            _ = try await executor.executeInParallel(
                calls,
                using: registry,
                agent: agent,
                context: nil
            )
            Issue.record("Should have thrown toolNotFound error")
        } catch let error as AgentError {
            #expect(error == .toolNotFound(name: "missing_tool"))
        }

        // Verify spy tool was never called
        let callCount = await spyTool.callCount
        #expect(callCount == 0)
    }

    // MARK: - Empty Input Tests

    @Test("Empty calls array returns empty results")
    func emptyCallsArray() async throws {
        let registry = ToolRegistry()
        let executor = ParallelToolExecutor()
        let agent = createMockAgent()

        let results = try await executor.executeInParallel(
            [],
            using: registry,
            agent: agent,
            context: nil
        )

        #expect(results.isEmpty)
    }

    @Test("Empty calls array with error strategy returns empty results")
    func emptyCallsWithErrorStrategy() async throws {
        let registry = ToolRegistry()
        let executor = ParallelToolExecutor()
        let agent = createMockAgent()

        let results = try await executor.executeInParallel(
            [],
            using: registry,
            agent: agent,
            context: nil,
            errorStrategy: .failFast
        )

        #expect(results.isEmpty)
    }

    // MARK: - Single Tool Tests

    @Test("Single tool execution works correctly")
    func singleToolExecution() async throws {
        let tool = MockDelayTool(name: "single", delay: .zero, resultValue: .string("single_result"))
        let registry = try await createRegistry(tools: [tool])
        let executor = ParallelToolExecutor()
        let agent = createMockAgent()

        let calls = [ToolCall(toolName: "single", arguments: [:])]

        let results = try await executor.executeInParallel(
            calls,
            using: registry,
            agent: agent,
            context: nil
        )

        #expect(results.count == 1)
        #expect(results[0].isSuccess == true)
        #expect(results[0].toolName == "single")
        #expect(results[0].value == SendableValue.string("single_result"))
    }

    @Test("Single failing tool returns failure result")
    func singleFailingTool() async throws {
        let tool = MockErrorTool(name: "fail_single")
        let registry = try await createRegistry(tools: [tool])
        let executor = ParallelToolExecutor()
        let agent = createMockAgent()

        let calls = [ToolCall(toolName: "fail_single", arguments: [:])]

        let results = try await executor.executeInParallel(
            calls,
            using: registry,
            agent: agent,
            context: nil
        )

        #expect(results.count == 1)
        #expect(results[0].isSuccess == false)
        #expect(results[0].toolName == "fail_single")
        #expect(results[0].error != nil)
    }

    // MARK: - Arguments Passing Tests

    @Test("Arguments are passed correctly to tools")
    func argumentsPassing() async throws {
        let spyTool = SpyTool(name: "spy", result: .string("received"))
        let registry = try await createRegistry(tools: [spyTool])
        let executor = ParallelToolExecutor()
        let agent = createMockAgent()

        let arguments: [String: SendableValue] = [
            "key1": .string("value1"),
            "key2": .int(42),
            "key3": .bool(true)
        ]

        let calls = [ToolCall(toolName: "spy", arguments: arguments)]

        _ = try await executor.executeInParallel(
            calls,
            using: registry,
            agent: agent,
            context: nil
        )

        // Verify the spy received the correct arguments
        let lastCall = await spyTool.lastCall
        #expect(lastCall != nil)
        #expect(lastCall?.arguments["key1"] == .string("value1"))
        #expect(lastCall?.arguments["key2"] == .int(42))
        #expect(lastCall?.arguments["key3"] == .bool(true))
    }

    // MARK: - Result Properties Tests

    @Test("Results include duration information")
    func resultsIncludeDuration() async throws {
        let tool = MockDelayTool(name: "delayed", delay: .milliseconds(50), resultValue: .string("done"))
        let registry = try await createRegistry(tools: [tool])
        let executor = ParallelToolExecutor()
        let agent = createMockAgent()

        let calls = [ToolCall(toolName: "delayed", arguments: [:])]

        let results = try await executor.executeInParallel(
            calls,
            using: registry,
            agent: agent,
            context: nil
        )

        #expect(results.count == 1)
        // Duration should be at least the delay time
        #expect(results[0].duration >= Duration.milliseconds(50))
    }

    @Test("Results include timestamp")
    func resultsIncludeTimestamp() async throws {
        let beforeExecution = Date()

        let tool = MockDelayTool(name: "timestamped", delay: .zero, resultValue: .string("ok"))
        let registry = try await createRegistry(tools: [tool])
        let executor = ParallelToolExecutor()
        let agent = createMockAgent()

        let calls = [ToolCall(toolName: "timestamped", arguments: [:])]

        let results = try await executor.executeInParallel(
            calls,
            using: registry,
            agent: agent,
            context: nil
        )

        let afterExecution = Date()

        #expect(results.count == 1)
        #expect(results[0].timestamp >= beforeExecution)
        #expect(results[0].timestamp <= afterExecution)
    }

    @Test("Results include tool arguments")
    func resultsIncludeArguments() async throws {
        let tool = MockDelayTool(name: "args_test", delay: .zero, resultValue: .string("ok"))
        let registry = try await createRegistry(tools: [tool])
        let executor = ParallelToolExecutor()
        let agent = createMockAgent()

        let arguments: [String: SendableValue] = ["param": .string("value")]
        let calls = [ToolCall(toolName: "args_test", arguments: arguments)]

        let results = try await executor.executeInParallel(
            calls,
            using: registry,
            agent: agent,
            context: nil
        )

        #expect(results.count == 1)
        #expect(results[0].arguments == arguments)
    }

    // MARK: Private

    // MARK: - Test Helpers

    private func createRegistry(tools: [any AnyJSONTool]) async throws -> ToolRegistry {
        let registry = ToolRegistry()
        try await registry.register(tools)
        return registry
    }

    private func createMockAgent() -> ParallelTestMockAgent {
        ParallelTestMockAgent()
    }
}
