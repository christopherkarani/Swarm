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
    InferenceProviderMetadata
{
    /// Provider configuration (endpoint, model, auth, structured-output mode).
    public let configuration: OpenAICompatibleProviderConfiguration

    /// Session used for POST requests.
    private let session: URLSession

    /// Backend resolving `configuration.apiKeyReference`, if any.
    private let secretStore: (any SecretStore)?

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
        self.secretStore = nil
        self.session = session
    }

    /// Creates a provider that resolves `configuration.apiKeyReference`.
    ///
    /// When the configuration carries an inline ``OpenAICompatibleProviderConfiguration/apiKey``
    /// it is used as-is; otherwise the reference is loaded from `secretStore`
    /// on every request. Use ``KeychainSecretStore`` on Apple platforms so the
    /// raw key never sits in persisted configuration.
    ///
    /// - Parameters:
    ///   - configuration: Endpoint, model, and auth.
    ///   - secretStore: Backend holding the referenced secret.
    ///   - session: Session used for POST requests. Inject a `URLProtocol`
    ///     stub in tests. Default: `URLSession.shared`.
    public init(
        configuration: OpenAICompatibleProviderConfiguration,
        secretStore: any SecretStore,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.secretStore = secretStore
        self.session = session
    }

    // MARK: - Metadata

    public var providerName: String? { configuration.providerName }
    public var modelName: String? { configuration.model }
    public var endpointURL: URL? { configuration.baseURL }

    public var capabilities: InferenceProviderCapabilities {
        var bits: InferenceProviderCapabilities = [
            .conversationMessages,
            .nativeToolCalling,
            .streamingToolCalls,
            .structuredOutputs,
        ]
        if configuration.supportsMultimodalAudio {
            bits.insert(.multimodalAudio)
        }
        return bits
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
        try await generateWithToolCalls(
            messages: [.user(prompt)],
            tools: tools,
            options: options,
            toolExecutor: nil
        )
    }

    public func streamWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        streamWithToolCalls(messages: [.user(prompt)], tools: tools, options: options)
    }

    // MARK: - Structured message inference

    public func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        let response = try await generateWithToolCalls(
            messages: messages,
            tools: [],
            options: options,
            toolExecutor: nil
        )
        return response.content ?? ""
    }

    public func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await generateWithToolCalls(
            messages: messages,
            tools: tools,
            options: options,
            toolExecutor: nil
        )
    }

    public func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        _ = toolExecutor
        return try await complete(
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
        // Unbounded: `streamCompletions` can yield events faster than the
        // consumer iterates (on Linux it replays a fully buffered body). A
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
        options: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        _ = toolExecutor
        return StreamHelper.makeTrackedStream(bufferingPolicy: .unbounded) { continuation in
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

    private func effectiveConfiguration() async throws -> OpenAICompatibleProviderConfiguration {
        var effective = configuration
        if effective.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            effective.apiKey = try await configuration.resolveAPIKey(using: secretStore)
        }
        return effective
    }

    private func complete(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        structuredOutput: StructuredOutputRequest?
    ) async throws -> InferenceResponse {
        let configuration = try await effectiveConfiguration()
        let request = try OpenAICompatibleCodec.makeRequest(
            configuration: configuration,
            messages: messages,
            tools: tools,
            options: options,
            stream: false,
            structuredOutput: structuredOutput,
            capabilities: capabilities
        )
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
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
        let chunk: OpenAICompatibleChatChunk
        do {
            chunk = try OpenAICompatibleChatChunk(decoding: data)
        } catch {
            throw AgentError.generationFailed(reason: "OpenAI-compatible response is not a JSON object")
        }
        return try OpenAICompatibleCodec.inferenceResponse(from: chunk)
    }

    private func streamCompletions(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        structuredOutput: StructuredOutputRequest?,
        continuation: AsyncThrowingStream<InferenceStreamUpdate, Error>.Continuation
    ) async throws {
        let configuration = try await effectiveConfiguration()
        let request = try OpenAICompatibleCodec.makeRequest(
            configuration: configuration,
            messages: messages,
            tools: tools,
            options: options,
            stream: true,
            structuredOutput: structuredOutput,
            capabilities: capabilities
        )

        var state = SSEStreamState()
        #if canImport(FoundationNetworking)
        // swift-corelibs-foundation has no reliable `URLSession.bytes(for:)`,
        // so Linux downloads the whole SSE body and then replays it line by
        // line. Events keep wire order but arrive only after the body ends.
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenAICompatibleErrorMapper.mapTransport(error)
        }
        try requireSuccess(response, body: data, model: configuration.model)
        for byte in data {
            if try consume(byte, state: &state, continuation: continuation) {
                return
            }
        }
        #else
        // `bytes(for:)` yields SSE lines as they arrive, so tokens reach the
        // caller while the model is still generating.
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw OpenAICompatibleErrorMapper.mapTransport(error)
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let body = try await Self.collectErrorBody(from: bytes)
            try requireSuccess(response, body: body, model: configuration.model)
        }
        _ = try httpResponse(response)
        do {
            for try await byte in bytes {
                if try consume(byte, state: &state, continuation: continuation) {
                    return
                }
            }
        } catch {
            throw OpenAICompatibleErrorMapper.mapTransport(error)
        }
        #endif

        if let line = try state.lineBuffer.flush(),
           try emit(state.parser.consume(line: line), accumulator: &state.accumulator, continuation: continuation)
        {
            return
        }
        _ = try emit(state.parser.finish(), accumulator: &state.accumulator, continuation: continuation)
        for update in state.accumulator.finish() {
            continuation.yield(update)
        }
    }

    /// Feeds one body byte; returns `true` once `[DONE]` has been emitted.
    private func consume(
        _ byte: UInt8,
        state: inout SSEStreamState,
        continuation: AsyncThrowingStream<InferenceStreamUpdate, Error>.Continuation
    ) throws -> Bool {
        guard let line = try state.lineBuffer.append(byte) else {
            return false
        }
        try Task.checkCancellation()
        return try emit(state.parser.consume(line: line), accumulator: &state.accumulator, continuation: continuation)
    }

    private func requireSuccess(_ response: URLResponse, body: Data, model: String) throws {
        let http = try httpResponse(response)
        if http.statusCode >= 400 {
            throw OpenAICompatibleErrorMapper.map(
                statusCode: http.statusCode,
                body: body,
                headers: http.allHeaderFields,
                model: model
            )
        }
    }

    #if !canImport(FoundationNetworking)
    /// Reads an error body for status mapping, capped so a misbehaving server
    /// cannot stream an unbounded error page into memory.
    private static func collectErrorBody(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var body = Data()
        do {
            for try await byte in bytes {
                body.append(byte)
                if body.count >= maxErrorBodyBytes {
                    break
                }
            }
        } catch {
            throw OpenAICompatibleErrorMapper.mapTransport(error)
        }
        return body
    }

    private static let maxErrorBodyBytes = 64 * 1024
    #endif

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

// MARK: - SSE stream state

extension OpenAICompatibleProvider {
    /// Parser and accumulator state for one SSE response.
    fileprivate struct SSEStreamState {
        var lineBuffer = OpenAICompatibleSSELineBuffer()
        var parser = OpenAICompatibleSSEParser()
        var accumulator = OpenAICompatibleStreamAccumulator()
    }
}

/// Splits an SSE byte stream into strictly decoded UTF-8 lines.
///
/// Lines are split on LF bytes before decoding. LF never occurs inside a
/// multi-byte UTF-8 sequence, so a character split across network chunks is
/// still decoded whole.
struct OpenAICompatibleSSELineBuffer: Sendable {
    private var pending: [UInt8] = []

    /// Appends one byte. Returns the completed line, without its LF, when
    /// `byte` ends a line.
    ///
    /// - Throws: ``AgentError/generationFailed(reason:)`` when the line is not
    ///   valid UTF-8.
    mutating func append(_ byte: UInt8) throws -> String? {
        guard byte == UInt8(ascii: "\n") else {
            pending.append(byte)
            return nil
        }
        return try takeLine()
    }

    /// Returns a trailing line that was not terminated by LF, if any.
    mutating func flush() throws -> String? {
        pending.isEmpty ? nil : try takeLine()
    }

    private mutating func takeLine() throws -> String {
        defer { pending.removeAll(keepingCapacity: true) }
        guard let line = String(validating: pending, as: UTF8.self) else {
            throw AgentError.generationFailed(reason: "OpenAI-compatible stream is not valid UTF-8")
        }
        return line
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

    /// Creates an OpenAI-compatible remote provider that resolves
    /// `configuration.apiKeyReference` from `secretStore` on every request.
    ///
    /// - Parameters:
    ///   - configuration: Endpoint, model, and auth.
    ///   - secretStore: Backend holding the referenced secret.
    ///   - session: Session used for POST requests. Default: `URLSession.shared`.
    static func openAICompatible(
        _ configuration: OpenAICompatibleProviderConfiguration,
        secretStore: any SecretStore,
        session: URLSession = .shared
    ) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(configuration: configuration, secretStore: secretStore, session: session)
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
