// AgentConfiguration+Builders.swift
// Swarm Framework
//
// Builder-style modifiers for AgentConfiguration.

import Foundation

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

    /// Sets the consecutive identical tool-call batches allowed before the run stops.
    ///
    /// Values below 2 coerce to 2.
    @discardableResult public func maxConsecutiveToolRepeats(_ value: Int) -> AgentConfiguration {
        var copy = self
        copy.maxConsecutiveToolRepeats = value
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

    // MARK: Foundation Models Execution

    /// Ignored. Construct a provider-owned tool loop adapter instead of setting this flag.
    ///
    /// - Parameter value: Previously selected the Foundation Models tool loop. Ignored.
    /// - Returns: A new configuration with the stored (ignored) flag.
    @available(*, deprecated, message: "Choose a provider-owned tool loop by constructing the InferenceProvider adapter. This flag is ignored.")
    @discardableResult public func foundationModelsExecution(
        _ value: FoundationModelsExecutionMode
    ) -> AgentConfiguration {
        var copy = self
        copy.foundationModelsExecution = value
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
