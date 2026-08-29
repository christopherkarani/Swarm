// ToolExecutionEngineTests.swift
// SwarmTests
//
// Clock injection and default-preserving Engine behavior.

import Foundation
@testable import Swarm
import Testing

@Suite("ToolExecutionSemantics Engine")
struct ToolExecutionSemanticsEngineTests {
    @Test("injected clock supplies success duration")
    func injectedClockSuppliesSuccessDuration() async throws {
        let clock = ScriptedToolClock(readings: [UInt64(1_000), UInt64(1_042)])
        let engine = ToolExecutionEngine(clock: clock)
        let registry = ToolRegistry()
        try await registry.register(MockDelayTool(name: "echo", delay: .zero, resultValue: .string("ok")))

        let outcome = try await engine.execute(
            toolName: "echo",
            arguments: [:],
            registry: registry,
            agent: ParallelTestMockAgent(),
            context: nil,
            resultBuilder: AgentResult.Builder(),
            observer: nil,
            tracing: nil,
            stopOnToolError: false
        )

        #expect(outcome.result.isSuccess == true)
        #expect(outcome.result.output == .string("ok"))
        #expect(outcome.result.duration == Duration(swarmNanoseconds: UInt64(42)))
    }

    @Test("injected clock supplies failure duration")
    func injectedClockSuppliesFailureDuration() async throws {
        let clock = ScriptedToolClock(readings: [UInt64(10), UInt64(17)])
        let engine = ToolExecutionEngine(clock: clock)
        let registry = ToolRegistry()
        try await registry.register(MockErrorTool(name: "boom"))

        let outcome = try await engine.execute(
            toolName: "boom",
            arguments: [:],
            registry: registry,
            agent: ParallelTestMockAgent(),
            context: nil,
            resultBuilder: AgentResult.Builder(),
            observer: nil,
            tracing: nil,
            stopOnToolError: false
        )

        #expect(outcome.result.isSuccess == false)
        #expect(outcome.result.duration == Duration(swarmNanoseconds: UInt64(7)))
    }

    @Test("automatic semantics do not add an approval throw")
    func automaticSemanticsDoNotAddAnApprovalThrow() async throws {
        let engine = ToolExecutionEngine()
        let registry = ToolRegistry()
        try await registry.register(
            FunctionTool(
                name: "echo",
                description: "Echo",
                executionSemantics: .automatic
            ) { _ in .string("ok") }
        )

        let outcome = try await engine.execute(
            toolName: "echo",
            arguments: [:],
            registry: registry,
            agent: ParallelTestMockAgent(),
            context: nil,
            resultBuilder: AgentResult.Builder(),
            observer: nil,
            tracing: nil,
            stopOnToolError: false
        )

        #expect(outcome.result.isSuccess == true)
    }

    @Test("always approval still executes on the Engine host path")
    func alwaysApprovalStillExecutesOnTheEngineHostPath() async throws {
        let engine = ToolExecutionEngine()
        let registry = ToolRegistry()
        try await registry.register(
            FunctionTool(
                name: "gated",
                description: "Gated",
                executionSemantics: ToolExecutionSemantics(approvalRequirement: .always)
            ) { _ in .string("ran") }
        )

        let outcome = try await engine.execute(
            toolName: "gated",
            arguments: [:],
            registry: registry,
            agent: ParallelTestMockAgent(),
            context: nil,
            resultBuilder: AgentResult.Builder(),
            observer: nil,
            tracing: nil,
            stopOnToolError: false
        )

        #expect(outcome.result.isSuccess == true)
        #expect(outcome.result.output == .string("ran"))
    }

    @Test("maps ToolResult success onto ToolExecutionResult")
    func mapsToolResultSuccessOntoToolExecutionResult() {
        let call = ToolCall(toolName: "echo", arguments: ["x": .int(1)])
        let toolResult = ToolResult.success(
            callId: call.id,
            output: .string("ok"),
            duration: .milliseconds(3)
        )

        let mapped = ToolExecutionResult.from(call: call, result: toolResult)

        #expect(mapped.isSuccess == true)
        #expect(mapped.toolName == "echo")
        #expect(mapped.value == .string("ok"))
        #expect(mapped.duration == .milliseconds(3))
        #expect(mapped.arguments["x"] == .int(1))
    }

    @Test("maps ToolResult failure onto ToolExecutionResult")
    func mapsToolResultFailureOntoToolExecutionResult() {
        let call = ToolCall(toolName: "boom", arguments: [:])
        let toolResult = ToolResult.failure(
            callId: call.id,
            error: "nope",
            duration: .milliseconds(2)
        )

        let mapped = ToolExecutionResult.from(call: call, result: toolResult)

        #expect(mapped.isSuccess == false)
        #expect(mapped.toolName == "boom")
        #expect(mapped.duration == .milliseconds(2))
        if let agentError = mapped.error as? AgentError,
           case let .toolFailure(toolName, message, _) = agentError {
            #expect(toolName == "boom")
            #expect(message == "nope")
        } else {
            Issue.record("expected toolFailure, got \(String(describing: mapped.error))")
        }
    }
}
