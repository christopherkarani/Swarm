import Foundation
@testable import Swarm
import Testing

@Suite("Agent handoff sibling tool calls", .ephemeralDefaultStores)
struct AgentHandoffSiblingToolCallTests {

    @Test("Every tool call in a handoff message gets a persisted tool result")
    func everyToolCallInHandoffMessageGetsPersistedResult() async throws {
        let sourceProvider = MockInferenceProvider()
        await sourceProvider.setToolCallResponses([
            Self.handoffResponse(calls: [
                ("call_a", "lookup_a"),
                ("call_handoff", "handoff_to_target"),
                ("call_b", "lookup_b"),
            ]),
        ])
        let toolA = SpyTool(name: "lookup_a")
        let toolB = SpyTool(name: "lookup_b")
        let source = try Self.makeSource(
            provider: sourceProvider,
            tools: [toolA, toolB],
            targetProvider: MockInferenceProvider(responses: ["target done"])
        )
        let session = InMemorySession()

        let result = try await source.run("please route this", session: session)

        #expect(result.output == "target done")
        #expect(await toolA.callCount == 1)
        // Control already moved to the target; the sibling is answered, not run.
        #expect(await toolB.callCount == 0)

        let entries = SwarmTranscript(memoryMessages: try await session.getAllItems()).entries
        let requestedIDs = entries.flatMap { $0.toolCalls.compactMap(\.id) }
        let answeredIDs = entries.filter { $0.role == .tool }.compactMap(\.toolCallID)
        #expect(requestedIDs == ["call_a", "call_handoff", "call_b"])
        #expect(Set(answeredIDs) == Set(requestedIDs))

        let skipped = try #require(entries.first { $0.toolCallID == "call_b" })
        #expect(skipped.content.contains("Not executed"))
        #expect(skipped.content.contains("handoff_to_target"))
        // The result keeps listing only calls that ran.
        #expect(!result.toolCalls.contains { $0.providerCallId == "call_b" })
    }

    @Test("Handoff keeps the parent's response ID")
    func handoffKeepsParentResponseID() async throws {
        let sourceProvider = MockInferenceProvider()
        await sourceProvider.setToolCallResponses([
            Self.handoffResponse(calls: [("call_handoff", "handoff_to_target")]),
        ])
        let source = try Self.makeSource(
            provider: sourceProvider,
            tools: [],
            targetProvider: MockInferenceProvider(responses: ["target done"]),
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false)
                .autoPreviousResponseId(true)
        )
        let session = InMemorySession()

        let response = try await source.runWithResponse("please route this", session: session)

        let tracked = await source.runEnvironment.responseTracker.getLatestResponseId(for: session.sessionId)
        #expect(tracked == response.responseId)
        let childResponseID = try #require(response.metadata["handoff.response.id"]?.stringValue)
        #expect(childResponseID != response.responseId)
    }

    @Test("Nested handoff history answers every tool call in the child request")
    func nestedHistoryAnswersEveryToolCallInChildRequest() async throws {
        let sourceProvider = MockInferenceProvider()
        await sourceProvider.setToolCallResponses([
            Self.handoffResponse(calls: [
                ("call_a", "lookup_a"),
                ("call_handoff", "handoff_to_target"),
                ("call_b", "lookup_b"),
            ]),
        ])
        let targetProvider = MockInferenceProvider(responses: ["target done"])
        let source = try Self.makeSource(
            provider: sourceProvider,
            tools: [SpyTool(name: "lookup_a"), SpyTool(name: "lookup_b")],
            targetProvider: targetProvider,
            history: .nested
        )

        let result = try await source.run("please route this")

        #expect(result.output == "target done")
        let childMessages = try #require(await targetProvider.generateMessageCalls.first?.messages)
        let requestedIDs = childMessages.flatMap { $0.toolCalls.compactMap(\.id) }
        let answeredIDs = Set(childMessages.filter { $0.role == .tool }.compactMap(\.toolCallID))
        #expect(requestedIDs == ["call_a", "call_b"])
        #expect(requestedIDs.allSatisfy { answeredIDs.contains($0) })
    }

    // MARK: - Helpers

    private static func handoffResponse(calls: [(id: String, name: String)]) -> InferenceResponse {
        InferenceResponse(
            content: nil,
            toolCalls: calls.map { call in
                InferenceResponse.ParsedToolCall(id: call.id, name: call.name, arguments: [:])
            },
            finishReason: .toolCall,
            usage: nil
        )
    }

    private static func makeSource(
        provider: MockInferenceProvider,
        tools: [any AnyJSONTool],
        targetProvider: MockInferenceProvider,
        configuration: AgentConfiguration = AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
        history: HandoffHistory = .none
    ) throws -> Agent {
        let target = try Agent(
            tools: [],
            instructions: "Handle routed work.",
            configuration: AgentConfiguration(name: "target-agent", defaultTracingEnabled: false),
            inferenceProvider: targetProvider
        )
        return try Agent(
            tools: tools,
            instructions: "Route to target.",
            configuration: configuration,
            inferenceProvider: provider,
            handoffs: [
                AnyHandoffConfiguration(HandoffConfiguration(
                    targetAgent: target,
                    toolNameOverride: "handoff_to_target",
                    history: history
                )),
            ]
        )
    }
}
