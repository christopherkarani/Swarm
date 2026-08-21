import Foundation
import Testing
@testable import Swarm

@Suite("InferenceProvider capability dispatch", .ephemeralDefaultStores)
struct InferenceProviderCapabilityDispatchTests {

    @Test("Agent uses InferenceProvider.promptTokenCounter instead of leftover protocol identity")
    func agentUsesProviderPromptTokenCounterProperty() async throws {
        let providerCounter = RecordingPromptTokenCounter()
        let environmentCounter = RecordingPromptTokenCounter()
        let provider = TokenPropertyProvider(counter: providerCounter)
        let agent = try Agent(
            instructions: "Reply briefly.",
            configuration: AgentConfiguration(contextMode: .strict4k, defaultTracingEnabled: false),
            inferenceProvider: provider
        ).promptTokenCounter(environmentCounter)

        _ = try await agent.run("Hello")

        #expect(await providerCounter.callCount > 0)
        #expect(await environmentCounter.callCount == 0)
    }

    @Test("Agent keeps the environment heuristic counter when promptTokenCounter is nil")
    func agentKeepsEnvironmentCounterWhenProviderHasNone() async throws {
        let environmentCounter = RecordingPromptTokenCounter()
        let provider = TextStubProvider()
        let agent = try Agent(
            instructions: "Reply briefly.",
            configuration: AgentConfiguration(contextMode: .strict4k, defaultTracingEnabled: false),
            inferenceProvider: provider
        ).promptTokenCounter(environmentCounter)

        _ = try await agent.run("Hello")

        #expect(await environmentCounter.callCount > 0)
        #expect(provider.promptTokenCounter == nil)
    }

    @Test("Native generateStructured(messages:) works without StructuredOutputInferenceProvider")
    func nativeStructuredPromptOverrideDoesNotNeedLeftoverProtocol() async throws {
        let structuredResult = StructuredOutputResult(
            format: .jsonObject,
            rawJSON: #"{"answer":"native-property"}"#,
            value: .dictionary(["answer": .string("native-property")]),
            source: .providerNative
        )
        let provider = NativeStructuredPromptProvider(result: structuredResult)
        let agent = try Agent(
            instructions: "Return structured JSON.",
            inferenceProvider: provider
        )
        let request = StructuredOutputRequest(format: .jsonObject)

        let result = try await agent.runStructured("Return native JSON.", request: request)

        #expect(result.structuredOutput.source == .providerNative)
        #expect(result.structuredOutput.rawJSON == structuredResult.rawJSON)
        #expect(await provider.structuredCallCount() == 1)
        #expect(!(provider is any StructuredOutputInferenceProvider))
    }

    @Test("Advertising structuredOutputs without an override still uses prompt fallback")
    func structuredBitWithoutOverrideUsesPromptFallback() async throws {
        let provider = StructuredBitWithoutOverrideProvider()
        let agent = try Agent(
            instructions: "Return structured JSON.",
            inferenceProvider: provider
        )
        let request = StructuredOutputRequest(format: .jsonObject)

        let result = try await agent.runStructured("Return a JSON answer.", request: request)

        #expect(result.structuredOutput.source == .promptFallback)
        #expect(provider.capabilities.contains(.structuredOutputs))
    }

    @Test("Agent does not take live streaming when the bit is unset even if leftover protocol remains")
    func unsetStreamingBitIgnoresLeftoverProtocol() async throws {
        let provider = LeftoverStreamingWithoutBitProvider(generateResponses: Self.echoThenDoneResponses)
        let agent = try Agent(
            tools: [CapabilityDispatchEchoTool()],
            configuration: .default.maxIterations(3),
            inferenceProvider: provider
        )

        var sawPartial = false
        for try await event in agent.stream("Hi") {
            if case .tool(.partial) = event {
                sawPartial = true
            }
        }

        #expect(sawPartial == false)
        #expect(provider.promptStreamCallCount() == 0)
        #expect(provider.generateCallCount() == 2)
    }

    @Test("Lying streamingToolCalls bit still generate-then-emits without partials")
    func streamingBitWithoutOverrideGenerateThenEmits() async throws {
        let provider = StreamingBitWithoutOverrideProvider(generateResponses: Self.echoThenDoneResponses)
        let agent = try Agent(
            tools: [CapabilityDispatchEchoTool()],
            configuration: .default.maxIterations(3),
            inferenceProvider: provider
        )

        var sawPartial = false
        var completedOutput: String?
        for try await event in agent.stream("Hi") {
            if case .tool(.partial) = event {
                sawPartial = true
            }
            if case let .lifecycle(.completed(result: result)) = event {
                completedOutput = result.output
            }
        }

        #expect(sawPartial == false)
        #expect(completedOutput == "All done")
        #expect(provider.generateCallCount() == 2)
    }

    @Test("Providers expose observability metadata through the defaulted requirement")
    func providersSurfaceMetadataWithoutLeftoverCasts() throws {
        let carrier = MetadataCarrierProvider(
            metadata: InferenceProviderMetadataSnapshot(
                providerName: "example",
                modelName: "example-model",
                endpointURL: URL(string: "https://api.example.com/v1")
            )
        )
        let provider: any InferenceProvider = carrier

        #expect(TextStubProvider().metadata == nil)

        let resolvedMetadata = try #require(provider.metadata)
        #expect(resolvedMetadata.providerName == "example")
        #expect(resolvedMetadata.modelName == "example-model")
        #expect(resolvedMetadata.endpointURL == URL(string: "https://api.example.com/v1"))
    }

    @Test("MultiProvider forwards the resolved child's metadata")
    func multiProviderForwardsResolvedChildMetadata() async throws {
        let defaultProvider = MetadataCarrierProvider(
            metadata: InferenceProviderMetadataSnapshot(providerName: "default", modelName: nil, endpointURL: nil)
        )
        let childProvider = MetadataCarrierProvider(
            metadata: InferenceProviderMetadataSnapshot(
                providerName: "child",
                modelName: "child-model",
                endpointURL: nil
            )
        )

        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        let initialMetadata = try #require(await multiProvider.metadata)
        #expect(initialMetadata.providerName == "default")

        try await multiProvider.register(prefix: "child", provider: childProvider)
        await multiProvider.setModel("child/child-model")

        let routedMetadata = try #require(await multiProvider.metadata)
        #expect(routedMetadata.providerName == "child")
        #expect(routedMetadata.modelName == "child-model")

        await multiProvider.unregister(prefix: "child")
        let afterUnregisterMetadata = try #require(await multiProvider.metadata)
        #expect(afterUnregisterMetadata.providerName == "default")

        await multiProvider.clearModel()
        let fallbackMetadata = try #require(await multiProvider.metadata)
        #expect(fallbackMetadata.providerName == "default")
    }

    private static let echoThenDoneResponses: [InferenceResponse] = [
        InferenceResponse(
            content: nil,
            toolCalls: [
                .init(id: "call_1", name: "echo", arguments: ["text": .string("hi")]),
            ],
            finishReason: .toolCall
        ),
        InferenceResponse(content: "All done", finishReason: .completed),
    ]
}

private struct CapabilityDispatchEchoTool: AnyJSONTool, Sendable {
    let name = "echo"
    let description = "Echoes the input text"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "text", description: "Text to echo", type: .string),
    ]

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        .string(try requiredString("text", from: arguments))
    }
}

private actor RecordingPromptTokenCounter: PromptTokenCounter {
    private(set) var callCount = 0

    func countTokens(in text: String) async throws -> Int {
        callCount += 1
        return max(1, text.count)
    }
}

private struct TextStubProvider: InferenceProvider, MessagesFromPromptInference {
    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        "ok"
    }

    func stream(prompt _: String, options _: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("ok")
            continuation.finish()
        }
    }
}

private struct TokenPropertyProvider: InferenceProvider, MessagesFromPromptInference {
    let counter: RecordingPromptTokenCounter

    var promptTokenCounter: (any PromptTokenCounter)? { counter }

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        "ok"
    }

    func stream(prompt _: String, options _: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("ok")
            continuation.finish()
        }
    }
}

private struct MetadataCarrierProvider: InferenceProvider, MessagesFromPromptInference {
    var metadata: (any InferenceProviderMetadata)?

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        "ok"
    }

    func stream(prompt _: String, options _: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("ok")
            continuation.finish()
        }
    }
}

private actor NativeStructuredPromptProvider: InferenceProvider, MessagesFromPromptInference {
    nonisolated let capabilities: InferenceProviderCapabilities = [.structuredOutputs]
    private let result: StructuredOutputResult
    private var structuredCalls = 0

    init(result: StructuredOutputResult) {
        self.result = result
    }

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        result.rawJSON
    }

    nonisolated func stream(prompt _: String, options _: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: AgentError.internalError(reason: "Unexpected streaming call"))
        }
    }

    func generateStructured(
        messages _: [InferenceMessage],
        request _: StructuredOutputRequest,
        options _: InferenceOptions
    ) async throws -> StructuredOutputResult {
        structuredCalls += 1
        return result
    }

    func structuredCallCount() -> Int {
        structuredCalls
    }
}

private struct StructuredBitWithoutOverrideProvider: InferenceProvider, MessagesFromPromptInference {
    var capabilities: InferenceProviderCapabilities { [.structuredOutputs] }

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        #"{"answer":"ok"}"#
    }

    func stream(prompt _: String, options _: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(#"{"answer":"ok"}"#)
            continuation.finish()
        }
    }
}

private final class GenerateScriptBox: @unchecked Sendable {
    private let lock = NSLock()
    private var generateResponses: [InferenceResponse]
    private var generateIndex = 0
    private var promptStreamCalls = 0

    init(generateResponses: [InferenceResponse]) {
        self.generateResponses = generateResponses
    }

    func nextGenerateResponse() -> InferenceResponse {
        lock.lock()
        defer { lock.unlock() }
        let response = generateResponses[min(generateIndex, generateResponses.count - 1)]
        generateIndex += 1
        return response
    }

    func recordPromptStream() {
        lock.lock()
        promptStreamCalls += 1
        lock.unlock()
    }

    func promptStreamCallCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return promptStreamCalls
    }

    func generateCallCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return generateIndex
    }
}

private struct LeftoverStreamingWithoutBitProvider: ToolCallStreamingInferenceProvider, MessagesFromPromptInference {
    nonisolated let capabilities: InferenceProviderCapabilities = []
    private let script: GenerateScriptBox

    init(generateResponses: [InferenceResponse]) {
        script = GenerateScriptBox(generateResponses: generateResponses)
    }

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        throw AgentError.generationFailed(reason: "Unexpected generate()")
    }

    func stream(prompt _: String, options _: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.finish(throwing: AgentError.generationFailed(reason: "Unexpected stream()"))
        }
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        script.nextGenerateResponse()
    }

    func generateWithToolCalls(
        prompt _: String,
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        script.nextGenerateResponse()
    }

    func streamWithToolCalls(
        prompt _: String,
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        script.recordPromptStream()
        return StreamHelper.makeTrackedStream { continuation in
            continuation.yield(
                .toolCallPartial(
                    PartialToolCallUpdate(
                        providerCallId: "call_1",
                        toolName: "echo",
                        index: 0,
                        argumentsFragment: #"{"text":"hi"}"#
                    )
                )
            )
            continuation.yield(
                .toolCallsCompleted([
                    .init(id: "call_1", name: "echo", arguments: ["text": .string("hi")]),
                ])
            )
            continuation.finish()
        }
    }

    func promptStreamCallCount() -> Int {
        script.promptStreamCallCount()
    }

    func generateCallCount() -> Int {
        script.generateCallCount()
    }
}

private struct StreamingBitWithoutOverrideProvider: InferenceProvider, MessagesFromPromptInference {
    nonisolated let capabilities: InferenceProviderCapabilities = [.streamingToolCalls]
    private let script: GenerateScriptBox

    init(generateResponses: [InferenceResponse]) {
        script = GenerateScriptBox(generateResponses: generateResponses)
    }

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        throw AgentError.generationFailed(reason: "Unexpected generate()")
    }

    func stream(prompt _: String, options _: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.finish(throwing: AgentError.generationFailed(reason: "Unexpected stream()"))
        }
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        script.nextGenerateResponse()
    }

    func generateCallCount() -> Int {
        script.generateCallCount()
    }
}
