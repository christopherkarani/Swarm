// AgentEventTests.swift
// SwarmTests
//
// Comprehensive tests for AgentEvent, ToolCall, and ToolResult types.

import Foundation
@testable import Swarm
import Testing

// MARK: - AgentEvent Tests

@Suite("AgentEvent Tests")
struct AgentEventTests {
    // MARK: - Lifecycle Events

    @Test("AgentEvent.started creation")
    func startedEventCreation() {
        let event = AgentEvent.lifecycle(.started(input: "What is 2+2?"))

        // Verify the event can be pattern-matched
        if case let .lifecycle(.started(input: input)) = event {
            #expect(input == "What is 2+2?")
        } else {
            Issue.record("Expected .lifecycle(.started) event")
        }
    }

    @Test("AgentEvent.completed creation")
    func completedEventCreation() {
        let result = AgentResult(
            output: "The answer is 4",
            iterationCount: 2,
            duration: .seconds(1)
        )

        let event = AgentEvent.lifecycle(.completed(result: result))

        // Verify the event can be pattern-matched
        if case let .lifecycle(.completed(result: capturedResult)) = event {
            #expect(capturedResult.output == "The answer is 4")
            #expect(capturedResult.iterationCount == 2)
        } else {
            Issue.record("Expected .lifecycle(.completed) event")
        }
    }

    @Test("AgentEvent.failed creation")
    func failedEventCreation() {
        let error = AgentError.toolNotFound(name: "calculator")
        let event = AgentEvent.lifecycle(.failed(error: error))

        // Verify the event can be pattern-matched
        if case let .lifecycle(.failed(error: capturedError)) = event {
            #expect(capturedError == error)
        } else {
            Issue.record("Expected .lifecycle(.failed) event")
        }
    }

    @Test("AgentEvent.cancelled creation")
    func cancelledEventCreation() {
        let event = AgentEvent.lifecycle(.cancelled)

        // Verify the event can be pattern-matched
        if case .lifecycle(.cancelled) = event {
            // Success
        } else {
            Issue.record("Expected .lifecycle(.cancelled) event")
        }
    }

    // MARK: - Thinking Events

    @Test("AgentEvent.thinking creation")
    func thinkingEventCreation() {
        let event = AgentEvent.output(.thinking(thought: "I need to calculate 2+2"))

        // Verify the event can be pattern-matched
        if case let .output(.thinking(thought: thought)) = event {
            #expect(thought == "I need to calculate 2+2")
        } else {
            Issue.record("Expected .output(.thinking) event")
        }
    }

    @Test("AgentEvent.thinkingPartial creation")
    func thinkingPartialEventCreation() {
        let event = AgentEvent.output(.thinkingPartial("I need to"))

        // Verify the event can be pattern-matched
        if case let .output(.thinkingPartial(partial)) = event {
            #expect(partial == "I need to")
        } else {
            Issue.record("Expected .output(.thinkingPartial) event")
        }
    }

    // MARK: - Tool Events

    @Test("AgentEvent.toolCallStarted creation")
    func toolCallStartedEventCreation() {
        let toolCall = ToolCall(
            toolName: "calculator",
            arguments: ["expression": .string("2+2")]
        )

        let event = AgentEvent.tool(.started(call: toolCall))

        // Verify the event can be pattern-matched
        if case let .tool(.started(call: call)) = event {
            #expect(call.toolName == "calculator")
            #expect(call.arguments["expression"] == .string("2+2"))
        } else {
            Issue.record("Expected .tool(.started) event")
        }
    }

    @Test("AgentEvent.toolCallCompleted creation")
    func toolCallCompletedEventCreation() {
        let toolCall = ToolCall(
            toolName: "calculator",
            arguments: ["expression": .string("2+2")]
        )

        let result = ToolResult.success(
            callId: toolCall.id,
            output: .int(4),
            duration: .milliseconds(100)
        )

        let event = AgentEvent.tool(.completed(call: toolCall, result: result))

        // Verify the event can be pattern-matched
        if case let .tool(.completed(call: call, result: capturedResult)) = event {
            #expect(call.toolName == "calculator")
            #expect(capturedResult.isSuccess == true)
            #expect(capturedResult.output == .int(4))
        } else {
            Issue.record("Expected .tool(.completed) event")
        }
    }

    @Test("AgentEvent.toolCallFailed creation")
    func toolCallFailedEventCreation() {
        let toolCall = ToolCall(
            toolName: "calculator",
            arguments: ["expression": .string("invalid")]
        )

        let error = AgentError.toolFailure(
            toolName: "calculator",
            message: "Invalid expression",
            cause: nil
        )

        let event = AgentEvent.tool(.failed(call: toolCall, error: error))

        // Verify the event can be pattern-matched
        if case let .tool(.failed(call: call, error: capturedError)) = event {
            #expect(call.toolName == "calculator")
            #expect(capturedError == error)
        } else {
            Issue.record("Expected .tool(.failed) event")
        }
    }

    // MARK: - Output Events

    @Test("AgentEvent.outputToken creation")
    func outputTokenEventCreation() {
        let event = AgentEvent.output(.token("Hello"))

        // Verify the event can be pattern-matched
        if case let .output(.token(token)) = event {
            #expect(token == "Hello")
        } else {
            Issue.record("Expected .output(.token) event")
        }
    }

    @Test("AgentEvent.outputChunk creation")
    func outputChunkEventCreation() {
        let event = AgentEvent.output(.chunk("Hello, world!"))

        // Verify the event can be pattern-matched
        if case let .output(.chunk(chunk)) = event {
            #expect(chunk == "Hello, world!")
        } else {
            Issue.record("Expected .output(.chunk) event")
        }
    }

    // MARK: - Iteration Events

    @Test("AgentEvent.iterationStarted creation")
    func iterationStartedEventCreation() {
        let event = AgentEvent.lifecycle(.iterationStarted(number: 1))

        // Verify the event can be pattern-matched
        if case let .lifecycle(.iterationStarted(number: number)) = event {
            #expect(number == 1)
        } else {
            Issue.record("Expected .lifecycle(.iterationStarted) event")
        }
    }

    @Test("AgentEvent.iterationCompleted creation")
    func iterationCompletedEventCreation() {
        let event = AgentEvent.lifecycle(.iterationCompleted(number: 5))

        // Verify the event can be pattern-matched
        if case let .lifecycle(.iterationCompleted(number: number)) = event {
            #expect(number == 5)
        } else {
            Issue.record("Expected .lifecycle(.iterationCompleted) event")
        }
    }

    // MARK: - All Event Cases

    @Test("All AgentEvent cases are Sendable")
    func allEventCasesAreSendable() {
        // This test verifies compilation - all events should conform to Sendable
        let events: [AgentEvent] = [
            .lifecycle(.started(input: "test")),
            .lifecycle(.completed(result: AgentResult(output: "done"))),
            .lifecycle(.failed(error: .cancelled)),
            .lifecycle(.cancelled),
            .output(.thinking(thought: "thinking")),
            .output(.thinkingPartial("think")),
            .tool(.started(call: ToolCall(toolName: "test"))),
            .tool(.completed(
                call: ToolCall(toolName: "test"),
                result: ToolResult.success(callId: UUID(), output: .null, duration: .zero)
            )),
            .tool(.failed(call: ToolCall(toolName: "test"), error: .cancelled)),
            .output(.token("hi")),
            .output(.chunk("hello")),
            .lifecycle(.iterationStarted(number: 1)),
            .lifecycle(.iterationCompleted(number: 1))
        ]

        #expect(events.count == 13)
    }
}
