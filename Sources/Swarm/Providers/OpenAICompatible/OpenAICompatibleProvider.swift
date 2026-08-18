// OpenAICompatibleProvider.swift
// Swarm Framework
//
// OpenAI-compatible remote inference provider (URLSession only).

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Remote inference provider for OpenAI-compatible Chat Completions APIs.
///
/// Talks to OpenAI, Azure OpenAI, OpenRouter, Ollama, LM Studio, and any other
/// host that implements `/v1/chat/completions`. Uses `URLSession` only — no
/// extra package dependencies.
///
/// ## What is sent
///
/// Prompt text, tool schemas, tool results, and structured-output schemas leave
/// the device. Contrast with ``FoundationModelsInferenceProvider``, which stays
/// on-device when Apple Intelligence is available.
///
/// ## Capabilities
///
/// - Structured ``InferenceMessage`` history (roles, `tool_calls`, `tool_call_id`)
/// - Function calling via ``ToolSchema``
/// - SSE streaming, including incremental tool-call argument deltas
/// - Token usage from `usage.prompt_tokens` / `usage.completion_tokens`
///   (`stream_options.include_usage` is requested when streaming)
/// - Structured outputs: native `response_format` when
///   ``OpenAICompatibleStructuredOutputMode/nativeJSONSchema`` is set;
///   otherwise labeled prompt-parse fallback
/// - W3C `traceparent` / `tracestate` via ``TraceContextHeaders/applyCurrent(to:)``
///
/// ```swift
/// let agent = try Agent(
///     "Be helpful.",
///     inferenceProvider: .openAICompatible(.ollama(model: "llama3.2"))
/// )
/// ```
///
/// Inject a `URLSession` with a `URLProtocol` stub in tests.
public struct OpenAICompatibleProvider: InferenceProvider,
    ToolCallStreamingInferenceProvider,
    StructuredOutputInferenceProvider,
    InferenceProviderMetadata
{
    /// Provider configuration (endpoint, model, auth, structured-output mode).
    public let configuration: OpenAICompatibleProviderConfiguration

    /// `URLSession` is thread-safe. swift-corelibs-foundation does not mark it
    /// `Sendable`, so the session is stored in this box.
    private let sessionBox: SessionBox

    /// Creates a provider.
    ///
    /// - Parameters:
    ///   - configuration: Endpoint, model, and auth.
    ///   - session: Session used for POST requests. Inject a `URLProtocol`
    ///     stub in tests. Default: `URLSession.shared`.
    public init(
        configuration: OpenAICompatibleProviderConfiguration,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.sessionBox = SessionBox(session)
    }

    // MARK: - Metadata

    public var providerName: String? { configuration.providerName }
    public var modelName: String? { configuration.model }
    public var endpointURL: URL? { configuration.baseURL }

    public var capabilities: InferenceProviderCapabilities {
        [
            .conversationMessages,
            .nativeToolCalling,
            .streamingToolCalls,
            .structuredOutputs,
        ]
    }

    // MARK: - InferenceProvider

    public func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await generate(messages: [.user(prompt)], options: options)
    }

    public func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        stream(messages: [.user(prompt)], options: options)
    }

    public func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await generateWithToolCalls(messages: [.user(prompt)], tools: tools, options: options)
    }

    public func streamWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        streamWithToolCalls(messages: [.user(prompt)], tools: tools, options: options)
    }

    // MARK: - ConversationInferenceProvider

    public func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        let response = try await generateWithToolCalls(messages: messages, tools: [], options: options)
        return response.content ?? ""
    }

    public func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await complete(
            messages: messages,
            tools: tools,
            options: options,
            structuredOutput: options.structuredOutput
        )
    }

    // MARK: - Streaming

    public func stream(
        messages: [InferenceMessage],
        options: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        // Unbounded: `streamCompletions` already holds the full SSE body and
        // yields every event before the consumer may start iterating. A
        // newest-100 buffer would drop the oldest tokens on long replies.
        StreamHelper.makeTrackedStream(bufferingPolicy: .unbounded) { continuation in
            do {
                for try await update in self.streamWithToolCalls(
                    messages: messages,
                    tools: [],
                    options: options
                ) {
                    if case let .outputChunk(chunk) = update, !chunk.isEmpty {
                        continuation.yield(chunk)
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: OpenAICompatibleErrorMapper.mapTransport(error))
            }
        }
    }

    public func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        StreamHelper.makeTrackedStream(bufferingPolicy: .unbounded) { continuation in
            do {
                try await self.streamCompletions(
                    messages: messages,
                    tools: tools,
                    options: options,
                    structuredOutput: options.structuredOutput,
                    continuation: continuation
                )
                continuation.finish()
            } catch {
                continuation.finish(throwing: OpenAICompatibleErrorMapper.mapTransport(error))
            }
        }
    }

    // MARK: - Structured outputs

    public func generateStructured(
        prompt: String,
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await generateStructured(messages: [.user(prompt)], request: request, options: options)
    }

    public func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        switch configuration.structuredOutputMode {
        case .nativeJSONSchema:
            do {
                _ = try OpenAICompatibleCodec.encodeResponseFormat(request)
            } catch {
                return try await promptFallbackStructured(
                    messages: messages,
                    request: request,
                    options: options
                )
            }
            let response = try await complete(
                messages: messages,
                tools: [],
                options: options,
                structuredOutput: request
            )
            return try StructuredOutputParser.parse(
                response.content ?? "",
                request: request,
                source: .providerNative
            )
        case .promptFallback:
            return try await promptFallbackStructured(
                messages: messages,
                request: request,
                options: options
            )
        }
    }

    // MARK: - HTTP

    private func complete(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        structuredOutput: StructuredOutputRequest?
    ) async throws -> InferenceResponse {
        let request = try OpenAICompatibleCodec.makeRequest(
            configuration: configuration,
            messages: messages,
            tools: tools,
            options: options,
            stream: false,
            structuredOutput: structuredOutput
        )
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await sessionBox.session.data(for: request)
        } catch {
            throw OpenAICompatibleErrorMapper.mapTransport(error)
        }
        try Task.checkCancellation()
        let http = try httpResponse(response)
        if http.statusCode >= 400 {
            throw OpenAICompatibleErrorMapper.map(
                statusCode: http.statusCode,
                body: data,
                headers: http.allHeaderFields,
                model: configuration.model
            )
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.generationFailed(reason: "OpenAI-compatible response is not a JSON object")
        }
        return try OpenAICompatibleCodec.inferenceResponse(from: OpenAICompatibleChatChunk(json: object))
    }

    private func streamCompletions(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        structuredOutput: StructuredOutputRequest?,
        continuation: AsyncThrowingStream<InferenceStreamUpdate, Error>.Continuation
    ) async throws {
        let request = try OpenAICompatibleCodec.makeRequest(
            configuration: configuration,
            messages: messages,
            tools: tools,
            options: options,
            stream: true,
            structuredOutput: structuredOutput
        )

        // `data(for:)` is used instead of `bytes(for:)` so URLProtocol stubs
        // (and swift-corelibs-foundation) deliver the SSE body reliably.
        // Events are still yielded in wire order after the body arrives.
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await sessionBox.session.data(for: request)
        } catch {
            throw OpenAICompatibleErrorMapper.mapTransport(error)
        }

        let http = try httpResponse(response)
        if http.statusCode >= 400 {
            throw OpenAICompatibleErrorMapper.map(
                statusCode: http.statusCode,
                body: data,
                headers: http.allHeaderFields,
                model: configuration.model
            )
        }

        var parser = OpenAICompatibleSSEParser()
        var accumulator = OpenAICompatibleStreamAccumulator()
        var finished = false
        let text = String(data: data, encoding: .utf8) ?? ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for line in lines {
            try Task.checkCancellation()
            let events = parser.consume(line: line)
            if try emit(events, accumulator: &accumulator, continuation: continuation) {
                finished = true
                break
            }
        }

        if !finished {
            _ = try emit(parser.finish(), accumulator: &accumulator, continuation: continuation)
            for update in accumulator.finish() {
                continuation.yield(update)
            }
        }
    }

    private func emit(
        _ events: [OpenAICompatibleSSEEvent],
        accumulator: inout OpenAICompatibleStreamAccumulator,
        continuation: AsyncThrowingStream<InferenceStreamUpdate, Error>.Continuation
    ) throws -> Bool {
        for event in events {
            switch event {
            case let .chunk(chunk):
                if let message = chunk.errorMessage {
                    throw AgentError.generationFailed(reason: message)
                }
                if let error = chunkError(chunk) {
                    throw error
                }
                for update in accumulator.consume(chunk) {
                    continuation.yield(update)
                }
            case .done:
                for update in accumulator.finish() {
                    continuation.yield(update)
                }
                return true
            case .malformed:
                continue
            }
        }
        return false
    }

    private func chunkError(_ chunk: OpenAICompatibleChatChunk) -> AgentError? {
        for choice in chunk.choices where choice.finishReason == "content_filter" {
            return .contentFiltered(reason: "OpenAI-compatible content filter")
        }
        return nil
    }

    private func promptFallbackStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        let structuredMessages = StructuredOutputPromptBuilder.appendInstruction(
            to: messages,
            request: request
        )
        let text = try await generate(messages: structuredMessages, options: options)
        return try StructuredOutputParser.parse(text, request: request, source: .promptFallback)
    }

    private func httpResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw AgentError.generationFailed(reason: "OpenAI-compatible endpoint returned a non-HTTP response")
        }
        return http
    }
}

// MARK: - Session box

extension OpenAICompatibleProvider {
    fileprivate final class SessionBox: @unchecked Sendable {
        let session: URLSession

        init(_ session: URLSession) {
            self.session = session
        }
    }
}

// MARK: - Dot-syntax entry points

public extension InferenceProvider where Self == OpenAICompatibleProvider {
    /// Creates an OpenAI-compatible remote provider.
    ///
    /// - Parameters:
    ///   - configuration: Endpoint, model, and auth. Use the convenience
    ///     factories on ``OpenAICompatibleProviderConfiguration`` for OpenAI,
    ///     Azure OpenAI, OpenRouter, Ollama, and LM Studio.
    ///   - session: Session used for POST requests. Default: `URLSession.shared`.
    static func openAICompatible(
        _ configuration: OpenAICompatibleProviderConfiguration,
        session: URLSession = .shared
    ) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(configuration: configuration, session: session)
    }

    /// Creates an OpenAI-compatible remote provider from raw fields.
    static func openAICompatible(
        baseURL: URL,
        model: String,
        apiKey: String? = nil,
        httpHeaders: [String: String] = [:],
        structuredOutputMode: OpenAICompatibleStructuredOutputMode = .nativeJSONSchema,
        session: URLSession = .shared
    ) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            configuration: OpenAICompatibleProviderConfiguration(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                httpHeaders: httpHeaders,
                structuredOutputMode: structuredOutputMode
            ),
            session: session
        )
    }
}
