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

    @Test("A recoverable tool failure in the handoff target does not release its tokens early")
    func targetToolFailureDoesNotReleaseHandoffTokens() async throws {
        let targetProvider = MockInferenceProvider(responses: ["my SSN is 123-45-6789"])
        await targetProvider.setToolCallResponses([Self.toolCallResponse(id: "call_fail", name: "failing_tool")])
        let target = try Agent(
            tools: [FailingTool()],
            instructions: "Answer.",
            configuration: Self.configuration(name: "target"),
            inferenceProvider: targetProvider
        )
        let source = try await Self.handoffSource(to: target, toolCalls: [])

        let events = await Self.collectUntilFailure(source.stream("tell me"))

        #expect(Self.tokens(in: events).isEmpty)
        #expect(Self.lastTerminal(in: events).map(Self.isFailed) == true)
    }

    @Test("A recoverable tool failure before the handoff does not release the target's tokens early")
    func sourceToolFailureDoesNotReleaseHandoffTokens() async throws {
        let target = try Agent(
            instructions: "Answer.",
            configuration: Self.configuration(name: "target"),
            inferenceProvider: MockInferenceProvider(responses: ["my SSN is 123-45-6789"])
        )
        let source = try await Self.handoffSource(
            to: target,
            toolCalls: [Self.toolCallResponse(id: "call_fail", name: "failing_tool")],
            tools: [FailingTool()]
        )

        let events = await Self.collectUntilFailure(source.stream("tell me"))

        #expect(Self.tokens(in: events).isEmpty)
        #expect(Self.lastTerminal(in: events).map(Self.isFailed) == true)
    }

    @Test("A recoverable tool failure neither drops held tokens nor ends the guarded stream")
    func recoverableToolFailureKeepsHeldTokens() async throws {
        let provider = ScriptedToolStreamingProvider(scripts: [
            [
                .outputChunk("Let me check. "),
                .toolCallsCompleted([
                    InferenceResponse.ParsedToolCall(id: "call_fail", name: "failing_tool", arguments: [:]),
                ]),
            ],
            [.outputChunk("All done")],
        ])
        let agent = try Agent(
            tools: [FailingTool()],
            instructions: "Answer.",
            configuration: Self.configuration(name: "agent").maxIterations(3),
            inferenceProvider: provider,
            outputGuardrails: [Self.noSSN]
        )

        let events = try await agent.stream("tell me").collect()

        #expect(Self.tokens(in: events).joined() == "Let me check. All done")
        let completedCount = events.count { if case .lifecycle(.completed) = $0 { true } else { false } }
        #expect(completedCount == 1)
        let lastTerminal = try #require(Self.lastTerminal(in: events))
        #expect(!Self.isFailed(lastTerminal))
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

    private static func toolCallResponse(id: String, name: String) -> InferenceResponse {
        InferenceResponse(
            content: nil,
            toolCalls: [InferenceResponse.ParsedToolCall(id: id, name: name, arguments: [:])],
            finishReason: .toolCall,
            usage: nil
        )
    }

    /// A guarded source agent that runs `toolCalls`, then hands off to `target`.
    private static func handoffSource(
        to target: Agent,
        toolCalls: [InferenceResponse],
        tools: [any AnyJSONTool] = []
    ) async throws -> Agent {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses(toolCalls + [toolCallResponse(id: "call_handoff", name: "handoff_to_target")])
        return try Agent(
            tools: tools,
            instructions: "Route.",
            configuration: configuration(name: "source"),
            inferenceProvider: provider,
            outputGuardrails: [noSSN],
            handoffs: [
                AnyHandoffConfiguration(HandoffConfiguration(targetAgent: target, toolNameOverride: "handoff_to_target")),
            ]
        )
    }

    /// The last `.completed` or `.failed` lifecycle event.
    private static func lastTerminal(in events: [AgentEvent]) -> AgentEvent? {
        events.last { event in
            switch event {
            case .lifecycle(.completed), .lifecycle(.failed): true
            default: false
            }
        }
    }

    private static func isFailed(_ event: AgentEvent) -> Bool {
        if case .lifecycle(.failed) = event { true } else { false }
    }

    private static func tokens(in events: [AgentEvent]) -> [String] {
        events.compactMap { event in
            if case let .output(.token(token)) = event { token } else { nil }
        }
    }
}

// MARK: - ScriptedToolStreamingProvider

/// Streams scripted tool-calling turns, one script per inference call.
///
/// A class rather than an actor: `streamWithToolCalls` is synchronous and an
/// actor here trips executor assumptions when called through an existential.
private final class ScriptedToolStreamingProvider: InferenceProvider, @unchecked Sendable {
    let capabilities: InferenceProviderCapabilities = [.streamingToolCalls]

    init(scripts: [[InferenceStreamUpdate]]) {
        self.scripts = scripts
    }

    func generate(messages _: [InferenceMessage], options _: InferenceOptions) async throws -> String {
        throw AgentError.generationFailed(reason: "Unexpected generate() call")
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions,
        toolExecutor _: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        throw AgentError.generationFailed(reason: "Unexpected generateWithToolCalls() call")
    }

    func streamWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions,
        toolExecutor _: ToolCallExecutor?
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        let updates = nextScript()
        return StreamHelper.makeTrackedStream { continuation in
            for update in updates {
                continuation.yield(update)
            }
            continuation.finish()
        }
    }

    private let lock = NSLock()
    private let scripts: [[InferenceStreamUpdate]]
    private var index = 0

    private func nextScript() -> [InferenceStreamUpdate] {
        lock.lock()
        defer { lock.unlock() }
        defer { index += 1 }
        return scripts[min(index, scripts.count - 1)]
    }
}
