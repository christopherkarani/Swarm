import Foundation
import Testing
@testable import Swarm

@Suite("OpenAI-compatible SSE parser")
struct OpenAICompatibleSSEParserTests {
    @Test("Parses multi-event content deltas and [DONE]")
    func parsesMultiEventContentDeltas() {
        var parser = OpenAICompatibleSSEParser()
        var events: [OpenAICompatibleSSEEvent] = []
        events += parser.consume(line: #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#)
        events += parser.consume(line: "")
        events += parser.consume(line: #"data: {"choices":[{"delta":{"content":"lo"}}]}"#)
        events += parser.consume(line: "")
        events += parser.consume(line: "data: [DONE]")
        events += parser.consume(line: "")
        events += parser.finish()

        #expect(events.count == 3)
        guard case let .chunk(first) = events[0] else {
            Issue.record("expected first chunk")
            return
        }
        #expect(first.choices.first?.delta?.content == "Hel")
        guard case let .chunk(second) = events[1] else {
            Issue.record("expected second chunk")
            return
        }
        #expect(second.choices.first?.delta?.content == "lo")
        #expect(events[2] == .done)
    }

    @Test("Accumulates split tool-call argument deltas")
    func accumulatesToolCallDeltas() {
        var parser = OpenAICompatibleSSEParser()
        var accumulator = OpenAICompatibleStreamAccumulator()
        var updates: [InferenceStreamUpdate] = []

        let lines = [
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"echo","arguments":""}}]}}]}"#,
            "",
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"t"}}]}}]}"#,
            "",
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"ext\":\"hi\"}"}}]}}],"usage":{"prompt_tokens":11,"completion_tokens":4}}"#,
            "",
            #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
            "",
            "data: [DONE]",
            "",
        ]

        for line in lines {
            for event in parser.consume(line: line) {
                switch event {
                case let .chunk(chunk):
                    updates += accumulator.consume(chunk)
                case .done:
                    updates += accumulator.finish()
                case .malformed:
                    Issue.record("unexpected malformed event")
                }
            }
        }

        let partials = updates.compactMap { update -> PartialToolCallUpdate? in
            if case let .toolCallPartial(partial) = update { return partial }
            return nil
        }
        #expect(partials.count == 3)
        #expect(partials.last?.argumentsFragment == #"{"text":"hi"}"#)

        guard case let .toolCallsCompleted(calls) = updates.last(where: {
            if case .toolCallsCompleted = $0 { return true }
            return false
        }) else {
            Issue.record("expected completed tool calls")
            return
        }
        #expect(calls.count == 1)
        #expect(calls[0].id == "call_1")
        #expect(calls[0].name == "echo")
        #expect(calls[0].arguments["text"]?.stringValue == "hi")

        guard case let .usage(usage) = updates.first(where: {
            if case .usage = $0 { return true }
            return false
        }) else {
            Issue.record("expected usage payload")
            return
        }
        #expect(usage == TokenUsage(inputTokens: 11, outputTokens: 4))
    }

    @Test("Emits usage before toolCallsCompleted so Agent can record it")
    func emitsUsageBeforeToolCallsCompleted() {
        var accumulator = OpenAICompatibleStreamAccumulator()
        var updates: [InferenceStreamUpdate] = []

        updates += accumulator.consume(
            OpenAICompatibleChatChunk(json: [
                "choices": [[
                    "delta": [
                        "tool_calls": [[
                            "index": 0,
                            "id": "call_1",
                            "function": ["name": "echo", "arguments": "{\"text\":\"hi\"}"],
                        ]],
                    ],
                    "finish_reason": "tool_calls",
                ]],
            ])
        )
        updates += accumulator.consume(
            OpenAICompatibleChatChunk(json: [
                "choices": [] as [Any],
                "usage": ["prompt_tokens": 11, "completion_tokens": 4],
            ])
        )
        updates += accumulator.finish()

        let kinds = updates.map { update -> String in
            switch update {
            case .outputChunk: "chunk"
            case .toolCallPartial: "partial"
            case .usage: "usage"
            case .toolCallsCompleted: "completed"
            }
        }
        #expect(kinds.contains("usage"))
        #expect(kinds.contains("completed"))
        #expect(kinds.lastIndex(of: "usage")! < kinds.lastIndex(of: "completed")!)
    }

    @Test("Skips truncated and malformed data lines without aborting")
    func skipsTruncatedAndMalformedLines() {
        var parser = OpenAICompatibleSSEParser()
        var events: [OpenAICompatibleSSEEvent] = []
        events += parser.consume(line: "data: {\"choices\":")
        events += parser.consume(line: "")
        events += parser.consume(line: "data: not-json")
        events += parser.consume(line: "")
        events += parser.consume(line: #"data: {"choices":[{"delta":{"content":"ok"}}]}"#)
        events += parser.consume(line: "")
        events += parser.consume(line: "data: [DONE]")
        events += parser.consume(line: "")

        let malformed = events.compactMap { event -> String? in
            if case let .malformed(payload) = event { return payload }
            return nil
        }
        #expect(malformed.count == 2)
        #expect(events.contains { event in
            if case let .chunk(chunk) = event {
                return chunk.choices.first?.delta?.content == "ok"
            }
            return false
        })
        #expect(events.contains(.done))
    }

    @Test("Joins multi-line data payloads into one event")
    func joinsMultiLineDataPayloads() {
        var parser = OpenAICompatibleSSEParser()
        var events: [OpenAICompatibleSSEEvent] = []
        events += parser.consume(line: #"data: {"choices":[{"delta":{"content":"ab"}}]}"#)
        events += parser.consume(line: "")
        #expect(events.count == 1)
        guard case let .chunk(chunk) = events[0] else {
            Issue.record("expected joined chunk")
            return
        }
        #expect(chunk.choices.first?.delta?.content == "ab")
    }
}
