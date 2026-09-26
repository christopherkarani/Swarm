// ToolRegistryTypedExecuteTests.swift
// SwarmTests
//
// Tests for the typed `ToolRegistry.execute(tool:input:)` overload.

import Foundation
@testable import Swarm
import Testing

// MARK: - Fixtures

private struct EchoInput: Codable, Sendable, Equatable {
    let text: String
}

private struct EchoOutput: Codable, Sendable, Equatable {
    let echoed: String
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        _count += 1
    }
}

private struct TypedEchoTool: Tool {
    typealias Input = EchoInput
    typealias Output = EchoOutput

    let name: String
    let description = "Echoes text with a prefix"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "text", description: "Text to echo", type: .string)
    ]
    let counter: CallCounter?

    init(name: String = "typed_echo", counter: CallCounter? = nil) {
        self.name = name
        self.counter = counter
    }

    func execute(_ input: Input) async throws -> Output {
        counter?.increment()
        return Output(echoed: "echo:\(input.text)")
    }
}

private struct GreetTool: Tool {
    struct Input: Codable, Sendable {
        let name: String
    }

    typealias Output = String

    let name = "typed_greet"
    let description = "Greets a person by name"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "name", description: "The person's name", type: .string)
    ]

    func execute(_ input: Input) async throws -> String {
        "Hello, \(input.name)!"
    }
}

private struct ScalarInputTool: Tool {
    typealias Input = String
    typealias Output = String

    let name = "scalar_input"
    let description = "Takes a scalar string input"
    let parameters: [ToolParameter] = []

    func execute(_ input: String) async throws -> String {
        input
    }
}

private struct MismatchedDynamicTool: AnyJSONTool {
    let name: String
    let description = "Returns an int regardless of schema"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "text", description: "Text", type: .string)
    ]

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        .int(1)
    }
}

private struct DisabledDynamicTool: AnyJSONTool {
    let name: String
    let description = "Always disabled"
    let parameters: [ToolParameter] = []
    let isEnabled = false

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        .string("never")
    }
}

private enum Mood: String, Codable, Sendable {
    case happy
    case calm
}

private struct MoodTool: Tool {
    struct Input: Codable, Sendable {
        let text: String
    }

    typealias Output = Mood

    let name = "typed_mood"
    let description = "Returns a mood for the text"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "text", description: "Text", type: .string)
    ]

    func execute(_ input: Input) async throws -> Mood {
        input.text.isEmpty ? .calm : .happy
    }
}

private struct OptionalEchoTool: Tool {
    typealias Input = EchoInput
    typealias Output = String?

    let name = "typed_optional_echo"
    let description = "Echoes text or returns nil for empty input"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "text", description: "Text to echo", type: .string)
    ]

    func execute(_ input: Input) async throws -> String? {
        input.text.isEmpty ? nil : "echo:\(input.text)"
    }
}

private struct FixedResultDynamicTool: AnyJSONTool {
    let name: String
    let description = "Returns a fixed result regardless of schema"
    let parameters: [ToolParameter]
    let result: SendableValue

    init(
        name: String,
        result: SendableValue,
        parameters: [ToolParameter] = [
            ToolParameter(name: "text", description: "Text", type: .string)
        ]
    ) {
        self.name = name
        self.result = result
        self.parameters = parameters
    }

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        result
    }
}

private struct GuardrailedEchoTool: Tool {
    typealias Input = EchoInput
    typealias Output = EchoOutput

    let name = "guardrailed_echo"
    let description = "Echo with configurable guardrails"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "text", description: "Text to echo", type: .string)
    ]
    let inputGuardrails: [any ToolInputGuardrail]
    let outputGuardrails: [any ToolOutputGuardrail]

    init(
        inputGuardrails: [any ToolInputGuardrail] = [],
        outputGuardrails: [any ToolOutputGuardrail] = []
    ) {
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
    }

    func execute(_ input: Input) async throws -> Output {
        Output(echoed: "echo:\(input.text)")
    }
}

// MARK: - Tests

@Suite("ToolRegistry typed execute")
struct ToolRegistryTypedExecuteTests {
    @Test("typed execute returns typed output equal to the untyped path")
    func typedExecuteMatchesUntypedPath() async throws {
        let counter = CallCounter()
        let registry = ToolRegistry()
        let tool = TypedEchoTool(counter: counter)
        try await registry.register(tool)

        let typed: EchoOutput = try await registry.execute(tool: tool, input: EchoInput(text: "hi"))
        #expect(typed == EchoOutput(echoed: "echo:hi"))
        #expect(counter.count == 1)

        let untyped = try await registry.execute(toolNamed: tool.name, arguments: ["text": .string("hi")])
        let decoded: EchoOutput = try untyped.decode()
        #expect(decoded == typed)
    }

    @Test("typed execute supports scalar outputs")
    func typedExecuteScalarOutput() async throws {
        let registry = ToolRegistry()
        let tool = GreetTool()
        try await registry.register(tool)

        let output: String = try await registry.execute(tool: tool, input: .init(name: "Ada"))
        #expect(output == "Hello, Ada!")
    }

    @Test("typed execute supports enum outputs")
    func typedExecuteEnumOutput() async throws {
        let registry = ToolRegistry()
        let tool = MoodTool()
        try await registry.register(tool)

        let output: Mood = try await registry.execute(tool: tool, input: .init(text: "hi"))
        #expect(output == .happy)
    }

    @Test("typed execute supports optional outputs")
    func typedExecuteOptionalOutput() async throws {
        let registry = ToolRegistry()
        let tool = OptionalEchoTool()
        try await registry.register(tool)

        let some: String? = try await registry.execute(tool: tool, input: EchoInput(text: "hi"))
        #expect(some == "echo:hi")

        let none: String? = try await registry.execute(tool: tool, input: EchoInput(text: ""))
        #expect(none == nil)
    }

    @Test("typed execute throws toolNotFound for an unregistered name")
    func typedExecuteUnregisteredThrowsToolNotFound() async throws {
        let registry = ToolRegistry()
        let tool = TypedEchoTool()
        do {
            let _: EchoOutput = try await registry.execute(tool: tool, input: EchoInput(text: "hi"))
            Issue.record("expected AgentError.toolNotFound")
        } catch let error as AgentError {
            guard case .toolNotFound(let name) = error else {
                Issue.record("expected toolNotFound, got \(error)")
                return
            }
            #expect(name == tool.name)
        }
    }

    @Test("typed execute throws toolNotFound for a disabled tool")
    func typedExecuteDisabledThrowsToolNotFound() async throws {
        let registry = ToolRegistry()
        try await registry.register(DisabledDynamicTool(name: "typed_echo"))
        let tool = TypedEchoTool()
        do {
            let _: EchoOutput = try await registry.execute(tool: tool, input: EchoInput(text: "hi"))
            Issue.record("expected AgentError.toolNotFound")
        } catch let error as AgentError {
            guard case .toolNotFound(let name) = error else {
                Issue.record("expected toolNotFound, got \(error)")
                return
            }
            #expect(name == tool.name)
        }
    }

    @Test("typed execute throws invalidToolArguments for scalar input")
    func typedExecuteScalarInputThrowsInvalidToolArguments() async throws {
        let registry = ToolRegistry()
        let tool = ScalarInputTool()
        try await registry.register(tool)
        do {
            let _: String = try await registry.execute(tool: tool, input: "x")
            Issue.record("expected AgentError.invalidToolArguments")
        } catch let error as AgentError {
            guard case .invalidToolArguments(let toolName, let reason) = error else {
                Issue.record("expected invalidToolArguments, got \(error)")
                return
            }
            #expect(toolName == tool.name)
            #expect(reason.contains("keyed object"))
            #expect(reason.contains("String"))
        }
    }

    @Test("typed execute throws toolFailure with cause on output mismatch")
    func typedExecuteOutputMismatchThrowsToolFailure() async throws {
        let registry = ToolRegistry()
        try await registry.register(MismatchedDynamicTool(name: "typed_echo"))
        let tool = TypedEchoTool()
        do {
            let _: EchoOutput = try await registry.execute(tool: tool, input: EchoInput(text: "hi"))
            Issue.record("expected AgentError.toolFailure")
        } catch let error as AgentError {
            guard case .toolFailure(let toolName, let message, let cause) = error else {
                Issue.record("expected toolFailure, got \(error)")
                return
            }
            #expect(toolName == tool.name)
            #expect((message ?? "").contains("EchoOutput"))
            #expect((message ?? "").contains(tool.name))
            #expect(cause != nil)
        }
    }

    @Test("typed execute throws toolFailure on scalar-to-scalar mismatch")
    func typedExecuteScalarMismatchThrowsToolFailure() async throws {
        let registry = ToolRegistry()
        try await registry.register(
            FixedResultDynamicTool(
                name: "typed_greet",
                result: .int(1),
                parameters: [ToolParameter(name: "name", description: "The person's name", type: .string)]
            )
        )
        let tool = GreetTool()
        do {
            let _: String = try await registry.execute(tool: tool, input: .init(name: "Ada"))
            Issue.record("expected AgentError.toolFailure")
        } catch let error as AgentError {
            guard case .toolFailure(let toolName, let message, let cause) = error else {
                Issue.record("expected toolFailure, got \(error)")
                return
            }
            #expect(toolName == tool.name)
            #expect((message ?? "").contains("String"))
            #expect(cause != nil)
        }
    }

    @Test("typed execute throws toolFailure on null result for non-optional output")
    func typedExecuteNullMismatchThrowsToolFailure() async throws {
        let registry = ToolRegistry()
        try await registry.register(FixedResultDynamicTool(name: "typed_echo", result: .null))
        let tool = TypedEchoTool()
        do {
            let _: EchoOutput = try await registry.execute(tool: tool, input: EchoInput(text: "hi"))
            Issue.record("expected AgentError.toolFailure")
        } catch let error as AgentError {
            guard case .toolFailure(let toolName, _, let cause) = error else {
                Issue.record("expected toolFailure, got \(error)")
                return
            }
            #expect(toolName == tool.name)
            #expect(cause != nil)
        }
    }

    @Test("typed execute runs both guardrail sets")
    func typedExecuteRunsGuardrails() async throws {
        let inputCounter = CallCounter()
        let outputCounter = CallCounter()
        let tool = GuardrailedEchoTool(
            inputGuardrails: [
                ClosureToolInputGuardrail(name: "recording_input") { _ in
                    inputCounter.increment()
                    return .passed()
                }
            ],
            outputGuardrails: [
                ClosureToolOutputGuardrail(name: "recording_output") { _, _ in
                    outputCounter.increment()
                    return .passed()
                }
            ]
        )
        let registry = ToolRegistry()
        try await registry.register(tool)

        let output: EchoOutput = try await registry.execute(tool: tool, input: EchoInput(text: "hi"))
        #expect(output == EchoOutput(echoed: "echo:hi"))
        #expect(inputCounter.count == 1)
        #expect(outputCounter.count == 1)
    }

    @Test("typed execute surfaces input tripwire exactly as the untyped path")
    func typedExecuteInputTripwireMatchesUntypedPath() async throws {
        let tool = GuardrailedEchoTool(
            inputGuardrails: [
                ClosureToolInputGuardrail(name: "blocking_input") { _ in
                    .tripwire(message: "blocked input")
                }
            ]
        )
        let registry = ToolRegistry()
        try await registry.register(tool)

        do {
            let _: EchoOutput = try await registry.execute(tool: tool, input: EchoInput(text: "hi"))
            Issue.record("expected GuardrailError on typed path")
        } catch {
            #expect(error is GuardrailError)
        }
        do {
            _ = try await registry.execute(toolNamed: tool.name, arguments: ["text": .string("hi")])
            Issue.record("expected GuardrailError on untyped path")
        } catch {
            #expect(error is GuardrailError)
        }
    }

    @Test("typed execute surfaces output tripwire exactly as the untyped path")
    func typedExecuteOutputTripwireMatchesUntypedPath() async throws {
        let tool = GuardrailedEchoTool(
            outputGuardrails: [
                ClosureToolOutputGuardrail(name: "blocking_output") { _, _ in
                    .tripwire(message: "blocked output")
                }
            ]
        )
        let registry = ToolRegistry()
        try await registry.register(tool)

        do {
            let _: EchoOutput = try await registry.execute(tool: tool, input: EchoInput(text: "hi"))
            Issue.record("expected GuardrailError on typed path")
        } catch {
            #expect(error is GuardrailError)
        }
        do {
            _ = try await registry.execute(toolNamed: tool.name, arguments: ["text": .string("hi")])
            Issue.record("expected GuardrailError on untyped path")
        } catch {
            #expect(error is GuardrailError)
        }
    }
}
