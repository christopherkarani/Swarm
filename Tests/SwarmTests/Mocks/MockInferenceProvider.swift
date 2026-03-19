// MockInferenceProvider.swift
// SwarmTests
//
// Mock inference provider for testing agents without Foundation Models.

import Foundation
@testable import Swarm

/// A mock inference provider for testing agents without Foundation Models.
///
/// Configure responses and verify calls for comprehensive agent testing.
///
/// Example:
/// ```swift
/// let mock = await MockInferenceProvider()
/// await mock.setResponses([
///     "The result is 4"
/// ])
///
/// let agent = try Agent(tools: [CalculatorTool()], inferenceProvider: mock)
/// let result = try await agent.run("What is 2+2?")
/// ```
public actor MockInferenceProvider: InferenceProvider,
    CapabilityReportingInferenceProvider,
    ConversationInferenceProvider,
    StreamingConversationInferenceProvider
{
    // MARK: Public

    // MARK: - Configurable Behavior

    /// Responses to return in sequence. Each call to `generate` consumes one response.
    public var responses: [String] = []

    /// Structured responses to return for `generateWithToolCalls`.
    ///
    /// When set, calls to `generateWithToolCalls` will return these responses in order.
    /// If exhausted, the mock falls back to using `responses` (text-only).
    public var toolCallResponses: [InferenceResponse] = []

    /// Error to throw on the next call. Set to nil to proceed normally.
    public var errorToThrow: Error?

    /// Delay to simulate network latency.
    public var responseDelay: Duration = .zero

    /// Default response when responses array is exhausted.
    public var defaultResponse = "Mock response"

    /// Provider capabilities advertised to the agent.
    public nonisolated let capabilities: InferenceProviderCapabilities

    // MARK: - Call Recording

    /// Recorded prompt-based generate calls for verification.
    public private(set) var generateCalls: [(prompt: String, options: InferenceOptions)] = []

    /// Recorded prompt-based stream calls for verification.
    public private(set) var streamCalls: [(prompt: String, options: InferenceOptions)] = []

    /// Recorded structured-message generations for verification.
    public private(set) var generateMessageCalls: [(messages: [InferenceMessage], options: InferenceOptions)] = []

    /// Recorded structured-message streams for verification.
    public private(set) var streamMessageCalls: [(messages: [InferenceMessage], options: InferenceOptions)] = []

    /// Recorded prompt-based tool call generations for verification.
    public private(set) var toolCallCalls: [(prompt: String, tools: [ToolSchema], options: InferenceOptions)] = []

    /// Recorded structured tool-call generations for verification.
    public private(set) var toolCallMessageCalls: [(messages: [InferenceMessage], tools: [ToolSchema], options: InferenceOptions)] = []

    /// Gets the number of prompt-based generate calls made.
    public var generateCallCount: Int {
        generateCalls.count
    }

    /// Gets the last prompt-based generate call, if any.
    public var lastGenerateCall: (prompt: String, options: InferenceOptions)? {
        generateCalls.last
    }

    // MARK: - Initialization

    /// Creates a new mock inference provider.
    public init(capabilities: InferenceProviderCapabilities = []) {
        self.capabilities = capabilities
    }

    /// Creates a mock with predefined responses.
    /// - Parameter responses: The responses to return in sequence.
    public init(
        responses: [String],
        capabilities: InferenceProviderCapabilities = []
    ) {
        self.responses = responses
        self.capabilities = capabilities
    }

    // MARK: - Configuration Methods

    /// Sets the responses to return in sequence.
    public func setResponses(_ responses: [String]) {
        self.responses = responses
        responseIndex = 0
    }

    /// Sets structured responses to return from `generateWithToolCalls`.
    public func setToolCallResponses(_ responses: [InferenceResponse]) {
        toolCallResponses = responses
        toolCallResponseIndex = 0
    }

    /// Sets an error to throw on the next call.
    public func setError(_ error: Error?) {
        errorToThrow = error
    }

    /// Sets the response delay.
    public func setDelay(_ delay: Duration) {
        responseDelay = delay
    }

    // MARK: - InferenceProvider Implementation

    public func generate(prompt: String, options: InferenceOptions) async throws -> String {
        generateCalls.append((prompt, options))
        return try await nextTextResponse()
    }

    nonisolated public func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()

        Task { @Sendable [weak self] in
            guard let self else {
                continuation.finish()
                return
            }
            do {
                await recordStreamCall(prompt: prompt, options: options)
                let response = try await generate(prompt: prompt, options: options)
                for char in response {
                    continuation.yield(String(char))
                    try await Task.sleep(for: .milliseconds(1))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        return stream
    }

    public func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        toolCallCalls.append((prompt, tools, options))
        return try await nextToolCallResponse()
    }

    public func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        generateMessageCalls.append((messages, options))
        return try await nextTextResponse()
    }

    nonisolated public func stream(
        messages: [InferenceMessage],
        options: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()

        Task { @Sendable [weak self] in
            guard let self else {
                continuation.finish()
                return
            }
            do {
                await recordStreamMessageCall(messages: messages, options: options)
                let response = try await generate(messages: messages, options: options)
                for char in response {
                    continuation.yield(String(char))
                    try await Task.sleep(for: .milliseconds(1))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        return stream
    }

    public func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        toolCallMessageCalls.append((messages, tools, options))
        return try await nextToolCallResponse()
    }

    // MARK: - Test Helpers

    /// Resets all recorded calls and response index.
    public func reset() {
        responseIndex = 0
        toolCallResponseIndex = 0
        generateCalls = []
        streamCalls = []
        generateMessageCalls = []
        streamMessageCalls = []
        toolCallCalls = []
        toolCallMessageCalls = []
        toolCallResponses = []
        errorToThrow = nil
    }

    /// Configures the mock for a simple tool calling sequence.
    /// - Parameters:
    ///   - toolCalls: Tool calls to simulate, with tool name and arguments.
    ///   - finalAnswer: The final answer to return.
    public func configureToolCallingSequence(
        toolCalls: [(name: String, args: [String: SendableValue])] = [],
        finalAnswer: String
    ) {
        var structured: [InferenceResponse] = []

        for (index, call) in toolCalls.enumerated() {
            structured.append(InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_\(index)",
                        name: call.name,
                        arguments: call.args
                    )
                ],
                finishReason: .toolCall,
                usage: nil
            ))
        }

        structured.append(InferenceResponse(
            content: finalAnswer,
            toolCalls: [],
            finishReason: .completed,
            usage: nil
        ))

        toolCallResponses = structured
        toolCallResponseIndex = 0
    }

    /// Configures the mock to always return tool calls (never finish with a text response).
    /// - Parameter toolName: The name of the tool to call in each response.
    ///
    /// This simulates an agent that keeps calling tools and never produces a final answer,
    /// which will trigger `maxIterationsExceeded` when the iteration limit is reached.
    public func configureInfiniteToolCalling(toolName: String = "noop") {
        let loopingToolCall = InferenceResponse(
            content: nil,
            toolCalls: [
                InferenceResponse.ParsedToolCall(
                    id: "call_loop",
                    name: toolName,
                    arguments: [:]
                )
            ],
            finishReason: .toolCall,
            usage: nil
        )
        toolCallResponses = [loopingToolCall]
        toolCallResponseIndex = 0
    }

    // MARK: Private

    /// Current index in the responses array.
    private var responseIndex = 0

    /// Current index in the tool call responses array.
    private var toolCallResponseIndex = 0

    private func nextTextResponse() async throws -> String {
        if let error = errorToThrow {
            throw error
        }

        if responseDelay > .zero {
            try await Task.sleep(for: responseDelay)
        }

        if responseIndex < responses.count {
            let response = responses[responseIndex]
            responseIndex += 1
            return response
        }

        return defaultResponse
    }

    private func nextToolCallResponse() async throws -> InferenceResponse {
        if let error = errorToThrow {
            throw error
        }

        if responseDelay > .zero {
            try await Task.sleep(for: responseDelay)
        }

        if toolCallResponseIndex < toolCallResponses.count {
            let response = toolCallResponses[toolCallResponseIndex]
            toolCallResponseIndex += 1
            return response
        }

        let content = try await nextTextResponse()
        return InferenceResponse(content: content, finishReason: .completed)
    }

    private func recordStreamCall(prompt: String, options: InferenceOptions) {
        streamCalls.append((prompt, options))
    }

    private func recordStreamMessageCall(messages: [InferenceMessage], options: InferenceOptions) {
        streamMessageCalls.append((messages, options))
    }
}
