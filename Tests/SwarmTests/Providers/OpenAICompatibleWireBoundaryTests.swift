// OpenAICompatibleWireBoundaryTests.swift
// Swarm Framework
//
// Golden characterization of the OpenAI-compatible wire boundary: SSE/unary
// decode leniency and request-body shape. Written against the pre-change
// implementation; must pass unchanged after the typed-boundary refactor.

import Foundation
import Testing
@testable import Swarm

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("OpenAI-compatible wire boundary goldens", .serialized)
struct OpenAICompatibleWireBoundaryTests {
    private let endpoint = URL(string: "https://api.example.test/v1")!

    // MARK: - Request body goldens (AC-004)

    @Test("Generate body maps messages, options, tools, and tool choice")
    func generateBodyGolden() throws {
        let request = try OpenAICompatibleCodec.makeRequest(
            configuration: .init(baseURL: endpoint, apiKey: "sk-test", model: "gpt-test"),
            messages: [
                .system("Be concise."),
                .user("Call echo"),
                .assistant(
                    "",
                    toolCalls: [
                        InferenceMessage.ToolCall(
                            id: "call_1",
                            name: "echo",
                            arguments: ["text": .string("hi")]
                        ),
                    ]
                ),
                .tool(name: "echo", content: "hi", toolCallID: "call_1"),
            ],
            tools: [
                ToolSchema(
                    name: "echo",
                    description: "Echo text",
                    parameters: [
                        ToolParameter(name: "text", description: "Text to echo", type: .string),
                    ]
                ),
            ],
            options: .default.temperature(0.2).maxTokens(64).toolChoice(.auto),
            stream: false,
            structuredOutput: nil
        )
        try assertBodyEquals(
            request.httpBody,
            expected: """
            {
              "model": "gpt-test",
              "messages": [
                {"role": "system", "content": "Be concise."},
                {"role": "user", "content": "Call echo"},
                {"role": "assistant", "content": "", "tool_calls": [
                  {"id": "call_1", "type": "function", "function": {"name": "echo", "arguments": "{\\"text\\":\\"hi\\"}"}}
                ]},
                {"role": "tool", "content": "hi", "tool_call_id": "call_1"}
              ],
              "temperature": 0.2,
              "max_tokens": 64,
              "tools": [
                {"type": "function", "function": {"name": "echo", "description": "Echo text", "parameters": {
                  "type": "object",
                  "properties": {"text": {"type": "string", "description": "Text to echo"}},
                  "additionalProperties": false,
                  "required": ["text"]
                }}}
              ],
              "tool_choice": "auto"
            }
            """
        )
    }

    @Test("Tool schema covers every parameter type with sorted required")
    func richParameterSchemaGolden() throws {
        let request = try OpenAICompatibleCodec.makeRequest(
            configuration: .init(baseURL: endpoint, model: "gpt-test"),
            messages: [.user("hi")],
            tools: [
                ToolSchema(
                    name: "search",
                    description: "Search things",
                    parameters: [
                        ToolParameter(name: "text", description: "Query", type: .string),
                        ToolParameter(
                            name: "count",
                            description: "Limit",
                            type: .int,
                            isRequired: false,
                            defaultValue: .int(3)
                        ),
                        ToolParameter(name: "ratio", description: "Ratio", type: .double),
                        ToolParameter(name: "flag", description: "Flag", type: .bool),
                        ToolParameter(
                            name: "tags",
                            description: "Tags",
                            type: .array(elementType: .string)
                        ),
                        ToolParameter(
                            name: "filter",
                            description: "Filter object",
                            type: .object(properties: [
                                ToolParameter(name: "q", description: "Nested", type: .string),
                            ])
                        ),
                        ToolParameter(
                            name: "mode",
                            description: "Mode",
                            type: .oneOf(["a", "b"])
                        ),
                        ToolParameter(name: "blob", description: "Anything", type: .any),
                    ]
                ),
            ],
            options: .default,
            stream: false,
            structuredOutput: nil
        )
        let body = try #require(request.httpBody)
        let parameters = try #require(
            ((try OpenAICompatibleJSON.object(from: body)["tools"] as? [[String: Any]])?
                .first?["function"] as? [String: Any])?["parameters"] as? [String: Any]
        )
        try assertJSONEquals(
            JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys]),
            expected: """
            {
              "type": "object",
              "properties": {
                "text": {"type": "string", "description": "Query"},
                "count": {"type": "integer", "description": "Limit", "default": 3},
                "ratio": {"type": "number", "description": "Ratio"},
                "flag": {"type": "boolean", "description": "Flag"},
                "tags": {"type": "array", "items": {"type": "string"}, "description": "Tags"},
                "filter": {
                  "type": "object",
                  "properties": {"q": {"type": "string", "description": "Nested"}},
                  "additionalProperties": false,
                  "required": ["q"],
                  "description": "Filter object"
                },
                "mode": {"type": "string", "enum": ["a", "b"], "description": "Mode"},
                "blob": {"description": "Anything"}
              },
              "additionalProperties": false,
              "required": ["blob", "filter", "flag", "mode", "ratio", "tags", "text"]
            }
            """
        )
    }

    @Test("Stream body sets stream flags and omits tools")
    func streamBodyGolden() throws {
        let request = try OpenAICompatibleCodec.makeRequest(
            configuration: .init(baseURL: endpoint, model: "gpt-test"),
            messages: [.user("Hi")],
            tools: [],
            options: .default,
            stream: true,
            structuredOutput: nil
        )
        try assertBodyEquals(
            request.httpBody,
            expected: """
            {
              "model": "gpt-test",
              "messages": [{"role": "user", "content": "Hi"}],
              "temperature": 1.0,
              "stream": true,
              "stream_options": {"include_usage": true}
            }
            """
        )
    }

    @Test("Full options body maps every scalar field")
    func fullOptionsBodyGolden() throws {
        var options = InferenceOptions.default
            .temperature(0.2)
            .maxTokens(64)
            .stopSequences(["END"])
            .topP(0.9)
            .presencePenalty(0.1)
            .frequencyPenalty(-0.1)
            .seed(42)
            .parallelToolCalls(false)
        options.toolChoice = .specific(toolName: "echo")
        let request = try OpenAICompatibleCodec.makeRequest(
            configuration: .init(baseURL: endpoint, model: "gpt-test"),
            messages: [.user("hi")],
            tools: [ToolSchema(name: "echo", description: "Echo", parameters: [])],
            options: options,
            stream: false,
            structuredOutput: nil
        )
        let body = try OpenAICompatibleJSON.object(from: #require(request.httpBody))
        #expect(body["temperature"] as? Double == 0.2)
        #expect(body["max_tokens"] as? Int == 64)
        #expect(body["stop"] as? [String] == ["END"])
        #expect(body["top_p"] as? Double == 0.9)
        #expect(body["presence_penalty"] as? Double == 0.1)
        #expect(body["frequency_penalty"] as? Double == -0.1)
        #expect(body["seed"] as? Int == 42)
        #expect(body["parallel_tool_calls"] as? Bool == false)
        let choice = try #require(body["tool_choice"] as? [String: Any])
        #expect(choice["type"] as? String == "function")
        let function = try #require(choice["function"] as? [String: Any])
        #expect(function["name"] as? String == "echo")
    }

    @Test("Structured json_schema body embeds sanitized response_format")
    func structuredSchemaBodyGolden() throws {
        let request = try OpenAICompatibleCodec.makeRequest(
            configuration: .init(
                baseURL: endpoint,
                model: "gpt-test",
                structuredOutputMode: .nativeJSONSchema
            ),
            messages: [.user("status")],
            tools: [],
            options: .default,
            stream: false,
            structuredOutput: StructuredOutputRequest(
                format: .jsonSchema(
                    name: "Status Report!",
                    schemaJSON: #"{"type":"object","properties":{"ok":{"type":"boolean"}}}"#
                )
            )
        )
        try assertBodyEquals(
            request.httpBody,
            expected: """
            {
              "model": "gpt-test",
              "messages": [{"role": "user", "content": "status"}],
              "temperature": 1.0,
              "response_format": {
                "type": "json_schema",
                "json_schema": {
                  "name": "Status_Report_",
                  "schema": {"type": "object", "properties": {"ok": {"type": "boolean"}}},
                  "strict": true
                }
              }
            }
            """
        )
    }

    @Test("Structured json_object body sends json_object format")
    func structuredObjectBodyGolden() throws {
        let request = try OpenAICompatibleCodec.makeRequest(
            configuration: .init(
                baseURL: endpoint,
                model: "gpt-test",
                structuredOutputMode: .nativeJSONSchema
            ),
            messages: [.user("status")],
            tools: [],
            options: .default,
            stream: false,
            structuredOutput: StructuredOutputRequest(format: .jsonObject)
        )
        let body = try OpenAICompatibleJSON.object(from: #require(request.httpBody))
        let format = try #require(body["response_format"] as? [String: Any])
        #expect(format.count == 1)
        #expect(format["type"] as? String == "json_object")
    }

    @Test("Tools suppress response_format on structured turns")
    func toolsSuppressResponseFormat() throws {
        let request = try OpenAICompatibleCodec.makeRequest(
            configuration: .init(
                baseURL: endpoint,
                model: "gpt-test",
                structuredOutputMode: .nativeJSONSchema
            ),
            messages: [.user("status")],
            tools: [ToolSchema(name: "echo", description: "Echo", parameters: [])],
            options: .default,
            stream: false,
            structuredOutput: StructuredOutputRequest(format: .jsonObject)
        )
        let body = try OpenAICompatibleJSON.object(from: #require(request.httpBody))
        #expect(body["tools"] != nil)
        #expect(body["response_format"] == nil)
    }

    @Test("Empty parameter list emits placeholder description")
    func emptyParametersGolden() throws {
        let request = try OpenAICompatibleCodec.makeRequest(
            configuration: .init(baseURL: endpoint, model: "gpt-test"),
            messages: [.user("hi")],
            tools: [ToolSchema(name: "echo", description: "Echo", parameters: [])],
            options: .default,
            stream: false,
            structuredOutput: nil
        )
        let body = try OpenAICompatibleJSON.object(from: #require(request.httpBody))
        let parameters = try #require(
            ((body["tools"] as? [[String: Any]])?.first?["function"] as? [String: Any])?["parameters"]
                as? [String: Any]
        )
        #expect(parameters["type"] as? String == "object")
        #expect((parameters["properties"] as? [String: Any])?.isEmpty == true)
        #expect(parameters["additionalProperties"] as? Bool == false)
        #expect(parameters["required"] == nil)
        #expect(parameters["description"] as? String == "Tool parameters for echo")
    }

    @Test("Assistant tool calls echo signatures and synthesize ids")
    func signatureAndIDGolden() throws {
        let request = try OpenAICompatibleCodec.makeRequest(
            configuration: .init(baseURL: endpoint, model: "gpt-test"),
            messages: [
                .assistant(
                    "working",
                    toolCalls: [
                        InferenceMessage.ToolCall(
                            id: nil,
                            name: "echo",
                            arguments: ["text": .string("hi")],
                            thoughtSignature: "sig-echo"
                        ),
                        InferenceMessage.ToolCall(
                            id: nil,
                            name: "echo",
                            arguments: [:]
                        ),
                    ]
                ),
                .tool(name: "echo", content: "ok"),
            ],
            tools: [],
            options: .default,
            stream: false,
            structuredOutput: nil
        )
        let body = try OpenAICompatibleJSON.object(from: #require(request.httpBody))
        let messages = try #require(body["messages"] as? [[String: Any]])
        let calls = try #require(messages[0]["tool_calls"] as? [[String: Any]])
        #expect(calls.count == 2)
        #expect(calls[0]["id"] as? String == "call_0")
        #expect(calls[1]["id"] as? String == "call_1")
        let extra = try #require(calls[0]["extra_content"] as? [String: Any])
        let google = try #require(extra["google"] as? [String: Any])
        #expect(google["thought_signature"] as? String == "sig-echo")
        #expect(calls[1]["extra_content"] == nil)
        #expect(messages[1]["tool_call_id"] as? String == "call_0")
    }

    // MARK: - SSE decode goldens (AC-001)

    @Test("SSE content deltas decode to chunk values")
    func sseContentGolden() throws {
        let chunk = try requireChunk(
            #"{"id":"chatcmpl-1","choices":[{"index":0,"delta":{"role":"assistant","content":"Hel"},"finish_reason":null}]}"#
        )
        #expect(chunk.id == "chatcmpl-1")
        #expect(chunk.errorMessage == nil)
        #expect(chunk.usage == nil)
        let choice = try #require(chunk.choices.first)
        #expect(choice.index == 0)
        #expect(choice.finishReason == nil)
        #expect(choice.message == nil)
        #expect(choice.delta?.role == "assistant")
        #expect(choice.delta?.content == "Hel")
        #expect(choice.delta?.toolCalls == [])
    }

    @Test("SSE tool-call delta decodes id, name, and arguments")
    func sseToolCallDeltaGolden() throws {
        let chunk = try requireChunk(
            #"{"choices":[{"index":1,"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"echo","arguments":"{\"text\":\"hi\"}"}}]},"finish_reason":"tool_calls"}]}"#
        )
        let choice = try #require(chunk.choices.first)
        #expect(choice.index == 1)
        #expect(choice.finishReason == "tool_calls")
        let call = try #require(choice.delta?.toolCalls.first)
        #expect(call.index == 0)
        #expect(call.id == "call_1")
        #expect(call.name == "echo")
        #expect(call.arguments == #"{"text":"hi"}"#)
        #expect(call.thoughtSignature == nil)
    }

    @Test("SSE usage frame decodes token counts")
    func sseUsageGolden() throws {
        let chunk = try requireChunk(
            #"{"choices":[{"delta":{}}],"usage":{"prompt_tokens":11,"completion_tokens":4,"total_tokens":15}}"#
        )
        #expect(chunk.usage == TokenUsage(inputTokens: 11, outputTokens: 4))
    }

    @Test("SSE error frame reports the message")
    func sseErrorGolden() throws {
        let chunk = try requireChunk(#"{"error":{"message":"bad"}}"#)
        #expect(chunk.errorMessage == "bad")
        #expect(chunk.choices.isEmpty)
    }

    @Test("SSE error alongside choices keeps both")
    func sseErrorWithChoicesGolden() throws {
        let chunk = try requireChunk(
            #"{"choices":[{"delta":{"content":"hi"}}],"error":{"message":"late"}}"#
        )
        #expect(chunk.errorMessage == "late")
        #expect(chunk.choices.first?.delta?.content == "hi")
    }

    @Test("Unary message with tool calls decodes all fields")
    func unaryMessageGolden() throws {
        let chunk = try requireChunk(
            """
            {"id":"chatcmpl-2","choices":[{"index":0,"message":{"role":"assistant","content":null,\
            "tool_calls":[{"id":"call_add","type":"function",\
            "function":{"name":"add","arguments":"{\\"a\\":2}"},\
            "extra_content":{"google":{"thought_signature":"sig-1"}}}]},\
            "finish_reason":"tool_calls"}],"usage":{"prompt_tokens":12,"completion_tokens":4}}
            """
        )
        #expect(chunk.id == "chatcmpl-2")
        let choice = try #require(chunk.choices.first)
        #expect(choice.finishReason == "tool_calls")
        #expect(choice.message?.content == nil)
        let call = try #require(choice.message?.toolCalls.first)
        #expect(call.index == 0)
        #expect(call.id == "call_add")
        #expect(call.name == "add")
        #expect(call.arguments == #"{"a":2}"#)
        #expect(call.thoughtSignature == "sig-1")
        #expect(chunk.usage == TokenUsage(inputTokens: 12, outputTokens: 4))
    }

    // MARK: - Decode leniency (AC-002)

    @Test("Unknown keys and finish reasons decode leniently")
    func unknownKeysAndFinishReasonAreIgnored() throws {
        let chunk = try requireChunk(
            """
            {"id":"x","choices":[{"index":0,"finish_reason":"eos_token",\
            "delta":{"role":"assistant","content":"hi"},"weird_future_field":{}}],\
            "usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2},\
            "future_top_level":[1,2,3]}
            """
        )
        #expect(chunk.choices.first?.finishReason == "eos_token")
        #expect(chunk.choices.first?.delta?.content == "hi")
        #expect(chunk.usage == TokenUsage(inputTokens: 1, outputTokens: 1))
    }

    @Test("Missing index falls back to the choice offset")
    func missingIndexFallsBackToOffset() throws {
        let chunk = try requireChunk(
            #"{"choices":[{"delta":{"content":"a"}},{"delta":{"content":"b"}}]}"#
        )
        #expect(chunk.choices.count == 2)
        #expect(chunk.choices[0].index == 0)
        #expect(chunk.choices[1].index == 1)
    }

    @Test("Missing tool-call index and arguments use lenient defaults")
    func missingToolCallFieldsUseDefaults() throws {
        let chunk = try requireChunk(
            #"{"choices":[{"delta":{"tool_calls":[{"id":"1","function":{"name":"f"}}]}}]}"#
        )
        let call = try #require(chunk.choices.first?.delta?.toolCalls.first)
        #expect(call.index == 0)
        #expect(call.name == "f")
        #expect(call.arguments == "")
    }

    @Test("Missing choices decode to an empty turn")
    func missingChoicesAreEmpty() throws {
        let chunk = try requireChunk(#"{"id":"x"}"#)
        #expect(chunk.choices.isEmpty)
        #expect(chunk.usage == nil)
    }

    @Test("Null content decodes to nil")
    func nullContentIsNil() throws {
        let chunk = try requireChunk(
            #"{"choices":[{"message":{"role":"assistant","content":null}}]}"#
        )
        #expect(chunk.choices.first?.message?.content == nil)
    }

    @Test("Non-string content degrades to nil without throwing")
    func arrayContentIsNil() throws {
        let chunk = try requireChunk(
            #"{"choices":[{"message":{"role":"assistant","content":[{"type":"text","text":"hi"}]}}]}"#
        )
        #expect(chunk.choices.first?.message?.role == "assistant")
        #expect(chunk.choices.first?.message?.content == nil)
    }

    @Test("Wrong-typed choice fields degrade per field")
    func wrongTypedChoiceFieldsDegrade() throws {
        let chunk = try requireChunk(
            #"{"choices":[{"index":"zero","delta":{"content":"hi"},"finish_reason":7}]}"#
        )
        let choice = try #require(chunk.choices.first)
        #expect(choice.index == 0)
        #expect(choice.finishReason == nil)
        #expect(choice.delta?.content == "hi")
    }

    @Test("Wrong-typed tool-call fields degrade per field")
    func wrongTypedToolCallFieldsDegrade() throws {
        let chunk = try requireChunk(
            #"{"choices":[{"delta":{"tool_calls":[{"index":"x","id":7,"function":{"name":"f","arguments":{"a":1}}}]}}]}"#
        )
        let call = try #require(chunk.choices.first?.delta?.toolCalls.first)
        #expect(call.index == 0)
        #expect(call.id == nil)
        #expect(call.name == "f")
        #expect(call.arguments == "")
    }

    @Test("Wrong-typed message degrades to nil while the chunk survives")
    func wrongTypedMessageIsNil() throws {
        let chunk = try requireChunk(
            #"{"choices":[{"index":0,"message":"oops","delta":{"content":"hi"}}]}"#
        )
        #expect(chunk.choices.first?.message == nil)
        #expect(chunk.choices.first?.delta?.content == "hi")
    }

    @Test("Wrong-typed choices degrade to an empty turn")
    func wrongTypedChoicesAreEmpty() throws {
        let chunk = try requireChunk(#"{"choices":"nope"}"#)
        #expect(chunk.choices.isEmpty)
    }

    @Test("Non-object choice element degrades the turn to empty")
    func nonObjectChoiceElementEmptiesTurn() throws {
        let chunk = try requireChunk(#"{"choices":[{"index":0},42]}"#)
        #expect(chunk.choices.isEmpty)
    }

    @Test("Double choice index falls back to the offset")
    func doubleIndexFallsBackToOffset() throws {
        let chunk = try requireChunk(
            #"{"choices":[{"index":1.5,"delta":{"content":"hi"}}]}"#
        )
        #expect(chunk.choices.first?.index == 0)
        #expect(chunk.choices.first?.delta?.content == "hi")
    }

    @Test("Usage tolerates partial, empty, and mistyped counts")
    func usageLeniency() throws {
        let onlyPrompt = try requireChunk(#"{"usage":{"prompt_tokens":5}}"#)
        #expect(onlyPrompt.usage == TokenUsage(inputTokens: 5, outputTokens: 0))
        let onlyCompletion = try requireChunk(#"{"usage":{"completion_tokens":7}}"#)
        #expect(onlyCompletion.usage == TokenUsage(inputTokens: 0, outputTokens: 7))
        let emptyUsage = try requireChunk(#"{"usage":{}}"#)
        #expect(emptyUsage.usage == nil)
        let totalOnly = try requireChunk(#"{"usage":{"total_tokens":9}}"#)
        #expect(totalOnly.usage == nil)
        let mistyped = try requireChunk(#"{"usage":{"prompt_tokens":"11"}}"#)
        #expect(mistyped.usage == nil)
        let wrongType = try requireChunk(#"{"usage":"nope"}"#)
        #expect(wrongType.usage == nil)
    }

    @Test("Usage truncates fractional token counts")
    func usageTruncatesDoubles() throws {
        let chunk = try requireChunk(
            #"{"usage":{"prompt_tokens":11.0,"completion_tokens":1.5}}"#
        )
        #expect(chunk.usage == TokenUsage(inputTokens: 11, outputTokens: 1))
    }

    @Test("Usage degrades out-of-range counts instead of trapping")
    func usageDegradesOutOfRangeDoubles() throws {
        let chunk = try requireChunk(
            #"{"usage":{"prompt_tokens":1e30,"completion_tokens":-1e30}}"#
        )
        #expect(chunk.usage == nil)
        let partial = try requireChunk(
            #"{"usage":{"prompt_tokens":1e30,"completion_tokens":4}}"#
        )
        #expect(partial.usage == TokenUsage(inputTokens: 0, outputTokens: 4))
    }

    @Test("Error without a message uses the default text")
    func errorWithoutMessageUsesDefault() throws {
        let chunk = try requireChunk(#"{"error":{"code":500}}"#)
        #expect(chunk.errorMessage == "OpenAI-compatible stream error")
    }

    @Test("String error payload yields no error message")
    func stringErrorYieldsNil() throws {
        let chunk = try requireChunk(#"{"error":"boom"}"#)
        #expect(chunk.errorMessage == nil)
    }

    // MARK: - Malformed handling (AC-003)

    @Test("Unparseable SSE payloads are malformed")
    func unparseableSSEIsMalformed() {
        for payload in ["not-json", #"{"choices":"#, "[1,2]", #""str""#, "5", "null"] {
            let events = parse(lines: ["data: \(payload)", ""])
            #expect(events.count == 1, "payload: \(payload)")
            guard case let .malformed(got) = events.first else {
                Issue.record("expected malformed for \(payload)")
                continue
            }
            #expect(got == payload)
        }
    }

    @Test("Malformed lines do not abort the stream")
    func malformedDoesNotAbortStream() throws {
        let events = parse(lines: [
            "data: not-json", "",
            #"data: {"choices":[{"delta":{"content":"ok"}}]}"#, "",
            "data: [DONE]", "",
        ])
        #expect(events.count == 3)
        #expect(events[0] == .malformed("not-json"))
        guard case let .chunk(chunk) = events[1] else {
            Issue.record("expected chunk")
            return
        }
        #expect(chunk.choices.first?.delta?.content == "ok")
        #expect(events[2] == .done)
    }

    @Test("Unary non-object JSON throws generationFailed")
    func unaryNonObjectThrowsGenerationFailed() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        OpenAICompatibleURLProtocol.enqueue(json: #"[{"message":"array"}]"#)
        let provider = OpenAICompatibleProvider(
            configuration: .init(baseURL: endpoint, model: "gpt-test"),
            session: OpenAICompatibleURLProtocol.makeSession()
        )
        do {
            _ = try await provider.generate(messages: [.user("hi")], options: .default)
            Issue.record("expected generate to throw")
        } catch let error as AgentError {
            guard case let .generationFailed(reason) = error else {
                Issue.record("expected generationFailed, got \(error)")
                return
            }
            #expect(reason == "OpenAI-compatible response is not a JSON object")
        }
    }

    @Test("Unary invalid JSON data throws")
    func unaryInvalidJSONThrows() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        OpenAICompatibleURLProtocol.enqueue(json: "not-json")
        let provider = OpenAICompatibleProvider(
            configuration: .init(baseURL: endpoint, model: "gpt-test"),
            session: OpenAICompatibleURLProtocol.makeSession()
        )
        var threw = false
        do {
            _ = try await provider.generate(messages: [.user("hi")], options: .default)
        } catch {
            threw = true
        }
        #expect(threw)
    }

    @Test("Streamed error frame fails generation with the server message")
    func streamedErrorFrameFailsGeneration() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        OpenAICompatibleURLProtocol.enqueueSSE("data: {\"error\":{\"message\":\"bad\"}}\n\n")
        let provider = OpenAICompatibleProvider(
            configuration: .init(baseURL: endpoint, model: "gpt-test"),
            session: OpenAICompatibleURLProtocol.makeSession()
        )
        do {
            for try await _ in provider.stream(messages: [.user("hi")], options: .default) {}
            Issue.record("expected stream to throw")
        } catch let error as AgentError {
            guard case let .generationFailed(reason) = error else {
                Issue.record("expected generationFailed, got \(error)")
                return
            }
            #expect(reason == "bad")
        }
    }

    @Test("Streamed content filter maps to contentFiltered")
    func streamedContentFilterMaps() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        OpenAICompatibleURLProtocol.enqueueSSE(
            "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"content_filter\"}]}\n\n"
        )
        let provider = OpenAICompatibleProvider(
            configuration: .init(baseURL: endpoint, model: "gpt-test"),
            session: OpenAICompatibleURLProtocol.makeSession()
        )
        do {
            for try await _ in provider.stream(messages: [.user("hi")], options: .default) {}
            Issue.record("expected stream to throw")
        } catch let error as AgentError {
            guard case .contentFiltered = error else {
                Issue.record("expected contentFiltered, got \(error)")
                return
            }
        }
    }

    // MARK: - Helpers

    private func parse(lines: [String]) -> [OpenAICompatibleSSEEvent] {
        var parser = OpenAICompatibleSSEParser()
        var events: [OpenAICompatibleSSEEvent] = []
        for line in lines {
            events += parser.consume(line: line)
        }
        events += parser.finish()
        return events
    }

    private func requireChunk(_ json: String) throws -> OpenAICompatibleChatChunk {
        let events = parse(lines: ["data: \(json)", ""])
        let event = try #require(events.first)
        guard case let .chunk(chunk) = event else {
            Issue.record("expected chunk, got \(event)")
            throw FixtureError.expectedChunk
        }
        return chunk
    }

    private func assertBodyEquals(_ body: Data?, expected: String) throws {
        try assertJSONEquals(#require(body), expected: expected)
    }

    private func assertJSONEquals(_ actual: Data, expected: String) throws {
        let actualValue = try JSONDecoder().decode(SendableValue.self, from: actual)
        let expectedValue = try JSONDecoder().decode(
            SendableValue.self,
            from: Data(expected.utf8)
        )
        #expect(actualValue == expectedValue)
    }
}

private enum FixtureError: Error {
    case expectedChunk
}
