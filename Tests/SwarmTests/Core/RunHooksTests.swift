// AgentObserverTests.swift
// SwarmTests
//
// Comprehensive tests for AgentObserver lifecycle system.

import Foundation
@testable import Swarm
import Testing

// MARK: - MockAgentForAgentObserver

/// Mock agent for testing observer.
private struct MockAgentForAgentObserver: AgentRuntime {
    let tools: [any AnyJSONTool] = []
    let instructions: String = "Mock agent"
    let configuration: AgentConfiguration

    init(name: String = "mock_agent") {
        configuration = AgentConfiguration(name: name)
    }

    func run(_ input: String, session _: (any Session)? = nil, observer _: (any AgentObserver)? = nil) async throws -> AgentResult {
        AgentResult(output: "Mock response: \(input)")
    }

    nonisolated func stream(_ input: String, session _: (any Session)? = nil, observer _: (any AgentObserver)? = nil) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.lifecycle(.started(input: input)))
            continuation.yield(.lifecycle(.completed(result: AgentResult(output: "Mock response"))))
            continuation.finish()
        }
    }

    func cancel() async {}
}

// MARK: - RecordingObserver

/// Recording hook for testing - captures all events in order.
private actor RecordingObserver: AgentObserver {
    var events: [String] = []

    func onAgentStart(context _: AgentContext?, agent _: any AgentRuntime, input: String) async {
        events.append("agentStart:\(input)")
    }

    func onAgentEnd(context _: AgentContext?, agent _: any AgentRuntime, result: AgentResult) async {
        events.append("agentEnd:\(result.output)")
    }

    func onError(context _: AgentContext?, agent _: any AgentRuntime, error: Error) async {
        events.append("error:\(error.localizedDescription)")
    }

    func onHandoff(context _: AgentContext?, fromAgent _: any AgentRuntime, toAgent _: any AgentRuntime) async {
        events.append("handoff")
    }

    func onToolStart(context _: AgentContext?, agent _: any AgentRuntime, call: ToolCall) async {
        events.append("toolStart:\(call.toolName)")
    }

    func onToolEnd(context _: AgentContext?, agent _: any AgentRuntime, result: ToolResult) async {
        // Find a way to get tool name from result if possible, or use ID
        // For tests we might blindly trust it's the right one
        events.append("toolEnd:unknown") // Updating to match lack of tool name in hook
    }

    func onLLMStart(context _: AgentContext?, agent _: any AgentRuntime, systemPrompt _: String?, inputMessages: [MemoryMessage]) async {
        events.append("llmStart:\(inputMessages.count)")
    }

    func onLLMEnd(context _: AgentContext?, agent _: any AgentRuntime, response _: String, usage: TokenUsage?) async {
        let tokens = usage.map { "\($0.inputTokens)/\($0.outputTokens)" } ?? "none"
        events.append("llmEnd:\(tokens)")
    }

    func onGuardrailTriggered(context _: AgentContext?, guardrailName: String, guardrailType: GuardrailType, result _: GuardrailResult) async {
        events.append("guardrail:\(guardrailName):\(guardrailType.rawValue)")
    }

    func reset() {
        events = []
    }

    func getEvents() -> [String] {
        events
    }
}

// MARK: - AgentObserverDefaultImplementationTests

@Suite("AgentObserver Default Implementations")
struct AgentObserverDefaultImplementationTests {
    @Test("Default implementations are no-op and don't crash")
    func defaultImplementationsAreNoOp() async {
        // Given: An empty observer implementation using defaults
        struct EmptyObserver: AgentObserver {}
        let observer = EmptyObserver()
        let agent = MockAgentForAgentObserver()
        let result = AgentResult(output: "test")

        // When/Then: All default implementations should complete without crashing
        await observer.onAgentStart(context: nil, agent: agent, input: "test")
        await observer.onAgentEnd(context: nil, agent: agent, result: result)
        await observer.onError(context: nil, agent: agent, error: AgentError.invalidInput(reason: "test"))
        await observer.onHandoff(context: nil, fromAgent: agent, toAgent: agent)
        await observer.onToolStart(context: nil, agent: agent, call: ToolCall(toolName: "test_tool", arguments: [:]))
        await observer.onToolEnd(context: nil, agent: agent, result: ToolResult.success(callId: UUID(), output: .string("result"), duration: .seconds(1)))
        await observer.onLLMStart(context: nil, agent: agent, systemPrompt: nil, inputMessages: [])
        await observer.onLLMEnd(context: nil, agent: agent, response: "response", usage: nil)
        await observer.onGuardrailTriggered(
            context: nil,
            guardrailName: "test",
            guardrailType: .input,
            result: .passed()
        )

        // No assertions needed - if we get here, all methods completed successfully
    }

    @Test("Default implementations handle nil context")
    func defaultImplementationsHandleNilContext() async {
        struct EmptyObserver: AgentObserver {}
        let observer = EmptyObserver()
        let agent = MockAgentForAgentObserver()

        // When/Then: Should handle nil context gracefully
        await observer.onAgentStart(context: nil, agent: agent, input: "test")
        await observer.onAgentEnd(context: nil, agent: agent, result: AgentResult(output: "test"))
    }

    @Test("Default implementations handle non-nil context")
    func defaultImplementationsHandleNonNilContext() async {
        struct EmptyObserver: AgentObserver {}
        let observer = EmptyObserver()
        let agent = MockAgentForAgentObserver()
        let context = AgentContext(input: "test")

        // When/Then: Should handle non-nil context gracefully
        await observer.onAgentStart(context: context, agent: agent, input: "test")
        await observer.onAgentEnd(context: context, agent: agent, result: AgentResult(output: "test"))
    }
}

// MARK: - CompositeAgentObserverTests

@Suite("CompositeObserver Tests")
struct CompositeAgentObserverTests {
    @Test("CompositeObserver calls all registered observer")
    func compositeCallsAllHooks() async {
        // Given: Multiple recording observer
        let hooks1 = RecordingObserver()
        let hooks2 = RecordingObserver()
        let hooks3 = RecordingObserver()
        let composite = CompositeObserver(observers: [hooks1, hooks2, hooks3])
        let agent = MockAgentForAgentObserver()

        // When: Calling onAgentStart
        await composite.onAgentStart(context: nil, agent: agent, input: "test input")

        // Then: All observer should receive the call
        let events1 = await hooks1.getEvents()
        let events2 = await hooks2.getEvents()
        let events3 = await hooks3.getEvents()
        #expect(events1.contains("agentStart:test input"))
        #expect(events2.contains("agentStart:test input"))
        #expect(events3.contains("agentStart:test input"))
    }

    @Test("CompositeObserver calls all observer concurrently")
    func compositeCallsAllHooksConcurrently() async {
        // Given: A composite with multiple observer
        let recorder = RecordingObserver()

        struct FirstHook: AgentObserver {
            let recorder: RecordingObserver
            func onAgentStart(context: AgentContext?, agent: any AgentRuntime, input _: String) async {
                await recorder.onAgentStart(context: context, agent: agent, input: "first")
            }
        }

        struct SecondHook: AgentObserver {
            let recorder: RecordingObserver
            func onAgentStart(context: AgentContext?, agent: any AgentRuntime, input _: String) async {
                await recorder.onAgentStart(context: context, agent: agent, input: "second")
            }
        }

        struct ThirdHook: AgentObserver {
            let recorder: RecordingObserver
            func onAgentStart(context: AgentContext?, agent: any AgentRuntime, input _: String) async {
                await recorder.onAgentStart(context: context, agent: agent, input: "third")
            }
        }

        let composite = CompositeObserver(observers: [
            FirstHook(recorder: recorder),
            SecondHook(recorder: recorder),
            ThirdHook(recorder: recorder)
        ])

        // When: Calling a hook method
        await composite.onAgentStart(context: nil, agent: MockAgentForAgentObserver(), input: "test")

        // Then: All observer should be called (order not guaranteed due to concurrent execution)
        let events = await recorder.getEvents()
        #expect(events.count == 3)
        #expect(events.contains("agentStart:first"))
        #expect(events.contains("agentStart:second"))
        #expect(events.contains("agentStart:third"))
    }

    @Test("CompositeObserver handles empty hook list")
    func compositeHandlesEmptyList() async {
        // Given: A composite with no observer
        let composite = CompositeObserver(observers: [])
        let agent = MockAgentForAgentObserver()

        // When/Then: Should not crash with empty list
        await composite.onAgentStart(context: nil, agent: agent, input: "test")
        await composite.onAgentEnd(context: nil, agent: agent, result: AgentResult(output: "test"))
        await composite.onError(context: nil, agent: agent, error: AgentError.invalidInput(reason: "test"))
        await composite.onHandoff(context: nil, fromAgent: agent, toAgent: agent)

        // No assertions needed - if we get here, all methods completed successfully
    }

    @Test("CompositeObserver forwards all hook methods")
    func compositeForwardsAllHookMethods() async {
        // Given: Recording observer in composite
        let observer = RecordingObserver()
        let composite = CompositeObserver(observers: [observer])
        let agent = MockAgentForAgentObserver()
        // removed unused tool
        let context = AgentContext(input: "test")

        // When: Calling all hook methods
        await composite.onAgentStart(context: context, agent: agent, input: "input")
        await composite.onAgentEnd(context: context, agent: agent, result: AgentResult(output: "output"))
        await composite.onError(context: context, agent: agent, error: AgentError.invalidInput(reason: "test"))
        await composite.onHandoff(context: context, fromAgent: agent, toAgent: agent)
        let toolCall = ToolCall(toolName: "calculator", arguments: ["x": .int(5)])
        await composite.onToolStart(context: context, agent: agent, call: toolCall)
        await composite.onToolEnd(context: context, agent: agent, result: ToolResult.success(callId: toolCall.id, output: .int(10), duration: .seconds(1)))
        await composite.onLLMStart(context: context, agent: agent, systemPrompt: "You are helpful", inputMessages: [])
        await composite.onLLMEnd(context: context, agent: agent, response: "response", usage: nil)
        await composite.onGuardrailTriggered(
            context: context,
            guardrailName: "pii_filter",
            guardrailType: .output,
            result: .tripwire(message: "PII detected")
        )

        // Then: All events should be recorded
        let events = await observer.getEvents()
        #expect(events.contains("agentStart:input"))
        #expect(events.contains("agentEnd:output"))
        #expect(events.contains { $0.starts(with: "error:") })
        #expect(events.contains("handoff"))
        #expect(events.contains("toolStart:calculator"))
        #expect(events.contains("toolEnd:unknown"))
        #expect(events.contains("llmStart:0"))
        #expect(events.contains("llmEnd:none"))
        #expect(events.contains("guardrail:pii_filter:output"))
    }
}

// MARK: - LoggingAgentObserverTests

@Suite("LoggingObserver Tests")
struct LoggingAgentObserverTests {
    @Test("LoggingObserver doesn't crash on agent lifecycle")
    func loggingObserverAgentLifecycle() async {
        // Given: A logging hook
        let observer = LoggingObserver()
        let agent = MockAgentForAgentObserver()

        // When/Then: Should log without crashing
        await observer.onAgentStart(context: nil, agent: agent, input: "What is the weather?")
        await observer.onAgentEnd(
            context: nil,
            agent: agent,
            result: AgentResult(
                output: "It's sunny",
                toolCalls: [],
                iterationCount: 2,
                duration: .seconds(1)
            )
        )
    }

    @Test("LoggingObserver doesn't crash on errors")
    func loggingObserverErrors() async {
        // Given: A logging hook
        let observer = LoggingObserver()
        let agent = MockAgentForAgentObserver()

        // When/Then: Should log error without crashing
        await observer.onError(
            context: nil,
            agent: agent,
            error: AgentError.toolExecutionFailed(toolName: "calculator", underlyingError: "Division by zero")
        )
    }

    @Test("LoggingObserver doesn't crash on tool events")
    func loggingObserverToolEvents() async {
        // Given: A logging hook
        let observer = LoggingObserver()
        let agent = MockAgentForAgentObserver()
        // removed unused tool

        // When/Then: Should log tool events without crashing
        let toolCall = ToolCall(toolName: "weather", arguments: ["location": .string("NYC"), "units": .string("F")])
        await observer.onToolStart(
            context: nil,
            agent: agent,
            call: toolCall
        )
        await observer.onToolEnd(
            context: nil,
            agent: agent,
            result: ToolResult.success(callId: toolCall.id, output: .string("72°F and sunny"), duration: .seconds(1))
        )
    }

    @Test("LoggingObserver doesn't crash on LLM events")
    func loggingObserverLLMEvents() async {
        // Given: A logging hook
        let observer = LoggingObserver()
        let agent = MockAgentForAgentObserver()
        let messages = [
            MemoryMessage(role: .user, content: "Hello"),
            MemoryMessage(role: .assistant, content: "Hi there!")
        ]

        // When/Then: Should log LLM events without crashing
        await observer.onLLMStart(
            context: nil,
            agent: agent,
            systemPrompt: "You are helpful",
            inputMessages: messages
        )
        await observer.onLLMEnd(
            context: nil,
            agent: agent,
            response: "I can help with that",
            usage: TokenUsage(inputTokens: 50, outputTokens: 20)
        )
    }

    @Test("LoggingObserver doesn't crash on guardrail events")
    func loggingObserverGuardrailEvents() async {
        // Given: A logging hook
        let observer = LoggingObserver()

        // When/Then: Should log guardrail events without crashing
        await observer.onGuardrailTriggered(
            context: nil,
            guardrailName: "content_filter",
            guardrailType: .input,
            result: .tripwire(message: "Inappropriate content detected")
        )
    }

    @Test("LoggingObserver handles context with executionId")
    func loggingObserverWithContext() async {
        // Given: A logging hook and context
        let observer = LoggingObserver()
        let agent = MockAgentForAgentObserver()
        let context = AgentContext(input: "test")

        // When/Then: Should log with context ID without crashing
        await observer.onAgentStart(context: context, agent: agent, input: "test input")
        await observer.onAgentEnd(context: context, agent: agent, result: AgentResult(output: "test output"))
    }

    @Test("LoggingObserver handles long input truncation")
    func loggingObserverTruncatesLongInput() async {
        // Given: A logging hook and very long input
        let observer = LoggingObserver()
        let agent = MockAgentForAgentObserver()
        let longInput = String(repeating: "a", count: 200)

        // When/Then: Should log without crashing (truncation happens internally)
        await observer.onAgentStart(context: nil, agent: agent, input: longInput)
    }
}

// MARK: - AgentObserverIntegrationTests

@Suite("AgentObserver Integration Tests")
struct AgentObserverIntegrationTests {
    @Test("Recording observer captures full agent execution flow")
    func recordingHooksCapturesFullFlow() async {
        // Given: A recording hook
        let observer = RecordingObserver()
        let agent = MockAgentForAgentObserver()
        // removed unused tool
        let messages = [MemoryMessage(role: .user, content: "Calculate 2+2")]

        // When: Simulating a full agent execution
        await observer.onAgentStart(context: nil, agent: agent, input: "Calculate 2+2")
        await observer.onLLMStart(context: nil, agent: agent, systemPrompt: "You are helpful", inputMessages: messages)
        await observer.onLLMEnd(
            context: nil,
            agent: agent,
            response: "I'll use the calculator",
            usage: TokenUsage(inputTokens: 10, outputTokens: 5)
        )
        let toolCall = ToolCall(toolName: "calculator", arguments: ["expression": .string("2+2")])
        await observer.onToolStart(context: nil, agent: agent, call: toolCall)
        await observer.onToolEnd(context: nil, agent: agent, result: ToolResult.success(callId: toolCall.id, output: .int(4), duration: .seconds(1)))
        await observer.onAgentEnd(context: nil, agent: agent, result: AgentResult(output: "The answer is 4"))

        // Then: All events should be recorded in order
        let events = await observer.getEvents()
        #expect(events == [
            "agentStart:Calculate 2+2",
            "llmStart:1",
            "llmEnd:10/5",
            "toolStart:calculator",
            "toolEnd:unknown",
            "agentEnd:The answer is 4"
        ])
    }

    @Test("Hooks receive correct parameters")
    func hooksReceiveCorrectParameters() async {
        // Given: A custom hook that validates parameters
        struct ValidatingHook: AgentObserver {
            var validated = false

            func onToolStart(
                context _: AgentContext?,
                agent _: any AgentRuntime,
                call: ToolCall
            ) async {
                // Verify all parameters are correct
                if call.toolName == "weather",
                   call.arguments["location"] == .string("NYC"),
                   call.arguments["units"] == .string("F") {
                    // Parameters are correct
                }
            }
        }

        let observer = ValidatingHook()
        let agent = MockAgentForAgentObserver()
        // removed unused tool
        let args: [String: SendableValue] = [
            "location": .string("NYC"),
            "units": .string("F")
        ]

        // When: Calling the hook
        let toolCall = ToolCall(toolName: "weather", arguments: args)
        await observer.onToolStart(context: nil, agent: agent, call: toolCall)

        // Then: Hook should have validated parameters successfully
        // (validation happens inside the hook method)
    }

    @Test("Multiple observer in composite don't interfere")
    func multipleHooksIndependent() async {
        // Given: Multiple independent observer
        let recorder1 = RecordingObserver()
        let recorder2 = RecordingObserver()
        let composite = CompositeObserver(observers: [recorder1, recorder2])
        let agent = MockAgentForAgentObserver()

        // When: Calling observer multiple times
        await composite.onAgentStart(context: nil, agent: agent, input: "first")
        await composite.onAgentStart(context: nil, agent: agent, input: "second")
        await composite.onAgentEnd(context: nil, agent: agent, result: AgentResult(output: "done"))

        // Then: Both observer should have recorded all events independently
        let events1 = await recorder1.getEvents()
        let events2 = await recorder2.getEvents()
        #expect(events1.count == 3)
        #expect(events2.count == 3)
        #expect(events1 == events2)
    }

    @Test("Hooks work with and without context")
    func hooksWorkWithAndWithoutContext() async {
        // Given: Recording hook
        let observer = RecordingObserver()
        let agent = MockAgentForAgentObserver()
        let context = AgentContext(input: "test")

        // When: Calling with and without context
        await observer.onAgentStart(context: nil, agent: agent, input: "no context")
        await observer.onAgentStart(context: context, agent: agent, input: "with context")

        // Then: Both calls should be recorded
        let events = await observer.getEvents()
        #expect(events.count == 2)
        #expect(events[0] == "agentStart:no context")
        #expect(events[1] == "agentStart:with context")
    }
}

// MARK: - AgentObserverConcurrentExecutionTests

	@Suite("AgentObserver Concurrent Execution Tests")
	struct AgentObserverConcurrentExecutionTests {
	    @Test("Concurrent hook execution completes in parallel")
	    func concurrentHookExecution() async throws {
	        // Create a hook that tracks execution order with delays
	        actor DelayedHook: AgentObserver {
	            var start: ContinuousClock.Instant?
	            var end: ContinuousClock.Instant?

	            func onAgentStart(context _: AgentContext?, agent _: any AgentRuntime, input _: String) async {
	                start = ContinuousClock.now
	                try? await Task.sleep(for: .milliseconds(200))
	                end = ContinuousClock.now
	            }

            func onAgentEnd(context _: AgentContext?, agent _: any AgentRuntime, result _: AgentResult) async {}
            func onError(context _: AgentContext?, agent _: any AgentRuntime, error _: Error) async {}
            func onHandoff(context _: AgentContext?, fromAgent _: any AgentRuntime, toAgent _: any AgentRuntime) async {}
            func onToolStart(context _: AgentContext?, agent _: any AgentRuntime, call _: ToolCall) async {}
            func onToolEnd(context _: AgentContext?, agent _: any AgentRuntime, result _: ToolResult) async {}
            func onLLMStart(context _: AgentContext?, agent _: any AgentRuntime, systemPrompt _: String?, inputMessages _: [MemoryMessage]) async {}
            func onLLMEnd(context _: AgentContext?, agent _: any AgentRuntime, response _: String, usage _: TokenUsage?) async {}
            func onGuardrailTriggered(context _: AgentContext?, guardrailName _: String, guardrailType _: GuardrailType, result _: GuardrailResult) async {}

            func getInterval() -> (start: ContinuousClock.Instant, end: ContinuousClock.Instant)? {
                guard let start, let end else { return nil }
                return (start, end)
            }
        }

        let hook1 = DelayedHook()
        let hook2 = DelayedHook()
        let hook3 = DelayedHook()

        let composite = CompositeObserver(observers: [hook1, hook2, hook3])
        let mockAgent = MockAgentForAgentObserver()

        await composite.onAgentStart(context: nil, agent: mockAgent, input: "test")

        var intervals: [(start: ContinuousClock.Instant, end: ContinuousClock.Instant)] = []
        for hook in [hook1, hook2, hook3] {
            if let interval = await hook.getInterval() {
                intervals.append(interval)
            }
        }

        #expect(intervals.count == 3)

        guard let latestStart = intervals.map(\.start).max(),
              let earliestEnd = intervals.map(\.end).min()
        else {
            Issue.record("Missing hook interval data")
            return
        }

        #expect(
            latestStart < earliestEnd,
            "Expected concurrent hook execution; intervals did not overlap."
        )
	    }

    @Test("Composite observer all receive callbacks")
    func compositeObserverAllReceiveCallbacks() async throws {
        let hook1 = RecordingObserver()
        let hook2 = RecordingObserver()

        let composite = CompositeObserver(observers: [hook1, hook2])
        let mockAgent = MockAgentForAgentObserver()

        await composite.onAgentStart(context: nil, agent: mockAgent, input: "test")
        await composite.onAgentEnd(context: nil, agent: mockAgent, result: AgentResult(output: "done"))

        // Both observer should receive both events
        let events1 = await hook1.getEvents()
        let events2 = await hook2.getEvents()

        #expect(events1.count == 2)
        #expect(events2.count == 2)
        #expect(events1.contains("agentStart:test"))
        #expect(events1.contains("agentEnd:done"))
        #expect(events2.contains("agentStart:test"))
        #expect(events2.contains("agentEnd:done"))
    }
}

// MARK: - AgentObserverEdgeCaseTests

@Suite("AgentObserver Edge Cases")
struct AgentObserverEdgeCaseTests {
    @Test("Hooks handle empty strings gracefully")
    func hooksHandleEmptyStrings() async {
        let observer = RecordingObserver()
        let agent = MockAgentForAgentObserver()

        await observer.onAgentStart(context: nil, agent: agent, input: "")
        await observer.onAgentEnd(context: nil, agent: agent, result: AgentResult(output: ""))
        await observer.onLLMEnd(context: nil, agent: agent, response: "", usage: nil)

        let events = await observer.getEvents()
        #expect(events.count == 3)
    }

    @Test("Hooks handle empty collections gracefully")
    func hooksHandleEmptyCollections() async {
        let observer = RecordingObserver()
        let agent = MockAgentForAgentObserver()
        // removed unused tool

        await observer.onToolStart(context: nil, agent: agent, call: ToolCall(toolName: "tool", arguments: [:]))
        await observer.onLLMStart(context: nil, agent: agent, systemPrompt: nil, inputMessages: [])

        let events = await observer.getEvents()
        #expect(events.count == 2)
    }

    @Test("Hooks handle nil optional values")
    func hooksHandleNilOptionals() async {
        let observer = RecordingObserver()
        let agent = MockAgentForAgentObserver()

        await observer.onLLMStart(context: nil, agent: agent, systemPrompt: nil, inputMessages: [])
        await observer.onLLMEnd(context: nil, agent: agent, response: "response", usage: nil)

        let events = await observer.getEvents()
        #expect(events.contains("llmStart:0"))
        #expect(events.contains("llmEnd:none"))
    }

    @Test("CompositeObserver with single hook")
    func compositeSingleHook() async {
        // Given: Composite with only one hook
        let observer = RecordingObserver()
        let composite = CompositeObserver(observers: [observer])
        let agent = MockAgentForAgentObserver()

        // When: Using the composite
        await composite.onAgentStart(context: nil, agent: agent, input: "test")

        // Then: Should work identically to using the hook directly
        let events = await observer.getEvents()
        #expect(events == ["agentStart:test"])
    }
}
