// ProviderOwnedToolLoopTests.swift
// SwarmTests
//
// Owned-loop retry isolation and nested-run hook inheritance.

import Foundation
@testable import Swarm
import Testing

@Suite("Provider-owned tool loop")
struct ProviderOwnedToolLoopTests {
    private static let transient = AgentError.generationFailed(reason: "transient 503 after tool")

    @Test("Hook-honoring native session does not retry tools after a retryable inference error")
    func nativeOwnedLoopDoesNotRetryToolAfterRetryableFailure() async throws {
        let tool = SpyTool(name: "count_me", result: .string("once"))
        let provider = HookHonoringThenFailingProvider(toolName: "count_me")
        let agent = try Agent(
            tools: [tool],
            instructions: "Use the counting tool.",
            configuration: AgentConfiguration.default
                .foundationModelsExecution(.nativeSession)
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

    @Test("Nested capture run does not inherit the parent owned-loop hook")
    func nestedCaptureRunDoesNotInheritParentOwnedLoopHook() async throws {
        let childRecorder = EnvironmentHookRecordingProvider()
        let child = try Agent(
            tools: [MockTool(name: "unused", result: .string("x"))],
            instructions: "Child",
            configuration: AgentConfiguration.default
                .foundationModelsExecution(.capture)
                .enableStreaming(false)
                .defaultTracingEnabled(false),
            inferenceProvider: childRecorder
        )

        let parentProvider = MockInferenceProvider()
        await parentProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_child",
                        name: "child_agent",
                        arguments: ["input": .string("nested")]
                    ),
                ],
                finishReason: .toolCall
            ),
            InferenceResponse(content: "parent done", finishReason: .completed),
        ])

        let parent = try Agent(
            tools: [child.asTool(name: "child_agent")],
            instructions: "Delegate to the child.",
            configuration: AgentConfiguration.default
                .foundationModelsExecution(.nativeSession)
                .enableStreaming(false)
                .defaultTracingEnabled(false),
            inferenceProvider: parentProvider
        )

        let result = try await parent.run("go")
        #expect(result.output == "parent done")
        #expect(await childRecorder.generateWithToolCallsCount == 1)
        #expect(await childRecorder.hookPresent == false)
    }

    @Test("Empty-tools native session still retries a transient inference error")
    func emptyToolsNativeSessionKeepsRetries() async throws {
        let provider = MockInferenceProvider(responses: ["recovered"])
        await provider.setErrorSequence([Self.transient])
        let agent = try Agent(
            tools: [],
            instructions: "Be brief.",
            configuration: AgentConfiguration.default
                .foundationModelsExecution(.nativeSession)
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

    @Test("Hook-honoring owned loop persists the provider transcript")
    func ownedLoopTranscriptIsPersistedToSession() async throws {
        let tool = SpyTool(name: "ping", result: .string("pong"))
        let provider = HookHonoringCompletingProvider(toolName: "ping")
        let session = InMemorySession(sessionId: "owned-loop-transcript")
        let agent = try Agent(
            tools: [tool],
            instructions: "Use ping.",
            configuration: AgentConfiguration.default
                .foundationModelsExecution(.nativeSession)
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

    @Test("Timeout deactivates the owned-loop gate so detached tool calls refuse")
    func timeoutDeactivatesOwnedLoopGateForDetachedToolCalls() async throws {
        let tool = SpyTool(name: "late_tool", result: .string("should-not-run"))
        let provider = HookHonoringLateToolProvider(toolName: "late_tool")
        let agent = try Agent(
            tools: [tool],
            instructions: "Use the late tool.",
            configuration: AgentConfiguration.default
                .foundationModelsExecution(.nativeSession)
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

    @Test("Cancel deactivates the owned-loop gate so detached tool calls refuse")
    func cancelDeactivatesOwnedLoopGateForDetachedToolCalls() async throws {
        let tool = SpyTool(name: "late_tool", result: .string("should-not-run"))
        let provider = HookHonoringLateToolProvider(toolName: "late_tool")
        let agent = try Agent(
            tools: [tool],
            instructions: "Use the late tool.",
            configuration: AgentConfiguration.default
                .foundationModelsExecution(.nativeSession)
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

    @Test("Capture mode with tools still retries a transient inference error")
    func captureModeWithToolsKeepsRetries() async throws {
        let provider = MockInferenceProvider(responses: ["recovered"])
        await provider.setErrorSequence([Self.transient])
        let agent = try Agent(
            tools: [MockTool(name: "echo", result: .string("pong"))],
            instructions: "Be brief.",
            configuration: AgentConfiguration.default
                .foundationModelsExecution(.capture)
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
}

// MARK: - Hook-honoring provider

/// Executes one hooked tool, then throws a retryable inference error.
private actor HookHonoringThenFailingProvider: InferenceProvider {
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
        try await honorHookThenFail()
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        try await honorHookThenFail()
    }

    private func honorHookThenFail() async throws -> InferenceResponse {
        inferenceCallCount += 1
        guard let hook = AgentEnvironmentValues.current.providerOwnedToolLoop else {
            throw AgentError.generationFailed(reason: "provider-owned tool loop hook missing")
        }
        _ = try await hook.toolRegistry.execute(
            toolNamed: toolName,
            arguments: [:],
            agent: hook.agent,
            context: hook.context,
            observer: hook.observer
        )
        throw AgentError.generationFailed(reason: "transient 503 after tool")
    }
}

// MARK: - Nested-run hook recorder

/// Records whether a provider-owned tool loop hook was visible on generateWithToolCalls.
private actor EnvironmentHookRecordingProvider: InferenceProvider {
    nonisolated let capabilities: InferenceProviderCapabilities = [
        .conversationMessages,
        .nativeToolCalling,
    ]

    private(set) var hookPresent = false
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
        recordHook()
        return InferenceResponse(content: "ok", finishReason: .completed)
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        recordHook()
        return InferenceResponse(content: "ok", finishReason: .completed)
    }

    private func recordHook() {
        generateWithToolCallsCount += 1
        hookPresent = AgentEnvironmentValues.current.providerOwnedToolLoop != nil
    }
}

// MARK: - Completing hook-honoring provider

/// Executes one hooked tool and returns a finished turn with a transcript.
private actor HookHonoringCompletingProvider: InferenceProvider {
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
        try await honorHookAndFinish()
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        try await honorHookAndFinish()
    }

    private func honorHookAndFinish() async throws -> InferenceResponse {
        inferenceCallCount += 1
        guard let hook = AgentEnvironmentValues.current.providerOwnedToolLoop else {
            throw AgentError.generationFailed(reason: "provider-owned tool loop hook missing")
        }
        let output = try await hook.executeTool(named: toolName, arguments: [:])
        let toolText = Agent.toolOutputText(for: output)
        return InferenceResponse(
            content: "done",
            finishReason: .completed,
            transcriptMessages: [
                SwarmTranscriptCodec.encodeMessage(
                    role: .assistant,
                    content: "",
                    toolCalls: [
                        InferenceResponse.ParsedToolCall(id: "call_ping", name: toolName, arguments: [:]),
                    ]
                ),
                SwarmTranscriptCodec.encodeMessage(
                    role: .tool,
                    content: toolText,
                    toolName: toolName,
                    toolCallID: "call_ping"
                ),
                SwarmTranscriptCodec.encodeMessage(role: .assistant, content: "done"),
            ]
        )
    }
}

// MARK: - Late detached tool after timeout

/// Sleeps past the agent timeout, then tries a tool on a fresh task (Apple-style).
private actor HookHonoringLateToolProvider: InferenceProvider {
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
        try await honorHookAfterDelay()
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        try await honorHookAfterDelay()
    }

    private func honorHookAfterDelay() async throws -> InferenceResponse {
        guard let hook = AgentEnvironmentValues.current.providerOwnedToolLoop else {
            throw AgentError.generationFailed(reason: "provider-owned tool loop hook missing")
        }
        startedDelay = true
        try? await Task.sleep(for: .seconds(5))
        attemptedDetachedTool = true
        let name = toolName
        detachedToolRan = await Task.detached {
            do {
                _ = try await hook.executeTool(named: name, arguments: [:])
                return true
            } catch {
                return false
            }
        }.value
        return InferenceResponse(content: "late", finishReason: .completed)
    }
}
