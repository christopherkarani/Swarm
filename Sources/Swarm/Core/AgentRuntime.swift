// AgentRuntime.swift
// Swarm Framework
//
// Core AgentRuntime protocol and related inference types.

import Foundation

// MARK: - AgentRuntime

/// A protocol defining the core behavior of an AI agent.
///
/// Agents are autonomous entities that can reason about tasks, use tools,
/// and maintain context across interactions. This protocol defines the
/// minimal interface that all agent implementations must support.
///
/// ## Guardrails
///
/// Agents can have input and output guardrails for validation and safety:
/// - Input guardrails validate user input before processing
/// - Output guardrails validate agent responses before returning
///
/// Example:
/// ```swift
/// let agent = Agent(
///     tools: [CalculatorTool(), DateTimeTool()],
///     instructions: "You are a helpful assistant."
/// )
/// let result = try await agent.run("What's 2+2?")
/// print(result.output)
/// ```
public protocol AgentRuntime: Sendable {
    /// The display name of this agent.
    ///
    /// Returns the agent's configured name. Used for logging, tracing,
    /// handoff identification, and multi-agent coordination.
    nonisolated var name: String { get }

    /// The tools available to this agent.
    nonisolated var tools: [any AnyJSONTool] { get }

    /// Instructions that define the agent's behavior and role.
    nonisolated var instructions: String { get }

    /// Configuration settings for the agent.
    nonisolated var configuration: AgentConfiguration { get }

    /// Optional memory system for context management.
    nonisolated var memory: (any Memory)? { get }

    /// Optional custom inference provider.
    nonisolated var inferenceProvider: (any InferenceProvider)? { get }

    /// Optional tracer for observability.
    nonisolated var tracer: (any Tracer)? { get }

    /// Input guardrails that validate user input before processing.
    ///
    /// Guardrails are executed in order. If any guardrail triggers a tripwire,
    /// execution stops and throws `GuardrailError.inputTripwireTriggered`.
    nonisolated var inputGuardrails: [any InputGuardrail] { get }

    /// Output guardrails that validate agent responses before returning.
    ///
    /// Guardrails are executed in order after the agent produces output.
    /// If any guardrail triggers a tripwire, throws `GuardrailError.outputTripwireTriggered`.
    nonisolated var outputGuardrails: [any OutputGuardrail] { get }

    /// Configured handoffs for this agent.
    ///
    /// Handoffs define how this agent can transfer execution to other agents,
    /// including callbacks, filters, and enablement checks.
    nonisolated var handoffs: [AnyHandoffConfiguration] { get }

    /// Executes the agent with the given input and returns a result.
    /// - Parameters:
    ///   - input: The user's input/query.
    ///   - session: Optional session for conversation history management.
    ///   - observer: Optional observer for lifecycle callbacks.
    /// - Returns: The result of the agent's execution.
    /// - Throws: `AgentError` if execution fails, or `GuardrailError` if guardrails trigger.
    func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult

    /// Streams the agent's execution, yielding events as they occur.
    /// - Parameters:
    ///   - input: The user's input/query.
    ///   - session: Optional session for conversation history management.
    ///   - observer: Optional observer for lifecycle callbacks.
    /// - Returns: An async stream of agent events.
    nonisolated func stream(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) -> AsyncThrowingStream<AgentEvent, Error>

    /// Cancels any ongoing execution.
    func cancel() async

    /// Executes the agent and returns a detailed response with tracking ID.
    ///
    /// This method provides enhanced response tracking capabilities compared to
    /// the standard `run()` method. The returned `AgentResponse` includes:
    /// - A unique response ID for conversation continuation
    /// - Detailed tool call records with timing information
    /// - Full metadata and token usage statistics
    ///
    /// - Parameters:
    ///   - input: The user's input/query.
    ///   - session: Optional session for conversation history management.
    ///   - observer: Optional observer for lifecycle callbacks.
    /// - Returns: An `AgentResponse` with unique ID and detailed metadata.
    /// - Throws: `AgentError` if execution fails, or `GuardrailError` if guardrails trigger.
    func runWithResponse(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) async throws -> AgentResponse
}

// MARK: - LegacyAgent Protocol Extensions

public extension AgentRuntime {
    /// Default name derived from configuration.
    nonisolated var name: String { configuration.name }

    /// Default memory implementation (none).
    nonisolated var memory: (any Memory)? { nil }

    /// Default inference provider (none, uses Foundation Models).
    nonisolated var inferenceProvider: (any InferenceProvider)? { nil }

    /// Default tracer implementation (none).
    nonisolated var tracer: (any Tracer)? { nil }

    /// Default input guardrails (none).
    nonisolated var inputGuardrails: [any InputGuardrail] { [] }

    /// Default output guardrails (none).
    nonisolated var outputGuardrails: [any OutputGuardrail] { [] }

    /// Default handoffs (none).
    nonisolated var handoffs: [AnyHandoffConfiguration] { [] }
}

// MARK: - Agent Convenience Extensions

public extension AgentRuntime {
    /// Convenience method for running without a session.
    func run(_ input: String, observer: (any AgentObserver)? = nil) async throws -> AgentResult {
        try await run(input, session: nil, observer: observer)
    }

    /// Convenience method for streaming without a session.
    nonisolated func stream(
        _ input: String,
        observer: (any AgentObserver)? = nil
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        stream(input, session: nil, observer: observer)
    }
}

// MARK: - LegacyAgent runWithResponse Extensions

public extension AgentRuntime {
    /// Default implementation of `runWithResponse` using `run()`.
    ///
    /// This creates an `AgentResponse` from the `AgentResult`, generating a unique
    /// response ID and converting tool results to `ToolCallRecord` format.
    func runWithResponse(
        _ input: String,
        session: (any Session)? = nil,
        observer: (any AgentObserver)? = nil
    ) async throws -> AgentResponse {
        let result = try await run(input, session: session, observer: observer)

        // Use reduce(into:) instead of uniqueKeysWithValues to avoid crash on duplicate IDs
        let toolCallsById = result.toolCalls.reduce(into: [UUID: ToolCall]()) { dict, call in
            dict[call.id] = call
        }

        let toolCallRecords: [ToolCallRecord] = result.toolResults.compactMap { toolResult in
            guard let toolCall = toolCallsById[toolResult.callId] else {
                Log.agents.warning("Tool result missing matching call: \(toolResult.callId)")
                return nil
            }
            return ToolCallRecord(
                toolName: toolCall.toolName,
                arguments: toolCall.arguments,
                result: toolResult.output,
                duration: toolResult.duration,
                timestamp: toolCall.timestamp,
                isSuccess: toolResult.isSuccess,
                errorMessage: toolResult.errorMessage
            )
        }

        return AgentResponse(
            responseId: UUID().uuidString,
            output: result.output,
            agentName: configuration.name,
            timestamp: Date(),
            metadata: result.metadata,
            toolCalls: toolCallRecords,
            usage: result.tokenUsage,
            iterationCount: result.iterationCount
        )
    }

    /// Convenience method for `runWithResponse` without a session.
    func runWithResponse(
        _ input: String,
        observer: (any AgentObserver)? = nil
    ) async throws -> AgentResponse {
        try await runWithResponse(input, session: nil, observer: observer)
    }
}

// MARK: - InferenceProvider

/// Protocol for inference providers.
///
/// Inference providers abstract the underlying language model, allowing
/// agents to work with different model backends (Foundation Models,
/// AnyLanguageModel, Conduit SDK, etc.).
///
public protocol InferenceProvider: Sendable {
    /// Generates a response for the given prompt.
    /// - Parameters:
    ///   - prompt: The input prompt.
    ///   - options: Generation options.
    /// - Returns: The generated text.
    /// - Throws: `AgentError` if generation fails.
    func generate(prompt: String, options: InferenceOptions) async throws -> String

    /// Streams a response for the given prompt.
    /// - Parameters:
    ///   - prompt: The input prompt.
    ///   - options: Generation options.
    /// - Returns: An async stream of response tokens.
    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error>

    /// Generates a response with potential tool calls.
    /// - Parameters:
    ///   - prompt: The input prompt.
    ///   - tools: Available tool schemas.
    ///   - options: Generation options.
    /// - Returns: The inference response which may include tool calls.
    /// - Throws: `AgentError` if generation fails.
    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse
}

// MARK: - InferenceOptions

/// Options for inference generation.
///
/// Customize model behavior including temperature, token limits,
/// and stop sequences. Supports fluent builder pattern for easy configuration.
///
/// Example:
/// ```swift
/// let options = InferenceOptions.default
///     .temperature(0.7)
///     .maxTokens(2000)
///     .stopSequences("END", "STOP")
/// ```
@Builder
public struct InferenceOptions: Sendable, Equatable {
    /// Default inference options.
    public static let `default` = InferenceOptions()

    // MARK: - Preset Configurations

    /// Creative preset with high temperature for diverse outputs.
    public static var creative: InferenceOptions {
        InferenceOptions(temperature: 1.2, topP: 0.95)
    }

    /// Precise preset with low temperature for deterministic outputs.
    public static var precise: InferenceOptions {
        InferenceOptions(temperature: 0.2, topP: 0.9)
    }

    /// Balanced preset for general use.
    public static var balanced: InferenceOptions {
        InferenceOptions(temperature: 0.7, topP: 0.9)
    }

    /// Code generation preset optimized for programming tasks.
    public static var codeGeneration: InferenceOptions {
        InferenceOptions(
            temperature: 0.1,
            maxTokens: 4000,
            stopSequences: ["```", "###"],
            topP: 0.95
        )
    }

    /// Chat preset optimized for conversational interactions.
    public static var chat: InferenceOptions {
        InferenceOptions(temperature: 0.8, topP: 0.9, presencePenalty: 0.6)
    }

    /// Temperature for generation (0.0 = deterministic, 2.0 = creative).
    public var temperature: Double

    /// Maximum tokens to generate.
    public var maxTokens: Int?

    /// Sequences that will stop generation.
    public var stopSequences: [String]

    /// Top-p (nucleus) sampling parameter.
    public var topP: Double?

    /// Top-k sampling parameter.
    public var topK: Int?

    /// Presence penalty for reducing repetition.
    public var presencePenalty: Double?

    /// Frequency penalty for reducing repetition.
    public var frequencyPenalty: Double?

    /// Controls how the model should choose tool usage when tools are provided.
    ///
    /// Providers that do not support tool choice may ignore this value.
    public var toolChoice: ToolChoice?

    /// Random seed for reproducible generation where supported by the provider.
    public var seed: Int?

    /// Whether parallel tool calls are allowed where supported by the provider.
    public var parallelToolCalls: Bool?

    /// Truncation strategy for oversized prompts where supported by the provider.
    public var truncation: TruncationStrategy?

    /// Verbosity preference where supported by the provider.
    public var verbosity: Verbosity?

    /// Provider-specific key/value options that should pass through untouched.
    public var providerSettings: [String: SendableValue]?

    /// Provider response identifier used to continue a prior conversation when supported.
    public var previousResponseId: String?

    /// Optional structured output contract for the request.
    public var structuredOutput: StructuredOutputRequest?

    /// Creates inference options.
    /// - Parameters:
    ///   - temperature: Generation temperature. Default: 1.0
    ///   - maxTokens: Maximum tokens. Default: nil
    ///   - stopSequences: Stop sequences. Default: []
    ///   - topP: Top-p sampling. Default: nil
    ///   - topK: Top-k sampling. Default: nil
    ///   - presencePenalty: Presence penalty. Default: nil
    ///   - frequencyPenalty: Frequency penalty. Default: nil
    ///   - toolChoice: Tool choice control. Default: nil
    ///   - seed: Deterministic seed. Default: nil
    ///   - parallelToolCalls: Allow parallel tool calls. Default: nil
    ///   - truncation: Truncation strategy. Default: nil
    ///   - verbosity: Verbosity preference. Default: nil
    ///   - providerSettings: Provider-specific pass-through settings. Default: nil
    ///   - previousResponseId: Previous response identifier for conversation continuation. Default: nil
    public init(
        temperature: Double = 1.0,
        maxTokens: Int? = nil,
        stopSequences: [String] = [],
        topP: Double? = nil,
        topK: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        toolChoice: ToolChoice? = nil,
        seed: Int? = nil,
        parallelToolCalls: Bool? = nil,
        truncation: TruncationStrategy? = nil,
        verbosity: Verbosity? = nil,
        providerSettings: [String: SendableValue]? = nil,
        previousResponseId: String? = nil,
        structuredOutput: StructuredOutputRequest? = nil
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.stopSequences = stopSequences
        self.topP = topP
        self.topK = topK
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.toolChoice = toolChoice
        self.seed = seed
        self.parallelToolCalls = parallelToolCalls
        self.truncation = truncation
        self.verbosity = verbosity
        self.providerSettings = providerSettings
        self.previousResponseId = previousResponseId
        self.structuredOutput = structuredOutput
    }

    // MARK: - Special Builder Methods

    /// Sets the stop sequences from variadic arguments.
    /// - Parameter sequences: Sequences that stop generation.
    /// - Returns: A modified options instance.
    public func stopSequences(_ sequences: String...) -> InferenceOptions {
        var copy = self
        copy.stopSequences = sequences
        return copy
    }

    /// Adds a single stop sequence.
    /// - Parameter sequence: The sequence to add.
    /// - Returns: A modified options instance.
    public func addStopSequence(_ sequence: String) -> InferenceOptions {
        var copy = self
        copy.stopSequences.append(sequence)
        return copy
    }

    /// Clears all stop sequences.
    /// - Returns: A modified options instance.
    public func clearStopSequences() -> InferenceOptions {
        var copy = self
        copy.stopSequences = []
        return copy
    }

    /// Creates a copy with custom modifications.
    /// - Parameter modifications: A closure that modifies the options.
    /// - Returns: A modified options instance.
    public func with(_ modifications: (inout InferenceOptions) -> Void) -> InferenceOptions {
        var copy = self
        modifications(&copy)
        return copy
    }
}

// MARK: - InferenceResponse

/// Response from an inference provider that may include tool calls.
///
/// This captures the model's output which can be either direct text
/// content, a request to call tools, or both.
public struct InferenceResponse: Sendable, Equatable {
    /// Why generation stopped.
    public enum FinishReason: String, Sendable, Codable {
        /// Generation completed normally.
        case completed
        /// Model requested tool calls.
        case toolCall
        /// Hit maximum token limit.
        case maxTokens
        /// Content was filtered.
        case contentFilter
        /// Generation was cancelled.
        case cancelled
    }

    /// A parsed tool call from the model's response.
    public struct ParsedToolCall: Sendable, Equatable {
        /// Unique identifier for this tool call (required for multi-turn tool conversations).
        public let id: String?

        /// The name of the tool to call.
        public let name: String

        /// The arguments for the tool.
        public let arguments: [String: SendableValue]

        /// Creates a parsed tool call.
        /// - Parameters:
        ///   - id: Unique identifier for the tool call. Default: nil
        ///   - name: The tool name.
        ///   - arguments: The tool arguments.
        public init(id: String? = nil, name: String, arguments: [String: SendableValue]) {
            self.id = id
            self.name = name
            self.arguments = arguments
        }
    }

    /// The text content of the response, if any.
    public let content: String?

    /// Tool calls requested by the model.
    public let toolCalls: [ParsedToolCall]

    /// The reason generation finished.
    public let finishReason: FinishReason

    /// Token usage statistics, if available.
    public let usage: TokenUsage?

    /// Whether this response includes tool calls.
    public var hasToolCalls: Bool {
        !toolCalls.isEmpty
    }

    /// Creates an inference response.
    /// - Parameters:
    ///   - content: Text content. Default: nil
    ///   - toolCalls: Tool calls. Default: []
    ///   - finishReason: Finish reason. Default: .completed
    ///   - usage: Token usage statistics. Default: nil
    public init(
        content: String? = nil,
        toolCalls: [ParsedToolCall] = [],
        finishReason: FinishReason = .completed,
        usage: TokenUsage? = nil
    ) {
        self.content = content
        self.toolCalls = toolCalls
        self.finishReason = finishReason
        self.usage = usage
    }
}
