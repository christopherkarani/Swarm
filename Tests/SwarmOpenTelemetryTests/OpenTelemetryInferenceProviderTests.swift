import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import Testing
import Swarm
@testable import SwarmOpenTelemetry

private struct PromptOnlyProvider: InferenceProvider {
    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        prompt
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await generate(prompt: messages.map(\.content).joined(separator: "\n"), options: options)
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        _ = toolExecutor
        return InferenceResponse(content: try await generate(messages: messages, options: options))
    }
}

private struct ToolStreamingProvider: InferenceProvider {
    var capabilities: InferenceProviderCapabilities { [.streamingToolCalls] }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        messages.map(\.content).joined(separator: "\n")
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        _ = toolExecutor
        return InferenceResponse(content: try await generate(messages: messages, options: options))
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        _ = toolExecutor
        let prompt = messages.map(\.content).joined(separator: "\n")
        return AsyncThrowingStream { continuation in
            continuation.yield(.outputChunk(prompt))
            continuation.finish()
        }
    }
}

private struct TwoLLMCallAgent: AgentRuntime {
    let provider: any InferenceProvider

    var tools: [any AnyJSONTool] { [] }
    var instructions: String { "test" }
    var configuration: AgentConfiguration { .default.name("two-call-agent") }
    var inferenceProvider: (any InferenceProvider)? { provider }

    func run(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) async throws -> AgentResult {
        let provider = AgentEnvironmentValues.current.inferenceProviderTransform?(provider) ?? provider
        _ = try await provider.generate(prompt: input, options: .default)
        _ = try await provider.generate(prompt: "\(input) again", options: .default)
        return AgentResult(output: "done", iterationCount: 1)
    }

    func stream(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func cancel() async {}
}

private final class RecordingSpanExporter: SpanExporter, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SpanData] = []

    var spans: [SpanData] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        lock.lock()
        storage.append(contentsOf: spans)
        lock.unlock()
        return .success
    }

    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        .success
    }

    func shutdown(explicitTimeout: TimeInterval?) {}
}

@Test("OpenTelemetry wrapper does not add unsupported tool streaming")
func openTelemetryWrapperDoesNotAddUnsupportedToolStreaming() {
    let wrapped = OpenTelemetryInferenceProvider(PromptOnlyProvider())

    #expect(!wrapped.capabilities.contains(.streamingToolCalls))
}

@Test("OpenTelemetry wrapper preserves supported tool streaming")
func openTelemetryWrapperPreservesSupportedToolStreaming() {
    let wrapped = OpenTelemetryInferenceProvider(ToolStreamingProvider())
    let provider: any InferenceProvider = wrapped

    #expect(provider.capabilities.contains(.streamingToolCalls))
    #expect(wrapped.capabilities.contains(.streamingToolCalls))
}

@Test("Raw provider OpenTelemetry instrumentation is public API")
func rawProviderOpenTelemetryInstrumentationIsPublicAPI() async throws {
    let provider = PromptOnlyProvider().instrumentedWithOpenTelemetry()

    let output = try await provider.generate(prompt: "hello", options: .default)

    #expect(output == "hello")
}

@Test("Erased OpenTelemetry wrapper preserves prompt-only tool streaming shape")
func erasedOpenTelemetryWrapperPreservesPromptOnlyToolStreamingShape() {
    let wrapped = OpenTelemetryAnyInferenceProvider(
        ToolStreamingProvider(),
        tracer: OpenTelemetry.instance.tracerProvider.get(instrumentationName: "test.llm"),
        captureContent: false
    )

    #expect(wrapped.capabilities.contains(.streamingToolCalls))
    #expect(InferenceProviderCapabilities.resolved(for: wrapped).contains(.conversationMessages))
    #expect(InferenceProviderCapabilities.resolved(for: wrapped).contains(.streamingToolCalls))
}

@Test("Erased OpenTelemetry wrapper forwards prompt tool streaming")
func erasedOpenTelemetryWrapperForwardsPromptToolStreaming() async throws {
    let wrapped = OpenTelemetryAnyInferenceProvider(
        PromptOnlyProvider(),
        tracer: OpenTelemetry.instance.tracerProvider.get(instrumentationName: "test.llm"),
        captureContent: false
    )

    var chunks: [String] = []
    for try await update in wrapped.streamWithToolCalls(prompt: "hello", tools: [], options: .default) {
        if case let .outputChunk(chunk) = update {
            chunks.append(chunk)
        }
    }

    #expect(chunks == ["hello"])
    #expect(wrapped.promptTokenCounter == nil)
}

@Test("Agent OpenTelemetry wrapper creates one parent trace for multiple LLM calls")
func agentOpenTelemetryWrapperCreatesOneParentTraceForMultipleLLMCalls() async throws {
    let exporter = RecordingSpanExporter()
    let tracerProvider = TracerProviderBuilder()
        .add(
            spanProcessor: SimpleSpanProcessor(spanExporter: exporter)
                .reportingOnlySampled(sampled: false)
        )
        .build()

    let agent = TwoLLMCallAgent(provider: PromptOnlyProvider())
        .instrumentedWithOpenTelemetry(
            tracer: tracerProvider.get(instrumentationName: "test.agent"),
            llmTracer: tracerProvider.get(instrumentationName: "test.llm")
        )

    _ = try await agent.run("hello")
    tracerProvider.forceFlush()

    let spans = exporter.spans
    let agentSpan = try #require(spans.first { $0.name == "swarm.agent.run two-call-agent" })
    let llmSpans = spans.filter { $0.name == "chat llm" }

    #expect(llmSpans.count == 2)
    #expect(llmSpans.allSatisfy { $0.traceId == agentSpan.traceId })
    #expect(llmSpans.allSatisfy { $0.parentSpanId == agentSpan.spanId })
}

@Test("Inference metadata snapshot exposes non-sensitive provider fields")
func inferenceMetadataSnapshotExposesProviderFields() {
    let endpoint = URL(string: "https://api.example.com/v1")
    let metadata = InferenceProviderMetadataSnapshot(
        providerName: "example",
        modelName: "example-model",
        endpointURL: endpoint
    )

    #expect(metadata.providerName == "example")
    #expect(metadata.modelName == "example-model")
    #expect(metadata.endpointURL == endpoint)
}

@Test("OTel wrapper forwards messages")
func openTelemetryWrapperForwardsMessages() async throws {
    let recorded = RecordedMessageCalls()
    let provider = RolePreservingProvider(recorded: recorded).instrumentedWithOpenTelemetry()

    try await assertRoleTaggedHistoryReachesBase(provider)
    #expect(recorded.all.allSatisfy { $0 == sampleConversationHistory })
}

@Test("Erased OTel wrapper forwards structured messages")
func erasedOpenTelemetryWrapperForwardsStructuredMessages() async throws {
    let recorded = RecordedMessageCalls()
    let provider = OpenTelemetryAnyInferenceProvider(
        RolePreservingStructuredProvider(recorded: recorded),
        tracer: OpenTelemetry.instance.tracerProvider.get(instrumentationName: "test.llm"),
        captureContent: false
    )

    try await assertRoleTaggedHistoryReachesBase(provider)
    #expect(recorded.all.allSatisfy { $0 == sampleConversationHistory })
}

@Test("Erased OTel wrapper forwards tool-streaming messages")
func erasedOpenTelemetryWrapperForwardsToolStreamingMessages() async throws {
    let recorded = RecordedMessageCalls()
    let provider = OpenTelemetryAnyInferenceProvider(
        RolePreservingToolStreamingProvider(recorded: recorded),
        tracer: OpenTelemetry.instance.tracerProvider.get(instrumentationName: "test.llm"),
        captureContent: false
    )

    #expect(provider.capabilities.contains(.streamingToolCalls))
    try await assertRoleTaggedHistoryReachesBase(provider)
    #expect(recorded.all.allSatisfy { $0 == sampleConversationHistory })
}

private let sampleConversationHistory: [InferenceMessage] = [
    .system("be terse"),
    .user("hello"),
    .assistant("hi"),
    .user("again"),
]

private func assertRoleTaggedHistoryReachesBase(_ provider: any InferenceProvider) async throws {
    let output = try await provider.generate(messages: sampleConversationHistory, options: .default)
    #expect(output == "ok")

    let toolResponse = try await provider.generateWithToolCalls(
        messages: sampleConversationHistory,
        tools: [],
        options: .default
    )
    #expect(toolResponse.content == "ok")

    var streamed = ""
    for try await token in provider.stream(messages: sampleConversationHistory, options: .default) {
        streamed += token
    }
    #expect(streamed == "ok")

    var toolStreamed = ""
    for try await update in provider.streamWithToolCalls(
        messages: sampleConversationHistory,
        tools: [],
        options: .default
    ) {
        if case let .outputChunk(chunk) = update {
            toolStreamed += chunk
        }
    }
    #expect(toolStreamed == "ok")

    let structured = try await provider.generateStructured(
        messages: sampleConversationHistory,
        request: StructuredOutputRequest(format: .jsonObject),
        options: .default
    )
    #expect(structured.rawJSON == "{}")
}

private final class RecordedMessageCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [[InferenceMessage]] = []

    func record(_ messages: [InferenceMessage]) {
        lock.lock()
        storage.append(messages)
        lock.unlock()
    }

    var all: [[InferenceMessage]] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private struct RolePreservingProvider: InferenceProvider {
    let recorded: RecordedMessageCalls

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await generate(messages: [.user(prompt)], options: options)
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        stream(messages: [.user(prompt)], options: options)
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await generateWithToolCalls(messages: [.user(prompt)], tools: tools, options: options)
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        recorded.record(messages)
        return "ok"
    }

    func stream(
        messages: [InferenceMessage],
        options: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        recorded.record(messages)
        return AsyncThrowingStream { continuation in
            continuation.yield("ok")
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        recorded.record(messages)
        return InferenceResponse(content: "ok")
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        recorded.record(messages)
        return AsyncThrowingStream { continuation in
            continuation.yield(.outputChunk("ok"))
            continuation.finish()
        }
    }

    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        recorded.record(messages)
        return StructuredOutputResult(
            format: request.format,
            rawJSON: "{}",
            value: .dictionary([:]),
            source: .promptFallback
        )
    }
}

private struct RolePreservingStructuredProvider: InferenceProvider {
    let inner: RolePreservingProvider

    init(recorded: RecordedMessageCalls) {
        inner = RolePreservingProvider(recorded: recorded)
    }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await inner.generate(prompt: prompt, options: options)
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        inner.stream(prompt: prompt, options: options)
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await inner.generateWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await inner.generate(messages: messages, options: options)
    }

    func stream(
        messages: [InferenceMessage],
        options: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        inner.stream(messages: messages, options: options)
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await inner.generateWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        inner.streamWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func generateStructured(
        prompt: String,
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await generateStructured(messages: [.user(prompt)], request: request, options: options)
    }

    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await inner.generateStructured(messages: messages, request: request, options: options)
    }
}

private struct RolePreservingToolStreamingProvider: InferenceProvider {
    var capabilities: InferenceProviderCapabilities { [.streamingToolCalls] }
    let inner: RolePreservingProvider

    init(recorded: RecordedMessageCalls) {
        inner = RolePreservingProvider(recorded: recorded)
    }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await inner.generate(prompt: prompt, options: options)
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        inner.stream(prompt: prompt, options: options)
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await inner.generateWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await inner.generate(messages: messages, options: options)
    }

    func stream(
        messages: [InferenceMessage],
        options: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        inner.stream(messages: messages, options: options)
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await inner.generateWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func streamWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        streamWithToolCalls(messages: [.user(prompt)], tools: tools, options: options)
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        inner.streamWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await inner.generateStructured(messages: messages, request: request, options: options)
    }
}
