// OpenTelemetryAnyInferenceProvider.swift
// SwarmOpenTelemetry

import Foundation
@preconcurrency import OpenTelemetryApi
import Swarm

func OpenTelemetryAnyInferenceProvider(
    _ base: any InferenceProvider,
    tracer: any OpenTelemetryApi.Tracer,
    captureContent: Bool
) -> any InferenceProvider {
    let core = OpenTelemetryAnyInferenceProviderCore(
        base: base,
        tracer: tracer,
        captureContent: captureContent
    )

    if base is any ToolCallStreamingConversationInferenceProvider,
       base is any StreamingConversationInferenceProvider,
       base is any StructuredOutputConversationInferenceProvider
    {
        return OpenTelemetryAnyFullConversationToolStreamingInferenceProvider(core: core)
    }

    if base is any ToolCallStreamingConversationInferenceProvider,
       base is any StreamingConversationInferenceProvider
    {
        return OpenTelemetryAnyStreamingConversationToolStreamingInferenceProvider(core: core)
    }

    if base is any ToolCallStreamingConversationInferenceProvider,
       base is any StructuredOutputConversationInferenceProvider
    {
        return OpenTelemetryAnyStructuredConversationToolStreamingInferenceProvider(core: core)
    }

    if base is any ToolCallStreamingConversationInferenceProvider {
        return OpenTelemetryAnyConversationToolStreamingInferenceProvider(core: core)
    }

    if base is any ToolCallStreamingInferenceProvider {
        return OpenTelemetryAnyPromptToolStreamingInferenceProvider(core: core)
    }

    if base is any StreamingConversationInferenceProvider,
       base is any StructuredOutputConversationInferenceProvider
    {
        return OpenTelemetryAnyStreamingStructuredConversationInferenceProvider(core: core)
    }

    if base is any StreamingConversationInferenceProvider {
        return OpenTelemetryAnyStreamingConversationInferenceProvider(core: core)
    }

    if base is any StructuredOutputConversationInferenceProvider {
        return OpenTelemetryAnyStructuredConversationInferenceProvider(core: core)
    }

    if base is any ConversationInferenceProvider {
        return OpenTelemetryAnyConversationInferenceProvider(core: core)
    }

    if base is any StructuredOutputInferenceProvider {
        return OpenTelemetryAnyStructuredInferenceProvider(core: core)
    }

    return OpenTelemetryAnyBaseInferenceProvider(core: core)
}

private final class OpenTelemetryAnyInferenceProviderCore: @unchecked Sendable {
    init(
        base: any InferenceProvider,
        tracer: any OpenTelemetryApi.Tracer,
        captureContent: Bool
    ) {
        self.base = base
        self.tracer = tracer
        self.captureContent = captureContent
    }

    let base: any InferenceProvider
    let tracer: any OpenTelemetryApi.Tracer
    let captureContent: Bool

    var metadata: (any InferenceProviderMetadata)? {
        base as? any InferenceProviderMetadata
    }

    var capabilities: InferenceProviderCapabilities {
        InferenceProviderCapabilities.resolved(for: base)
    }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await withLLMSpan(operation: "chat", inputLength: prompt.count, options: options) { span in
            let response = try await self.base.generate(prompt: prompt, options: options)
            span.setAttribute(key: "gen_ai.response.output_length", value: response.count)
            return response
        }
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        instrumentStream(inputLength: prompt.count, options: options) { continuation, span in
            var outputLength = 0
            for try await token in self.base.stream(prompt: prompt, options: options) {
                outputLength += token.count
                continuation.yield(token)
            }
            span.setAttribute(key: "gen_ai.response.output_length", value: outputLength)
        }
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await withLLMSpan(operation: "chat", inputLength: prompt.count, options: options) { span in
            span.setAttribute(key: "gen_ai.request.tools.count", value: tools.count)
            let response = try await self.base.generateWithToolCalls(prompt: prompt, tools: tools, options: options)
            self.apply(response: response, to: span)
            return response
        }
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await withLLMSpan(operation: "chat", inputLength: Self.inputLength(messages), options: options) { span in
            span.setAttribute(key: "gen_ai.request.messages.count", value: messages.count)
            let response = try await self.base.generate(messages: messages, options: options)
            span.setAttribute(key: "gen_ai.response.output_length", value: response.count)
            return response
        }
    }

    func stream(messages: [InferenceMessage], options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        instrumentStream(inputLength: Self.inputLength(messages), options: options) { continuation, span in
            span.setAttribute(key: "gen_ai.request.messages.count", value: messages.count)
            var outputLength = 0
            for try await token in self.base.stream(messages: messages, options: options) {
                outputLength += token.count
                continuation.yield(token)
            }
            span.setAttribute(key: "gen_ai.response.output_length", value: outputLength)
        }
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await withLLMSpan(operation: "chat", inputLength: Self.inputLength(messages), options: options) { span in
            span.setAttribute(key: "gen_ai.request.messages.count", value: messages.count)
            span.setAttribute(key: "gen_ai.request.tools.count", value: tools.count)
            let response = try await self.base.generateWithToolCalls(
                messages: messages,
                tools: tools,
                options: options
            )
            self.apply(response: response, to: span)
            return response
        }
    }

    func generateStructured(
        prompt: String,
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await withLLMSpan(operation: "chat", inputLength: prompt.count, options: options) { span in
            span.setAttribute(key: "gen_ai.output.type", value: "json")
            let result: StructuredOutputResult
            if let structuredProvider = self.base as? any StructuredOutputInferenceProvider {
                result = try await structuredProvider.generateStructured(
                    prompt: prompt,
                    request: request,
                    options: options
                )
            } else {
                result = try await self.base.generateStructured(prompt: prompt, request: request, options: options)
            }
            span.setAttribute(key: "gen_ai.response.output_length", value: result.rawJSON.count)
            return result
        }
    }

    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await withLLMSpan(operation: "chat", inputLength: Self.inputLength(messages), options: options) { span in
            span.setAttribute(key: "gen_ai.request.messages.count", value: messages.count)
            span.setAttribute(key: "gen_ai.output.type", value: "json")
            let result = try await self.base.generateStructured(
                messages: messages,
                request: request,
                options: options
            )
            span.setAttribute(key: "gen_ai.response.output_length", value: result.rawJSON.count)
            return result
        }
    }

    func streamWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        instrumentToolStream(inputLength: prompt.count, toolCount: tools.count, options: options) {
            guard let toolStreamingProvider = self.base as? any ToolCallStreamingInferenceProvider else {
                throw AgentError.generationFailed(reason: "Provider does not support prompt tool-call streaming")
            }
            return toolStreamingProvider.streamWithToolCalls(prompt: prompt, tools: tools, options: options)
        }
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        instrumentToolStream(inputLength: Self.inputLength(messages), toolCount: tools.count, options: options) {
            self.base.streamWithToolCalls(messages: messages, tools: tools, options: options)
        }
    }

    private static func inputLength(_ messages: [InferenceMessage]) -> Int {
        messages.reduce(0) { $0 + $1.content.count }
    }

    private func withLLMSpan<T: Sendable>(
        operation: String,
        inputLength: Int,
        options: InferenceOptions,
        _ body: @escaping @Sendable (any SpanBase) async throws -> T
    ) async throws -> T {
        let builder = makeSpanBuilder(operation: operation, inputLength: inputLength, options: options)
        return try await builder.withActiveSpan { span in
            try await OpenTelemetryTracePropagation.withCurrentSpan(span) {
                OpenTelemetryAttributes.applyMetadata(metadata, to: span)
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

    private func makeSpanBuilder(
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

    private func apply(response: InferenceResponse, to span: any SpanBase) {
        if let content = response.content {
            span.setAttribute(key: "gen_ai.response.output_length", value: content.count)
        }
        span.setAttribute(key: "gen_ai.response.finish_reasons", value: response.finishReason.rawValue)
        span.setAttribute(key: "gen_ai.response.tool_calls.count", value: response.toolCalls.count)
        OpenTelemetryAttributes.applyUsage(response.usage, to: span)
    }

    private func instrumentStream(
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
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func instrumentToolStream(
        inputLength: Int,
        toolCount: Int,
        options: InferenceOptions,
        makeStream: @escaping @Sendable () throws -> AsyncThrowingStream<InferenceStreamUpdate, Error>
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await withLLMSpan(operation: "chat", inputLength: inputLength, options: options) { span in
                        span.setAttribute(key: "gen_ai.request.tools.count", value: toolCount)
                        var outputLength = 0
                        var completedToolCallCount = 0
                        var usage: TokenUsage?
                        for try await update in try makeStream() {
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
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

private struct OpenTelemetryAnyBaseInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
    var providerName: String? { core.metadata?.providerName }
    var modelName: String? { core.metadata?.modelName }
    var endpointURL: URL? { core.metadata?.endpointURL }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await core.generate(prompt: prompt, options: options)
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(prompt: prompt, options: options)
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await core.generate(messages: messages, options: options)
    }

    func stream(messages: [InferenceMessage], options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(messages: messages, options: options)
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        core.streamWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await core.generateStructured(messages: messages, request: request, options: options)
    }
}

private struct OpenTelemetryAnyStructuredInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    StructuredOutputInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
    var providerName: String? { core.metadata?.providerName }
    var modelName: String? { core.metadata?.modelName }
    var endpointURL: URL? { core.metadata?.endpointURL }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await core.generate(prompt: prompt, options: options)
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(prompt: prompt, options: options)
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    func generateStructured(
        prompt: String,
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await core.generateStructured(prompt: prompt, request: request, options: options)
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await core.generate(messages: messages, options: options)
    }

    func stream(messages: [InferenceMessage], options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(messages: messages, options: options)
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        core.streamWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await core.generateStructured(messages: messages, request: request, options: options)
    }
}

private struct OpenTelemetryAnyConversationInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    ConversationInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
    var providerName: String? { core.metadata?.providerName }
    var modelName: String? { core.metadata?.modelName }
    var endpointURL: URL? { core.metadata?.endpointURL }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await core.generate(prompt: prompt, options: options)
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(prompt: prompt, options: options)
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await core.generate(messages: messages, options: options)
    }

    func stream(messages: [InferenceMessage], options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(messages: messages, options: options)
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(messages: messages, tools: tools, options: options)
    }
}

private struct OpenTelemetryAnyStreamingConversationInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    ConversationInferenceProvider,
    StreamingConversationInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
    var providerName: String? { core.metadata?.providerName }
    var modelName: String? { core.metadata?.modelName }
    var endpointURL: URL? { core.metadata?.endpointURL }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await core.generate(prompt: prompt, options: options)
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(prompt: prompt, options: options)
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await core.generate(messages: messages, options: options)
    }

    func stream(messages: [InferenceMessage], options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(messages: messages, options: options)
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(messages: messages, tools: tools, options: options)
    }
}

private struct OpenTelemetryAnyStructuredConversationInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    ConversationInferenceProvider,
    StructuredOutputConversationInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
    var providerName: String? { core.metadata?.providerName }
    var modelName: String? { core.metadata?.modelName }
    var endpointURL: URL? { core.metadata?.endpointURL }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await core.generate(prompt: prompt, options: options)
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(prompt: prompt, options: options)
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await core.generate(messages: messages, options: options)
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await core.generateStructured(messages: messages, request: request, options: options)
    }
}

private struct OpenTelemetryAnyStreamingStructuredConversationInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    ConversationInferenceProvider,
    StreamingConversationInferenceProvider,
    StructuredOutputConversationInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
    var providerName: String? { core.metadata?.providerName }
    var modelName: String? { core.metadata?.modelName }
    var endpointURL: URL? { core.metadata?.endpointURL }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await core.generate(prompt: prompt, options: options)
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(prompt: prompt, options: options)
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await core.generate(messages: messages, options: options)
    }

    func stream(messages: [InferenceMessage], options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(messages: messages, options: options)
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await core.generateStructured(messages: messages, request: request, options: options)
    }
}

private struct OpenTelemetryAnyPromptToolStreamingInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    ToolCallStreamingInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
    var providerName: String? { core.metadata?.providerName }
    var modelName: String? { core.metadata?.modelName }
    var endpointURL: URL? { core.metadata?.endpointURL }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await core.generate(prompt: prompt, options: options)
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(prompt: prompt, options: options)
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    func streamWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        core.streamWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await core.generate(messages: messages, options: options)
    }

    func stream(messages: [InferenceMessage], options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(messages: messages, options: options)
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        core.streamWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await core.generateStructured(messages: messages, request: request, options: options)
    }
}

private struct OpenTelemetryAnyConversationToolStreamingInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    ConversationInferenceProvider,
    ToolCallStreamingConversationInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
    var providerName: String? { core.metadata?.providerName }
    var modelName: String? { core.metadata?.modelName }
    var endpointURL: URL? { core.metadata?.endpointURL }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await core.generate(prompt: prompt, options: options)
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(prompt: prompt, options: options)
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await core.generate(messages: messages, options: options)
    }

    func stream(messages: [InferenceMessage], options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(messages: messages, options: options)
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func streamWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        core.streamWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        core.streamWithToolCalls(messages: messages, tools: tools, options: options)
    }
}

private struct OpenTelemetryAnyStreamingConversationToolStreamingInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    ConversationInferenceProvider,
    StreamingConversationInferenceProvider,
    ToolCallStreamingConversationInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
    var providerName: String? { core.metadata?.providerName }
    var modelName: String? { core.metadata?.modelName }
    var endpointURL: URL? { core.metadata?.endpointURL }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await core.generate(prompt: prompt, options: options)
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(prompt: prompt, options: options)
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await core.generate(messages: messages, options: options)
    }

    func stream(messages: [InferenceMessage], options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(messages: messages, options: options)
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        core.streamWithToolCalls(messages: messages, tools: tools, options: options)
    }
}

private struct OpenTelemetryAnyStructuredConversationToolStreamingInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    ConversationInferenceProvider,
    ToolCallStreamingConversationInferenceProvider,
    StructuredOutputConversationInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
    var providerName: String? { core.metadata?.providerName }
    var modelName: String? { core.metadata?.modelName }
    var endpointURL: URL? { core.metadata?.endpointURL }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await core.generate(prompt: prompt, options: options)
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(prompt: prompt, options: options)
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await core.generate(messages: messages, options: options)
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        core.streamWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await core.generateStructured(messages: messages, request: request, options: options)
    }
}

private struct OpenTelemetryAnyFullConversationToolStreamingInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    ConversationInferenceProvider,
    StreamingConversationInferenceProvider,
    ToolCallStreamingConversationInferenceProvider,
    StructuredOutputConversationInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
    var providerName: String? { core.metadata?.providerName }
    var modelName: String? { core.metadata?.modelName }
    var endpointURL: URL? { core.metadata?.endpointURL }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await core.generate(prompt: prompt, options: options)
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(prompt: prompt, options: options)
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await core.generate(messages: messages, options: options)
    }

    func stream(messages: [InferenceMessage], options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(messages: messages, options: options)
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        core.streamWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await core.generateStructured(messages: messages, request: request, options: options)
    }
}
