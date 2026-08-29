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

/// Optional graph runtime override for orchestration execution.
struct SwarmGraphRunOptionsOverride: Sendable, Equatable {
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
/// When running on the graph runtime, these hints are forwarded to the internal routing engine.
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
    ///
    /// Post-initialization writes are coerced like the initializer: values of
    /// zero or less are dropped to `nil` (with a `Log.agents` warning), so a
    /// write of `-5` reads back as `nil`.
    ///
    /// Default: `nil`
    public var tokenBudget: Int? {
        didSet { tokenBudget = Self.coercedTokenBudget(tokenBudget) }
    }

    /// Current network state hint. Default: `.online`
    public var networkState: NetworkState

    public init(
        latencyTier: LatencyTier = .interactive,
        privacyRequired: Bool = false,
        tokenBudget: Int? = nil,
        networkState: NetworkState = .online
    ) {
        self.latencyTier = latencyTier
        self.privacyRequired = privacyRequired
        self.tokenBudget = Self.coercedTokenBudget(tokenBudget)
        self.networkState = networkState
    }
}

// MARK: - InferencePolicy Write-Path Coercion

private extension InferencePolicy {
    /// Drops non-positive token budgets to `nil`, matching the designated
    /// initializer; warns via ``Log/agents`` when dropped. Shared by `init`
    /// and `didSet` so both write paths stay identical.
    static func coercedTokenBudget(_ value: Int?) -> Int? {
        guard let value, value > 0 else {
            if let value {
                Log.agents.warning("InferencePolicy: tokenBudget \(value) must be > 0; dropping value")
            }
            return nil
        }
        return value
    }
}

// MARK: - AgentConfiguration

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
/// - ``includeToolCallDetails(_:)`` - Legacy result-detail compatibility setting
/// - ``stopOnToolError(_:)`` - Set error handling behavior
/// - ``includeReasoning(_:)`` - Legacy reasoning-event compatibility setting
/// - ``sessionHistoryLimit(_:)`` - Set history limit
/// - ``parallelToolCalls(_:)`` - Set parallel execution
/// - ``previousResponseId(_:)`` - Set response continuation
/// - ``autoPreviousResponseId(_:)`` - Set auto response tracking
/// - ``defaultTracingEnabled(_:)`` - Set default tracing
/// - ``autoAttachMetricsCollector(_:)`` - Auto-attach a ``MetricsCollector``
/// - ``resilience(_:)`` - Set retry, circuit-breaker, and rate-limit policies for inference
///
/// ## Thread Safety
///
/// `AgentConfiguration` is a value type (`struct`) and is `Sendable`, making it
/// safe to pass across concurrency boundaries.
///
/// ## Post-Initialization Writes
///
/// ``maxIterations``, ``timeout``, and ``temperature`` are mutation-proofed:
/// `didSet` observers coerce any write with the exact same rules (and
/// ``Log/agents`` warnings) as the designated initializer, so e.g.
/// `config.maxIterations = 0` reads back as `1`. Property setters cannot
/// throw, which is why invalid values are coerced rather than rejected.
public struct AgentConfiguration: Sendable, Equatable {
    // MARK: - Default Configuration

    /// Default configuration with sensible defaults.
    public static let `default` = AgentConfiguration()

    /// Recommended defaults for on-device agents.
    public static var onDeviceDefault: AgentConfiguration {
        #if os(macOS)
        AgentConfiguration(
            contextProfile: .platformDefault,
            sessionHistoryLimit: 24
        )
        #else
        AgentConfiguration(
            sessionHistoryLimit: 12,
            contextMode: .strict4k
        )
        #endif
    }

    // MARK: - Identity

    /// The name of the agent for identification and logging.
    /// Default: "Agent"
    public var name: String

    // MARK: - Iteration Limits

    /// Maximum number of reasoning iterations before stopping.
    /// Default: 10
    ///
    /// Post-initialization writes are coerced like the initializer: values
    /// below 1 self-correct to 1 (with a `Log.agents` warning), so a write of
    /// `0` reads back as `1`.
    public var maxIterations: Int {
        didSet { maxIterations = Self.coercedMaxIterations(maxIterations) }
    }

    /// Maximum time allowed for the entire execution.
    /// Default: 60 seconds
    ///
    /// Post-initialization writes are coerced like the initializer: non-positive
    /// durations fall back to the 60-second default (with a `Log.agents` warning).
    public var timeout: Duration {
        didSet { timeout = Self.coercedTimeout(timeout) }
    }

    // MARK: - Model Settings

    /// Temperature for model generation (0.0 = deterministic, 2.0 = creative).
    /// Default: 1.0
    ///
    /// Post-initialization writes are coerced like the initializer: non-finite
    /// or out-of-range values fall back to 1.0 (with a `Log.agents` warning).
    public var temperature: Double {
        didSet { temperature = Self.coercedTemperature(temperature) }
    }

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

    // MARK: - Graph Runtime Settings

    /// Internal graph runtime override for orchestration execution.
    ///
    /// This property is for internal framework use only. It allows fine-tuning
    /// of graph runtime behavior during orchestration runs, including step limits,
    /// concurrency controls, and debug options.
    ///
    /// - Note: This is not part of the public API and may change without notice.
    /// - Important: Use standard configuration properties instead of this override
    ///   for stable, supported behavior.
    var graphRunOptionsOverride: SwarmGraphRunOptionsOverride?

    /// Inference routing policy hints.
    ///
    /// Controls model selection when multiple backends are available. Use this
    /// to specify latency requirements, privacy constraints, token budgets,
    /// and network state preferences.
    ///
    /// When using the graph runtime, these hints feed the runtime's internal routing layer.
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
    /// ``AgentEvent/output(_:)`` events such as
    /// ``AgentEvent/Output/token(_:)`` and ``AgentEvent/Output/chunk(_:)``.
    /// When disabled, the agent emits the completed response through
    /// ``AgentEvent/Lifecycle/completed(result:)``.
    ///
    /// Default: `true`
    ///
    /// - SeeAlso: ``AgentEvent/output(_:)``, ``AgentEvent/Lifecycle/completed(result:)``
    public var enableStreaming: Bool

    /// Legacy compatibility setting for result detail inclusion.
    ///
    /// This property currently has no effect. Tool execution details are always
    /// recorded in ``AgentResult/toolCalls`` and ``AgentResult/toolResults``;
    /// ``AgentResponse/toolCalls`` exposes the corresponding ``ToolCallRecord``
    /// values. It remains available so existing configurations continue to
    /// compile, but new code should not depend on this flag.
    ///
    /// Default: `true`
    ///
    /// - SeeAlso: ``AgentResult/toolCalls``, ``AgentResult/toolResults``,
    ///   ``AgentResponse/toolCalls``
    public var includeToolCallDetails: Bool

    /// Whether to stop execution after the first tool error.
    ///
    /// When `true`, if any tool call throws an error, execution immediately
    /// stops and the error is propagated to the caller. This is useful when
    /// you want strict error handling and don't want partial results.
    ///
    /// When `false` (default), tool errors are recorded as
    /// ``ToolResult/Outcome/failure(message:)`` and execution continues. The
    /// agent may attempt to recover or provide partial results. When `true`, a
    /// failure is propagated as ``AgentError/toolFailure(toolName:message:cause:)``.
    ///
    /// Default: `false`
    ///
    /// - SeeAlso: ``ToolResult``, ``AgentError/toolFailure(toolName:message:cause:)``
    public var stopOnToolError: Bool

    /// Legacy compatibility setting for reasoning-event inclusion.
    ///
    /// This property currently has no effect. If a provider emits reasoning,
    /// the runtime exposes it as ``AgentEvent/Output/thinking(thought:)`` or
    /// ``AgentEvent/Output/thinkingPartial(_:)`` inside
    /// ``AgentEvent/output(_:)``. Consumers should filter those current event
    /// cases rather than rely on this flag.
    ///
    /// Default: `true`
    ///
    /// - SeeAlso: ``AgentEvent/output(_:)``, ``AgentEvent/Output/thinking(thought:)``
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

    /// Whether to auto-attach a ``MetricsCollector`` so execution metrics flow
    /// without passing a tracer manually.
    ///
    /// When `true`, ``Agent`` creates a ``MetricsCollector`` at initialization
    /// (or when this flag is enabled via ``Agent/withConfiguration(_:)``) and
    /// composes it into the tracer chain. Read snapshots from
    /// ``Agent/metricsCollector``.
    ///
    /// Default: `false` — metrics collection stays opt-in.
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .autoAttachMetricsCollector(true)
    /// let agent = try Agent("Be helpful.", configuration: config,
    ///     inferenceProvider: provider)
    /// _ = try await agent.run("Hello")
    /// let snapshot = await agent.metricsCollector?.snapshot()
    /// ```
    ///
    /// - SeeAlso: ``autoAttachMetricsCollector(_:)``, ``MetricsCollector``,
    ///   ``Agent/metricsCollector``
    public var autoAttachMetricsCollector: Bool

    // MARK: - Resilience Settings

    /// Retry, circuit-breaker, and rate-limit policies for **provider inference**.
    ///
    /// Default: ``ResilienceConfiguration/disabled`` (``RetryPolicy/noRetry``, no
    /// breaker, no limiter). That default is a no-op — agent execution matches
    /// Swarm before this field existed.
    ///
    /// Policies wrap provider inference only. Tool execution is never retried.
    /// Retries consume the remaining ``timeout`` budget and cannot outlive the
    /// run. Circuit-breaker and rate-limiter state is scoped per ``Agent``
    /// instance. See ``ResilienceConfiguration`` and ``InferenceRetryability``.
    ///
    /// - SeeAlso: ``resilience(_:)``, ``ResilienceConfiguration``
    public var resilience: ResilienceConfiguration

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
    ///   - autoAttachMetricsCollector: Auto-attach a ``MetricsCollector``. Default: false
    ///   - resilience: Retry / circuit-breaker / rate-limit policies for inference. Default: ``ResilienceConfiguration/disabled``
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
        defaultTracingEnabled: Bool = true,
        autoAttachMetricsCollector: Bool = false,
        resilience: ResilienceConfiguration = .disabled
    ) {
        self.name = name
        self.maxIterations = Self.coercedMaxIterations(maxIterations)
        self.timeout = Self.coercedTimeout(timeout)
        self.temperature = Self.coercedTemperature(temperature)
        self.maxTokens = maxTokens
        self.stopSequences = stopSequences
        self.modelSettings = modelSettings
        self.contextProfile = contextProfile
        self.graphRunOptionsOverride = nil
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
        self.autoAttachMetricsCollector = autoAttachMetricsCollector
        self.resilience = resilience
    }
}

// MARK: - Write-Path Coercion

private extension AgentConfiguration {
    /// Coerces `maxIterations` to at least 1, matching the designated
    /// initializer; warns via ``Log/agents`` when clamping occurs. Shared by
    /// `init` and `didSet` so both write paths stay identical.
    static func coercedMaxIterations(_ value: Int) -> Int {
        guard value < 1 else { return value }
        Log.agents.warning("AgentConfiguration: maxIterations \(value) must be >= 1; using 1")
        return max(1, value)
    }

    /// Falls back to the 60-second default for non-positive timeouts, matching
    /// the designated initializer; warns via ``Log/agents`` when replaced.
    static func coercedTimeout(_ value: Duration) -> Duration {
        guard value <= .zero else { return value }
        Log.agents.warning("AgentConfiguration: timeout must be positive; using default 60 seconds")
        return .seconds(60)
    }

    /// Falls back to 1.0 for non-finite or out-of-range temperatures, matching
    /// the designated initializer; warns via ``Log/agents`` when replaced.
    /// Shares ``ModelSettings/temperatureRange`` so both types' temperature
    /// bounds cannot drift apart.
    static func coercedTemperature(_ value: Double) -> Double {
        guard value.isFinite, ModelSettings.temperatureRange.contains(value) else {
            Log.agents.warning("AgentConfiguration: temperature \(value) out of [0.0, 2.0]; using default 1.0")
            return 1.0
        }
        return value
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

    // MARK: Graph Runtime Settings

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
    /// Enabled runs emit incremental ``AgentEvent/output(_:)`` events when the
    /// provider streams. Disabled runs emit the completed response through
    /// ``AgentEvent/Lifecycle/completed(result:)``.
    ///
    /// - Parameter value: `true` to enable streaming, `false` for complete responses
    /// - Returns: A new configuration with the updated streaming setting
    /// - SeeAlso: ``AgentEvent/output(_:)``, ``AgentEvent/Lifecycle/completed(result:)``
    @discardableResult public func enableStreaming(_ value: Bool) -> AgentConfiguration {
        var copy = self
        copy.enableStreaming = value
        return copy
    }

    /// Sets the legacy result-detail compatibility setting.
    ///
    /// The value is retained for source compatibility but has no effect. Tool
    /// details are always exposed through ``AgentResult/toolCalls`` and
    /// ``AgentResult/toolResults``.
    ///
    /// - Parameter value: Ignored compatibility value
    /// - Returns: A new configuration with the updated stored value
    /// - SeeAlso: ``includeToolCallDetails``, ``AgentResponse/toolCalls``
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
    /// - Parameter value: `true` to stop on the first tool error
    /// - Returns: A new configuration with the updated error handling setting
    /// - SeeAlso: ``stopOnToolError``, ``ToolResult/Outcome/failure(message:)``
    @discardableResult public func stopOnToolError(_ value: Bool) -> AgentConfiguration {
        var copy = self
        copy.stopOnToolError = value
        return copy
    }

    /// Sets the legacy reasoning-event compatibility setting.
    ///
    /// The value is retained for source compatibility but has no effect. Current
    /// reasoning events, when emitted by a provider, are nested under
    /// ``AgentEvent/output(_:)``.
    ///
    /// - Parameter value: Ignored compatibility value
    /// - Returns: A new configuration with the updated stored value
    /// - SeeAlso: ``includeReasoning``, ``AgentEvent/Output/thinking(thought:)``
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

    /// Sets whether to auto-attach a ``MetricsCollector`` to the tracer chain.
    ///
    /// When `true`, the agent records execution metrics without requiring you
    /// to construct and pass a collector as `tracer`. Default: `false`.
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .autoAttachMetricsCollector(true)
    /// ```
    ///
    /// - Parameter value: `true` to auto-attach a metrics collector
    /// - Returns: A new configuration with the updated setting
    /// - SeeAlso: ``autoAttachMetricsCollector``, ``MetricsCollector``,
    ///   ``Agent/metricsCollector``
    @discardableResult public func autoAttachMetricsCollector(_ value: Bool) -> AgentConfiguration {
        var copy = self
        copy.autoAttachMetricsCollector = value
        return copy
    }

    // MARK: Resilience Settings

    /// Sets retry, circuit-breaker, and rate-limit policies for provider inference.
    ///
    /// Default: ``ResilienceConfiguration/disabled``.
    ///
    /// Tool execution is never wrapped. See ``ResilienceConfiguration`` for
    /// timeout interaction, breaker scoping, and the retryability table.
    ///
    /// ## Example
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .resilience(ResilienceConfiguration(retryPolicy: .standard))
    /// ```
    ///
    /// - Parameter value: The resilience configuration
    /// - Returns: A new configuration with the updated resilience policies
    /// - SeeAlso: ``resilience``, ``ResilienceConfiguration``, ``InferenceRetryability``
    @discardableResult public func resilience(_ value: ResilienceConfiguration) -> AgentConfiguration {
        var copy = self
        copy.resilience = value
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
            graphRunOptionsOverride: \(graphRunOptionsOverride.map { String(describing: $0) } ?? "nil"),
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
            defaultTracingEnabled: \(defaultTracingEnabled),
            autoAttachMetricsCollector: \(autoAttachMetricsCollector),
            resilience: \(String(describing: resilience))
        )
        """
    }
}
