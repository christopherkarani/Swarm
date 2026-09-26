// OpenAICompatibleTypedWireTests.swift
// Swarm Framework
//
// Direct tests for the typed Codable wire boundary: one throwing decode per
// payload on the way in, typed `Encodable` values on the way out.

import Foundation
import Testing
@testable import Swarm

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exercises the Codable wire boundary directly: one throwing decode per
/// payload on the way in, typed `Encodable` values on the way out.
@Suite("OpenAI-compatible typed wire boundary", .serialized)
struct OpenAICompatibleTypedWireBoundaryTests {
    private let endpoint = URL(string: "https://api.example.test/v1")!

    @Test("Wire chunk decodes leniently from raw data")
    func wireChunkDecodesLeniently() throws {
        let wire = try JSONDecoder().decode(
            OpenAICompatibleWire.Chunk.self,
            from: Data(
                """
                {"id":"x","choices":[{"finish_reason":"eos_token",\
                "delta":{"role":"assistant","content":"hi"},"future":1}],\
                "usage":{"prompt_tokens":1,"completion_tokens":1},\
                "future_top_level":{}}
                """.utf8
            )
        )
        #expect(wire.id == "x")
        #expect(wire.choices.count == 1)
        #expect(wire.choices[0].index == nil)
        #expect(wire.choices[0].finishReason == "eos_token")
        #expect(wire.choices[0].delta?.content == "hi")
        #expect(wire.usage?.promptTokens == 1)
        #expect(wire.usage?.completionTokens == 1)
        #expect(wire.error == nil)
    }

    @Test("Wire chunk requires a JSON object")
    func wireChunkRejectsNonObject() {
        for payload in ["[1,2]", #""str""#, "5", "null", "not-json"] {
            #expect(throws: (any Error).self, "payload: \(payload)") {
                try JSONDecoder().decode(
                    OpenAICompatibleWire.Chunk.self,
                    from: Data(payload.utf8)
                )
            }
        }
    }

    @Test("Chunk decoding applies the offset fallback")
    func chunkDecodingAppliesOffsetFallback() throws {
        let chunk = try OpenAICompatibleChatChunk(decoding: Data(
            #"{"choices":[{"delta":{"content":"a"}},{"index":5,"delta":{"content":"b"}}]}"#.utf8
        ))
        #expect(chunk.choices.count == 2)
        #expect(chunk.choices[0].index == 0)
        #expect(chunk.choices[1].index == 5)
    }

    @Test("Chunk init from wire maps every field")
    func chunkInitFromWire() throws {
        let wire = try JSONDecoder().decode(
            OpenAICompatibleWire.Chunk.self,
            from: Data(
                """
                {"id":"c","choices":[{"index":2,"message":{"role":"assistant",\
                "content":"hi","tool_calls":[{"index":4,"id":"k","function":\
                {"name":"f","arguments":"{}"},"extra_content":{"google":\
                {"thought_signature":"s"}}}]},"finish_reason":"stop"}],\
                "usage":{"prompt_tokens":3,"completion_tokens":6},\
                "error":{"message":"late"}}
                """.utf8
            )
        )
        let chunk = OpenAICompatibleChatChunk(wire: wire)
        #expect(chunk.id == "c")
        #expect(chunk.choices.first?.index == 2)
        #expect(chunk.choices.first?.message?.content == "hi")
        let call = try #require(chunk.choices.first?.message?.toolCalls.first)
        #expect(call.index == 4)
        #expect(call.id == "k")
        #expect(call.name == "f")
        #expect(call.arguments == "{}")
        #expect(call.thoughtSignature == "s")
        #expect(chunk.usage == TokenUsage(inputTokens: 3, outputTokens: 6))
        #expect(chunk.errorMessage == "late")
    }

    @Test("Request body builds a typed wire value")
    func requestBodyIsTyped() throws {
        let body: OpenAICompatibleWire.Request = try OpenAICompatibleCodec.requestBody(
            configuration: .init(baseURL: endpoint, model: "gpt-test"),
            messages: [.user("hi")],
            tools: [
                ToolSchema(
                    name: "echo",
                    description: "Echo",
                    parameters: [
                        ToolParameter(name: "text", description: "Text", type: .string),
                    ]
                ),
            ],
            options: .default.temperature(0.2).toolChoice(.auto),
            stream: true,
            structuredOutput: nil
        )
        #expect(body.model == "gpt-test")
        #expect(body.messages.count == 1)
        #expect(body.messages[0].role == "user")
        #expect(body.temperature == 0.2)
        #expect(body.maxTokens == nil)
        #expect(body.tools?.count == 1)
        #expect(body.tools?[0].function.name == "echo")
        #expect(body.toolChoice == .auto)
        #expect(body.stream == true)
        #expect(body.streamOptions?.includeUsage == true)
        #expect(body.responseFormat == nil)
    }

    @Test("Wire request encodes to the golden JSON shape")
    func wireRequestEncodesGolden() throws {
        let body: OpenAICompatibleWire.Request = try OpenAICompatibleCodec.requestBody(
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
                format: .jsonSchema(name: "Status", schemaJSON: #"{"type":"object"}"#)
            )
        )
        let data = try OpenAICompatibleWire.encode(body)
        let actual = try JSONDecoder().decode(SendableValue.self, from: data)
        let expected = try JSONDecoder().decode(
            SendableValue.self,
            from: Data(
                """
                {"model":"gpt-test","messages":[{"role":"user","content":"status"}],\
                "temperature":1.0,"response_format":{"type":"json_schema",\
                "json_schema":{"name":"Status","schema":{"type":"object"},"strict":true}}}
                """.utf8
            )
        )
        #expect(actual == expected)
    }

    @Test("Encoded message carries signatures only when present")
    func encodedMessageWire() {
        let message = InferenceMessage(
            body: .assistant(
                "working",
                toolCalls: [
                    InferenceMessage.ToolCall(
                        id: "call_1",
                        name: "echo",
                        arguments: ["text": .string("hi")],
                        thoughtSignature: "sig-echo"
                    ),
                    InferenceMessage.ToolCall(id: "call_2", name: "echo", arguments: [:]),
                ]
            )
        )
        let encoded: OpenAICompatibleWire.RequestMessage = OpenAICompatibleCodec.encodeMessage(message)
        #expect(encoded.role == "assistant")
        #expect(encoded.name == nil)
        #expect(encoded.toolCalls?.count == 2)
        #expect(
            encoded.toolCalls?[0].extraContent?.google.thoughtSignature == "sig-echo"
        )
        #expect(encoded.toolCalls?[1].extraContent == nil)
    }

    @Test("Specific tool choice encodes to a function reference")
    func specificToolChoiceWire() throws {
        let choice = OpenAICompatibleCodec.encodeToolChoice(.specific(toolName: "echo"))
        let data = try OpenAICompatibleWire.encode(choice)
        let actual = try JSONDecoder().decode(SendableValue.self, from: data)
        #expect(
            actual == .dictionary([
                "type": .string("function"),
                "function": .dictionary(["name": .string("echo")]),
            ])
        )
    }

    @Test("Parameters schema builds a typed value")
    func parametersSchemaIsTyped() throws {
        let schema: SendableValue = OpenAICompatibleCodec.parametersSchema(
            for: ToolSchema(
                name: "echo",
                description: "Echo",
                parameters: [
                    ToolParameter(name: "text", description: "Text", type: .string),
                ]
            )
        )
        #expect(
            schema == .dictionary([
                "type": .string("object"),
                "properties": .dictionary([
                    "text": .dictionary([
                        "type": .string("string"),
                        "description": .string("Text"),
                    ]),
                ]),
                "additionalProperties": .bool(false),
                "required": .array([.string("text")]),
            ])
        )
    }

    @Test("Non-object structured schema throws invalidInput")
    func nonObjectSchemaThrows() {
        #expect(throws: AgentError.self) {
            try OpenAICompatibleCodec.encodeResponseFormat(
                StructuredOutputRequest(
                    format: .jsonSchema(name: "Bad", schemaJSON: "[1,2]")
                )
            )
        }
        do {
            _ = try OpenAICompatibleCodec.encodeResponseFormat(
                StructuredOutputRequest(
                    format: .jsonSchema(name: "Bad", schemaJSON: "not-json")
                )
            )
            Issue.record("expected invalidInput")
        } catch let error as AgentError {
            guard case let .invalidInput(reason) = error else {
                Issue.record("expected invalidInput, got \(error)")
                return
            }
            #expect(reason == "Structured output JSON schema is not a JSON object")
        } catch {
            Issue.record("expected AgentError, got \(error)")
        }
    }

    @Test("Unary invalid JSON data throws the fixed generationFailed reason")
    func unaryInvalidJSONThrowsFixedReason() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        OpenAICompatibleURLProtocol.enqueue(json: "not-json")
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
}
