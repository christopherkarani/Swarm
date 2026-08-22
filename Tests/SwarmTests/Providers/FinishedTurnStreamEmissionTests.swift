// FinishedTurnStreamEmissionTests.swift
// SwarmTests
//
// The shared finished-turn degradation helper emits the canonical
// InferenceStreamUpdate ordering every non-streaming adapter must match.

import Foundation
@testable import Swarm
import Testing

@Suite("Finished-turn stream emission")
struct FinishedTurnStreamEmissionTests {
    private func collect(_ stream: AsyncThrowingStream<InferenceStreamUpdate, Error>) async throws -> [InferenceStreamUpdate] {
        var updates: [InferenceStreamUpdate] = []
        for try await update in stream {
            updates.append(update)
        }
        return updates
    }

    @Test("Emits canonical order: outputChunk, toolCallsCompleted, usage, finishedTurn")
    func canonicalOrdering() async throws {
        let toolCall = InferenceResponse.ParsedToolCall(id: "t1", name: "echo", arguments: [:])
        let transcript = [InferenceMessage.assistant("", toolCalls: [InferenceMessage.ToolCall(toolCall)])]
        let usage = TokenUsage(inputTokens: 7, outputTokens: 3)
        let response = InferenceResponse(
            content: "partial answer",
            toolCalls: [toolCall],
            finishReason: .toolCall,
            usage: usage,
            transcriptMessages: transcript
        )

        let updates = try await collect(streamFinishedToolTurn { response })

        #expect(updates.count == 4)
        #expect(updates[0] == .outputChunk("partial answer"))
        #expect(updates[1] == .toolCallsCompleted([toolCall]))
        #expect(updates[2] == .usage(usage))
        #expect(updates[3] == .finishedTurn(response))
    }

    @Test("Omits empty content and finishedTurn when there is no inner transcript")
    func omitsEmptySegments() async throws {
        let response = InferenceResponse(content: "", toolCalls: [], finishReason: .completed)

        let updates = try await collect(streamFinishedToolTurn { response })

        #expect(updates.isEmpty)
    }

    @Test("Propagates generation errors to the stream consumer")
    func propagatesErrors() async {
        struct Boom: Error {}

        await #expect(throws: Boom.self) {
            try await collect(streamFinishedToolTurn { throw Boom() })
        }
    }
}
