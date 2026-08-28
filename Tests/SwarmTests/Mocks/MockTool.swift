// MockTool.swift
// SwarmTests
//
// Mock tool implementations for testing.

import Foundation
@testable import Swarm

// MARK: - MockTool

/// A configurable mock tool for testing.
///
/// Example:
/// ```swift
/// let tool = MockTool(
///     name: "weather",
///     result: .string("72°F and sunny")
/// )
/// let result = try await tool.execute(arguments: ["location": "NYC"])
/// ```
public struct MockTool: AnyJSONTool, Sendable {
    // MARK: Public

    public let name: String
    public let description: String
    public let parameters: [ToolParameter]
    public let inputGuardrails: [any ToolInputGuardrail]
    public let outputGuardrails: [any ToolOutputGuardrail]

    /// Creates a mock tool with a fixed result.
    /// - Parameters:
    ///   - name: The tool name.
    ///   - description: The tool description.
    ///   - parameters: The tool parameters.
    ///   - result: The fixed result to return.
    ///   - inputGuardrails: Input guardrails for the tool.
    ///   - outputGuardrails: Output guardrails for the tool.
    public init(
        name: String = "mock_tool",
        description: String = "A mock tool for testing",
        parameters: [ToolParameter] = [],
        result: SendableValue = .string("mock result"),
        inputGuardrails: [any ToolInputGuardrail] = [],
        outputGuardrails: [any ToolOutputGuardrail] = []
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
        resultHandler = { _ in result }
    }

    /// Creates a mock tool with a custom handler.
    /// - Parameters:
    ///   - name: The tool name.
    ///   - description: The tool description.
    ///   - parameters: The tool parameters.
    ///   - handler: The custom execution handler.
    ///   - inputGuardrails: Input guardrails for the tool.
    ///   - outputGuardrails: Output guardrails for the tool.
    public init(
        name: String,
        description: String = "A mock tool for testing",
        parameters: [ToolParameter] = [],
        inputGuardrails: [any ToolInputGuardrail] = [],
        outputGuardrails: [any ToolOutputGuardrail] = [],
        handler: @escaping @Sendable ([String: SendableValue]) async throws -> SendableValue
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
        resultHandler = handler
    }

    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        try await resultHandler(arguments)
    }

    // MARK: Private

    private let resultHandler: @Sendable ([String: SendableValue]) async throws -> SendableValue
}

// MARK: - FailingTool

/// A tool that throws an error when executed.
public struct FailingTool: AnyJSONTool, Sendable {
    public let name: String
    public let description: String
    public let parameters: [ToolParameter]
    public let inputGuardrails: [any ToolInputGuardrail]
    public let outputGuardrails: [any ToolOutputGuardrail]
    public let error: Error

    /// Creates a tool that always fails.
    /// - Parameters:
    ///   - name: The tool name.
    ///   - error: The error to throw.
    ///   - inputGuardrails: Input guardrails for the tool.
    ///   - outputGuardrails: Output guardrails for the tool.
    public init(
        name: String = "failing_tool",
        error: Error = AgentError.toolFailure(toolName: "failing_tool", message: "Intentional failure", cause: nil),
        inputGuardrails: [any ToolInputGuardrail] = [],
        outputGuardrails: [any ToolOutputGuardrail] = []
    ) {
        self.name = name
        description = "A tool that always fails"
        parameters = []
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
        self.error = error
    }

    public func execute(arguments _: [String: SendableValue]) async throws -> SendableValue {
        throw error
    }
}

// MARK: - SpyTool

/// A spy tool that records all invocations.
public actor SpyTool: AnyJSONTool {
    // MARK: Public

    nonisolated public let name: String
    nonisolated public let description: String
    nonisolated public let parameters: [ToolParameter]
    nonisolated public let inputGuardrails: [any ToolInputGuardrail]
    nonisolated public let outputGuardrails: [any ToolOutputGuardrail]

    /// The number of times the tool was called.
    public var callCount: Int {
        calls.count
    }

    /// The last call arguments, if any.
    public var lastCall: (arguments: [String: SendableValue], timestamp: Date)? {
        calls.last
    }

    /// All recorded calls.
    public var allCalls: [(arguments: [String: SendableValue], timestamp: Date)] {
        calls
    }

    /// Creates a spy tool.
    /// - Parameters:
    ///   - name: The tool name.
    ///   - result: The result to return.
    ///   - delay: Delay before returning.
    ///   - inputGuardrails: Input guardrails for the tool.
    ///   - outputGuardrails: Output guardrails for the tool.
    public init(
        name: String = "spy_tool",
        result: SendableValue = .string("spy result"),
        delay: Duration = .zero,
        inputGuardrails: [any ToolInputGuardrail] = [],
        outputGuardrails: [any ToolOutputGuardrail] = []
    ) {
        self.name = name
        description = "A spy tool that records calls"
        parameters = []
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
        self.result = result
        self.delay = delay
    }

    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        calls.append((arguments, Date()))

        if delay > .zero {
            try await Task.sleep(for: delay)
        }

        return result
    }

    /// Resets the recorded calls.
    public func reset() {
        calls = []
    }

    /// Returns true if the tool was called with the given argument.
    public func wasCalledWith(argument key: String, value: SendableValue) -> Bool {
        calls.contains { call in
            call.arguments[key] == value
        }
    }

    // MARK: Private

    private var calls: [(arguments: [String: SendableValue], timestamp: Date)] = []
    private let result: SendableValue
    private let delay: Duration
}

// MARK: - EchoTool

/// A tool that returns the arguments it received (echo).
public struct EchoTool: AnyJSONTool, Sendable {
    public let name = "echo"
    public let description = "Returns the arguments it received"
    public let parameters: [ToolParameter] = [
        ToolParameter(name: "message", description: "Message to echo", type: .string, isRequired: false)
    ]
    public let inputGuardrails: [any ToolInputGuardrail]
    public let outputGuardrails: [any ToolOutputGuardrail]

    public init(
        inputGuardrails: [any ToolInputGuardrail] = [],
        outputGuardrails: [any ToolOutputGuardrail] = []
    ) {
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
    }

    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        .dictionary(arguments)
    }
}
