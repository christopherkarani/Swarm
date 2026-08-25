// TurnEngineCharacterizationTests.swift
// Swarm Framework
//
// W3-T2 characterization suite (AC-201 / REQ-008): pins the exact observable
// ``AgentEvent`` stream order produced by the turn kernel now living in
// ``TurnEngine`` — including the deliberate double emission of
// `.tool(.completed)` then `.tool(.failed)` on tool failure — so the
// extraction stays provably behavior-preserving.

import Foundation
import Testing
@testable import Swarm

@Suite("TurnEngine Characterization", .ephemeralDefaultStores)
private struct TurnEngineCharacterizationTests {
    // MARK: - Helpers

    /// Stable, human-readable label for an event so whole streams can be
    /// compared element-for-element as arrays of strings.
    private func label(_ event: AgentEvent) -> String {
        switch event {
        case let .lifecycle(lifecycle):
            switch lifecycle {
            case let .started(input):
                return "started(\(input))"
            case .completed:
                return "completed"
            case let .failed(error):
                return "failed(\(String(describing: error)))"
            case .cancelled:
                return "cancelled"
            case .guardrailFailed:
                return "guardrailFailed"
            case let .iterationStarted(number):
                return "iterationStarted(\(number))"
            case let .iterationCompleted(number):
                return "iterationCompleted(\(number))"
            }
        case let .tool(tool):
            switch tool {
            case let .started(call):
                return "toolStarted(\(call.toolName))"
            case .partial:
                return "toolPartial"
            case let .completed(call, _):
                return "toolCompleted(\(call.toolName))"
            case let .failed(call, _):
                return "toolFailed(\(call.toolName))"
            }
        case let .output(output):
            switch output {
            case let .token(token):
                return "token(\(token))"
            case let .chunk(chunk):
                return "chunk(\(chunk))"
            case let .thinking(thought):
                return "thinking(\(thought))"
            case let .thinkingPartial(partialThought):
                return "thinkingPartial(\(partialThought))"
            }
        case .handoff:
            return "handoff"
        case let .observation(observation):
            switch observation {
            case .llmStarted:
                return "llmStarted"
            case .llmCompleted:
                return "llmCompleted"
            default:
                return "observation"
            }
        }
    }

    private func collectEvents(_ agent: Agent, input: String) async -> (events: [AgentEvent], thrown: Error?) {
        var events: [AgentEvent] = []
        var thrown: Error?
        do {
            for try await event in agent.stream(input) {
                events.append(event)
            }
        } catch {
            thrown = error
        }
        return (events, thrown)
    }

    // MARK: - REQ-008: tool-failure double emission order

    @Test("failing tool emits .tool(.completed) immediately followed by .tool(.failed)")
    func toolFailureEmitsCompletedThenFailedAdjacently() async throws {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(id: "call_1", name: "failing_tool", arguments: [:]),
                ],
                finishReason: .toolCall
            ),
            InferenceResponse(content: "Recovered from failure", toolCalls: [], finishReason: .completed),
        ])

        let agent = try Agent(
            tools: [FailingTool(name: "failing_tool")],
            instructions: "Characterization agent",
            inferenceProvider: provider
        )

        let (events, thrown) = await collectEvents(agent, input: "Start")
        #expect(thrown == nil)

        let completedIndex = events.firstIndex { event in
            if case let .tool(.completed(call, result)) = event {
                return call.toolName == "failing_tool" && !result.isSuccess
            }
            return false
        }
        let failedIndex = events.firstIndex { event in
            if case let .tool(.failed(call, error)) = event {
                if case .toolFailure(let toolName, _, _) = error {
                    return call.toolName == "failing_tool" && toolName == "failing_tool"
                }
                return false
            }
            return false
        }

        // The pinned invariant: completed THEN failed, adjacent, exactly once.
        #expect(completedIndex != nil, "expected a .tool(.completed) carrying the failure result")
        #expect(failedIndex != nil, "expected a .tool(.failed) event")
        #expect(failedIndex == completedIndex.map { $0 + 1 }, ".tool(.failed) must directly follow its .tool(.completed)")

        let failedCount = events.filter { event in
            if case .tool(.failed) = event { return true }
            return false
        }.count
        #expect(failedCount == 1)

        // The run itself still completes after a tolerated tool failure.
        #expect(events.last.map(label) == "completed")
    }

    // MARK: - Lifecycle ordering across a full scripted run

    @Test("successful tool run emits the exact pinned lifecycle/iteration/tool/output sequence")
    func successfulToolRunEventOrderIsPinned() async throws {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(id: "call_1", name: "test_tool", arguments: [:]),
                ],
                finishReason: .toolCall
            ),
            InferenceResponse(content: "Done", toolCalls: [], finishReason: .completed),
        ])

        let agent = try Agent(
            tools: [MockTool(name: "test_tool", result: .string("42"))],
            instructions: "Characterization agent",
            inferenceProvider: provider
        )

        let (events, thrown) = await collectEvents(agent, input: "Start")
        #expect(thrown == nil)

        let actual = events.map(label)
        let expected = [
            "started(Start)",
            "iterationStarted(1)",
            "llmStarted",
            "llmCompleted",
            "toolStarted(test_tool)",
            "toolCompleted(test_tool)",
            "iterationCompleted(1)",
            "iterationStarted(2)",
            "llmStarted",
            "token(Done)",
            "llmCompleted",
            "iterationCompleted(2)",
            "completed",
        ]
        #expect(actual == expected)
    }

    @Test("max-iterations failure ends the stream with .lifecycle(.failed) after all iteration/tool events")
    func maxIterationsFailureLifecycleOrderIsPinned() async throws {
        let provider = MockInferenceProvider()
        // One scripted tool call per iteration; two iterations exhaust the budget.
        let loopingCall = InferenceResponse(
            content: nil,
            toolCalls: [
                InferenceResponse.ParsedToolCall(id: "call_loop", name: "noop", arguments: [:]),
            ],
            finishReason: .toolCall
        )
        await provider.setToolCallResponses([loopingCall, loopingCall])

        let agent = try Agent(
            tools: [MockTool(name: "noop")],
            instructions: "Characterization agent",
            configuration: AgentConfiguration.default.maxIterations(2),
            inferenceProvider: provider
        )

        let (events, thrown) = await collectEvents(agent, input: "Start")

        guard case let .maxIterationsExceeded(iterations)? = thrown as? AgentError else {
            Issue.record("Expected AgentError.maxIterationsExceeded to rethrow, got \(String(describing: thrown))")
            return
        }
        #expect(iterations == 2)

        let actual = events.map(label)
        let expected = [
            "started(Start)",
            "iterationStarted(1)",
            "llmStarted",
            "llmCompleted",
            "toolStarted(noop)",
            "toolCompleted(noop)",
            "iterationCompleted(1)",
            "iterationStarted(2)",
            "llmStarted",
            "llmCompleted",
            "toolStarted(noop)",
            "toolCompleted(noop)",
            "iterationCompleted(2)",
            "failed(AgentError.maxIterationsExceeded(iterations: 2))",
        ]
        #expect(actual == expected)

        // The failure lifecycle event is always last.
        #expect(actual.last?.hasPrefix("failed(") == true)
    }

    // MARK: - Without-tools path ordering

    @Test("no-tool run orders llm/token/lifecycle events deterministically")
    func withoutToolsRunOrderingIsPinned() async throws {
        let provider = MockInferenceProvider()
        await provider.setResponses(["Hi"])

        let agent = try Agent(
            tools: [],
            instructions: "Characterization agent",
            inferenceProvider: provider
        )

        let (events, thrown) = await collectEvents(agent, input: "Start")
        #expect(thrown == nil)

        let tokens = events.compactMap { event -> String? in
            if case let .output(.token(token)) = event { return token }
            return nil
        }
        #expect(tokens.joined() == "Hi")

        let labels = events.map(label)
        let llmStart = labels.firstIndex(of: "llmStarted")
        let llmEnd = labels.firstIndex(of: "llmCompleted")
        let firstToken = labels.firstIndex { $0.hasPrefix("token(") }
        let iterationEnd = labels.firstIndex(of: "iterationCompleted(1)")

        #expect(llmStart != nil)
        #expect(firstToken != nil)
        #expect(llmEnd != nil)
        #expect(iterationEnd != nil)
        #expect(llmStart! < firstToken!)
        #expect(firstToken! < llmEnd!)
        #expect(llmEnd! < iterationEnd!)

        // Lifecycle bookends.
        #expect(labels.first?.hasPrefix("started(") == true)
        #expect(labels.last == "completed")
        #expect(labels.filter { $0 == "iterationStarted(1)" }.count == 1)
        #expect(labels.filter { $0 == "iterationCompleted(1)" }.count == 1)
    }
}
