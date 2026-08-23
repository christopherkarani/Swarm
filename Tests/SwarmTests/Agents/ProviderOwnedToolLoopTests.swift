// ProviderOwnedToolLoopTests.swift
// SwarmTests
//
// Provider-owned tool loop: Capabilities, executor, finished transcript.

import Foundation
@testable import Swarm
import Testing

@Suite("Provider-owned tool loop")
struct ProviderOwnedToolLoopTests {
    private let _ephemeralDefaultStores = SwarmEphemeralStoreBootstrap.installOnce

    private static let transient = AgentError.generationFailed(reason: "transient 503 after tool")

    @Test("Owned-loop adapter does not retry tools after a retryable inference error")
    func ownedLoopDoesNotRetryToolAfterRetryableFailure() async throws {
        let tool = SpyTool(name: "count_me", result: .string("once"))
        let provider = ExecutorHonoringThenFailingProvider(toolName: "count_me")
        let agent = try Agent(
            tools: [tool],
            instructions: "Use the counting tool.",
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .timeout(.seconds(15))
                .resilience(ResilienceConfiguration(retryPolicy: .standard))
                .defaultTracingEnabled(false),
            inferenceProvider: provider
        )

        await #expect(throws: AgentError.self) {
            _ = try await agent.run("use the tool")
        }

        #expect(await tool.callCount == 1)
        #expect(await provider.inferenceCallCount == 1)
    }

    @Test("Capture child still iterates when the parent owns the loop")
    func nestedCaptureRunStillIterates() async throws {
        let childRecorder = CaptureCallCountingProvider()
        let child = try Agent(
            tools: [MockTool(name: "unused", result: .string("x"))],
            instructions: "Child",
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .defaultTracingEnabled(false),
            inferenceProvider: childRecorder
        )

        let parentProvider = ExecutorHonoringCompletingProvider(
            toolName: "child_agent",
            arguments: ["input": .string("nested")]
        )

        let parent = try Agent(
            tools: [child.asTool(name: "child_agent")],
            instructions: "Delegate to the child.",
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .defaultTracingEnabled(false),
            inferenceProvider: parentProvider
        )

        let result = try await parent.run("go")
        #expect(result.output == "done")
        #expect(await childRecorder.generateWithToolCallsCount == 1)
        #expect(await childRecorder.receivedExecutor == false)
    }

    @Test("Empty-tools owned loop still retries a transient inference error")
    func emptyToolsOwnedLoopKeepsRetries() async throws {
        let provider = MockOwnedLoopProvider(responses: ["recovered"])
        await provider.setErrorSequence([Self.transient])
        let agent = try Agent(
            tools: [],
            instructions: "Be brief.",
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .timeout(.seconds(15))
                .resilience(ResilienceConfiguration(
                    retryPolicy: RetryPolicy(maxAttempts: 3, backoff: .immediate)
                ))
                .defaultTracingEnabled(false),
            inferenceProvider: provider
        )

        let result = try await agent.run("hello")
        #expect(result.output == "recovered")
        #expect(await provider.recordedInferenceCallCount == 2)
    }

    @Test("Owned loop persists the InferenceMessage transcript on Session")
    func ownedLoopTranscriptIsPersistedToSession() async throws {
        let tool = SpyTool(name: "ping", result: .string("pong"))
        let provider = ExecutorHonoringCompletingProvider(toolName: "ping")
        let session = InMemorySession(sessionId: "owned-loop-transcript")
        let agent = try Agent(
            tools: [tool],
            instructions: "Use ping.",
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .defaultTracingEnabled(false),
            inferenceProvider: provider
        )

        let result = try await agent.run("use ping", session: session)
        #expect(result.output == "done")
        #expect(await tool.callCount == 1)
        #expect(await provider.inferenceCallCount == 1)

        let items = try await session.getAllItems()
        #expect(items.contains { $0.role == .user && $0.content == "use ping" })
        #expect(items.contains { $0.role == .tool && $0.content == "pong" })
        #expect(items.contains { $0.role == .assistant && $0.content == "done" })
    }

    @Test("Timeout deactivates the executor so detached tool calls refuse")
    func timeoutDeactivatesExecutorForDetachedToolCalls() async throws {
        let tool = SpyTool(name: "late_tool", result: .string("should-not-run"))
        let provider = ExecutorHonoringLateToolProvider(toolName: "late_tool")
        let agent = try Agent(
            tools: [tool],
            instructions: "Use the late tool.",
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .timeout(.seconds(1))
                .resilience(ResilienceConfiguration(retryPolicy: .noRetry))
                .defaultTracingEnabled(false),
            inferenceProvider: provider
        )

        let runTask = Task {
            try await agent.run("use the tool")
        }
        for _ in 0..<200 {
            if await provider.startedDelay { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await provider.startedDelay)

        do {
            _ = try await runTask.value
            Issue.record("Expected timeout")
        } catch let error as AgentError {
            #expect(error == .timeout(duration: .seconds(1)))
        } catch {
            Issue.record("Expected AgentError.timeout, got \(error)")
        }

        #expect(await provider.attemptedDetachedTool == true)
        #expect(await provider.detachedToolRan == false)
        #expect(await tool.callCount == 0)
    }

    @Test("Cancel deactivates the executor so detached tool calls refuse")
    func cancelDeactivatesExecutorForDetachedToolCalls() async throws {
        let tool = SpyTool(name: "late_tool", result: .string("should-not-run"))
        let provider = ExecutorHonoringLateToolProvider(toolName: "late_tool")
        let agent = try Agent(
            tools: [tool],
            instructions: "Use the late tool.",
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .timeout(.seconds(15))
                .resilience(ResilienceConfiguration(retryPolicy: .noRetry))
                .defaultTracingEnabled(false),
            inferenceProvider: provider
        )

        let runTask = Task {
            try await agent.run("use the tool")
        }
        for _ in 0..<200 {
            if await provider.startedDelay { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await provider.startedDelay)
        await agent.cancel()

        do {
            _ = try await runTask.value
            Issue.record("Expected cancellation")
        } catch let error as AgentError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("Expected AgentError.cancelled, got \(error)")
        }

        #expect(await provider.attemptedDetachedTool == true)
        #expect(await provider.detachedToolRan == false)
        #expect(await tool.callCount == 0)
    }

    @Test("Capture adapter with tools still retries a transient inference error")
    func captureModeWithToolsKeepsRetries() async throws {
        let provider = MockInferenceProvider(responses: ["recovered"])
        await provider.setErrorSequence([Self.transient])
        let agent = try Agent(
            tools: [MockTool(name: "echo", result: .string("pong"))],
            instructions: "Be brief.",
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .timeout(.seconds(15))
                .resilience(ResilienceConfiguration(
                    retryPolicy: RetryPolicy(maxAttempts: 3, backoff: .immediate)
                ))
                .defaultTracingEnabled(false),
            inferenceProvider: provider
        )

        let result = try await agent.run("hello")
        #expect(result.output == "recovered")
        #expect(await provider.recordedInferenceCallCount == 2)
    }

    @Test("Owned-loop adapter without an executor throws")
    func ownedLoopWithoutExecutorThrows() async throws {
        let provider = FoundationModelsStyleOwnedProvider()
        await #expect(throws: AgentError.providerOwnedToolLoopRequiresExecutor) {
            _ = try await provider.generateWithToolCalls(
                messages: [.user("hi")],
                tools: [],
                options: .default,
                toolExecutor: nil
            )
        }
    }

    @Test("Default 4-arg generate throws when the capability bit is set even if an executor is passed")
    func defaultOwnedLoopGenerateDropsNothingItThrows() async throws {
        let provider = DefaultWitnessOwnedLoopProvider()
        let executor = ToolCallExecutor { _, _ in .string("unused") }
        await #expect(throws: AgentError.providerOwnedToolLoopRequiresExecutor) {
            _ = try await provider.generateWithToolCalls(
                messages: [.user("hi")],
                tools: [],
                options: .default,
                toolExecutor: executor
            )
        }
    }

    @Test("Default 4-arg stream throws when the capability bit is set")
    func defaultOwnedLoopStreamThrows() async throws {
        let provider = DefaultWitnessOwnedLoopProvider()
        let executor = ToolCallExecutor { _, _ in .string("unused") }
        let stream = provider.streamWithToolCalls(
            messages: [.user("hi")],
            tools: [],
            options: .default,
            toolExecutor: executor
        )
        await #expect(throws: AgentError.providerOwnedToolLoopRequiresExecutor) {
            for try await _ in stream {}
        }
    }

    @Test("Owned-loop executor stops the loop so Agent can hand off")
    func ownedLoopExecutorStopsForHandoff() async throws {
        let targetProvider = MockInferenceProvider(responses: ["from target"])
        let target = try Agent(
            tools: [],
            instructions: "Target",
            configuration: AgentConfiguration(name: "target", defaultTracingEnabled: false),
            inferenceProvider: targetProvider
        )
        let provider = ExecutorHonoringCompletingProvider(toolName: "handoff_to_target")
        let source = try Agent(
            tools: [],
            instructions: "Source",
            configuration: AgentConfiguration(name: "source", defaultTracingEnabled: false),
            inferenceProvider: provider,
            handoffs: [
                AnyHandoffConfiguration(
                    HandoffConfiguration(
                        targetAgent: target,
                        toolNameOverride: "handoff_to_target"
                    )
                ),
            ]
        )

        let result = try await source.run("route")
        #expect(result.output == "from target")
        #expect(await provider.inferenceCallCount == 1)
    }

    @Test("Owned-loop handoff still completes when the adapter remaps it to cancellation")
    func ownedLoopHandoffSurvivesCancellationRemap() async throws {
        let targetProvider = MockInferenceProvider(responses: ["from target"])
        let target = try Agent(
            tools: [],
            instructions: "Target",
            configuration: AgentConfiguration(name: "target", defaultTracingEnabled: false),
            inferenceProvider: targetProvider
        )
        let provider = ExecutorRemappingHandoffToCancellationProvider(toolName: "handoff_to_target")
        let source = try Agent(
            tools: [],
            instructions: "Source",
            configuration: AgentConfiguration(name: "source", defaultTracingEnabled: false),
            inferenceProvider: provider,
            handoffs: [
                AnyHandoffConfiguration(
                    HandoffConfiguration(
                        targetAgent: target,
                        toolNameOverride: "handoff_to_target"
                    )
                ),
            ]
        )

        let result = try await source.run("route")
        #expect(result.output == "from target")
    }

    @Test("Deprecated nativeSession flag does not stop Agent iterating a capture adapter")
    func deprecatedFlagDoesNotChooseTheLoop() async throws {
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
            InferenceResponse(content: "Done", finishReason: .completed),
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
        #expect(await mockProvider.toolCallMessageCalls.count == 2)
    }
}

#if canImport(FoundationModels)
@Suite("Foundation Models factories")
struct FoundationModelsFactoryCapabilityTests {
    @Test("Capture factory does not advertise a provider-owned tool loop")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func captureFactoryOmitsOwnedLoopBit() {
        let provider = FoundationModelsInferenceProvider()
        #expect(provider.capabilities.contains(.providerOwnedToolLoop) == false)
    }

    @Test("Owned-loop factory advertises a provider-owned tool loop")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func ownedLoopFactoryAdvertisesBit() {
        let provider = FoundationModelsInferenceProvider(ownsToolLoop: true)
        #expect(provider.capabilities.contains(.providerOwnedToolLoop))
    }

    @Test("Owned-loop adapter throws modelNotAvailable when Apple Intelligence is off")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func ownedLoopUnavailableThrowsModelNotAvailable() async throws {
        guard FoundationModelsInferenceProvider.isAvailable == false else { return }
        let provider = FoundationModelsInferenceProvider(ownsToolLoop: true)
        let executor = ToolCallExecutor { _, _ in .string("unused") }
        await #expect(throws: AgentError.modelNotAvailable(model: "Apple Foundation Models")) {
            _ = try await provider.generateWithToolCalls(
                messages: [.user("hi")],
                tools: [],
                options: .default,
                toolExecutor: executor
            )
        }
    }
}
#endif

// MARK: - Owned-loop test adapters

private actor ExecutorHonoringThenFailingProvider: InferenceProvider, MessagesFromPromptInference {
    nonisolated let capabilities: InferenceProviderCapabilities = [
        .conversationMessages,
        .nativeToolCalling,
        .providerOwnedToolLoop,
    ]

    let toolName: String
    private(set) var inferenceCallCount = 0

    init(toolName: String) {
        self.toolName = toolName
    }

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        throw AgentError.generationFailed(reason: "expected generateWithToolCalls")
    }

    nonisolated func stream(
        prompt _: String,
        options _: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt _: String,
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        throw AgentError.generationFailed(reason: "expected messages seam")
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        inferenceCallCount += 1
        guard let toolExecutor else {
            throw AgentError.providerOwnedToolLoopRequiresExecutor
        }
        _ = try await toolExecutor.executeTool(named: toolName, arguments: [:])
        throw AgentError.generationFailed(reason: "transient 503 after tool")
    }
}

private actor CaptureCallCountingProvider: InferenceProvider, MessagesFromPromptInference {
    nonisolated let capabilities: InferenceProviderCapabilities = [
        .conversationMessages,
        .nativeToolCalling,
    ]

    private(set) var receivedExecutor = false
    private(set) var generateWithToolCallsCount = 0

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        "ok"
    }

    nonisolated func stream(
        prompt _: String,
        options _: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt _: String,
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        generateWithToolCallsCount += 1
        return InferenceResponse(content: "ok", finishReason: .completed)
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        generateWithToolCallsCount += 1
        receivedExecutor = toolExecutor != nil
        return InferenceResponse(content: "ok", finishReason: .completed)
    }
}

private actor ExecutorHonoringCompletingProvider: InferenceProvider, MessagesFromPromptInference {
    nonisolated let capabilities: InferenceProviderCapabilities = [
        .conversationMessages,
        .nativeToolCalling,
        .providerOwnedToolLoop,
    ]

    let toolName: String
    let arguments: [String: SendableValue]
    private(set) var inferenceCallCount = 0

    init(toolName: String, arguments: [String: SendableValue] = [:]) {
        self.toolName = toolName
        self.arguments = arguments
    }

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        throw AgentError.generationFailed(reason: "expected generateWithToolCalls")
    }

    nonisolated func stream(
        prompt _: String,
        options _: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt _: String,
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        throw AgentError.generationFailed(reason: "expected messages seam")
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        inferenceCallCount += 1
        guard let toolExecutor else {
            throw AgentError.providerOwnedToolLoopRequiresExecutor
        }
        let output = try await toolExecutor.executeTool(named: toolName, arguments: arguments)
        let toolText = Agent.toolOutputText(for: output)
        return InferenceResponse(
            content: "done",
            finishReason: .completed,
            transcriptMessages: [
                .assistant("", toolCalls: [
                    InferenceMessage.ToolCall(id: "call_ping", name: toolName, arguments: [:]),
                ]),
                .tool(name: toolName, content: toolText, toolCallID: "call_ping"),
                .assistant("done"),
            ]
        )
    }
}

private actor ExecutorRemappingHandoffToCancellationProvider: InferenceProvider, MessagesFromPromptInference {
    nonisolated let capabilities: InferenceProviderCapabilities = [
        .conversationMessages,
        .nativeToolCalling,
        .providerOwnedToolLoop,
    ]

    let toolName: String

    init(toolName: String) {
        self.toolName = toolName
    }

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        throw AgentError.generationFailed(reason: "expected generateWithToolCalls")
    }

    nonisolated func stream(
        prompt _: String,
        options _: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt _: String,
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        throw AgentError.generationFailed(reason: "expected messages seam")
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        guard let toolExecutor else {
            throw AgentError.providerOwnedToolLoopRequiresExecutor
        }
        do {
            _ = try await toolExecutor.executeTool(named: toolName, arguments: [:])
        } catch {
            throw CancellationError()
        }
        return InferenceResponse(content: "should-not-return", finishReason: .completed)
    }
}

private actor ExecutorHonoringLateToolProvider: InferenceProvider, MessagesFromPromptInference {
    nonisolated let capabilities: InferenceProviderCapabilities = [
        .conversationMessages,
        .nativeToolCalling,
        .providerOwnedToolLoop,
    ]

    let toolName: String
    private(set) var startedDelay = false
    private(set) var attemptedDetachedTool = false
    private(set) var detachedToolRan = false

    init(toolName: String) {
        self.toolName = toolName
    }

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        throw AgentError.generationFailed(reason: "expected generateWithToolCalls")
    }

    nonisolated func stream(
        prompt _: String,
        options _: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt _: String,
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        throw AgentError.generationFailed(reason: "expected messages seam")
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        guard let toolExecutor else {
            throw AgentError.providerOwnedToolLoopRequiresExecutor
        }
        startedDelay = true
        try? await Task.sleep(for: .seconds(5))
        attemptedDetachedTool = true
        let name = toolName
        detachedToolRan = await Task.detached {
            do {
                _ = try await toolExecutor.executeTool(named: name, arguments: [:])
                return true
            } catch {
                return false
            }
        }.value
        return InferenceResponse(content: "late", finishReason: .completed)
    }
}

/// Capture-style mock that advertises the owned-loop bit and implements the 4-arg call.
private actor MockOwnedLoopProvider: InferenceProvider, MessagesFromPromptInference {
    nonisolated let capabilities: InferenceProviderCapabilities = [
        .conversationMessages,
        .providerOwnedToolLoop,
    ]

    var responses: [String]
    var errorSequence: [Error] = []
    private(set) var recordedInferenceCallCount = 0

    init(responses: [String]) {
        self.responses = responses
    }

    func setErrorSequence(_ errors: [Error]) {
        errorSequence = errors
    }

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        try nextText()
    }

    nonisolated func stream(
        prompt _: String,
        options _: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt _: String,
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        InferenceResponse(content: try nextText(), finishReason: .completed)
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions,
        toolExecutor _: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        InferenceResponse(content: try nextText(), finishReason: .completed)
    }

    private func nextText() throws -> String {
        recordedInferenceCallCount += 1
        if !errorSequence.isEmpty {
            throw errorSequence.removeFirst()
        }
        if responses.isEmpty {
            return "Mock response"
        }
        return responses.removeFirst()
    }
}

/// Advertises the owned-loop bit but only implements the 3-arg witness.
private struct DefaultWitnessOwnedLoopProvider: InferenceProvider, MessagesFromPromptInference {
    nonisolated let capabilities: InferenceProviderCapabilities = [
        .conversationMessages,
        .providerOwnedToolLoop,
    ]

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        "unused"
    }

    func stream(
        prompt _: String,
        options _: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func generateWithToolCalls(
        prompt _: String,
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        InferenceResponse(content: "should-not-run")
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        InferenceResponse(content: "should-not-run")
    }
}

private struct FoundationModelsStyleOwnedProvider: InferenceProvider, MessagesFromPromptInference {
    nonisolated let capabilities: InferenceProviderCapabilities = [
        .conversationMessages,
        .providerOwnedToolLoop,
    ]

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        "unused"
    }

    func stream(
        prompt _: String,
        options _: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func generateWithToolCalls(
        prompt _: String,
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        InferenceResponse(content: "unused")
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        guard toolExecutor != nil else {
            throw AgentError.providerOwnedToolLoopRequiresExecutor
        }
        return InferenceResponse(content: "ok")
    }
}
