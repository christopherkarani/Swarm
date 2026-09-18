// ToolInvocationObserverTests.swift
// SwarmTests
//
// Pins ToolInvocation through AgentObserver.onToolEnd.

import Foundation
@testable import Swarm
import Testing

@Suite("ToolInvocation Observer")
struct ToolInvocationObserverTests {
    @Test("AC-004: ToolExecutionEngine calls onToolEnd(invocation:) rather than result-only")
    func toolExecutionEngineCallsInvocationOnToolEnd() async throws {
        let recorder = DistinguishingToolEndObserver()
        let registry = ToolRegistry()
        try await registry.register(MockTool(name: "calculator", result: .string("4")))

        _ = try await ToolExecutionEngine().execute(
            toolName: "calculator",
            arguments: [:],
            registry: registry,
            agent: MockAgentForInvocationEvents(),
            context: nil,
            resultBuilder: AgentResult.Builder(),
            observer: recorder,
            tracing: nil,
            stopOnToolError: false
        )

        let invocationCalls = await recorder.invocationCalls
        let resultOnlyCalls = await recorder.resultOnlyCalls
        #expect(invocationCalls.count == 1)
        #expect(resultOnlyCalls.isEmpty)
        #expect(invocationCalls[0].call.toolName == "calculator")
        #expect(invocationCalls[0].result.output == .string("4"))
    }

    @Test("AC-004: ToolExecutionEngine failure path also uses onToolEnd(invocation:)")
    func toolExecutionEngineFailureCallsInvocationOnToolEnd() async throws {
        let recorder = DistinguishingToolEndObserver()
        let registry = ToolRegistry()
        try await registry.register(FailingTool(name: "boom"))

        _ = try await ToolExecutionEngine().execute(
            toolName: "boom",
            arguments: [:],
            registry: registry,
            agent: MockAgentForInvocationEvents(),
            context: nil,
            resultBuilder: AgentResult.Builder(),
            observer: recorder,
            tracing: nil,
            stopOnToolError: false
        )

        let invocationCalls = await recorder.invocationCalls
        let resultOnlyCalls = await recorder.resultOnlyCalls
        #expect(invocationCalls.count == 1)
        #expect(resultOnlyCalls.isEmpty)
        #expect(invocationCalls[0].call.toolName == "boom")
        #expect(invocationCalls[0].result.isSuccess == false)
    }

    @Test("AC-005: EventStreamObserver onToolEnd(invocation:) uses call.toolName without prior onToolStart")
    func eventStreamObserverUsesInvocationToolNameWithoutPriorStart() async throws {
        let (stream, continuation) = AsyncThrowingStream<AgentEvent, any Error>.makeStream()
        let observer = EventStreamObserver(continuation: continuation)
        let agent = MockAgentForInvocationEvents()
        let call = ToolCall(toolName: "calculator", arguments: [:])
        let invocation = ToolInvocation(
            call: call,
            duration: .milliseconds(5),
            outcome: .success(.string("4"))
        )

        await observer.onToolEnd(context: nil, agent: agent, invocation: invocation)
        continuation.finish()

        var events: [AgentEvent] = []
        for try await event in stream {
            events.append(event)
        }

        #expect(events.count == 1)
        guard case let .tool(.completed(call: completedCall, result: result)) = events[0] else {
            Issue.record("expected completed event")
            return
        }
        #expect(completedCall.toolName == "calculator")
        #expect(completedCall.toolName != "unknown")
        #expect(completedCall.id == call.id)
        #expect(result.isSuccess)
        #expect(result.output == .string("4"))
    }

    @Test("AC-006: result-only onToolEnd after onToolStart still emits started, completed, and failed")
    func eventStreamTreatsResultOnlyFailureAsCompletedAndFailed() async throws {
        let (stream, continuation) = AsyncThrowingStream<AgentEvent, any Error>.makeStream()
        let observer = EventStreamObserver(continuation: continuation)
        let agent = MockAgentForInvocationEvents()
        let callId = UUID()
        let call = ToolCall(id: callId, toolName: "calculator", arguments: [:])

        await observer.onToolStart(context: nil, agent: agent, call: call)
        await observer.onToolEnd(
            context: nil,
            agent: agent,
            result: ToolResult.failure(callId: callId, error: "Division by zero", duration: .milliseconds(5))
        )
        continuation.finish()

        var events: [AgentEvent] = []
        for try await event in stream {
            events.append(event)
        }

        #expect(events.count == 3)
        guard case let .tool(.started(call: startedCall)) = events[0] else {
            Issue.record("expected started event")
            return
        }
        #expect(startedCall.id == callId)
        guard case let .tool(.completed(call: _, result: result)) = events[1] else {
            Issue.record("expected completed event")
            return
        }
        #expect(!result.isSuccess)
        #expect(result.errorMessage == "Division by zero")
        guard case let .tool(.failed(call: failedCall, error: error)) = events[2] else {
            Issue.record("expected failed event")
            return
        }
        #expect(failedCall.id == callId)
        guard case let .toolFailure(toolName: toolName, message: message, cause: cause) = error else {
            Issue.record("expected toolFailure")
            return
        }
        #expect(toolName == "calculator")
        #expect(message == "Division by zero")
        #expect(cause == nil)
    }

    @Test("EventStreamObserver onToolEnd(invocation:) still dual-emits completed and failed")
    func eventStreamObserverInvocationFailureStillDualEmits() async throws {
        let (stream, continuation) = AsyncThrowingStream<AgentEvent, any Error>.makeStream()
        let observer = EventStreamObserver(continuation: continuation)
        let agent = MockAgentForInvocationEvents()
        let call = ToolCall(toolName: "calculator", arguments: [:])
        let invocation = ToolInvocation(
            call: call,
            duration: .milliseconds(5),
            outcome: .failure(message: "Division by zero")
        )

        await observer.onToolEnd(context: nil, agent: agent, invocation: invocation)
        continuation.finish()

        var events: [AgentEvent] = []
        for try await event in stream {
            events.append(event)
        }

        #expect(events.count == 2)
        guard case let .tool(.completed(call: completedCall, result: result)) = events[0] else {
            Issue.record("expected completed event")
            return
        }
        #expect(completedCall.toolName == "calculator")
        #expect(!result.isSuccess)
        guard case let .tool(.failed(call: failedCall, error: error)) = events[1] else {
            Issue.record("expected failed event")
            return
        }
        #expect(failedCall.toolName == "calculator")
        guard case let .toolFailure(toolName: toolName, message: message, cause: _) = error else {
            Issue.record("expected toolFailure")
            return
        }
        #expect(toolName == "calculator")
        #expect(message == "Division by zero")
    }

    @Test("CompositeObserver forwards invocation so children see the call")
    func compositeObserverForwardsInvocationToChildren() async {
        let recorder = InvocationNameRecorder()
        let composite = CompositeObserver(observers: [recorder])
        let agent = MockAgentForInvocationEvents()
        let call = ToolCall(toolName: "calculator", arguments: [:])
        let invocation = ToolInvocation(
            call: call,
            duration: .zero,
            outcome: .success(.string("4"))
        )

        await composite.onToolEnd(context: nil, agent: agent, invocation: invocation)

        let names = await recorder.names
        #expect(names == ["calculator"])
    }

    @Test("Default onToolEnd(invocation:) forwards to result-only conformers")
    func defaultOnToolEndInvocationForwardsToResultOnly() async {
        let recorder = ResultOnlyRecorder()
        let agent = MockAgentForInvocationEvents()
        let call = ToolCall(toolName: "calculator", arguments: [:])
        let invocation = ToolInvocation(
            call: call,
            duration: .zero,
            outcome: .success(.string("4"))
        )

        await recorder.onToolEnd(context: nil, agent: agent, invocation: invocation)

        let results = await recorder.results
        #expect(results.count == 1)
        #expect(results[0] == invocation.result)
    }
}

// MARK: - Recorders

private actor DistinguishingToolEndObserver: AgentObserver {
    var invocationCalls: [ToolInvocation] = []
    var resultOnlyCalls: [ToolResult] = []

    func onToolEnd(context _: AgentContext?, agent _: any AgentRuntime, invocation: ToolInvocation) async {
        invocationCalls.append(invocation)
    }

    func onToolEnd(context _: AgentContext?, agent _: any AgentRuntime, result: ToolResult) async {
        resultOnlyCalls.append(result)
    }
}

private actor InvocationNameRecorder: AgentObserver {
    var names: [String] = []

    func onToolEnd(context _: AgentContext?, agent _: any AgentRuntime, invocation: ToolInvocation) async {
        names.append(invocation.call.toolName)
    }
}

private actor ResultOnlyRecorder: AgentObserver {
    var results: [ToolResult] = []

    func onToolEnd(context _: AgentContext?, agent _: any AgentRuntime, result: ToolResult) async {
        results.append(result)
    }
}

private struct MockAgentForInvocationEvents: AgentRuntime {
    let tools: [any AnyJSONTool] = []
    let instructions: String = "Mock agent"
    let configuration: AgentConfiguration = AgentConfiguration(name: "mock")

    func run(_ input: String, session _: (any Session)? = nil, observer _: (any AgentObserver)? = nil) async throws -> AgentResult {
        AgentResult(output: input)
    }

    nonisolated func stream(
        _ input: String,
        session _: (any Session)? = nil,
        observer _: (any AgentObserver)? = nil
    ) -> AsyncThrowingStream<AgentEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.lifecycle(.started(input: input)))
            continuation.finish()
        }
    }

    func cancel() async {}
}
