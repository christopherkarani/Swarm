// ParallelToolExecutorTests+Mocks.swift
// SwarmTests
//
// Mock types for ParallelToolExecutor tests.

import Foundation
@testable import Swarm

// MARK: - MockDelayTool

/// A mock tool with configurable delay for testing parallel execution order.
struct MockDelayTool: AnyJSONTool, Sendable {
    let name: String
    let delay: Duration
    let resultValue: SendableValue

    var description: String { "Mock tool with delay of \(delay)" }
    var parameters: [ToolParameter] { [] }
    var inputGuardrails: [any ToolInputGuardrail] { [] }
    var outputGuardrails: [any ToolOutputGuardrail] { [] }

    func execute(arguments _: [String: SendableValue]) async throws -> SendableValue {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        return resultValue
    }
}

// MARK: - MockErrorTool

/// A mock tool that always throws an error.
struct MockErrorTool: AnyJSONTool, Sendable {
    let name: String
    let error: Error

    var description: String { "Mock tool that throws an error" }
    var parameters: [ToolParameter] { [] }
    var inputGuardrails: [any ToolInputGuardrail] { [] }
    var outputGuardrails: [any ToolOutputGuardrail] { [] }

    init(name: String, error: Error = AgentError.toolFailure(toolName: "mock_error", message: "Intentional failure", cause: nil)) {
        self.name = name
        self.error = error
    }

    func execute(arguments _: [String: SendableValue]) async throws -> SendableValue {
        throw error
    }
}

// MARK: - ParallelTestMockAgent

/// A minimal mock agent for testing parallel tool execution.
struct ParallelTestMockAgent: AgentRuntime {
    let tools: [any AnyJSONTool]
    let instructions: String
    let configuration: AgentConfiguration
    let memory: (any Memory)?
    let inferenceProvider: (any InferenceProvider)?
    let tracer: (any Tracer)?
    let inputGuardrails: [any InputGuardrail]
    let outputGuardrails: [any OutputGuardrail]
    let handoffs: [AnyHandoffConfiguration]

    init(
        tools: [any AnyJSONTool] = [],
        instructions: String = "Test agent",
        configuration: AgentConfiguration = .default,
        memory: (any Memory)? = nil,
        inferenceProvider: (any InferenceProvider)? = nil,
        tracer: (any Tracer)? = nil,
        inputGuardrails: [any InputGuardrail] = [],
        outputGuardrails: [any OutputGuardrail] = [],
        handoffs: [AnyHandoffConfiguration] = []
    ) {
        self.tools = tools
        self.instructions = instructions
        self.configuration = configuration
        self.memory = memory
        self.inferenceProvider = inferenceProvider
        self.tracer = tracer
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
        self.handoffs = handoffs
    }

    func run(_: String, session _: (any Session)?, observer _: (any AgentObserver)?) async throws -> AgentResult {
        AgentResult(output: "Mock result", toolCalls: [], toolResults: [], iterationCount: 1, duration: .zero)
    }

    nonisolated func stream(_: String, session _: (any Session)?, observer _: (any AgentObserver)?) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func cancel() async {}
}

// MARK: - DelayedTestTool

/// A test tool that delays for a specified duration before returning
struct DelayedTestTool: AnyJSONTool, Sendable {
    let name: String
    let delay: Duration
    let result: SendableValue

    var description: String { "A tool that delays for \(delay)" }
    var parameters: [ToolParameter] { [] }

    func execute(arguments _: [String: SendableValue]) async throws -> SendableValue {
        try await Task.sleep(for: delay)
        return result
    }
}

// MARK: - ToolExecutionCounter

actor ToolExecutionCounter {
    private var count: Int = 0

    func increment() {
        count += 1
    }

    func snapshot() -> Int {
        count
    }
}

// MARK: - CountingTool

struct CountingTool: AnyJSONTool, Sendable {
    let name: String
    let counter: ToolExecutionCounter

    var description: String { "Tool that increments a counter" }
    var parameters: [ToolParameter] { [] }

    func execute(arguments _: [String: SendableValue]) async throws -> SendableValue {
        await counter.increment()
        return .string("ok")
    }
}

// MARK: - DisabledTestTool

struct DisabledTestTool: AnyJSONTool, Sendable {
    let name: String

    var description: String { "Disabled tool" }
    var parameters: [ToolParameter] { [] }
    var isEnabled: Bool { false }

    func execute(arguments _: [String: SendableValue]) async throws -> SendableValue {
        .string("unused")
    }
}
