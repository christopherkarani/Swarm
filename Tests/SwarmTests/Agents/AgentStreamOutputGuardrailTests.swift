import Foundation
@testable import Swarm
import Testing

@Suite("Agent stream output guardrails", .ephemeralDefaultStores)
struct AgentStreamOutputGuardrailTests {

    @Test("A tripped output guardrail leaks no tokens to the stream")
    func trippedGuardrailLeaksNoTokens() async throws {
        let agent = try Agent(
            instructions: "Answer.",
            configuration: Self.configuration(name: "agent"),
            inferenceProvider: MockInferenceProvider(responses: ["my SSN is 123-45-6789"]),
            outputGuardrails: [Self.noSSN]
        )

        let events = await Self.collectUntilFailure(agent.stream("tell me"))

        #expect(Self.tokens(in: events).isEmpty)
        #expect(events.contains { if case .lifecycle(.failed) = $0 { true } else { false } })
    }

    @Test("A passing output guardrail releases every token before completion")
    func passingGuardrailReleasesTokens() async throws {
        let agent = try Agent(
            instructions: "Answer.",
            configuration: Self.configuration(name: "agent"),
            inferenceProvider: MockInferenceProvider(responses: ["all clear"]),
            outputGuardrails: [Self.noSSN]
        )

        let events = try await agent.stream("tell me").collect()

        #expect(Self.tokens(in: events).joined() == "all clear")
        let lastToken = try #require(events.lastIndex { if case .output(.token) = $0 { true } else { false } })
        let completed = try #require(events.firstIndex { if case .lifecycle(.completed) = $0 { true } else { false } })
        #expect(lastToken < completed)
    }

    @Test("Handoff target tokens wait for the streaming agent's output guardrails")
    func handoffTargetTokensWaitForParentGuardrails() async throws {
        let target = try Agent(
            instructions: "Answer.",
            configuration: Self.configuration(name: "target"),
            inferenceProvider: MockInferenceProvider(responses: ["my SSN is 123-45-6789"])
        )
        let sourceProvider = MockInferenceProvider()
        await sourceProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(id: "call_handoff", name: "handoff_to_target", arguments: [:]),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
        ])
        let source = try Agent(
            instructions: "Route.",
            configuration: Self.configuration(name: "source"),
            inferenceProvider: sourceProvider,
            outputGuardrails: [Self.noSSN],
            handoffs: [
                AnyHandoffConfiguration(HandoffConfiguration(targetAgent: target, toolNameOverride: "handoff_to_target")),
            ]
        )

        let events = await Self.collectUntilFailure(source.stream("tell me"))

        #expect(Self.tokens(in: events).isEmpty)
    }

    @Test("Without output guardrails tokens still stream before completion")
    func noGuardrailsStreamsLive() async throws {
        let agent = try Agent(
            instructions: "Answer.",
            configuration: Self.configuration(name: "agent"),
            inferenceProvider: MockInferenceProvider(responses: ["hello"])
        )

        let events = try await agent.stream("tell me").collect()

        #expect(Self.tokens(in: events).joined() == "hello")
    }

    // MARK: - Helpers

    private static let noSSN = OutputGuard("no_ssn") { output in
        output.contains("SSN") ? .tripwire(message: "PII detected") : .passed()
    }

    private static func configuration(name: String) -> AgentConfiguration {
        AgentConfiguration(name: name, defaultTracingEnabled: false).enableStreaming(true)
    }

    private static func collectUntilFailure(_ stream: AsyncThrowingStream<AgentEvent, Error>) async -> [AgentEvent] {
        var events: [AgentEvent] = []
        do {
            for try await event in stream {
                events.append(event)
            }
            Issue.record("Expected the output guardrail to fail the run")
        } catch {}
        return events
    }

    private static func tokens(in events: [AgentEvent]) -> [String] {
        events.compactMap { event in
            if case let .output(.token(token)) = event { token } else { nil }
        }
    }
}
