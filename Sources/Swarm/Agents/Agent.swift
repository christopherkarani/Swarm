// Agent.swift
// Swarm Framework
//
// Tool-calling agent that uses structured LLM tool calling APIs.

import Foundation

// MARK: - Agent

/// An agent that uses structured LLM tool calling APIs for reliable tool invocation.
///
/// Unlike Agent which parses tool calls from text output, Agent
/// leverages the LLM's native tool calling capabilities via `generateWithToolCalls()`
/// for more reliable and type-safe tool invocation.
///
/// If no inference provider is configured, Agent will try to use Apple Foundation Models
/// (on-device) when available. If Foundation Models are unavailable and no provider is set,
/// Agent throws `AgentError.inferenceProviderUnavailable`.
///
/// Provider resolution order is:
/// 1. Apple Foundation Models when `inferencePolicy.privacyRequired` is true
/// 2. An explicit provider passed to `Agent(...)` (including `Agent(_:)`)
/// 3. A provider set via `.environment(\.inferenceProvider, ...)`
/// 4. `Swarm.defaultProvider` (set via `Swarm.configure(provider:)`)
/// 5. Apple Foundation Models (on-device), if available
/// 6. Otherwise, throw `AgentError.inferenceProviderUnavailable`
///
/// The agent follows a loop-based execution pattern:
/// 1. Build prompt with system instructions + conversation history
/// 2. Call provider with tool schemas
/// 3. If tool calls requested, execute each tool and add results to history
/// 4. If no tool calls, return content as final answer
/// 5. Repeat until done or max iterations reached
///
/// Example:
/// ```swift
/// let agent = Agent(
///     tools: [WeatherTool(), CalculatorTool()],
///     instructions: "You are a helpful assistant with access to tools."
/// )
///
/// let result = try await agent.run("What's the weather in Tokyo?")
/// print(result.output)
/// ```
public struct Agent: AgentRuntime, Sendable {
    // MARK: Public

    // MARK: - Agent Protocol Properties

    /// The tools available to this agent for function calling.
    ///
    /// Tools are registered at initialization and remain immutable throughout the agent's lifetime.
    /// The agent uses these tool schemas to inform the LLM about available capabilities.
    ///
    /// To add tools, use the ``init(_:configuration:memory:inferenceProvider:tracer:inputGuardrails:outputGuardrails:guardrailRunnerConfiguration:handoffs:tools:)`` initializer
    /// with a `@ToolBuilder` closure, or ``withTools(_:)``.
    ///
    /// ## Tool Execution
    /// When the LLM requests a tool call, the agent executes the corresponding tool
    /// and returns the result to the LLM for further processing.
    public private(set) var tools: [any AnyJSONTool]

    /// The system instructions that define this agent's behavior and capabilities.
    ///
    /// Instructions are sent to the LLM with every request to guide the agent's responses,
    /// personality, and decision-making. They describe what the agent should do, how it
    /// should behave, and any constraints it should follow.
    ///
    /// If no instructions are provided, a default instruction set is used:
    /// `"You are a helpful AI assistant with access to tools."`
    ///
    /// ## Example Instructions
    /// ```swift
    /// "You are a weather assistant. Be concise and friendly."
    /// ```
    ///
    /// To set instructions, use one of the ``Agent`` initializers.
    public private(set) var instructions: String

    /// The runtime configuration settings for this agent.
    ///
    /// Configuration controls agent behavior such as maximum iterations, timeout duration,
    /// streaming preferences, and the agent's display name. Use this to customize
    /// how the agent executes during a run.
    ///
    /// ## Default Configuration
    /// If not specified, the agent uses ``AgentConfiguration/default`` which provides
    /// sensible defaults for most use cases.
    ///
    /// ## Customizing Configuration
    /// ```swift
    /// let config = AgentConfiguration.default
    ///     .maxIterations(10)
    ///     .timeout(.seconds(30))
    ///
    /// let agent = Agent(instructions: "Helpful assistant", configuration: config)
    /// ```
    ///
    /// See ``AgentConfiguration`` for all available configuration options.
    public private(set) var configuration: AgentConfiguration

    /// The explicitly configured memory system for conversation history and context retrieval.
    ///
    /// When configured, the agent uses memory to:
    /// - Retrieve relevant context from previous conversations (RAG)
    /// - Store conversation summaries for long-term context
    /// - Provide additional context to the LLM beyond the current session
    ///
    /// ## Memory vs Session
    /// - **Memory**: Provides additional context (RAG, summaries) - not for conversation storage
    /// - **Session**: Stores the actual conversation history and is the source of truth for transcripts
    ///
    /// If no explicit memory is set, Swarm uses ``makeDefaultMemory()``
    /// internally: ContextCore + Wax ``DefaultAgentMemory`` when the Integrations
    /// trait is enabled, otherwise ``SlidingWindowMemory``.
    /// This property only reflects an explicit override.
    ///
    /// ## Setting Memory
    /// Use ``init(_:configuration:memory:inferenceProvider:tracer:inputGuardrails:outputGuardrails:guardrailRunnerConfiguration:handoffs:tools:)``
    /// or pass memory to an ``Agent`` initializer.
    ///
    /// See ``Memory`` for available memory implementations.
    public private(set) var memory: (any Memory)?
    private let defaultMemory: (any Memory)?

    /// The optional custom inference provider for LLM requests.
    ///
    /// The inference provider determines which LLM backend the agent uses for generating
    /// responses. If not set, the agent follows a resolution order to find a provider:
    ///
    /// 1. Apple Foundation Models when `configuration.inferencePolicy.privacyRequired` is true
    /// 2. Explicit provider passed to ``Agent`` initialization
    /// 3. Provider set via `.environment(\.inferenceProvider, ...)`
    /// 4. ``Swarm/defaultProvider`` (configured via `Swarm.configure(provider:)`)
    /// 5. Apple Foundation Models (on-device), if available
    /// 6. Throws ``AgentError/inferenceProviderUnavailable``
    ///
    /// ## Usage
    /// Set a specific provider when you want this agent to use a different backend than
    /// the globally configured one. Built-in inference is Apple Foundation Models;
    /// inject any ``InferenceProvider`` for custom backends.
    public private(set) var inferenceProvider: (any InferenceProvider)?

    /// The input validation guardrails for this agent.
    ///
    /// Input guardrails validate user input before it's processed by the agent.
    /// They can reject inappropriate requests, check for safety concerns, or enforce
    /// business rules before the LLM is invoked.
    ///
    /// Guardrails are executed in order during ``run(_:session:observer:)`` and
    /// ``stream(_:session:observer:)`` before any LLM calls are made.
    ///
    /// ## Adding Guardrails
    /// Use an ``Agent`` initializer to configure input guardrails.
    ///
    /// See ``InputGuardrail`` for creating custom guardrails.
    public private(set) var inputGuardrails: [any InputGuardrail]

    /// The output validation guardrails for this agent.
    ///
    /// Output guardrails validate the agent's responses before they are returned to the user.
    /// They can check for harmful content, enforce output format requirements, or
    /// validate that the response meets quality standards.
    ///
    /// Guardrails are executed after the LLM generates a response but before it's
    /// returned in ``run(_:session:observer:)``.
    ///
    /// ## Adding Guardrails
    /// Use an ``Agent`` initializer to configure output guardrails.
    ///
    /// See ``OutputGuardrail`` for creating custom guardrails.
    public private(set) var outputGuardrails: [any OutputGuardrail]

    /// The optional tracer for observability and debugging.
    ///
    /// When configured, the tracer receives events throughout the agent's execution,
    /// including LLM calls, tool executions, and timing information. This enables
    /// monitoring, debugging, and performance analysis.
    ///
    /// If not set but ``AgentConfiguration/defaultTracingEnabled`` is `true`,
    /// a default ``SwiftLogTracer`` is automatically created.
    ///
    /// ## Setting a Tracer
    /// Use ``init(_:configuration:memory:inferenceProvider:tracer:inputGuardrails:outputGuardrails:guardrailRunnerConfiguration:handoffs:tools:)``
    /// or pass a tracer to an ``Agent`` initializer.
    ///
    /// See ``Tracer`` for the protocol definition and available implementations.
    public private(set) var tracer: (any Tracer)?

    /// The auto-attached ``MetricsCollector``, when
    /// ``AgentConfiguration/autoAttachMetricsCollector`` is `true`.
    ///
    /// `nil` when the configuration flag is off. When present, the collector
    /// is composed into the tracer chain so execution metrics accumulate
    /// without passing a tracer manually. Call ``MetricsCollector/snapshot()``
    /// to read counters, durations, and token totals.
    ///
    /// - SeeAlso: ``AgentConfiguration/autoAttachMetricsCollector(_:)``,
    ///   ``MetricsCollector``
    public private(set) var metricsCollector: MetricsCollector?

    /// The configuration for the guardrail runner.
    ///
    /// This configuration controls how input and output guardrails are executed,
    /// including sequential or parallel execution and error handling behavior.
    ///
    /// ## Default Behavior
    /// If not specified, uses ``GuardrailRunnerConfiguration/default`` which runs
    /// guardrails sequentially and stops on the first failure.
    ///
    /// See ``GuardrailRunnerConfiguration`` for customization options.
    public private(set) var guardrailRunnerConfiguration: GuardrailRunnerConfiguration

    /// The configured handoffs for multi-agent orchestration.
    ///
    /// Handoffs enable the agent to transfer control to other agents when appropriate.
    /// Each handoff appears to the LLM as a callable tool, and when invoked,
    /// execution transfers to the target agent.
    ///
    /// ## Multi-Agent Orchestration
    /// Handoffs are the foundation of Swarm's multi-agent patterns. Use them to:
    /// - Route requests to specialized agents
    /// - Build hierarchical agent systems
    /// - Implement agent teams with different expertise
    ///
    /// ## Adding Handoffs
    /// ```swift
    /// let agent = try Agent(
    ///     "Route requests to the right specialist.",
    ///     handoffs: [billingAgent.asHandoff(), supportAgent.asHandoff()]
    /// )
    /// ```
    ///
    /// See ``AnyHandoffConfiguration`` and ``HandoffOptions`` for more details.
    public var handoffs: [AnyHandoffConfiguration] {
        _handoffs
    }

    // MARK: - Initialization

    /// Creates a new Agent.
    /// - Parameters:
    ///   - tools: Tools available to the agent. Default: []
    ///   - instructions: System instructions defining agent behavior. Default: ""
    ///   - configuration: Agent configuration settings. Default: .default
    ///   - memory: Optional explicit memory override. Default: ContextCore+Wax `DefaultAgentMemory` when Integrations is enabled; otherwise `SlidingWindowMemory`
    ///   - inferenceProvider: Optional custom inference provider. Default: nil
    ///   - tracer: Optional tracer for observability. Default: nil
    ///   - inputGuardrails: Input validation guardrails. Default: []
    ///   - outputGuardrails: Output validation guardrails. Default: []
    ///   - guardrailRunnerConfiguration: Configuration for guardrail runner. Default: .default
    ///   - handoffs: Handoff configurations for multi-agent orchestration. Default: []
    /// - Throws: `ToolRegistryError.duplicateToolName` if duplicate tool names are provided.
    @_disfavoredOverload
    public init(
        tools: [any AnyJSONTool] = [],
        instructions: String = "",
        configuration: AgentConfiguration = .default,
        memory: (any Memory)? = nil,
        inferenceProvider: (any InferenceProvider)? = nil,
        tracer: (any Tracer)? = nil,
        inputGuardrails: [any InputGuardrail] = [],
        outputGuardrails: [any OutputGuardrail] = [],
        guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default,
        handoffs: [AnyHandoffConfiguration] = []
    ) throws {
        try self.init(
            tools: tools,
            instructions: instructions,
            configuration: configuration,
            memory: memory,
            inferenceProvider: inferenceProvider,
            tracer: tracer,
            inputGuardrails: inputGuardrails,
            outputGuardrails: outputGuardrails,
            guardrailRunnerConfiguration: guardrailRunnerConfiguration,
            handoffs: handoffs,
            runEnvironment: .live
        )
    }

    /// Designated initializer with explicit per-run dependencies.
    ///
    /// ``runEnvironment`` defaults to ``AgentRunEnvironment/live`` so agents
    /// built through public initializers share dedup and session-serialization
    /// state exactly as they did when these dependencies were process globals.
    init(
        tools: [any AnyJSONTool] = [],
        instructions: String = "",
        configuration: AgentConfiguration = .default,
        memory: (any Memory)? = nil,
        inferenceProvider: (any InferenceProvider)? = nil,
        tracer: (any Tracer)? = nil,
        inputGuardrails: [any InputGuardrail] = [],
        outputGuardrails: [any OutputGuardrail] = [],
        guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default,
        handoffs: [AnyHandoffConfiguration] = [],
        runEnvironment: AgentRunEnvironment = .live
    ) throws {
        self.tools = tools
        self.instructions = instructions
        self.configuration = configuration
        self.memory = memory
        self.defaultMemory = try memory == nil
            ? Self.makeDefaultMemory(waxStoreURL: runEnvironment.defaultMemoryStoreURL)
            : nil
        self.inferenceProvider = inferenceProvider
        self.tracer = tracer
        self.metricsCollector = configuration.autoAttachMetricsCollector
            ? (tracer as? MetricsCollector ?? MetricsCollector())
            : nil
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
        self.guardrailRunnerConfiguration = guardrailRunnerConfiguration
        _handoffs = handoffs
        toolRegistry = try ToolRegistry(tools: tools)
        inferenceCircuitBreaker = configuration.resilience.makeCircuitBreaker(
            agentName: configuration.name
        )
        inferenceRateLimiter = configuration.resilience.makeRateLimiter()
        self.runEnvironment = runEnvironment
    }

    /// Convenience initializer that takes an unlabeled inference provider.
    ///
    /// This enables an opinionated, easy setup:
    /// ```swift
    /// let agent = try Agent(.foundationModels())
    /// ```
    public init(
        _ inferenceProvider: any InferenceProvider,
        tools: [any AnyJSONTool] = [],
        instructions: String = "",
        configuration: AgentConfiguration = .default,
        memory: (any Memory)? = nil,
        tracer: (any Tracer)? = nil,
        inputGuardrails: [any InputGuardrail] = [],
        outputGuardrails: [any OutputGuardrail] = [],
        guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default,
        handoffs: [AnyHandoffConfiguration] = []
    ) throws {
        try self.init(
            tools: tools,
            instructions: instructions,
            configuration: configuration,
            memory: memory,
            inferenceProvider: inferenceProvider,
            tracer: tracer,
            inputGuardrails: inputGuardrails,
            outputGuardrails: outputGuardrails,
            guardrailRunnerConfiguration: guardrailRunnerConfiguration,
            handoffs: handoffs
        )
    }

    /// Creates a new Agent with typed tools.
    /// - Parameters:
    ///   - tools: Typed tools available to the agent. Default: []
    ///   - instructions: System instructions defining agent behavior. Default: ""
    ///   - configuration: Agent configuration settings. Default: .default
    ///   - memory: Optional explicit memory override. Default: ContextCore+Wax `DefaultAgentMemory` when Integrations is enabled; otherwise `SlidingWindowMemory`
    ///   - inferenceProvider: Optional custom inference provider. Default: nil
    ///   - tracer: Optional tracer for observability. Default: nil
    ///   - inputGuardrails: Input validation guardrails. Default: []
    ///   - outputGuardrails: Output validation guardrails. Default: []
    ///   - guardrailRunnerConfiguration: Configuration for guardrail runner. Default: .default
    ///   - handoffs: Handoff configurations for multi-agent orchestration. Default: []
    /// - Throws: `ToolRegistryError.duplicateToolName` if duplicate tool names are provided.
    public init(
        tools: [some Tool] = [],
        instructions: String = "",
        configuration: AgentConfiguration = .default,
        memory: (any Memory)? = nil,
        inferenceProvider: (any InferenceProvider)? = nil,
        tracer: (any Tracer)? = nil,
        inputGuardrails: [any InputGuardrail] = [],
        outputGuardrails: [any OutputGuardrail] = [],
        guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default,
        handoffs: [AnyHandoffConfiguration] = []
    ) throws {
        let bridged = tools.map { AnyJSONToolAdapter($0) }
        try self.init(
            tools: bridged,
            instructions: instructions,
            configuration: configuration,
            memory: memory,
            inferenceProvider: inferenceProvider,
            tracer: tracer,
            inputGuardrails: inputGuardrails,
            outputGuardrails: outputGuardrails,
            guardrailRunnerConfiguration: guardrailRunnerConfiguration,
            handoffs: handoffs
        )
    }

    /// Creates a new Agent with simplified handoff declaration.
    ///
    /// This convenience initializer accepts an array of `AgentRuntime` conforming agents
    /// and automatically wraps each one as an `AnyHandoffConfiguration`, simplifying
    /// multi-agent orchestration setup.
    ///
    /// Example:
    /// ```swift
    /// let triageAgent = Agent(
    ///     instructions: "Route requests to the right specialist.",
    ///     handoffAgents: [billingAgent, supportAgent, salesAgent]
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - tools: Tools available to the agent. Default: []
    ///   - instructions: System instructions defining agent behavior. Default: ""
    ///   - configuration: Agent configuration settings. Default: .default
    ///   - memory: Optional explicit memory override. Default: ContextCore+Wax `DefaultAgentMemory` when Integrations is enabled; otherwise `SlidingWindowMemory`
    ///   - inferenceProvider: Optional custom inference provider. Default: nil
    ///   - tracer: Optional tracer for observability. Default: nil
    ///   - inputGuardrails: Input validation guardrails. Default: []
    ///   - outputGuardrails: Output validation guardrails. Default: []
    ///   - guardrailRunnerConfiguration: Configuration for guardrail runner. Default: .default
    ///   - handoffAgents: Agents to hand off to, automatically wrapped as handoff configurations.
    /// - Throws: `ToolRegistryError.duplicateToolName` if duplicate tool names are provided.
    @_disfavoredOverload
    public init(
        tools: [any AnyJSONTool] = [],
        instructions: String = "",
        configuration: AgentConfiguration = .default,
        memory: (any Memory)? = nil,
        inferenceProvider: (any InferenceProvider)? = nil,
        tracer: (any Tracer)? = nil,
        inputGuardrails: [any InputGuardrail] = [],
        outputGuardrails: [any OutputGuardrail] = [],
        guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default,
        handoffAgents: [any AgentRuntime]
    ) throws {
        let configs = handoffAgents.map { agent in
            AnyHandoffConfiguration(
                targetAgent: agent,
                toolNameOverride: nil,
                toolDescription: nil
            )
        }
        try self.init(
            tools: tools,
            instructions: instructions,
            configuration: configuration,
            memory: memory,
            inferenceProvider: inferenceProvider,
            tracer: tracer,
            inputGuardrails: inputGuardrails,
            outputGuardrails: outputGuardrails,
            guardrailRunnerConfiguration: guardrailRunnerConfiguration,
            handoffs: configs
        )
    }

    // MARK: - V3 Canonical Init

    /// V3 canonical initializer — instructions-first, `@ToolBuilder` trailing closure.
    ///
    /// This is the recommended path for creating agents in V3:
    /// ```swift
    /// let agent = try Agent("You are a helpful assistant.") {
    ///     WeatherTool()
    ///     SearchTool()
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - instructions: System instructions defining agent behavior.
    ///   - configuration: Agent configuration settings. Default: `.default`
    ///   - memory: Optional explicit memory override. Default: ContextCore+Wax `DefaultAgentMemory` when Integrations is enabled; otherwise `SlidingWindowMemory`
    ///   - inferenceProvider: Optional custom inference provider. Default: `nil`
    ///   - tracer: Optional tracer for observability. Default: `nil`
    ///   - inputGuardrails: Input validation guardrails. Default: `[]`
    ///   - outputGuardrails: Output validation guardrails. Default: `[]`
    ///   - guardrailRunnerConfiguration: Configuration for guardrail runner. Default: `.default`
    ///   - handoffs: Handoff configurations for multi-agent orchestration. Default: `[]`
    ///   - tools: A `@ToolBuilder` closure producing the agent's tools. Default: empty.
    /// - Throws: `ToolRegistryError.duplicateToolName` if duplicate tool names are provided.
    public init(
        _ instructions: String,
        configuration: AgentConfiguration = .default,
        memory: (any Memory)? = nil,
        inferenceProvider: (any InferenceProvider)? = nil,
        tracer: (any Tracer)? = nil,
        inputGuardrails: [any InputGuardrail] = [],
        outputGuardrails: [any OutputGuardrail] = [],
        guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default,
        handoffs: [AnyHandoffConfiguration] = [],
        @ToolBuilder tools: () -> ToolCollection = { .empty }
    ) throws {
        try self.init(
            tools: tools().storage,
            instructions: instructions,
            configuration: configuration,
            memory: memory,
            inferenceProvider: inferenceProvider,
            tracer: tracer,
            inputGuardrails: inputGuardrails,
            outputGuardrails: outputGuardrails,
            guardrailRunnerConfiguration: guardrailRunnerConfiguration,
            handoffs: handoffs
        )
    }

    // MARK: Private

    var _handoffs: [AnyHandoffConfiguration]

    // MARK: - Internal State

    private var toolRegistry: ToolRegistry
    /// Registry of in-flight runs; copies of this value share the actor, so
    /// every run started through any copy is reachable from ``cancel()``.
    let activeRuns = ActiveRunRegistry()
    /// Created from ``AgentConfiguration/resilience`` at init. Copies of this value share the actor.
    let inferenceCircuitBreaker: CircuitBreaker?
    /// Created from ``AgentConfiguration/resilience`` at init. Copies of this value share the actor.
    let inferenceRateLimiter: RateLimiter?
    /// Per-run dependency bundle (response tracker, default-memory session
    /// tracker, shared configuration source). Defaults to ``AgentRunEnvironment/live``;
    /// a separately constructed environment isolates tracker state per agent.
    let runEnvironment: AgentRunEnvironment

    /// Shared default environment backing agents constructed through public initializers.
    /// All such agents observe one instance, preserving the former process-global
    /// sharing semantics across agent copies.
    static let defaultRunEnvironment = AgentRunEnvironment.live

    /// Former process-global response tracker; delegates to ``defaultRunEnvironment``.
    static var autoResponseTracker: ResponseTracker { defaultRunEnvironment.responseTracker }

    /// Former process-global default-memory session tracker; delegates to ``defaultRunEnvironment``.
    static var defaultMemorySessionTracker: DefaultMemorySessionTracker { defaultRunEnvironment.defaultMemorySessionTracker }

    static let responseIDMetadataKey = "response.id"
    static let transcriptSchemaVersionMetadataKey = "swarm.transcript.schema_version"
    static let transcriptHashMetadataKey = "swarm.transcript.hash"
    static let structuredOutputJSONMetadataKey = "structured_output.raw_json"
    static let structuredOutputSourceMetadataKey = "structured_output.source"
    static let structuredOutputFormatMetadataKey = "structured_output.format"

    struct InternalRunResult: Sendable {
        let agentResult: AgentResult
        let structuredOutput: StructuredOutputResult?
    }

    struct ToolLoopOutcome: Sendable {
        let output: String
        let structuredOutput: StructuredOutputResult?
        let transcriptMessages: [MemoryMessage]
    }

    struct FinalAssistantResponse: Sendable {
        let content: String
        let structuredOutput: StructuredOutputResult?
    }

    // MARK: - Turn Dependency Resolution

    /// Gathers every resolution channel for one turn — explicit configuration,
    /// the TaskLocal environment snapshot, package globals, and the agent's
    /// base tools — and resolves them exactly once into an
    /// ``AgentTurnDependencies`` value.
    func resolveTurnDependencies() async throws -> AgentTurnDependencies {
        let query = AgentTurnDependencyQuery(
            configuration: configuration,
            explicitProvider: inferenceProvider,
            explicitMemory: memory,
            defaultMemory: defaultMemory,
            explicitTracer: tracer,
            metricsCollector: metricsCollector,
            baseTools: await toolRegistry.allTools,
            environment: AgentEnvironmentValues.current,
            globalProvider: await runEnvironment.defaultProvider(),
            globalWebSearch: await runEnvironment.webConfiguration()
        )
        return try AgentTurnDependencyResolver.resolve(query)
    }
}

// MARK: - V3 Modifiers

public extension Agent {
    /// Sets the memory system. Returns a new Agent with memory configured.
    ///
    /// ```swift
    /// let agent = try Agent("Be helpful.")
    ///     .withMemory(.conversation(maxMessages: 50))
    /// ```
    @discardableResult
    func withMemory(_ memory: some Memory) -> Agent {
        var copy = self
        copy.memory = memory
        return copy
    }

    /// Sets the tracer for observability.
    @discardableResult
    func withTracer(_ tracer: any Tracer) -> Agent {
        var copy = self
        copy.tracer = tracer
        return copy
    }

    /// Sets input and/or output guardrails.
    @discardableResult
    func withGuardrails(
        input: [any InputGuardrail] = [],
        output: [any OutputGuardrail] = []
    ) -> Agent {
        var copy = self
        if !input.isEmpty { copy.inputGuardrails = input }
        if !output.isEmpty { copy.outputGuardrails = output }
        return copy
    }

    /// Sets handoff agents for multi-agent orchestration.
    @discardableResult
    func withHandoffs(_ agents: [any AgentRuntime]) -> Agent {
        var copy = self
        copy._handoffs = agents.map { agent in
            AnyHandoffConfiguration(
                targetAgent: agent,
                toolNameOverride: nil,
                toolDescription: nil
            )
        }
        return copy
    }

    /// Replaces the tool set with the given array of `any Tool`.
    @discardableResult
    func withTools(_ tools: [any Tool]) throws -> Agent {
        var copy = self
        let bridged = tools.map { bridgeToolToAnyJSON($0) }
        copy.toolRegistry = try ToolRegistry(tools: bridged)
        copy.tools = bridged
        return copy
    }

    /// Replaces the tool set using a `@ToolBuilder` closure.
    @discardableResult
    func withTools(@ToolBuilder _ builder: () -> ToolCollection) throws -> Agent {
        var copy = self
        let storage = builder().storage
        copy.toolRegistry = try ToolRegistry(tools: storage)
        copy.tools = storage
        return copy
    }

    /// Sets the agent configuration.
    @discardableResult
    func withConfiguration(_ config: AgentConfiguration) -> Agent {
        var copy = self
        copy.configuration = config
        if config.autoAttachMetricsCollector, copy.metricsCollector == nil {
            copy.metricsCollector = copy.tracer as? MetricsCollector ?? MetricsCollector()
        }
        return copy
    }

    /// Executes the agent using function-call syntax.
    ///
    /// This sugar lets you invoke the agent as if it were a function:
    /// ```swift
    /// let result = try await agent("Summarize this document.")
    /// ```
    ///
    /// - Parameters:
    ///   - input: The user's input/query.
    ///   - session: Optional session for conversation history management. Default: nil
    ///   - observer: Optional observer for lifecycle callbacks. Default: nil
    /// - Returns: The result of the agent's execution.
    /// - Throws: `AgentError` if execution fails, or `GuardrailError` if guardrails trigger.
    func callAsFunction(
        _ input: String,
        session: (any Session)? = nil,
        observer: (any AgentObserver)? = nil
    ) async throws -> AgentResult {
        try await run(input, session: session, observer: observer)
    }
}
