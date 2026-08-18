// FoundationModelsExecutionModeTests.swift
//
// Flag defaulting and non-FM providers ignoring native session mode.

import Foundation
@testable import Swarm
import Testing

@Suite("FoundationModels Execution Mode")
struct FoundationModelsExecutionModeTests {
    @Test("Capture remains the AgentConfiguration default")
    func captureIsDefault() {
        #expect(AgentConfiguration.default.foundationModelsExecution == .capture)
        #expect(AgentConfiguration().foundationModelsExecution == .capture)
    }

    @Test("Non-FM providers ignore nativeSession and keep the Swarm tool loop")
    func nonFMProvidersIgnoreNativeFlag() async throws {
        let spy = MockTool(
            name: "test_tool",
            description: "Test tool",
            parameters: [ToolParameter(name: "location", description: "Location", type: .string)],
            result: .string("Tool result")
        )
        let mockProvider = MockInferenceProvider()
        await mockProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_123",
                        name: "test_tool",
                        arguments: ["location": .string("NYC")]
                    ),
                ],
                finishReason: .toolCall
            ),
            InferenceResponse(
                content: "Done",
                toolCalls: [],
                finishReason: .completed
            ),
        ])

        let config = AgentConfiguration.default
            .foundationModelsExecution(.nativeSession)
            .defaultTracingEnabled(false)
        let agent = try Agent(
            tools: [spy],
            instructions: "You are a helpful assistant.",
            configuration: config,
            inferenceProvider: mockProvider
        )

        let result = try await agent.run("Use the tool")
        #expect(result.output == "Done")
        #expect(result.toolCalls.count == 1)

        let recorded = await mockProvider.toolCallMessageCalls
        #expect(recorded.count == 2)
    }

    @Test("Native session with MockInferenceProvider records the messages seam")
    func nativeSessionWithMockRecordsMessageSeam() async throws {
        let spy = MockTool(
            name: "test_tool",
            description: "Test tool",
            parameters: [ToolParameter(name: "location", description: "Location", type: .string)],
            result: .string("Tool result")
        )
        let mockProvider = MockInferenceProvider()
        await mockProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_123",
                        name: "test_tool",
                        arguments: ["location": .string("NYC")]
                    ),
                ],
                finishReason: .toolCall
            ),
            InferenceResponse(
                content: "Done",
                toolCalls: [],
                finishReason: .completed
            ),
        ])

        let config = AgentConfiguration.default
            .foundationModelsExecution(.nativeSession)
            .defaultTracingEnabled(false)
        let agent = try Agent(
            tools: [spy],
            instructions: "You are a helpful assistant.",
            configuration: config,
            inferenceProvider: mockProvider
        )

        let result = try await agent.run("Use the tool")
        #expect(result.output == "Done")

        let recorded = await mockProvider.toolCallMessageCalls
        #expect(!recorded.isEmpty)
        #expect(await mockProvider.toolCallCalls.isEmpty)
        #expect(await mockProvider.generateCalls.isEmpty)
    }

    @Test("Finished native-mode response does not start a second model call")
    func nativeSessionFinishedTurnDoesNotIterate() async throws {
        let spy = MockTool(
            name: "test_tool",
            description: "Test tool",
            parameters: [ToolParameter(name: "location", description: "Location", type: .string)],
            result: .string("unused")
        )
        let mockProvider = MockInferenceProvider()
        await mockProvider.setToolCallResponses([
            InferenceResponse(
                content: "already finished",
                toolCalls: [],
                finishReason: .completed
            ),
        ])

        let config = AgentConfiguration.default
            .foundationModelsExecution(.nativeSession)
            .defaultTracingEnabled(false)
        let agent = try Agent(
            tools: [spy],
            instructions: "You are a helpful assistant.",
            configuration: config,
            inferenceProvider: mockProvider
        )

        let result = try await agent.run("Answer without tools")
        #expect(result.output == "already finished")
        #expect(result.toolCalls.isEmpty)
        #expect(await mockProvider.toolCallMessageCalls.count == 1)
    }

    @Test("Native session with no tools still hits generateWithToolCalls")
    func nativeSessionWithoutToolsUsesToolCallMessageSeam() async throws {
        let mockProvider = MockInferenceProvider(responses: ["plain text"])
        let config = AgentConfiguration.default
            .foundationModelsExecution(.nativeSession)
            .defaultTracingEnabled(false)
        let agent = try Agent(
            tools: [],
            instructions: "Be brief.",
            configuration: config,
            inferenceProvider: mockProvider
        )

        let result = try await agent.run("Hello")
        #expect(result.output == "plain text")
        #expect(await mockProvider.toolCallMessageCalls.count == 1)
        #expect(await mockProvider.generateMessageCalls.isEmpty)
        #expect(await mockProvider.generateCalls.isEmpty)
    }

    @Test("Native session copies the provider-owned tool loop onto the environment")
    func nativeSessionCopiesProviderOwnedToolLoopOntoEnvironment() async throws {
        let recorder = EnvironmentRecordingProvider(
            response: InferenceResponse(content: "ok", finishReason: .completed)
        )
        let config = AgentConfiguration.default
            .foundationModelsExecution(.nativeSession)
            .defaultTracingEnabled(false)
        let agent = try Agent(
            tools: [MockTool(name: "echo", result: .string("pong"))],
            instructions: "Be brief.",
            configuration: config,
            inferenceProvider: recorder
        )

        _ = try await agent.run("Hello")
        #expect(await recorder.hookPresent)
        #expect(await recorder.toolCallMessageCallCount == 1)
    }

    @Test("Native session flag still streams tokens from a non-FM mock")
    func nativeSessionWithMockStillStreamsTokens() async throws {
        let mockProvider = MockInferenceProvider(responses: ["hello stream"])
        let config = AgentConfiguration.default
            .foundationModelsExecution(.nativeSession)
            .enableStreaming(true)
            .defaultTracingEnabled(false)
        let agent = try Agent(
            tools: [MockTool(name: "echo", result: .string("pong"))],
            instructions: "Be brief.",
            configuration: config,
            inferenceProvider: mockProvider
        )

        var tokens: [String] = []
        for try await event in agent.stream("Hello") {
            if case let .output(.token(token)) = event {
                tokens.append(token)
            }
        }

        #expect(tokens.joined().contains("hello stream"))
        #expect(await mockProvider.toolCallMessageCalls.count == 1)
    }

    @Test("Native session flag does not disable retries on non-FM providers")
    func nativeSessionDoesNotDisableRetriesForNonFM() async throws {
        let mockProvider = MockInferenceProvider(responses: ["recovered"])
        await mockProvider.setErrorSequence([
            AgentError.generationFailed(reason: "transient 503"),
        ])
        let config = AgentConfiguration.default
            .foundationModelsExecution(.nativeSession)
            .enableStreaming(false)
            .timeout(.seconds(15))
            .resilience(ResilienceConfiguration(retryPolicy: .standard))
            .defaultTracingEnabled(false)
        let agent = try Agent(
            tools: [MockTool(name: "echo", result: .string("pong"))],
            instructions: "Be brief.",
            configuration: config,
            inferenceProvider: mockProvider
        )

        let result = try await agent.run("Hello")
        #expect(result.output == "recovered")
        #expect(await mockProvider.recordedInferenceCallCount == 2)
    }

    @Test("Owned-loop execution gate starts active and deactivates")
    func ownedLoopExecutionGateDeactivates() {
        let gate = ProviderOwnedLoopGate()
        #expect(gate.isActive)
        gate.deactivate()
        #expect(gate.isActive == false)
    }

    @Test("FM provider-owned loop is skipped when Apple Intelligence is unavailable")
    func fmProviderOwnedLoopSkippedWhenAppleUnavailable() async throws {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) else { return }
        #if os(tvOS) || os(watchOS)
        return
        #else
        guard !FoundationModelsInferenceProvider.isAvailable else { return }

        let dummy = try Agent(
            tools: [],
            instructions: "Be brief.",
            configuration: .default.defaultTracingEnabled(false),
            inferenceProvider: MockInferenceProvider(responses: ["x"])
        )
        var env = AgentEnvironment()
        env.providerOwnedToolLoop = ProviderOwnedToolLoop(
            toolRegistry: ToolRegistry(),
            agent: dummy,
            context: nil,
            observer: nil,
            tracing: nil,
            resultBuilder: AgentResult.Builder(),
            stopOnToolError: false,
            conversationID: "unavailable-test",
            enableStreaming: false
        )
        let provider = FoundationModelsInferenceProvider()
        try await AgentEnvironmentValues.$current.withValue(env) {
            let finished = try await provider.completeProviderOwnedToolLoopIfRequested(
                messages: [.user("hi")],
                tools: [],
                options: .default
            )
            #expect(finished == nil)
        }
        #endif
        #endif
    }
}

/// Records whether Agent published a provider-owned tool loop on the environment.
private actor EnvironmentRecordingProvider: InferenceProvider {
    nonisolated let capabilities: InferenceProviderCapabilities = [
        .conversationMessages,
        .nativeToolCalling,
    ]

    let response: InferenceResponse
    private(set) var hookPresent = false
    private(set) var toolCallMessageCallCount = 0

    init(response: InferenceResponse) {
        self.response = response
    }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        response.content ?? "ok"
    }

    nonisolated func stream(
        prompt: String,
        options: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        response
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        toolCallMessageCallCount += 1
        let hook = AgentEnvironmentValues.current.providerOwnedToolLoop
        hookPresent = hook != nil
        return response
    }
}
