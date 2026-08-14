import Foundation
import Testing
@testable import Swarm

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("OpenAI-compatible provider request and response shape")
struct OpenAICompatibleProviderTests {
    private let endpoint = URL(string: "https://api.example.test/v1")!

    @Test("Chat request maps messages, tools, stream flags, and Bearer auth")
    func chatRequestMapsMessagesToolsStreamAndAuth() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        OpenAICompatibleURLProtocol.enqueue(json: Self.completionJSON(content: "hello", prompt: 9, completion: 3))

        let session = OpenAICompatibleURLProtocol.makeSession()
        let provider = OpenAICompatibleProvider(
            configuration: OpenAICompatibleProviderConfiguration(
                baseURL: endpoint,
                apiKey: "sk-test",
                model: "gpt-test",
                httpHeaders: ["X-Custom": "swarm"]
            ),
            session: session
        )

        let messages: [InferenceMessage] = [
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
        ]
        let tools = [
            ToolSchema(
                name: "echo",
                description: "Echo text",
                parameters: [
                    ToolParameter(name: "text", description: "Text to echo", type: .string),
                ]
            ),
        ]

        let response = try await provider.generateWithToolCalls(
            messages: messages,
            tools: tools,
            options: .default.temperature(0.2).maxTokens(64).toolChoice(.auto)
        )

        #expect(response.content == "hello")
        #expect(response.usage == TokenUsage(inputTokens: 9, outputTokens: 3))

        let recorded = try #require(OpenAICompatibleURLProtocol.requests.first)
        #expect(recorded.url?.absoluteString == "https://api.example.test/v1/chat/completions")
        #expect(recorded.headers["Authorization"] == "Bearer sk-test")
        #expect(recorded.headers["X-Custom"] == "swarm")
        #expect(recorded.headers["Content-Type"] == "application/json")

        let body = try OpenAICompatibleJSON.object(from: recorded.body)
        #expect(body["model"] as? String == "gpt-test")
        #expect(body["temperature"] as? Double == 0.2)
        #expect(body["max_tokens"] as? Int == 64)
        #expect(body["stream"] == nil)
        #expect(body["tool_choice"] as? String == "auto")

        let encodedMessages = try #require(body["messages"] as? [[String: Any]])
        #expect(encodedMessages.count == 4)
        #expect(encodedMessages[0]["role"] as? String == "system")
        #expect(encodedMessages[2]["role"] as? String == "assistant")
        let toolCalls = try #require(encodedMessages[2]["tool_calls"] as? [[String: Any]])
        #expect(toolCalls[0]["id"] as? String == "call_1")
        #expect(encodedMessages[3]["role"] as? String == "tool")
        #expect(encodedMessages[3]["tool_call_id"] as? String == "call_1")

        let encodedTools = try #require(body["tools"] as? [[String: Any]])
        let function = try #require(encodedTools[0]["function"] as? [String: Any])
        #expect(function["name"] as? String == "echo")
    }

    @Test("Streaming request sets stream and include_usage")
    func streamingRequestSetsStreamFlags() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        OpenAICompatibleURLProtocol.enqueueSSE(
            """
            data: {"choices":[{"delta":{"content":"Hi"}}]}

            data: {"choices":[{"delta":{}}],"usage":{"prompt_tokens":4,"completion_tokens":1}}

            data: [DONE]

            """
        )

        let provider = OpenAICompatibleProvider(
            configuration: .init(baseURL: endpoint, apiKey: "sk-test", model: "gpt-test"),
            session: OpenAICompatibleURLProtocol.makeSession()
        )

        var chunks: [String] = []
        var usage: TokenUsage?
        for try await update in provider.streamWithToolCalls(
            messages: [.user("Hi")],
            tools: [],
            options: .default
        ) {
            switch update {
            case let .outputChunk(text):
                chunks.append(text)
            case let .usage(value):
                usage = value
            default:
                break
            }
        }

        #expect(chunks == ["Hi"])
        #expect(usage == TokenUsage(inputTokens: 4, outputTokens: 1))

        let body = try OpenAICompatibleJSON.object(
            from: #require(OpenAICompatibleURLProtocol.requests.first).body
        )
        #expect(body["stream"] as? Bool == true)
        let streamOptions = try #require(body["stream_options"] as? [String: Any])
        #expect(streamOptions["include_usage"] as? Bool == true)
    }

    @Test("Injects current W3C trace-context headers")
    func injectsTraceContextHeaders() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        OpenAICompatibleURLProtocol.enqueue(json: Self.completionJSON(content: "ok"))

        let headers = try #require(
            TraceContextHeaders(
                traceparent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
                tracestate: "rojo=00f067aa0ba902b7"
            )
        )
        let provider = OpenAICompatibleProvider(
            configuration: .init(baseURL: endpoint, apiKey: "sk-test", model: "gpt-test"),
            session: OpenAICompatibleURLProtocol.makeSession()
        )

        _ = try await TraceContextHeaders.withCurrent(headers) {
            try await provider.generate(messages: [.user("ping")], options: .default)
        }

        let recorded = try #require(OpenAICompatibleURLProtocol.requests.first)
        #expect(recorded.headers["traceparent"] == headers.traceparent)
        #expect(recorded.headers["tracestate"] == "rojo=00f067aa0ba902b7")
    }

    @Test("Native structured output sends response_format and labels providerNative")
    func nativeStructuredOutputUsesResponseFormat() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        OpenAICompatibleURLProtocol.enqueue(json: Self.completionJSON(content: #"{"ok":true}"#))

        let provider = OpenAICompatibleProvider(
            configuration: .init(
                baseURL: endpoint,
                model: "gpt-test",
                structuredOutputMode: .nativeJSONSchema
            ),
            session: OpenAICompatibleURLProtocol.makeSession()
        )
        let request = StructuredOutputRequest(
            format: .jsonSchema(name: "Status", schemaJSON: #"{"type":"object","properties":{"ok":{"type":"boolean"}}}"#)
        )
        let result = try await provider.generateStructured(
            messages: [.user("status")],
            request: request,
            options: .default
        )

        #expect(result.source == .providerNative)
        #expect(result.value["ok"]?.boolValue == true)

        let body = try OpenAICompatibleJSON.object(
            from: #require(OpenAICompatibleURLProtocol.requests.first).body
        )
        let format = try #require(body["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
    }

    @Test("Prompt-fallback structured output omits response_format and labels promptFallback")
    func promptFallbackStructuredOutputIsHonest() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        OpenAICompatibleURLProtocol.enqueue(json: Self.completionJSON(content: #"{"ok":true}"#))

        let provider = OpenAICompatibleProvider(
            configuration: .ollama(model: "llama3.2", baseURL: endpoint),
            session: OpenAICompatibleURLProtocol.makeSession()
        )
        let result = try await provider.generateStructured(
            messages: [.user("status")],
            request: StructuredOutputRequest(format: .jsonObject),
            options: .default
        )

        #expect(result.source == .promptFallback)
        let body = try OpenAICompatibleJSON.object(
            from: #require(OpenAICompatibleURLProtocol.requests.first).body
        )
        #expect(body["response_format"] == nil)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.contains { ($0["content"] as? String)?.contains("valid JSON") == true })
    }

    @Test("Azure convenience factory uses api-key and api-version")
    func azureConvenienceFactoryUsesApiKeyAndVersion() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        OpenAICompatibleURLProtocol.enqueue(json: Self.completionJSON(content: "ok"))

        let configuration = OpenAICompatibleProviderConfiguration.azureOpenAI(
            resource: "contoso",
            deployment: "gpt-4o",
            apiKey: "azure-key"
        )
        let provider = OpenAICompatibleProvider(
            configuration: configuration,
            session: OpenAICompatibleURLProtocol.makeSession()
        )
        _ = try await provider.generate(messages: [.user("hi")], options: .default)

        let recorded = try #require(OpenAICompatibleURLProtocol.requests.first)
        #expect(recorded.headers["api-key"] == "azure-key")
        #expect(recorded.headers["Authorization"] == nil)
        #expect(recorded.url?.absoluteString.contains("/openai/deployments/gpt-4o/chat/completions") == true)
        #expect(recorded.url?.absoluteString.contains("api-version=2024-10-21") == true)
    }

    @Test("Does not send Bearer when apiKey is omitted")
    func omitsBearerWhenAPIKeyMissing() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        OpenAICompatibleURLProtocol.enqueue(json: Self.completionJSON(content: "ok"))

        let provider = OpenAICompatibleProvider(
            configuration: .ollama(model: "llama3.2", baseURL: endpoint),
            session: OpenAICompatibleURLProtocol.makeSession()
        )
        _ = try await provider.generate(messages: [.user("hi")], options: .default)

        let recorded = try #require(OpenAICompatibleURLProtocol.requests.first)
        #expect(recorded.headers["Authorization"] == nil)
    }

    @Test("Omits response_format when tools are present on a structured turn")
    func omitsResponseFormatWhenToolsArePresent() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        OpenAICompatibleURLProtocol.enqueue(json: Self.completionJSON(content: #"{"ok":true}"#))

        let provider = OpenAICompatibleProvider(
            configuration: .init(
                baseURL: endpoint,
                model: "gpt-test",
                structuredOutputMode: .nativeJSONSchema
            ),
            session: OpenAICompatibleURLProtocol.makeSession()
        )
        var options = InferenceOptions.default
        options.structuredOutput = StructuredOutputRequest(
            format: .jsonSchema(name: "Status", schemaJSON: #"{"type":"object"}"#)
        )
        _ = try await provider.generateWithToolCalls(
            messages: [.user("status")],
            tools: [
                ToolSchema(name: "echo", description: "Echo", parameters: []),
            ],
            options: options
        )

        let body = try OpenAICompatibleJSON.object(
            from: #require(OpenAICompatibleURLProtocol.requests.first).body
        )
        #expect(body["tools"] != nil)
        #expect(body["response_format"] == nil)
    }

    @Test("Correlates tool_call_id from the prior assistant call when the result omits it")
    func correlatesToolCallIDFromAssistantCall() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        OpenAICompatibleURLProtocol.enqueue(json: Self.completionJSON(content: "done"))

        let provider = OpenAICompatibleProvider(
            configuration: .init(baseURL: endpoint, model: "gpt-test"),
            session: OpenAICompatibleURLProtocol.makeSession()
        )
        _ = try await provider.generateWithToolCalls(
            messages: [
                .user("add"),
                .assistant(
                    "",
                    toolCalls: [
                        InferenceMessage.ToolCall(
                            id: "call_add",
                            name: "add",
                            arguments: ["a": .int(2)]
                        ),
                    ]
                ),
                .tool(name: "add", content: "5"),
            ],
            tools: [
                ToolSchema(name: "add", description: "Add", parameters: []),
            ],
            options: .default
        )

        let body = try OpenAICompatibleJSON.object(
            from: #require(OpenAICompatibleURLProtocol.requests.first).body
        )
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages[2]["tool_call_id"] as? String == "call_add")
        #expect(messages[2]["tool_call_id"] as? String != "add")
    }

    @Test("Reports conversation, tool, streaming, and structured capabilities")
    func reportsExpectedCapabilities() {
        let provider = OpenAICompatibleProvider(
            configuration: .openAI(apiKey: "sk", model: "gpt-4o")
        )
        #expect(provider.capabilities.contains(.conversationMessages))
        #expect(provider.capabilities.contains(.nativeToolCalling))
        #expect(provider.capabilities.contains(.streamingToolCalls))
        #expect(provider.capabilities.contains(.structuredOutputs))
        #expect(provider.capabilities.contains(.privateInference) == false)
        #expect(provider.providerName == "openai")
        #expect(provider.modelName == "gpt-4o")
    }

    private static func completionJSON(content: String, prompt: Int = 1, completion: Int = 1) -> String {
        """
        {
          "choices": [
            {
              "index": 0,
              "message": { "role": "assistant", "content": \(encode(content)) },
              "finish_reason": "stop"
            }
          ],
          "usage": { "prompt_tokens": \(prompt), "completion_tokens": \(completion) }
        }
        """
    }

    private static func encode(_ string: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed])
        return String(data: data ?? Data("\"\"".utf8), encoding: .utf8) ?? "\"\""
    }
}
