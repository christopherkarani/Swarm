// OpenTelemetryInferenceProvider.swift
// SwarmOpenTelemetry

import Foundation
@preconcurrency import OpenTelemetryApi
import Swarm

/// An inference-provider wrapper that emits OpenTelemetry GenAI spans.
///
/// Advanced provider protocols are exposed through conditional conformances, so
/// wrapping a provider does not advertise capabilities the underlying provider
/// cannot actually satisfy.
public struct OpenTelemetryInferenceProvider<Base: InferenceProvider>: @unchecked Sendable,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata
{
    public init(
        _ base: Base,
        tracer: any OpenTelemetryApi.Tracer = OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: "swarm.llm",
            instrumentationVersion: nil
        ),
        captureContent: Bool = false
    ) {
        self.base = base
        self.tracer = tracer
        self.captureContent = captureContent
    }

    public var capabilities: InferenceProviderCapabilities {
        InferenceProviderCapabilities.resolved(for: base)
    }

    public var providerName: String? {
        metadata?.providerName
    }

    public var modelName: String? {
        metadata?.modelName
    }

    public var endpointURL: URL? {
        metadata?.endpointURL
    }

    public func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await withLLMSpan(operation: "chat", inputLength: prompt.count, options: options) { span in
            let response = try await base.generate(prompt: prompt, options: options)
            span.setAttribute(key: "gen_ai.response.output_length", value: response.count)
            return response
        }
    }

    public func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        instrumentStream(inputLength: prompt.count, options: options) { continuation, span in
            var outputLength = 0
            for try await token in base.stream(prompt: prompt, options: options) {
                outputLength += token.count
                continuation.yield(token)
            }
            span.setAttribute(key: "gen_ai.response.output_length", value: outputLength)
        }
    }

    public func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await withLLMSpan(operation: "chat", inputLength: prompt.count, options: options) { span in
            span.setAttribute(key: "gen_ai.request.tools.count", value: tools.count)
            let response = try await base.generateWithToolCalls(prompt: prompt, tools: tools, options: options)
            apply(response: response, to: span)
            return response
        }
    }

    public func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await withLLMSpan(operation: "chat", inputLength: Self.inputLength(messages), options: options) { span in
            span.setAttribute(key: "gen_ai.request.messages.count", value: messages.count)
            let response = try await base.generate(messages: messages, options: options)
            span.setAttribute(key: "gen_ai.response.output_length", value: response.count)
            return response
        }
    }

    public func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await withLLMSpan(operation: "chat", inputLength: Self.inputLength(messages), options: options) { span in
            span.setAttribute(key: "gen_ai.request.messages.count", value: messages.count)
            span.setAttribute(key: "gen_ai.request.tools.count", value: tools.count)
            let response = try await base.generateWithToolCalls(messages: messages, tools: tools, options: options)
            apply(response: response, to: span)
            return response
        }
    }

    public func stream(
        messages: [InferenceMessage],
        options: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        instrumentStream(inputLength: Self.inputLength(messages), options: options) { continuation, span in
            span.setAttribute(key: "gen_ai.request.messages.count", value: messages.count)
            var outputLength = 0
            for try await token in base.stream(messages: messages, options: options) {
                outputLength += token.count
                continuation.yield(token)
            }
            span.setAttribute(key: "gen_ai.response.output_length", value: outputLength)
        }
    }

    public func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        instrumentToolStream(inputLength: Self.inputLength(messages), toolCount: tools.count, options: options) {
            base.streamWithToolCalls(messages: messages, tools: tools, options: options)
        }
    }

    public func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await withLLMSpan(operation: "chat", inputLength: Self.inputLength(messages), options: options) { span in
            span.setAttribute(key: "gen_ai.request.messages.count", value: messages.count)
            span.setAttribute(key: "gen_ai.output.type", value: "json")
            let result = try await base.generateStructured(messages: messages, request: request, options: options)
            span.setAttribute(key: "gen_ai.response.output_length", value: result.rawJSON.count)
            return result
        }
    }

    fileprivate let base: Base
    fileprivate let tracer: any OpenTelemetryApi.Tracer
    fileprivate let captureContent: Bool

    fileprivate var metadata: (any InferenceProviderMetadata)? {
        base as? any InferenceProviderMetadata
    }
}

extension OpenTelemetryInferenceProvider: ConversationInferenceProvider where Base: ConversationInferenceProvider {}

extension OpenTelemetryInferenceProvider: StreamingConversationInferenceProvider where Base: StreamingConversationInferenceProvider {}

extension OpenTelemetryInferenceProvider: ToolCallStreamingInferenceProvider where Base: ToolCallStreamingInferenceProvider {
  public func streamWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        instrumentToolStream(inputLength: prompt.count, toolCount: tools.count, options: options) {
            base.streamWithToolCalls(prompt: prompt, tools: tools, options: options)
        }
    }
}

extension OpenTelemetryInferenceProvider: ToolCallStreamingConversationInferenceProvider
where Base: ToolCallStreamingConversationInferenceProvider {}

extension OpenTelemetryInferenceProvider: StructuredOutputInferenceProvider where Base: StructuredOutputInferenceProvider {
  public func generateStructured(
        prompt: String,
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await withLLMSpan(operation: "chat", inputLength: prompt.count, options: options) { span in
            span.setAttribute(key: "gen_ai.output.type", value: "json")
            let result = try await base.generateStructured(prompt: prompt, request: request, options: options)
            span.setAttribute(key: "gen_ai.response.output_length", value: result.rawJSON.count)
            return result
        }
    }
}

extension OpenTelemetryInferenceProvider: StructuredOutputConversationInferenceProvider
where Base: StructuredOutputConversationInferenceProvider {}

private extension OpenTelemetryInferenceProvider {
    static func inputLength(_ messages: [InferenceMessage]) -> Int {
        messages.reduce(0) { $0 + $1.content.count }
    }

    func withLLMSpan<T: Sendable>(
        operation: String,
        inputLength: Int,
        options: InferenceOptions,
        _ body: @escaping @Sendable (any SpanBase) async throws -> T
    ) async throws -> T {
        let builder = makeSpanBuilder(operation: operation, inputLength: inputLength, options: options)
        return try await builder.withActiveSpan { span in
            try await OpenTelemetryTracePropagation.withCurrentSpan(span) {
                prepare(span: span)
                do {
                    let result = try await body(span)
                    span.status = .ok
                    return result
                } catch {
                    OpenTelemetryAttributes.recordError(error, on: span)
                    throw error
                }
            }
        }
    }

    func makeSpanBuilder(
        operation: String,
        inputLength: Int,
        options: InferenceOptions
    ) -> any SpanBuilder {
        let builder = tracer.spanBuilder(spanName: "\(operation) \(metadata?.modelName ?? "llm")")
        builder.setSpanKind(spanKind: .client)
        builder.setAttribute(key: "gen_ai.operation.name", value: operation)
        builder.setAttribute(key: "gen_ai.request.input_length", value: inputLength)
        builder.setAttribute(key: "gen_ai.request.temperature", value: options.temperature)
        if let maxTokens = options.maxTokens {
            builder.setAttribute(key: "gen_ai.request.max_tokens", value: maxTokens)
        }
        if captureContent {
            builder.setAttribute(key: "swarm.capture_content.enabled", value: true)
        }
        return builder
    }

    func prepare(span: any SpanBase) {
        OpenTelemetryAttributes.applyMetadata(metadata, to: span)
    }

    func apply(response: InferenceResponse, to span: any SpanBase) {
        if let content = response.content {
            span.setAttribute(key: "gen_ai.response.output_length", value: content.count)
        }
        span.setAttribute(key: "gen_ai.response.finish_reasons", value: response.finishReason.rawValue)
        span.setAttribute(key: "gen_ai.response.tool_calls.count", value: response.toolCalls.count)
        OpenTelemetryAttributes.applyUsage(response.usage, to: span)
    }

    func instrumentStream(
        inputLength: Int,
        options: InferenceOptions,
        body: @escaping @Sendable (AsyncThrowingStream<String, Error>.Continuation, any SpanBase) async throws -> Void
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await withLLMSpan(operation: "chat", inputLength: inputLength, options: options) { span in
                        try await body(continuation, span)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func instrumentToolStream(
        inputLength: Int,
        toolCount: Int,
        options: InferenceOptions,
        makeStream: @escaping @Sendable () -> AsyncThrowingStream<InferenceStreamUpdate, Error>
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await withLLMSpan(operation: "chat", inputLength: inputLength, options: options) { span in
                        span.setAttribute(key: "gen_ai.request.tools.count", value: toolCount)
                        var outputLength = 0
                        var completedToolCallCount = 0
                        var usage: TokenUsage?
                        for try await update in makeStream() {
                            switch update {
                            case let .outputChunk(chunk):
                                outputLength += chunk.count
                            case let .toolCallsCompleted(calls):
                                completedToolCallCount = calls.count
                            case let .usage(tokenUsage):
                                usage = tokenUsage
                            case .toolCallPartial:
                                break
                            }
                            continuation.yield(update)
                        }
                        span.setAttribute(key: "gen_ai.response.output_length", value: outputLength)
                        span.setAttribute(key: "gen_ai.response.tool_calls.count", value: completedToolCallCount)
                        OpenTelemetryAttributes.applyUsage(usage, to: span)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

protocol OpenTelemetryInstrumentedInferenceProvider {}

extension OpenTelemetryInferenceProvider: OpenTelemetryInstrumentedInferenceProvider {}

public extension InferenceProvider {
    /// Wraps this provider so each LLM request emits an OpenTelemetry GenAI span.
    func instrumentedWithOpenTelemetry(
        tracer: any OpenTelemetryApi.Tracer = OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: "swarm.llm",
            instrumentationVersion: nil
        ),
        captureContent: Bool = false
    ) -> some InferenceProvider {
        OpenTelemetryInferenceProvider(
            self,
            tracer: tracer,
            captureContent: captureContent
        )
    }
}
