import Foundation
@testable import Swarm
import Testing

struct AgentTurnTranscriptTests {
    @Test("Named append operations keep inference and memory projections aligned")
    func appendOperationsPreserveRolesAndToolIDs() {
        let call = InferenceResponse.ParsedToolCall(
            id: "call-weather",
            name: "weather",
            arguments: ["city": .string("Nairobi")]
        )
        var transcript = AgentTurnTranscript()

        transcript.appendAssistant(content: "", toolCalls: [call])
        transcript.appendToolResult(
            toolName: "weather",
            result: "sunny",
            toolCallID: call.id
        )

        #expect(transcript.inferenceMessages == [
            .assistant("", toolCalls: [
                InferenceMessage.ToolCall(id: call.id, name: call.name, arguments: call.arguments),
            ]),
            .tool(name: "weather", content: "sunny", toolCallID: "call-weather"),
        ])

        let entries = transcript.memoryMessages.map { SwarmTranscriptCodec.decodeEntry(from: $0) }
        #expect(entries.map(\.role) == [.assistant, .tool])
        #expect(entries[0].toolCalls == [
            SwarmTranscriptToolCall(id: call.id, name: call.name, arguments: call.arguments),
        ])
        #expect(entries[1].toolName == "weather")
        #expect(entries[1].toolCallID == call.id)
        #expect(transcript.memoryMessages[0].metadata[SwarmTranscriptCodec.entryIDKey] == entries[0].messageID.uuidString)
        #expect(transcript.memoryMessages[1].metadata[SwarmTranscriptCodec.entryIDKey] == entries[1].messageID.uuidString)
    }

    @Test("Owned provider transcripts retain order, IDs, tool calls, and structured output")
    func ownedLoopProjectionPreservesProviderTranscript() {
        let providerMessages: [InferenceMessage] = [
            .assistant("", toolCalls: [
                .init(id: "call-search", name: "search", arguments: [:]),
            ]),
            .tool(name: "search", content: "result", toolCallID: "call-search"),
            .assistant("provider final"),
        ]
        let structured = StructuredOutputResult(
            format: .jsonObject,
            rawJSON: #"{"answer":"ok"}"#,
            value: .dictionary(["answer": .string("ok")]),
            source: .providerNative
        )
        var transcript = AgentTurnTranscript()

        transcript.appendOwnedLoopTranscript(
            providerMessages,
            finalizedResponse: .init(content: structured.rawJSON, structuredOutput: structured)
        )

        #expect(transcript.inferenceMessages.map(\.role) == [.assistant, .tool, .assistant])
        #expect(transcript.inferenceMessages[0].toolCalls.first?.id == "call-search")
        #expect(transcript.inferenceMessages[1].toolCallID == "call-search")
        #expect(transcript.inferenceMessages[2].content == structured.rawJSON)

        let entries = transcript.memoryMessages.map { SwarmTranscriptCodec.decodeEntry(from: $0) }
        #expect(entries.count == 3)
        #expect(entries[0].toolCalls.first?.id == "call-search")
        #expect(entries[1].toolCallID == "call-search")
        #expect(entries[2].structuredOutput?.result == structured)
        #expect(entries[2].content == structured.rawJSON)
    }

    @Test("An empty owned transcript becomes one final assistant message")
    func emptyOwnedLoopAddsFinalAssistant() {
        let structured = StructuredOutputResult(
            format: .jsonObject,
            rawJSON: "[]",
            value: .array([]),
            source: .promptFallback
        )
        var transcript = AgentTurnTranscript()

        transcript.appendOwnedLoopTranscript(
            [],
            finalizedResponse: .init(content: "[]", structuredOutput: structured)
        )

        #expect(transcript.inferenceMessages == [.assistant("[]")])
        let entry = transcript.memoryMessages.first.map(SwarmTranscriptCodec.decodeEntry(from:))
        #expect(entry?.role == .assistant)
        #expect(entry?.structuredOutput?.result == structured)
    }
}
