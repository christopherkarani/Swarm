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
            case .finishedTurn: "finished"
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

@Suite("OpenAI-compatible SSE parser fail-closed")
struct OpenAICompatibleSSEParserFailClosedTests {
    @Test("Object arguments throw naming the field")
    func objectArgumentsThrow() throws {
        let data = Data(#"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"echo","arguments":{"text":"hi"}}}]}}]}"#.utf8)

        let field = try #require(throwsFieldName { try OpenAICompatibleChatChunk(jsonData: data) })
        #expect(field == "choices[0].delta.tool_calls[0].function.arguments")
    }

    @Test("Mistyped choices throw naming the field")
    func mistypedChoicesThrow() throws {
        let data = Data(#"{"choices":{}}"#.utf8)

        let field = try #require(throwsFieldName { try OpenAICompatibleChatChunk(jsonData: data) })
        #expect(field == "choices")
    }

    @Test("Mistyped tool calls throw naming the field")
    func mistypedToolCallsThrow() throws {
        let data = Data(#"{"choices":[{"delta":{"tool_calls":{}}}]}"#.utf8)

        let field = try #require(throwsFieldName { try OpenAICompatibleChatChunk(jsonData: data) })
        #expect(field == "choices[0].delta.tool_calls")
    }

    @Test("Non-JSON payload throws invalidJSON")
    func nonJSONThrowsInvalidJSON() {
        do {
            _ = try OpenAICompatibleChatChunk(jsonData: Data("not-json".utf8))
            Issue.record("expected invalidJSON")
        } catch let error as OpenAICompatibleChunkDecodingError {
            guard case .invalidJSON = error else {
                Issue.record("expected invalidJSON, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("Stream surfaces mistyped chunks as field-context malformed events and continues")
    func streamSkipsMistypedChunkWithFieldContext() {
        var parser = OpenAICompatibleSSEParser()
        var events: [OpenAICompatibleSSEEvent] = []
        events += parser.consume(line: #"data: {"choices":[{"delta":{"content":"ok"}}]}"#)
        events += parser.consume(line: "")
        events += parser.consume(line: #"data: {"choices":{}}"#)
        events += parser.consume(line: "")
        events += parser.consume(line: "data: [DONE]")
        events += parser.consume(line: "")
        events += parser.finish()

        #expect(events.count == 3)
        guard case let .chunk(chunk) = events[0] else {
            Issue.record("expected first chunk")
            return
        }
        #expect(chunk.choices.first?.delta?.content == "ok")
        guard case let .malformed(payload) = events[1] else {
            Issue.record("expected malformed event for mistyped choices")
            return
        }
        #expect(payload.contains("'choices'"))
        #expect(events[2] == .done)
    }

    @Test("Typed decoding matches the dictionary entry on valid inputs")
    func typedDecodingMatchesDictionaryEntryOnValidInputs() throws {
        let fixtures = [
            #"{"id":"chatcmpl-1","choices":[{"index":0,"message":{"role":"assistant","content":"hi"},"finish_reason":"stop"}],"usage":{"prompt_tokens":11,"completion_tokens":4}}"#,
            #"{"choices":[{"delta":{"role":"assistant","content":null,"tool_calls":[{"index":0,"id":"call_1","function":{"name":"echo","arguments":"{}"},"extra_content":{"google":{"thought_signature":"sig"}}}]}}]}"#,
            #"{"choices":[{"delta":{"content":[{"type":"text","text":"blocks"}]}}]}"#,
            #"{"choices":[{"delta":{},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":11.0,"completion_tokens":4.5}}"#,
            #"{"error":{"message":"overloaded"}}"#,
            #"{"error":{"message":42},"choices":[]}"#,
            #"{}"#,
        ]
        for fixture in fixtures {
            let data = Data(fixture.utf8)
            let typed = try OpenAICompatibleChatChunk(jsonData: data)
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(typed == OpenAICompatibleChatChunk(json: object))
        }
    }

    @Test("Typed decoding preserves legacy lossy defaults on valid inputs")
    func typedDecodingPreservesLegacyDefaults() throws {
        let usageChunk = try OpenAICompatibleChatChunk(
            jsonData: Data(#"{"choices":[{"delta":{},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":11.0,"completion_tokens":4.5}}"#.utf8)
        )
        #expect(usageChunk.usage == TokenUsage(inputTokens: 11, outputTokens: 4))
        #expect(usageChunk.choices.first?.index == 0)
        let delta = try #require(usageChunk.choices.first?.delta)
        #expect(delta.toolCalls.isEmpty)

        let errorChunk = try OpenAICompatibleChatChunk(
            jsonData: Data(#"{"error":{"message":42},"choices":[]}"#.utf8)
        )
        #expect(errorChunk.errorMessage == "OpenAI-compatible stream error")

        let emptyChunk = try OpenAICompatibleChatChunk(jsonData: Data("{}".utf8))
        #expect(emptyChunk.choices.isEmpty)
        #expect(emptyChunk.usage == nil)
        #expect(emptyChunk.errorMessage == nil)

        let offsetChunk = try OpenAICompatibleChatChunk(
            jsonData: Data(#"{"choices":[{"delta":{"content":"a"}},{"delta":{"content":"b"}}]}"#.utf8)
        )
        #expect(offsetChunk.choices.map(\.index) == [0, 1])
    }

    @Test("Array content parts decode lossily instead of failing")
    func arrayContentDecodesLossily() throws {
        let chunk = try OpenAICompatibleChatChunk(
            jsonData: Data(#"{"choices":[{"delta":{"content":[{"type":"text"}]}}]}"#.utf8)
        )
        #expect(chunk.choices.first?.delta?.content == nil)
    }

    @Test("Legacy dictionary init keeps lenient fallback for invalid shapes")
    func legacyDictionaryInitKeepsLenientFallback() {
        // The non-streaming provider path calls init(json:) without try, so
        // invalid shapes keep the legacy lenient result there.
        let chunk = OpenAICompatibleChatChunk(json: ["choices": ["not": "an array"]])
        #expect(chunk.choices.isEmpty)
    }

    private func throwsFieldName(_ decode: () throws -> OpenAICompatibleChatChunk) throws -> String? {
        do {
            _ = try decode()
            Issue.record("expected shapeMismatch")
            return nil
        } catch let error as OpenAICompatibleChunkDecodingError {
            guard case let .shapeMismatch(field, _) = error else {
                Issue.record("expected shapeMismatch, got \(error)")
                return nil
            }
            return field
        }
    }
}
