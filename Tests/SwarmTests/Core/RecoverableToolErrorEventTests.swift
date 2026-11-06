import Foundation
@testable import Swarm
import Testing

@Suite("Recoverable tool error events", .ephemeralDefaultStores)
struct RecoverableToolErrorEventTests {

    @Test("Recoverable tool failure emits a tool failure, not a run failure")
    func recoverableToolFailureDoesNotFailTheRun() async throws {
        let agent = try await Self.makeAgent(stopOnToolError: false)

        let events = try await agent.stream("use the tool").collect()

        #expect(Self.runFailures(in: events) == 0)
        #expect(events.contains { if case .tool(.failed) = $0 { true } else { false } })
        #expect(events.contains { if case .lifecycle(.completed) = $0 { true } else { false } })
    }

    @Test("Fatal tool failure emits exactly one run failure")
    func fatalToolFailureFailsTheRunOnce() async throws {
        let agent = try await Self.makeAgent(stopOnToolError: true)

        var events: [AgentEvent] = []
        do {
            for try await event in agent.stream("use the tool") {
                events.append(event)
            }
            Issue.record("Expected the run to fail")
        } catch {}

        #expect(Self.runFailures(in: events) == 1)
        #expect(!events.contains { if case .lifecycle(.completed) = $0 { true } else { false } })
    }

    // MARK: - Helpers

    private static func runFailures(in events: [AgentEvent]) -> Int {
        events.count { if case .lifecycle(.failed) = $0 { true } else { false } }
    }

    private static func makeAgent(stopOnToolError: Bool) async throws -> Agent {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(id: "call_1", name: "failing_tool", arguments: [:]),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
            InferenceResponse(content: "recovered", finishReason: .completed),
        ])
        return try Agent(
            tools: [FailingTool()],
            instructions: "Use the tool.",
            configuration: AgentConfiguration(name: "agent", defaultTracingEnabled: false)
                .stopOnToolError(stopOnToolError),
            inferenceProvider: provider
        )
    }
}
