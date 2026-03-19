// AgentConfiguration.swift
// Swarm Framework
//
// Runtime configuration settings for agent execution.

import Foundation
import Logging

/// Context envelope mode used by agent prompt construction.
public enum ContextMode: Sendable, Equatable {
    /// Adaptive context sizing based on configured profile/platform defaults.
    case adaptive

    /// Strict 4K token limit for context window.
    case strict4k
}

/// Optional Hive run options override for orchestration execution.
struct SwarmHiveRunOptionsOverride: Sendable, Equatable {
    var maxSteps: Int?
    var maxConcurrentTasks: Int?
    var debugPayloads: Bool?
    var deterministicTokenStreaming: Bool?
    var eventBufferCapacity: Int?

    init(
        maxSteps: Int? = nil,
        maxConcurrentTasks: Int? = nil,
        debugPayloads: Bool? = nil,
        deterministicTokenStreaming: Bool? = nil,
        eventBufferCapacity: Int? = nil
    ) {
        self.maxSteps = maxSteps
        self.maxConcurrentTasks = maxConcurrentTasks
        self.debugPayloads = debugPayloads
        self.deterministicTokenStreaming = deterministicTokenStreaming
        self.eventBufferCapacity = eventBufferCapacity
    }
}

// MARK: - InferencePolicy

/// Policy hints for model inference routing.
///
/// When running on the Hive runtime, these map to `HiveInferenceHints`.
public struct InferencePolicy: Sendable, Equatable {
    /// Desired latency tier for inference.
    public enum LatencyTier: String, Sendable, Equatable {
        /// Low-latency, interactive use (e.g., chat).
        case interactive
        /// Higher latency acceptable (e.g., batch processing).
        case background
    }

    /// Network conditions relevant to inference routing.
    public enum NetworkState: String, Sendable, Equatable {
        case offline
        case online
        case metered
    }

    /// Desired latency tier. Default: `.interactive`
    public var latencyTier: LatencyTier

    /// Whether on-device/private inference is required. Default: `false`
    public var privacyRequired: Bool

    /// Optional output token budget hint for inference.
    ///
    /// This limits the model's generation length, not the context window.
    /// For context window management, see ``AgentConfiguration/contextProfile``.
    /// Default: `nil`
    public var tokenBudget: Int?

    /// Current network state hint. Default: `.online`
    public var networkState: NetworkState

    public init(
        latencyTier: LatencyTier = .interactive,
        privacyRequired: Bool = false,
        tokenBudget: Int? = nil,
        networkState: NetworkState = .online
    ) {
        if let tokenBudget, tokenBudget <= 0 {
            Log.agents.warning("InferencePolicy: tokenBudget \(tokenBudget) must be > 0; dropping value")
        }
        self.latencyTier = latencyTier
        self.privacyRequired = privacyRequired
        self.tokenBudget = tokenBudget.flatMap { $0 > 0 ? $0 : nil }
        self.networkState = networkState
    }
}

// MARK: - AgentConfiguration

/// Configuration settings for agent execution.
///
/// Use this struct to customize agent behavior including iteration limits,
/// timeouts, model parameters, and execution options.
///
/// Example:
/// ```swift
/// let config = AgentConfiguration.default
///     .maxIterations(15)
///     .temperature(0.8)
///     .timeout(.seconds(120))
/// ```
/// Configuration settings for agent execution.
///
/// Use this struct to customize agent behavior including iteration limits,
/// timeouts, model parameters, and execution options.
///
/// ## Creating Configurations
///
/// Create a configuration using the static ``default`` property and chain
/// modifier methods to customize:
///
/// ```swift
/// let config = AgentConfiguration.default
///     .name("WeatherBot")
///     .maxIterations(20)
///     .temperature(0.8)
///     .timeout(.seconds(120))
/// ```
///
/// ## Builder Methods
///
/// All configuration properties have corresponding builder-style modifier
/// methods that return a new configuration with the updated value:
///
/// - ``name(_:)`` - Set the agent name
/// - ``maxIterations(_:)`` - Set iteration limit
/// - ``timeout(_:)`` - Set execution timeout
/// - ``temperature(_:)`` - Set model temperature
/// - ``maxTokens(_:)`` - Set token limit
/// - ``stopSequences(_:)`` - Set stop sequences
/// - ``modelSettings(_:)`` - Set extended model settings
/// - ``contextProfile(_:)`` - Set context profile
/// - ``contextMode(_:)`` - Set context mode
/// - ``inferencePolicy(_:)`` - Set inference routing policy
/// - ``enableStreaming(_:)`` - Set streaming behavior
/// - ``includeToolCallDetails(_:)`` - Set tool detail inclusion
/// - ``stopOnToolError(_:)`` - Set error handling behavior
/// - ``includeReasoning(_:)`` - Set reasoning inclusion
/// - ``sessionHistoryLimit(_:)`` - Set history limit
/// - ``parallelToolCalls(_:)`` - Set parallel execution
/// - ``previousResponseId(_:)`` - Set response continuation
/// - ``autoPreviousResponseId(_:)`` - Set auto response tracking
/// - ``defaultTracingEnabled(_:)`` - Set default tracing
///
/// ## Thread Safety
///
/// `AgentConfiguration` is a value type (`struct`) and is `Sendable`, making it
/// safe to pass across concurrency boundaries.
public struct AgentConfiguration: Sendable, Equatable {
    // MARK: - Default Configuration

    /// Default configuration with sensible defaults.
    public static let `default` = AgentConfiguration()

    // MARK: - Identity

    /// The name of the agent for identification and logging.
    /// Default: "Agent"
    public var name: String

    // MARK: - Iteration Limits

    /// Maximum number of reasoning iterations before stopping.
    /// Default: 10
    public var maxIterations: Int

    /// Maximum time allowed for the entire execution.
    /// Default: 60 seconds
    public var timeout: Duration

    // MARK: - Model Settings

    /// Temperature for model generation (0.0 = deterministic, 2.0 = creative).
    /// Default: 1.0
    public var temperature: Double

    /// Maximum tokens to generate per response.
    /// Default: nil (model default)
    public var maxTokens: Int?

    /// Sequences that will stop generation when encountered.
    /// Default: empty
    public var stopSequences: [String]

    /// Extended model settings for fine-grained control.
    ///
    /// When set, values in `modelSettings` take precedence over the individual
    /// `temperature`, `maxTokens`, and `stopSequences` properties above.
    /// This allows for backward compatibility while enabling advanced configuration.
    ///
    /// Example:
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .modelSettings(ModelSettings.creative
    ///         .toolChoice(.required)
    ///         .parallelToolCalls(true)
    ///     )
    /// ```
    public var modelSettings: ModelSettings?

    // MARK: - Context Settings

    /// Context budgeting profile for long-running agent workflows.
    ///
    /// Default: `.platformDefault`
    public var contextProfile: ContextProfile

    /// Context envelope mode for prompt construction.
    ///
    /// When set to `.strict4k`, the runtime uses `ContextProfile.strict4k`
    /// regardless of `contextProfile`.
    public var contextMode: ContextMode

    // MARK: - Hive Runtime Settings

    /// Internal Hive run options override for orchestration execution.
    ///
    /// This property is for internal framework use only. It allows fine-tuning
    /// of Hive runtime behavior during orchestration runs, including step limits,
    /// concurrency controls, and debug options.
    ///
    /// - Note: This is not part of the public API and may change without notice.
    /// - Important: Use standard configuration properties instead of this override
    ///   for stable, supported behavior.
    var hiveRunOptionsOverride: SwarmHiveRunOptionsOverride?

    /// Inference routing policy hints.
    ///
    /// Controls model selection when multiple backends are available. Use this
    /// to specify latency requirements, privacy constraints, token budgets,
    /// and network state preferences.
    ///
    /// When using the Hive runtime, these hints map directly to `HiveInferenceHints`.
    ///
    /// ## Use Cases
    /// - **Privacy**: Force on-device inference for sensitive data
    /// - **Latency**: Prioritize low-latency backends for real-time interactions
    /// - **Budget**: Limit output tokens to control costs
    ///
    /// ## Example
    /// ```swift
    /// let policy = InferencePolicy(
    ///     latencyTier: .interactive,
    ///     privacyRequired: true,  // Use on-device only
    ///     tokenBudget: 500
    /// )
    /// let config = AgentConfiguration.default
    ///     .inferencePolicy(policy)
    /// ```
    ///
    /// Default: `nil` (use default routing)
    ///
    /// - SeeAlso: ``InferencePolicy``
    public var inferencePolicy: InferencePolicy?

    // MARK: - Behavior Settings

    /// Whether to stream responses as they're generated.
    ///
    /// When enabled, the agent delivers response content incrementally through
    /// ``AgentEvent/responseChunk(_:)`` events. This provides better perceived
    /// performance and allows real-time UI updates.
    ///
    /// When disabled, the complete response is returned as a single
    /// ``AgentEvent/completion(_:)`` event.
    ///
    /// ## Example
    /// ```swift
    /// // Streaming (default) - good for interactive UIs
    /// let streamingConfig = AgentConfiguration.default
    ///     .enableStreaming(true)
    ///
    /// // Non-streaming - good for batch processing
    /// let batchConfig = AgentConfiguration.default
    ///     .enableStreaming(false)
    /// ```
    ///
    /// Default: `true`
    ///
    /// - SeeAlso: ``AgentEvent/responseChunk(_:)``
    public var enableStreaming: Bool

    /// Whether to include detailed tool call information in the result.
    ///
    /// When enabled, the agent includes ``ToolCallDetail`` objects in the
    /// ``AgentResponse/toolCalls`` array, showing which tools were called,
    /// with what arguments, and their results.
    ///
    /// This is useful for:
    /// - Debugging agent behavior
    /// - Audit logging
    /// - Building execution traces
    /// - UI displays showing tool usage
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .includeToolCallDetails(true)
    ///
    /// // Later, inspect the response
    /// let response = try await agent.run("...", config: config)
    /// for detail in response.toolCalls {
    ///     print("Tool: \(detail.name), Result: \(detail.result)")
    /// }
    /// ```
    ///
    /// Default: `true`
    ///
    /// - SeeAlso: ``ToolCallDetail``, ``AgentResponse/toolCalls``
    public var includeToolCallDetails: Bool

    /// Whether to stop execution after the first tool error.
    ///
    /// When `true`, if any tool call throws an error, execution immediately
    /// stops and the error is propagated to the caller. This is useful when
    /// you want strict error handling and don't want partial results.
    ///
    /// When `false` (default), tool errors are included in the response's
    /// ``ToolCallDetail/error`` field and execution continues. The agent
    /// may attempt to recover or provide partial results.
    ///
    /// ## Example
    /// ```swift
    /// // Strict mode - fail fast on any error
    /// let strictConfig = AgentConfiguration.default
    ///     .stopOnToolError(true)
    ///
    /// // Lenient mode - collect all results including errors
    /// let lenientConfig = AgentConfiguration.default
    ///     .stopOnToolError(false)
    /// ```
    ///
    /// Default: `false`
    ///
    /// - SeeAlso: ``ToolCallDetail/error``, ``AgentError/toolCallFailed(_:)``
    public var stopOnToolError: Bool

    /// Whether to include the agent's reasoning/thinking in events.
    ///
    /// When enabled, the agent emits ``AgentEvent/reasoning(_:)`` events
    /// containing its chain-of-thought or reasoning process. This helps
    /// understand how the agent arrived at its conclusions.
    ///
    /// Reasoning may include:
    /// - Step-by-step problem solving
    /// - Tool selection rationale
    /// - Confidence assessments
    /// - Intermediate conclusions
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .includeReasoning(true)
    ///
    /// for try await event in agent.stream("...", config: config) {
    ///     if case .reasoning(let text) = event {
    ///         print("Thinking: \(text)")
    ///     }
    /// }
    /// ```
    ///
    /// Default: `true`
    ///
    /// - SeeAlso: ``AgentEvent/reasoning(_:)``
    public var includeReasoning: Bool

    // MARK: - Session Settings

    /// Maximum number of session history messages to load on each agent run.
    ///
    /// When a ``ConversationSession`` is provided to an agent, this controls
    /// how many recent messages are loaded as context. Older messages are
    /// excluded, which helps manage token usage and context window limits.
    ///
    /// Set to `nil` to load all messages (use with caution on long sessions).
    ///
    /// ## Performance Impact
    /// - Lower values: Faster inference, less token usage, but less context
    /// - Higher values: More context, but slower and more expensive
    ///
    /// ## Example
    /// ```swift
    /// // Recent context only (default)
    /// let recentConfig = AgentConfiguration.default
    ///     .sessionHistoryLimit(20)
    ///
    /// // Full history for important conversations
    /// let fullConfig = AgentConfiguration.default
    ///     .sessionHistoryLimit(nil)
    /// ```
    ///
    /// Default: 50
    ///
    /// - SeeAlso: ``ConversationSession``
    public var sessionHistoryLimit: Int?

    // MARK: - Parallel Execution Settings

    /// Whether to execute multiple tool calls in parallel.
    ///
    /// When enabled, if the agent requests multiple tool calls in a single turn,
    /// they will be executed concurrently using Swift's structured concurrency.
    /// This can significantly improve performance but may increase resource usage.
    ///
    /// ## Performance Impact
    /// - Sequential: Each tool waits for previous to complete
    /// - Parallel: All tools execute simultaneously
    /// - Speedup: Up to N× faster (where N = number of tools)
    ///
    /// ## Requirements
    /// - Tools must be independent (no shared mutable state)
    /// - All tools must be thread-safe
    ///
    /// ## Example
    /// ```swift
    /// // Enable parallel execution for independent tools
    /// let config = AgentConfiguration.default
    ///     .parallelToolCalls(true)
    ///
    /// // Good for: fetching data from multiple APIs
    /// // Bad for: tools that modify shared resources
    /// ```
    ///
    /// Default: `false`
    ///
    /// - SeeAlso: ``Agent/tools``, ``AgentConfiguration/stopOnToolError``
    public var parallelToolCalls: Bool

    // MARK: - Response Tracking Settings

    /// Previous response ID for conversation continuation.
    ///
    /// Set this to continue a conversation from a specific response.
    /// The agent uses this ID to retrieve context and maintain continuity
    /// across separate `run()` calls or sessions.
    ///
    /// This is typically used when:
    /// - Resuming a conversation after app restart
    /// - Connecting separate agent runs into a coherent thread
    /// - Implementing conversation branching
    ///
    /// - Note: Usually set automatically when `autoPreviousResponseId` is enabled
    /// - Important: The ID must be a valid response ID from a previous run
    ///
    /// ## Example
    /// ```swift
    /// // Store the response ID for later continuation
    /// let response1 = try await agent.run("Hello")
    /// let responseId = response1.responseId
    ///
    /// // Continue the conversation later
    /// let config = AgentConfiguration.default
    ///     .previousResponseId(responseId)
    /// let response2 = try await agent.run("How are you?", config: config)
    /// ```
    ///
    /// - SeeAlso: ``AgentResponse/responseId``, ``autoPreviousResponseId``
    public var previousResponseId: String?

    /// Whether to automatically populate previous response ID.
    ///
    /// When enabled, the agent automatically tracks response IDs from each
    /// run and uses them for conversation continuation within a session.
    /// This provides seamless multi-turn conversations without manual ID management.
    ///
    /// ## Behavior
    /// - After each `run()`, the response ID is automatically stored
    /// - The next `run()` automatically uses this ID for continuation
    /// - Works within a single agent instance's lifetime
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .autoPreviousResponseId(true)
    ///
    /// let agent = Agent(configuration: config)
    ///
    /// // These are automatically connected into one conversation
    /// let r1 = try await agent.run("What's the weather?")
    /// let r2 = try await agent.run("And tomorrow?")  // Automatically continues
    /// ```
    ///
    /// Default: `false`
    ///
    /// - SeeAlso: ``previousResponseId``, ``AgentResponse/responseId``
    public var autoPreviousResponseId: Bool

    // MARK: - Observability Settings

    /// Whether to enable default tracing when no explicit tracer is configured.
    ///
    /// When `true` and no tracer is set on the agent or via environment,
    /// the agent automatically uses a `SwiftLogTracer` at `.debug` level
    /// for execution tracing. Set to `false` to disable automatic tracing.
    ///
    /// ## Tracing Behavior
    /// - `true` + no tracer: Uses `SwiftLogTracer` with `.debug` level
    /// - `true` + tracer set: Uses the configured tracer
    /// - `false`: No tracing regardless of other settings
    ///
    /// ## Example
    /// ```swift
    /// // Default tracing (uses SwiftLogTracer)
    /// let config1 = AgentConfiguration.default
    ///     .defaultTracingEnabled(true)
    ///
    /// // No automatic tracing
    /// let config2 = AgentConfiguration.default
    ///     .defaultTracingEnabled(false)
    ///
    /// // Custom tracer takes precedence
    /// let agent = Agent(configuration: config2, tracer: myCustomTracer)
    /// ```
    ///
    /// Default: `true`
    ///
    /// - SeeAlso: ``Agent/init(configuration:instructions:tools:outputSchema:tracer:)``,
    ///   ``SwiftLogTracer``
    public var defaultTracingEnabled: Bool

    // MARK: - Initialization

    /// Creates a new agent configuration.
    /// - Parameters:
    ///   - name: The agent name for identification. Default: "Agent"
    ///   - maxIterations: Maximum reasoning iterations. Default: 10
    ///   - timeout: Maximum execution time. Default: 60 seconds
    ///   - temperature: Model temperature (0.0-2.0). Default: 1.0
    ///   - maxTokens: Maximum tokens per response. Default: nil
    ///   - stopSequences: Generation stop sequences. Default: []
    ///   - modelSettings: Extended model settings. Default: nil
    ///   - enableStreaming: Enable response streaming. Default: true
    ///   - includeToolCallDetails: Include tool details in results. Default: true
    ///   - stopOnToolError: Stop on first tool error. Default: false
    ///   - includeReasoning: Include reasoning in events. Default: true
    ///   - sessionHistoryLimit: Maximum session history messages to load. Default: 50
    ///   - contextMode: Context envelope mode. Default: `.adaptive`
    ///   - contextProfile: Context budgeting profile. Default: `.platformDefault`
    ///   - inferencePolicy: Inference routing policy hints. Default: nil
    ///   - parallelToolCalls: Enable parallel tool execution. Default: false
    ///   - previousResponseId: Previous response ID for continuation. Default: nil
    ///   - autoPreviousResponseId: Enable auto response ID tracking. Default: false
    ///   - defaultTracingEnabled: Enable default tracing when no tracer configured. Default: true
    public init(
        name: String = "Agent",
        maxIterations: Int = 10,
        timeout: Duration = .seconds(60),
        temperature: Double = 1.0,
        maxTokens: Int? = nil,
        stopSequences: [String] = [],
        modelSettings: ModelSettings? = nil,
        contextProfile: ContextProfile = .platformDefault,
        inferencePolicy: InferencePolicy? = nil,
        enableStreaming: Bool = true,
        includeToolCallDetails: Bool = true,
        stopOnToolError: Bool = false,
        includeReasoning: Bool = true,
        sessionHistoryLimit: Int? = 50,
        contextMode: ContextMode = .adaptive,
        parallelToolCalls: Bool = false,
        previousResponseId: String? = nil,
        autoPreviousResponseId: Bool = false,
        defaultTracingEnabled: Bool = true
    ) {
        if maxIterations < 1 {
            Log.agents.warning("AgentConfiguration: maxIterations \(maxIterations) must be >= 1; using 1")
        }
        if timeout <= .zero {
            Log.agents.warning("AgentConfiguration: timeout must be positive; using default 60 seconds")
        }
        if !temperature.isFinite || !(0.0 ... 2.0).contains(temperature) {
            Log.agents.warning("AgentConfiguration: temperature \(temperature) out of [0.0, 2.0]; using default 1.0")
        }
        self.name = name
        self.maxIterations = max(1, maxIterations)
        self.timeout = timeout > .zero ? timeout : .seconds(60)
        self.temperature = (temperature.isFinite && (0.0 ... 2.0).contains(temperature)) ? temperature : 1.0
        self.maxTokens = maxTokens
        self.stopSequences = stopSequences
        self.modelSettings = modelSettings
        self.contextProfile = contextProfile
        self.hiveRunOptionsOverride = nil
        self.inferencePolicy = inferencePolicy
        self.enableStreaming = enableStreaming
        self.includeToolCallDetails = includeToolCallDetails
        self.stopOnToolError = stopOnToolError
        self.includeReasoning = includeReasoning
        self.sessionHistoryLimit = sessionHistoryLimit
        self.contextMode = contextMode
        self.parallelToolCalls = parallelToolCalls
        self.previousResponseId = previousResponseId
        self.autoPreviousResponseId = autoPreviousResponseId
        self.defaultTracingEnabled = defaultTracingEnabled
    }
}

// MARK: - Builder Modifier Methods

extension AgentConfiguration {
    // MARK: Identity

    /// Sets the name of the agent for identification and logging.
    ///
    /// The name is used in log messages, debug output, and tracing to identify
    /// which agent is executing. Choose descriptive names for better observability
    /// when running multiple agents.
    ///
    /// Default: "Agent"
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .name("WeatherAssistant")
    /// ```
    ///
    /// - Parameter value: The agent name for identification
    /// - Returns: A new configuration with the updated name
    /// - SeeAlso: ``name``
    @discardableResult public func name(_ value: String) -> AgentConfiguration {
        var copy = self
        copy.name = value
        return copy
    }

    // MARK: Iteration Limits

    /// Sets the maximum number of reasoning iterations before stopping.
    ///
    /// Prevents infinite loops by limiting how many times the agent can
    /// call tools and receive responses. When the limit is reached,
    /// ``AgentError/maxIterationsExceeded(iterations:)`` is thrown.
    ///
    /// Each iteration consists of:
    /// 1. Sending the current context to the model
    /// 2. Receiving the model's response
    /// 3. Executing any requested tool calls
    /// 4. Adding results to the context
    ///
    /// Default: 10
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .maxIterations(20)  // Allow more iterations for complex tasks
    /// ```
    ///
    /// - Parameter value: Maximum reasoning iterations (must be >= 1)
    /// - Returns: A new configuration with the updated iteration limit
    /// - SeeAlso: ``maxIterations``, ``timeout(_:)``, ``stopOnToolError(_:)``
    @discardableResult public func maxIterations(_ value: Int) -> AgentConfiguration {
        var copy = self
        copy.maxIterations = value
        return copy
    }

    /// Sets the maximum time allowed for the entire execution.
    ///
    /// If execution exceeds this duration, ``AgentError/executionTimeout``
    /// is thrown and the agent stops processing. This includes time spent
    /// on model inference and tool execution.
    ///
    /// ## Use Cases
    /// - Prevent long-running tasks from hanging
    /// - Enforce SLA requirements
    /// - Control costs in pay-per-use environments
    ///
    /// Default: 60 seconds
    ///
    /// ## Example
    /// ```swift
    /// // Quick responses for interactive use
    /// let quickConfig = AgentConfiguration.default
    ///     .timeout(.seconds(10))
    ///
    /// // Longer timeout for complex analysis
    /// let analysisConfig = AgentConfiguration.default
    ///     .timeout(.minutes(5))
    /// ```
    ///
    /// - Parameter value: Maximum execution time
    /// - Returns: A new configuration with the updated timeout
    /// - SeeAlso: ``timeout``, ``maxIterations(_:)``
    @discardableResult public func timeout(_ value: Duration) -> AgentConfiguration {
        var copy = self
        copy.timeout = value
        return copy
    }

    // MARK: Model Settings

    /// Sets the temperature for model generation.
    ///
    /// Controls the randomness/creativity of the model's output:
    /// - `0.0`: Deterministic, always picks the most likely token
    /// - `0.7`: Balanced, some creativity while staying focused
    /// - `1.0`: Default, moderate creativity
    /// - `2.0`: Maximum creativity, more varied outputs
    ///
    /// ## When to Adjust
    /// - Lower for: code generation, factual queries, structured output
    /// - Higher for: creative writing, brainstorming, diverse suggestions
    ///
    /// Default: 1.0
    ///
    /// ## Example
    /// ```swift
    /// // Creative writing
    /// let creativeConfig = AgentConfiguration.default
    ///     .temperature(1.2)
    ///
    /// // Precise code generation
    /// let codeConfig = AgentConfiguration.default
    ///     .temperature(0.2)
    /// ```
    ///
    /// - Parameter value: Temperature between 0.0 and 2.0
    /// - Returns: A new configuration with the updated temperature
    /// - SeeAlso: ``temperature``, ``maxTokens(_:)``, ``modelSettings(_:)``
    @discardableResult public func temperature(_ value: Double) -> AgentConfiguration {
        var copy = self
        copy.temperature = value
        return copy
    }

    /// Sets the maximum tokens to generate per response.
    ///
    /// Limits the length of the model's output. This is useful for:
    /// - Controlling costs in token-based pricing
    /// - Preventing overly long responses
    /// - Ensuring responses fit within display constraints
    ///
    /// Note: This limits output length, not the context window. For context
    /// management, see ``contextProfile(_:)``.
    ///
    /// Default: nil (model default)
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .maxTokens(500)  // Keep responses concise
    /// ```
    ///
    /// - Parameter value: Maximum tokens per response, or nil for model default
    /// - Returns: A new configuration with the updated token limit
    /// - SeeAlso: ``maxTokens``, ``temperature(_:)``, ``contextProfile(_:)``
    @discardableResult public func maxTokens(_ value: Int?) -> AgentConfiguration {
        var copy = self
        copy.maxTokens = value
        return copy
    }

    /// Sets the sequences that will stop generation when encountered.
    ///
    /// When the model generates any of these sequences, it stops immediately
    /// and returns the response up to that point. This is useful for:
    /// - Stopping at natural boundaries ("END", "STOP")
    /// - Preventing runaway generation
    /// - Integrating with parsing pipelines
    ///
    /// Default: empty
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .stopSequences(["END", "<|end|>"])
    /// ```
    ///
    /// - Parameter value: Array of stop sequences
    /// - Returns: A new configuration with the updated stop sequences
    /// - SeeAlso: ``stopSequences``
    @discardableResult public func stopSequences(_ value: [String]) -> AgentConfiguration {
        var copy = self
        copy.stopSequences = value
        return copy
    }

    /// Sets extended model settings for fine-grained control.
    ///
    /// When set, values in `modelSettings` take precedence over individual
    /// properties like `temperature`, `maxTokens`, and `stopSequences`.
    /// This enables advanced configuration options not exposed as top-level
    /// properties.
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .modelSettings(ModelSettings.creative
    ///         .toolChoice(.required)
    ///         .parallelToolCalls(true)
    ///     )
    /// ```
    ///
    /// - Parameter value: Extended model settings, or nil to use individual properties
    /// - Returns: A new configuration with the updated model settings
    /// - SeeAlso: ``modelSettings``, ``temperature(_:)``, ``maxTokens(_:)``
    @discardableResult public func modelSettings(_ value: ModelSettings?) -> AgentConfiguration {
        var copy = self
        copy.modelSettings = value
        return copy
    }

    // MARK: Context Settings

    /// Sets the context budgeting profile for long-running workflows.
    ///
    /// Controls how the agent manages the context window as conversations
    /// grow long. Different profiles optimize for different use cases:
    /// - ``ContextProfile/platformDefault``: Automatic platform-optimized settings
    /// - ``ContextProfile/strict4k``: Hard 4K token limit
    /// - ``ContextProfile/custom(_:)``: Custom truncation strategy
    ///
    /// Default: `.platformDefault`
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .contextProfile(.strict4k)
    /// ```
    ///
    /// - Parameter value: The context budgeting profile
    /// - Returns: A new configuration with the updated context profile
    /// - SeeAlso: ``contextProfile``, ``contextMode(_:)``
    @discardableResult public func contextProfile(_ value: ContextProfile) -> AgentConfiguration {
        var copy = self
        copy.contextProfile = value
        return copy
    }

    /// Sets the context envelope mode for prompt construction.
    ///
    /// Controls how the context window is managed:
    /// - ``ContextMode/adaptive``: Uses the configured `contextProfile`
    /// - ``ContextMode/strict4k``: Forces `ContextProfile.strict4k` regardless of profile
    ///
    /// Default: `.adaptive`
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .contextMode(.strict4k)
    /// ```
    ///
    /// - Parameter value: The context envelope mode
    /// - Returns: A new configuration with the updated context mode
    /// - SeeAlso: ``contextMode``, ``contextProfile(_:)``
    @discardableResult public func contextMode(_ value: ContextMode) -> AgentConfiguration {
        var copy = self
        copy.contextMode = value
        return copy
    }

    // MARK: Hive Runtime Settings

    /// Sets the inference routing policy hints.
    ///
    /// Controls model selection when multiple backends are available.
    /// Use this to specify latency requirements, privacy constraints,
    /// token budgets, and network state preferences.
    ///
    /// ## Example
    /// ```swift
    /// let policy = InferencePolicy(
    ///     latencyTier: .interactive,
    ///     privacyRequired: true,
    ///     tokenBudget: 500
    /// )
    /// let config = AgentConfiguration.default
    ///     .inferencePolicy(policy)
    /// ```
    ///
    /// - Parameter value: Inference routing policy, or nil for default routing
    /// - Returns: A new configuration with the updated inference policy
    /// - SeeAlso: ``inferencePolicy``, ``InferencePolicy``
    @discardableResult public func inferencePolicy(_ value: InferencePolicy?) -> AgentConfiguration {
        var copy = self
        copy.inferencePolicy = value
        return copy
    }

    // MARK: Behavior Settings

    /// Sets whether to stream responses as they're generated.
    ///
    /// When enabled, the agent delivers response content incrementally through
    /// ``AgentEvent/responseChunk(_:)`` events. This provides better perceived
    /// performance and allows real-time UI updates.
    ///
    /// Default: true
    ///
    /// ## Example
    /// ```swift
    /// // Non-streaming for batch processing
    /// let batchConfig = AgentConfiguration.default
    ///     .enableStreaming(false)
    /// ```
    ///
    /// - Parameter value: true to enable streaming, false for complete responses
    /// - Returns: A new configuration with the updated streaming setting
    /// - SeeAlso: ``enableStreaming``, ``AgentEvent/responseChunk(_:)``
    @discardableResult public func enableStreaming(_ value: Bool) -> AgentConfiguration {
        var copy = self
        copy.enableStreaming = value
        return copy
    }

    /// Sets whether to include detailed tool call information in the result.
    ///
    /// When enabled, ``ToolCallDetail`` objects are included in the
    /// ``AgentResponse/toolCalls`` array, showing which tools were called,
    /// with what arguments, and their results.
    ///
    /// Default: true
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .includeToolCallDetails(true)
    /// ```
    ///
    /// - Parameter value: true to include tool call details
    /// - Returns: A new configuration with the updated setting
    /// - SeeAlso: ``includeToolCallDetails``, ``ToolCallDetail``
    @discardableResult public func includeToolCallDetails(_ value: Bool) -> AgentConfiguration {
        var copy = self
        copy.includeToolCallDetails = value
        return copy
    }

    /// Sets whether to stop execution after the first tool error.
    ///
    /// When `true`, if any tool call throws an error, execution immediately
    /// stops and the error is propagated. When `false`, errors are captured
    /// and execution continues.
    ///
    /// Default: false
    ///
    /// ## Example
    /// ```swift
    /// // Strict mode - fail fast
    /// let strictConfig = AgentConfiguration.default
    ///     .stopOnToolError(true)
    /// ```
    ///
    /// - Parameter value: true to stop on first tool error
    /// - Returns: A new configuration with the updated error handling setting
    /// - SeeAlso: ``stopOnToolError``, ``ToolCallDetail/error``
    @discardableResult public func stopOnToolError(_ value: Bool) -> AgentConfiguration {
        var copy = self
        copy.stopOnToolError = value
        return copy
    }

    /// Sets whether to include the agent's reasoning in events.
    ///
    /// When enabled, the agent emits ``AgentEvent/reasoning(_:)`` events
    /// containing its chain-of-thought or reasoning process.
    ///
    /// Default: true
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .includeReasoning(true)
    /// ```
    ///
    /// - Parameter value: true to include reasoning events
    /// - Returns: A new configuration with the updated reasoning setting
    /// - SeeAlso: ``includeReasoning``, ``AgentEvent/reasoning(_:)``
    @discardableResult public func includeReasoning(_ value: Bool) -> AgentConfiguration {
        var copy = self
        copy.includeReasoning = value
        return copy
    }

    // MARK: Session Settings

    /// Sets the maximum number of session history messages to load.
    ///
    /// Controls how many recent messages are loaded when a ``ConversationSession``
    /// is provided. Set to `nil` to load all messages (use with caution).
    ///
    /// Default: 50
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .sessionHistoryLimit(20)  // Use only recent context
    /// ```
    ///
    /// - Parameter value: Maximum messages to load, or nil for all
    /// - Returns: A new configuration with the updated history limit
    /// - SeeAlso: ``sessionHistoryLimit``, ``ConversationSession``
    @discardableResult public func sessionHistoryLimit(_ value: Int?) -> AgentConfiguration {
        var copy = self
        copy.sessionHistoryLimit = value
        return copy
    }

    // MARK: Parallel Execution Settings

    /// Sets whether to execute multiple tool calls in parallel.
    ///
    /// When enabled, multiple tool calls in a single turn are executed
    /// concurrently using Swift's structured concurrency.
    ///
    /// Default: false
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .parallelToolCalls(true)
    /// ```
    ///
    /// - Parameter value: true to enable parallel execution
    /// - Returns: A new configuration with the updated parallel setting
    /// - SeeAlso: ``parallelToolCalls``
    @discardableResult public func parallelToolCalls(_ value: Bool) -> AgentConfiguration {
        var copy = self
        copy.parallelToolCalls = value
        return copy
    }

    // MARK: Response Tracking Settings

    /// Sets the previous response ID for conversation continuation.
    ///
    /// Set this to continue a conversation from a specific response.
    /// The ID must be from a previous run in the same session.
    ///
    /// - Note: Usually set automatically when `autoPreviousResponseId` is enabled
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .previousResponseId("resp_123abc")
    /// ```
    ///
    /// - Parameter value: Previous response ID, or nil to start fresh
    /// - Returns: A new configuration with the updated response ID
    /// - SeeAlso: ``previousResponseId``, ``autoPreviousResponseId(_:)``
    @discardableResult public func previousResponseId(_ value: String?) -> AgentConfiguration {
        var copy = self
        copy.previousResponseId = value
        return copy
    }

    /// Sets whether to automatically populate previous response ID.
    ///
    /// When enabled, the agent automatically tracks response IDs from each
    /// run and uses them for conversation continuation within a session.
    ///
    /// Default: false
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .autoPreviousResponseId(true)
    /// ```
    ///
    /// - Parameter value: true to enable automatic response ID tracking
    /// - Returns: A new configuration with the updated auto-tracking setting
    /// - SeeAlso: ``autoPreviousResponseId``, ``previousResponseId(_:)``
    @discardableResult public func autoPreviousResponseId(_ value: Bool) -> AgentConfiguration {
        var copy = self
        copy.autoPreviousResponseId = value
        return copy
    }

    // MARK: Observability Settings

    /// Sets whether to enable default tracing when no explicit tracer is configured.
    ///
    /// When `true` and no tracer is set, the agent automatically uses a
    /// `SwiftLogTracer` at `.debug` level for execution tracing.
    ///
    /// Default: true
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .defaultTracingEnabled(false)  // Disable automatic tracing
    /// ```
    ///
    /// - Parameter value: true to enable default tracing
    /// - Returns: A new configuration with the updated tracing setting
    /// - SeeAlso: ``defaultTracingEnabled``, ``SwiftLogTracer``
    @discardableResult public func defaultTracingEnabled(_ value: Bool) -> AgentConfiguration {
        var copy = self
        copy.defaultTracingEnabled = value
        return copy
    }
}

// MARK: - CustomStringConvertible

extension AgentConfiguration: CustomStringConvertible {
    public var description: String {
        """
        AgentConfiguration(
            name: "\(name)",
            maxIterations: \(maxIterations),
            timeout: \(timeout),
            temperature: \(temperature),
            maxTokens: \(maxTokens.map(String.init) ?? "nil"),
            stopSequences: \(stopSequences),
            modelSettings: \(modelSettings.map { String(describing: $0) } ?? "nil"),
            contextProfile: \(contextProfile),
            hiveRunOptionsOverride: \(hiveRunOptionsOverride.map { String(describing: $0) } ?? "nil"),
            inferencePolicy: \(inferencePolicy.map { String(describing: $0) } ?? "nil"),
            enableStreaming: \(enableStreaming),
            includeToolCallDetails: \(includeToolCallDetails),
            stopOnToolError: \(stopOnToolError),
            includeReasoning: \(includeReasoning),
            sessionHistoryLimit: \(sessionHistoryLimit.map(String.init) ?? "nil"),
            contextMode: \(contextMode),
            parallelToolCalls: \(parallelToolCalls),
            previousResponseId: \(previousResponseId.map { "\"\($0)\"" } ?? "nil"),
            autoPreviousResponseId: \(autoPreviousResponseId),
            defaultTracingEnabled: \(defaultTracingEnabled)
        )
        """
    }
}
