// OpenAICompatibleThoughtSignatureTests.swift
// SwarmTests
//
// Tests for Gemini thought-signature round-tripping through the
// OpenAI-compatible codec: parse, accumulate, transcript, re-encode.

import Foundation
import Testing
@testable import Swarm

@Suite("OpenAI-compatible thought signatures")
struct OpenAICompatibleThoughtSignatureTests {
    @Test("SSE tool-call delta parses thought_signature")
    func parsesThoughtSignatureFromSSE() {
        var parser = OpenAICompatibleSSEParser()
        let events = parser.consume(line: #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"echo","arguments":"{}"},"extra_content":{"google":{"thought_signature":"sig-abc"}}}]}}]}"#)
            + parser.consume(line: "")

        guard case let .chunk(chunk) = events.first else {
            Issue.record("expected chunk event")
            return
        }
        #expect(chunk.choices.first?.delta?.toolCalls.first?.thoughtSignature == "sig-abc")
    }

    @Test("Missing thought_signature parses as nil")
    func missingThoughtSignatureIsNil() {
        var parser = OpenAICompatibleSSEParser()
        let events = parser.consume(line: #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"echo","arguments":"{}"}}]}}]}"#)
            + parser.consume(line: "")

        guard case let .chunk(chunk) = events.first else {
            Issue.record("expected chunk event")
            return
        }
        #expect(chunk.choices.first?.delta?.toolCalls.first?.thoughtSignature == nil)
    }

    @Test("Non-streaming response carries the signature")
    func nonStreamingResponseCarriesSignature() throws {
        let chunk = OpenAICompatibleChatChunk(json: [
            "choices": [[
                "message": [
                    "tool_calls": [[
                        "id": "call_1",
                        "function": ["name": "echo", "arguments": #"{"text":"hi"}"#],
                        "extra_content": ["google": ["thought_signature": "sig-1"]],
                    ]],
                ],
                "finish_reason": "tool_calls",
            ]],
        ])

        let response = try OpenAICompatibleCodec.inferenceResponse(from: chunk)

        #expect(response.toolCalls.first?.thoughtSignature == "sig-1")
    }

    @Test("Stream accumulator carries the signature to completion")
    func streamAccumulatorCarriesSignature() {
        var parser = OpenAICompatibleSSEParser()
        var accumulator = OpenAICompatibleStreamAccumulator()
        var updates: [InferenceStreamUpdate] = []
        let lines = [
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"echo","arguments":""},"extra_content":{"google":{"thought_signature":"sig-stream"}}}]}}]}"#,
            "",
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{}"}}]}}]}"#,
            "",
            #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
            "",
        ]
        for line in lines {
            for event in parser.consume(line: line) {
                if case let .chunk(chunk) = event {
                    updates += accumulator.consume(chunk)
                }
            }
        }
        updates += accumulator.finish()

        let completed = updates.compactMap { update -> [InferenceResponse.ParsedToolCall]? in
            if case let .toolCallsCompleted(calls) = update { return calls }
            return nil
        }.flatMap { $0 }
        #expect(completed.first?.thoughtSignature == "sig-stream")
    }

    @Test("Encoding echoes extra_content for signed calls only")
    func encodingEchoesSignature() {
        let signed = InferenceMessage.ToolCall(
            id: "call_1",
            name: "echo",
            arguments: ["text": .string("hi")],
            thoughtSignature: "sig-echo"
        )
        let unsigned = InferenceMessage.ToolCall(
            id: "call_2",
            name: "echo",
            arguments: [:]
        )
        let message = InferenceMessage(body: .assistant("working", toolCalls: [signed, unsigned]))

        let encoded = OpenAICompatibleCodec.encodeMessage(message)
        guard let calls = encoded["tool_calls"] as? [[String: Any]] else {
            Issue.record("expected tool_calls array")
            return
        }
        #expect(calls.count == 2)
        let extra = calls[0]["extra_content"] as? [String: Any]
        let google = extra?["google"] as? [String: Any]
        #expect(google?["thought_signature"] as? String == "sig-echo")
        #expect(calls[1]["extra_content"] == nil)
    }

    @Test("Turn transcript preserves signatures both directions")
    func transcriptPreservesSignatures() {
        let parsed = InferenceResponse.ParsedToolCall(
            id: "call_1",
            name: "echo",
            arguments: [:],
            thoughtSignature: "sig-turn"
        )
        let assistant = AgentTurnTranscript.Message.assistant("working", toolCalls: [parsed])

        let inference = assistant.inferenceMessage
        #expect(inference.toolCalls.first?.thoughtSignature == "sig-turn")

        let roundTripped = AgentTurnTranscript.Message(inference)
        guard case let .assistant(_, toolCalls) = roundTripped else {
            Issue.record("expected assistant message")
            return
        }
        #expect(toolCalls.first?.thoughtSignature == "sig-turn")
    }
}
