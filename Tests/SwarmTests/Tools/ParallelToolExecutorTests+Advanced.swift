// ParallelToolExecutorTests+Advanced.swift
// SwarmTests
//
// Advanced tests for ParallelToolExecutor: convenience methods, cancellation, and edge cases.

import Foundation
@testable import Swarm
import Testing

// MARK: - ParallelToolExecutorAdvancedTests

@Suite("ParallelToolExecutor Advanced Tests")
struct ParallelToolExecutorAdvancedTests {
    // MARK: Internal

    // MARK: - Convenience Method Tests

    @Test("executeAllCapturingErrors works correctly")
    func testExecuteAllCapturingErrors() async throws {
        let successTool = MockDelayTool(name: "success", delay: .zero, resultValue: .string("ok"))
        let errorTool = MockErrorTool(name: "error")

        let registry = try await createRegistry(tools: [successTool, errorTool])
        let executor = ParallelToolExecutor()
        let agent = ParallelTestMockAgent()

        let calls = [
            ToolCall(toolName: "success", arguments: [:]),
            ToolCall(toolName: "error", arguments: [:])
        ]

        // Should not throw, errors are captured
        let results = try await executor.executeAllCapturingErrors(
            calls,
            using: registry,
            agent: agent
        )

        #expect(results.count == 2)
        #expect(results[0].isSuccess == true)
        #expect(results[1].isSuccess == false)
    }

    @Test("executeAllOrFail throws on first error")
    func testExecuteAllOrFail() async throws {
        let successTool = MockDelayTool(name: "success", delay: .zero, resultValue: .string("ok"))
        let errorTool = MockErrorTool(name: "error")

        let registry = try await createRegistry(tools: [successTool, errorTool])
        let executor = ParallelToolExecutor()
        let agent = ParallelTestMockAgent()

        let calls = [
            ToolCall(toolName: "success", arguments: [:]),
            ToolCall(toolName: "error", arguments: [:])
        ]

        var didThrow = false
        do {
            _ = try await executor.executeAllOrFail(
                calls,
                using: registry,
                agent: agent
            )
        } catch {
            didThrow = true
        }

        #expect(didThrow == true)
    }

    // MARK: - All Successes Tests

    @Test("All successful tools return all success results")
    func allSuccessfulTools() async throws {
        let tool1 = MockDelayTool(name: "tool1", delay: .zero, resultValue: .string("result1"))
        let tool2 = MockDelayTool(name: "tool2", delay: .zero, resultValue: .int(42))
        let tool3 = MockDelayTool(name: "tool3", delay: .zero, resultValue: .bool(true))

        let registry = try await createRegistry(tools: [tool1, tool2, tool3])
        let executor = ParallelToolExecutor()
        let agent = ParallelTestMockAgent()

        let calls = [
            ToolCall(toolName: "tool1", arguments: [:]),
            ToolCall(toolName: "tool2", arguments: [:]),
            ToolCall(toolName: "tool3", arguments: [:])
        ]

        let results = try await executor.executeInParallel(
            calls,
            using: registry,
            agent: agent,
            context: nil
        )

        #expect(results.count == 3)
        #expect(results.allSatisfy { $0.isSuccess })
        #expect(results[0].value == SendableValue.string("result1"))
        #expect(results[1].value == SendableValue.int(42))
        #expect(results[2].value == SendableValue.bool(true))
    }

    @Test("All failing tools returns all failure results with continueOnError")
    func allFailingTools() async throws {
        let error1 = MockErrorTool(name: "fail1")
        let error2 = MockErrorTool(name: "fail2")
        let error3 = MockErrorTool(name: "fail3")

        let registry = try await createRegistry(tools: [error1, error2, error3])
        let executor = ParallelToolExecutor()
        let agent = ParallelTestMockAgent()

        let calls = [
            ToolCall(toolName: "fail1", arguments: [:]),
            ToolCall(toolName: "fail2", arguments: [:]),
            ToolCall(toolName: "fail3", arguments: [:])
        ]

        let results = try await executor.executeInParallel(
            calls,
            using: registry,
            agent: agent,
            context: nil,
            errorStrategy: .continueOnError
        )

        #expect(results.count == 3)
        #expect(results.allSatisfy { !$0.isSuccess })
        #expect(results.allSatisfy { $0.error != nil })
    }

    // MARK: - Same Tool Multiple Calls Tests

    @Test("executeInParallel measures duration through the Engine clock")
    func executeInParallelMeasuresDurationThroughEngineClock() async throws {
        let clock = ScriptedToolClock(readings: [UInt64(0), UInt64(25_000_000)])
        let tool = MockDelayTool(name: "instant", delay: .zero, resultValue: .string("ok"))
        let registry = try await createRegistry(tools: [tool])
        let executor = ParallelToolExecutor(engine: ToolExecutionEngine(clock: clock))
        let agent = ParallelTestMockAgent()

        let results = try await executor.executeInParallel(
            [ToolCall(toolName: "instant", arguments: [:])],
            using: registry,
            agent: agent,
            context: nil
        )

        #expect(results.count == 1)
        #expect(results[0].isSuccess == true)
        #expect(results[0].duration == Duration(swarmNanoseconds: UInt64(25_000_000)))
    }

    @Test("explicit externalMutation tools serialize in input order")
    func explicitExternalMutationToolsSerializeInInputOrder() async throws {
        let log = ToolPhaseLog()
        let semantics = ToolExecutionSemantics(sideEffectLevel: .externalMutation)
        let first = FunctionTool(
            name: "mutate_a",
            description: "First mutation",
            executionSemantics: semantics
        ) { _ in
            await log.record("start-a")
            await Task.yield()
            await log.record("end-a")
            return .string("a")
        }
        let second = FunctionTool(
            name: "mutate_b",
            description: "Second mutation",
            executionSemantics: semantics
        ) { _ in
            await log.record("start-b")
            await Task.yield()
            await log.record("end-b")
            return .string("b")
        }

        let registry = try await createRegistry(tools: [first, second])
        let executor = ParallelToolExecutor()
        let agent = ParallelTestMockAgent()

        let results = try await executor.executeInParallel(
            [
                ToolCall(toolName: "mutate_a", arguments: [:]),
                ToolCall(toolName: "mutate_b", arguments: [:])
            ],
            using: registry,
            agent: agent,
            context: nil
        )

        #expect(results.count == 2)
        #expect(results[0].toolName == "mutate_a")
        #expect(results[1].toolName == "mutate_b")
        #expect(results[0].isSuccess == true)
        #expect(results[1].isSuccess == true)
        let events = await log.snapshot()
        #expect(events == ["start-a", "end-a", "start-b", "end-b"])
    }

    @Test("mixed batch keeps consecutive parallel-eligible tools concurrent")
    func mixedBatchKeepsParallelEligibleToolsConcurrent() async throws {
        let log = ToolPhaseLog()
        let gate = ToolOverlapGate(expected: 2)
        let readSemantics = ToolExecutionSemantics(sideEffectLevel: .readOnly)
        let mutateSemantics = ToolExecutionSemantics(sideEffectLevel: .externalMutation)

        let readA = FunctionTool(
            name: "read_a",
            description: "Read A",
            executionSemantics: readSemantics
        ) { _ in
            await log.record("start-a")
            await gate.arrive()
            await log.record("end-a")
            return .string("a")
        }
        let readB = FunctionTool(
            name: "read_b",
            description: "Read B",
            executionSemantics: readSemantics
        ) { _ in
            await log.record("start-b")
            await gate.arrive()
            await log.record("end-b")
            return .string("b")
        }
        let mutate = FunctionTool(
            name: "mutate",
            description: "Mutate",
            executionSemantics: mutateSemantics
        ) { _ in
            await log.record("start-m")
            await log.record("end-m")
            return .string("m")
        }

        let registry = try await createRegistry(tools: [readA, readB, mutate])
        let executor = ParallelToolExecutor()
        let agent = ParallelTestMockAgent()

        let results = try await executor.executeInParallel(
            [
                ToolCall(toolName: "read_a", arguments: [:]),
                ToolCall(toolName: "read_b", arguments: [:]),
                ToolCall(toolName: "mutate", arguments: [:])
            ],
            using: registry,
            agent: agent,
            context: nil
        )

        #expect(results.map(\.toolName) == ["read_a", "read_b", "mutate"])
        #expect(results.allSatisfy { $0.isSuccess })

        let events = await log.snapshot()
        let startA = try #require(events.firstIndex(of: "start-a"))
        let startB = try #require(events.firstIndex(of: "start-b"))
        let endA = try #require(events.firstIndex(of: "end-a"))
        let endB = try #require(events.firstIndex(of: "end-b"))
        let startM = try #require(events.firstIndex(of: "start-m"))
        #expect(max(startA, startB) < min(endA, endB))
        #expect(max(endA, endB) < startM)
    }

    @Test("continueOnError preserves original error identity")
    func continueOnErrorPreservesOriginalErrorIdentity() async throws {
        let unique = UniqueToolError(code: 7)
        let successTool = MockDelayTool(name: "ok", delay: .zero, resultValue: .string("ok"))
        let errorTool = MockErrorTool(name: "boom", error: unique)
        let registry = try await createRegistry(tools: [successTool, errorTool])
        let executor = ParallelToolExecutor()
        let agent = ParallelTestMockAgent()

        let results = try await executor.executeInParallel(
            [
                ToolCall(toolName: "ok", arguments: [:]),
                ToolCall(toolName: "boom", arguments: [:])
            ],
            using: registry,
            agent: agent,
            context: nil,
            errorStrategy: .continueOnError
        )

        #expect(results.count == 2)
        #expect(results[0].isSuccess == true)
        #expect(results[1].isSuccess == false)
        let agentError = try #require(results[1].error as? AgentError)
        guard case let .toolFailure(toolName, _, cause) = agentError else {
            Issue.record("expected toolFailure, got \(agentError)")
            return
        }
        #expect(toolName == "boom")
        let captured = try #require(cause as? UniqueToolError)
        #expect(captured == unique)
    }

    @Test("continueOnError keeps AgentError thrown by the tool")
    func continueOnErrorKeepsAgentErrorThrownByTheTool() async throws {
        let original = AgentError.toolFailure(
            toolName: "boom",
            message: "specific-message",
            cause: nil
        )
        let errorTool = MockErrorTool(name: "boom", error: original)
        let registry = try await createRegistry(tools: [errorTool])
        let executor = ParallelToolExecutor()
        let agent = ParallelTestMockAgent()

        let results = try await executor.executeInParallel(
            [ToolCall(toolName: "boom", arguments: [:])],
            using: registry,
            agent: agent,
            context: nil,
            errorStrategy: .continueOnError
        )

        let agentError = try #require(results[0].error as? AgentError)
        #expect(agentError == original)
    }

    @Test("failFast throws the original tool error")
    func failFastThrowsTheOriginalToolError() async throws {
        let unique = UniqueToolError(code: 11)
        let errorTool = MockErrorTool(name: "boom", error: unique)
        let registry = try await createRegistry(tools: [errorTool])
        let executor = ParallelToolExecutor()
        let agent = ParallelTestMockAgent()

        do {
            _ = try await executor.executeInParallel(
                [ToolCall(toolName: "boom", arguments: [:])],
                using: registry,
                agent: agent,
                context: nil,
                errorStrategy: .failFast
            )
            Issue.record("expected toolFailure to be thrown")
        } catch let error as AgentError {
            guard case let .toolFailure(toolName, _, cause) = error else {
                Issue.record("expected toolFailure, got \(error)")
                return
            }
            #expect(toolName == "boom")
            let captured = try #require(cause as? UniqueToolError)
            #expect(captured == unique)
        } catch {
            Issue.record("expected AgentError.toolFailure, got \(error)")
        }
    }

    @Test("Same tool can be called multiple times")
    func sameToolMultipleCalls() async throws {
        let tool = MockDelayTool(name: "reusable", delay: .zero, resultValue: .string("result"))
        let registry = try await createRegistry(tools: [tool])
        let executor = ParallelToolExecutor()
        let agent = ParallelTestMockAgent()

        let calls = [
            ToolCall(toolName: "reusable", arguments: ["id": .int(1)]),
            ToolCall(toolName: "reusable", arguments: ["id": .int(2)]),
            ToolCall(toolName: "reusable", arguments: ["id": .int(3)])
        ]

        let results = try await executor.executeInParallel(
            calls,
            using: registry,
            agent: agent,
            context: nil
        )

        #expect(results.count == 3)
        #expect(results.allSatisfy { $0.toolName == "reusable" })
        #expect(results.allSatisfy { $0.isSuccess })

        // Verify arguments are preserved for each call
        #expect(results[0].arguments["id"] == .int(1))
        #expect(results[1].arguments["id"] == .int(2))
        #expect(results[2].arguments["id"] == .int(3))
    }

    // MARK: Private

    // MARK: - Test Helpers

    private func createRegistry(tools: [any AnyJSONTool]) async throws -> ToolRegistry {
        let registry = ToolRegistry()
        try await registry.register(tools)
        return registry
    }
}

// MARK: - ParallelToolExecutorCancellationTests

@Suite("ParallelToolExecutor Cancellation Tests")
struct ParallelToolExecutorCancellationTests {
    @Test("Parallel execution respects task cancellation")
    func parallelExecutionRespectsCancellation() async throws {
        // Create a slow tool that takes 2 seconds
        let slowTool = DelayedTestTool(name: "slow", delay: .seconds(2), result: .string("completed"))
        let registry = ToolRegistry()
        try await registry.register([slowTool])
        let executor = ParallelToolExecutor()
        let agent = ParallelTestMockAgent()

        let calls = [ToolCall(toolName: "slow", arguments: [:])]

        // Start execution in a cancellable task
        let task = Task {
            try await executor.executeInParallel(
                calls,
                using: registry,
                agent: agent,
                context: nil
            )
        }

        // Cancel after a short delay
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        // The task should throw CancellationError
        do {
            _ = try await task.value
            Issue.record("Expected CancellationError to be thrown")
        } catch is CancellationError {
            // Expected - cancellation was respected
        } catch {
            // Other errors are acceptable if they indicate cancellation
            #expect(error is CancellationError, "Expected CancellationError, got \(type(of: error))")
        }
    }

    @Test("Multiple parallel tools with early cancellation")
    func multipleToolsWithEarlyCancellation() async throws {
        // Create multiple slow tools
        let tool1 = DelayedTestTool(name: "slow1", delay: .seconds(1), result: .string("one"))
        let tool2 = DelayedTestTool(name: "slow2", delay: .seconds(1), result: .string("two"))
        let tool3 = DelayedTestTool(name: "slow3", delay: .seconds(1), result: .string("three"))
        let registry = ToolRegistry()
        try await registry.register([tool1, tool2, tool3])
        let executor = ParallelToolExecutor()
        let agent = ParallelTestMockAgent()

        let calls = [
            ToolCall(toolName: "slow1", arguments: [:]),
            ToolCall(toolName: "slow2", arguments: [:]),
            ToolCall(toolName: "slow3", arguments: [:])
        ]

        let task = Task {
            try await executor.executeInParallel(
                calls,
                using: registry,
                agent: agent,
                context: nil
            )
        }

        // Cancel almost immediately
        try await Task.sleep(for: .milliseconds(10))
        task.cancel()

        // Should complete quickly due to cancellation
        let startTime = ContinuousClock.now
        _ = try? await task.value
        let elapsed = ContinuousClock.now - startTime

        // If cancellation works, this should complete much faster than 1 second
        #expect(elapsed < .seconds(1), "Cancellation took too long: \(elapsed)")
    }
}
