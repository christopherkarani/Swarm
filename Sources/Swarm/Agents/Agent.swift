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
    /// with a `@ToolBuilder` closure, or the ``Builder`` API.
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
    /// To set instructions, use any of the ``Agent`` initializers or the ``Builder/instructions(_:)`` method.
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
    /// or the ``Builder/memory(_:)`` method.
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
    /// Use the ``Builder/inputGuardrails(_:)`` or ``Builder/addInputGuardrail(_:)`` methods.
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
    /// Use the ``Builder/outputGuardrails(_:)`` or ``Builder/addOutputGuardrail(_:)`` methods.
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
    /// or the ``Builder/tracer(_:)`` method.
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
    /// let agent = try Agent("Route requests to the right specialist.") {
    ///     handoff(to: billingAgent)
    ///     handoff(to: supportAgent)
    /// }
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

    // MARK: - Agent Protocol Methods

    /// Executes the agent with the given input and returns a result.
    /// - Parameters:
    ///   - input: The user's input/query.
    ///   - session: Optional session for conversation history management.
    ///   - observer: Optional run observer for observing agent execution events.
    /// - Returns: The result of the agent's execution.
    /// - Throws: `AgentError` if execution fails, or `GuardrailError` if guardrails trigger.
    public func run(_ input: String, session: (any Session)? = nil, observer: (any AgentObserver)? = nil) async throws -> AgentResult {
        let runID = UUID()
        let task = Task { [self] in
            try await runInternal(input, session: session, observer: observer, structuredOutputRequest: nil)
        }
        await activeRuns.begin(runID) { [task] in
            task.cancel()
        }

        do {
            let result = try await withTaskCancellationHandler(
                operation: {
                    try await task.value.agentResult
                },
                onCancel: {
                    task.cancel()
                }
            )
            await activeRuns.finish(runID)
            return result
        } catch {
            task.cancel()
            await activeRuns.finish(runID)
            throw normalizeCancellation(error)
        }
    }

    /// Executes the agent and enforces a structured output contract for the final assistant response.
    public func runStructured(
        _ input: String,
        request: StructuredOutputRequest,
        session: (any Session)? = nil,
        observer: (any AgentObserver)? = nil
    ) async throws -> StructuredAgentResult {
        let runID = UUID()
        let task = Task { [self] in
            try await runInternal(input, session: session, observer: observer, structuredOutputRequest: request)
        }
        await activeRuns.begin(runID) { [task] in
            task.cancel()
        }

        do {
            let result = try await withTaskCancellationHandler(
                operation: {
                    try await task.value
                },
                onCancel: {
                    task.cancel()
                }
            )
            await activeRuns.finish(runID)

            guard let structuredOutput = result.structuredOutput else {
                throw AgentError.generationFailed(reason: "Structured output request completed without a structured result")
            }

            return StructuredAgentResult(agentResult: result.agentResult, structuredOutput: structuredOutput)
        } catch {
            task.cancel()
            await activeRuns.finish(runID)
            throw normalizeCancellation(error)
        }
    }

    /// Cancels every in-flight execution on this agent.
    ///
    /// All runs started through ``run(_:session:observer:)`` or
    /// ``runStructured(_:request:session:observer:)`` that have not finished
    /// yet are cancelled, including runs started concurrently on copies of
    /// this agent value. Earlier releases cancelled only the most recently
    /// registered run; the run registry now tracks every concurrent run by
    /// ID, so cancellation reaches all of them.
    public func cancel() async {
        await activeRuns.cancelAll()
    }

    /// Streams the agent's execution, yielding events as they occur.
    /// - Parameters:
    ///   - input: The user's input/query.
    ///   - session: Optional session for conversation history management.
    ///   - observer: Optional run observer for observing agent execution events.
    /// - Returns: An async stream of agent events.
    public func stream(_ input: String, session: (any Session)? = nil, observer: (any AgentObserver)? = nil) -> AsyncThrowingStream<AgentEvent, Error> {
        let agent = self
        return StreamHelper.makeTrackedStream(bufferingPolicy: .unbounded) { continuation in
            // Create event bridge observer
            let streamObserver = EventStreamObserver(continuation: continuation)

            // Combine with user-provided observer
            let combinedObserver: any AgentObserver = if let userObserver = observer {
                CompositeObserver(observers: [userObserver, streamObserver])
            } else {
                streamObserver
            }

            do {
                _ = try await agent.run(input, session: session, observer: combinedObserver)
                continuation.finish()
            } catch {
                // Error is handled by EventStreamObserver.onError
                continuation.finish(throwing: error)
            }
        }
    }

    public func runWithResponse(
        _ input: String,
        session: (any Session)? = nil,
        observer: (any AgentObserver)? = nil
    ) async throws -> AgentResponse {
        let result = try await run(input, session: session, observer: observer)
        let responseID = responseID(from: result)
        return makeResponse(from: result, responseID: responseID)
    }

    // MARK: Private

    var _handoffs: [AnyHandoffConfiguration]

    // MARK: - Internal State

    private var toolRegistry: ToolRegistry
    /// Registry of in-flight runs; copies of this value share the actor, so
    /// every run started through any copy is reachable from ``cancel()``.
    private let activeRuns = ActiveRunRegistry()
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

    private static let responseIDMetadataKey = "response.id"
    private static let transcriptSchemaVersionMetadataKey = "swarm.transcript.schema_version"
    private static let transcriptHashMetadataKey = "swarm.transcript.hash"
    private static let structuredOutputJSONMetadataKey = "structured_output.raw_json"
    private static let structuredOutputSourceMetadataKey = "structured_output.source"
    private static let structuredOutputFormatMetadataKey = "structured_output.format"

    private struct InternalRunResult: Sendable {
        let agentResult: AgentResult
        let structuredOutput: StructuredOutputResult?
    }

    /// Registry of in-flight runs keyed by run ID: ``KeyedRunRegistry``
    /// specialized to the facade's `UUID` run identifiers.
    ///
    /// Unlike the single-slot state it replaced (pre-W3-T1), this supports
    /// multiple concurrent runs on copies of one agent value: `cancelAll()`
    /// reaches every in-flight run and empties the registry, while
    /// `finish(_:)` removes exactly the run that completed so finished runs
    /// never shadow live ones. The implementation is shared with the graph
    /// runtime's `TrackedRunRegistry` alias so begin/finish/cancel semantics
    /// cannot drift between the two call sites.
    typealias ActiveRunRegistry = KeyedRunRegistry<UUID>

    private func resolvedActiveTracer() -> (any Tracer)? {
        AgentDependencyResolver.activeTracer(
            explicitTracer: tracer,
            environmentTracer: AgentEnvironmentValues.current.tracer,
            defaultTracingEnabled: configuration.defaultTracingEnabled,
            autoAttachMetricsCollector: configuration.autoAttachMetricsCollector,
            metricsCollector: metricsCollector
        )
    }

    private func runInternal(
        _ input: String,
        session: (any Session)? = nil,
        observer: (any AgentObserver)? = nil,
        structuredOutputRequest: StructuredOutputRequest?
    ) async throws -> InternalRunResult {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.invalidInput(reason: "Input cannot be empty")
        }

        let activeTracer = resolvedActiveTracer()
        let activeMemory = resolvedMemory()
        let memoryHooks = activeMemory.map { MemoryHooks.resolved(from: $0) } ?? .empty
        let trackedSessionMemory = activeMemory.flatMap { memory in
            resolvedTrackedSessionMemory(from: memory, defaultMemory: defaultMemory)
        }
        var defaultMemoryRunKey: ObjectIdentifier?

        if let session,
           let trackedSessionMemory
        {
            let memoryKey = memoryObjectIdentifier(trackedSessionMemory)
            defaultMemoryRunKey = memoryKey
            if try await runEnvironment.defaultMemorySessionTracker.beginRun(for: memoryKey, sessionID: session.sessionId) {
                await trackedSessionMemory.clear()
            }
        }

        let tracing = TracingHelper(
            tracer: activeTracer,
            agentName: configuration.name.isEmpty ? "Agent" : configuration.name
        )
        let runtimeToolRegistry = try await resolvedToolRegistry()
        await tracing.traceStart(input: input)

        // Notify observer of agent start
        await observer?.onAgentStart(context: nil, agent: self, input: input)

        if let beginMemorySession = memoryHooks.beginMemorySession {
            await beginMemorySession()
        }

        do {
            // Run input guardrails (with observer for event emission)
            let runner = GuardrailRunner(configuration: guardrailRunnerConfiguration, observer: observer)
            _ = try await runner.runInputGuardrails(inputGuardrails, input: input, context: nil)

            // Reset cancellation state and create result builder
            let resultBuilder = AgentResult.Builder()
            _ = resultBuilder.start()
            let responseID = UUID().uuidString
            _ = resultBuilder.setMetadata(Self.responseIDMetadataKey, .string(responseID))
            if let structuredOutputRequest {
                _ = resultBuilder.setMetadata(
                    Self.structuredOutputFormatMetadataKey,
                    .string(Self.structuredOutputFormatDescription(structuredOutputRequest.format))
                )
            }

            // Load conversation history from session (limit to recent messages)
            var sessionHistory: [MemoryMessage] = []
            if let session {
                sessionHistory = try await session.getItems(limit: configuration.sessionHistoryLimit)
            }

            let replayTranscript = SwarmTranscript(memoryMessages: sessionHistory)
            try replayTranscript.validateReplayCompatibility()

            // Seed memory with session history once when the memory is eligible.
            if let activeMemory, session != nil {
                await activeMemory.seedSessionHistoryIfNeeded(sessionHistory)
            }

            // Create user message for this turn
            let userMessage = SwarmTranscriptCodec.encodeMessage(role: .user, content: input)

            // Execute the tool calling loop with session context
            let provider = try await resolvedInferenceProvider()
            let executionContext = AgentContext(input: input)
            let runtimeEnvironment = runtimeEnvironment(for: provider)
            let ownsToolLoop = provider.capabilities.contains(.providerOwnedToolLoop)
            let executionGate = ownsToolLoop ? ProviderOwnedLoopGate() : nil
            let pendingHandoff = OwnedLoopPendingHandoff()
            configuration.warnIfDeprecatedNativeSessionFlag()
            let toolLoopOutcome = try await AgentEnvironmentValues.$current.withValue(runtimeEnvironment) {
                try await TurnEngine(agent: self).executeToolCallingLoop(
                    input: input,
                    toolRegistry: runtimeToolRegistry,
                    provider: provider,
                    sessionHistory: sessionHistory,
                    session: session,
                    resultBuilder: resultBuilder,
                    observer: observer,
                    tracing: tracing,
                    structuredOutputRequest: structuredOutputRequest,
                    executionContext: executionContext,
                    executionGate: executionGate,
                    pendingHandoff: pendingHandoff
                )
            }

            _ = resultBuilder.setOutput(toolLoopOutcome.output)
            applyStructuredOutputMetadata(toolLoopOutcome.structuredOutput, to: resultBuilder)

            // Run output guardrails BEFORE storing in session/memory
            _ = try await runner.runOutputGuardrails(
                outputGuardrails,
                output: toolLoopOutcome.output,
                agent: self,
                context: nil
            )

            // Store turn in session for conversation persistence
            // Session is the source of truth for conversation history
            if let session {
                try await session.addItems([userMessage] + toolLoopOutcome.transcriptMessages)

                let persistedTranscript = SwarmTranscript(memoryMessages: try await session.getAllItems())
                try persistedTranscript.validateReplayCompatibility()
                _ = resultBuilder.setMetadata(
                    Self.transcriptSchemaVersionMetadataKey,
                    .string(persistedTranscript.schemaVersion.rawValue)
                )
                if let transcriptHash = try? persistedTranscript.transcriptHash() {
                    _ = resultBuilder.setMetadata(Self.transcriptHashMetadataKey, .string(transcriptHash))
                }
            } else if let activeMemory, shouldPersistNoSessionTurn(to: activeMemory) {
                await persistNoSessionTurn(
                    userMessage: userMessage,
                    transcriptMessages: toolLoopOutcome.transcriptMessages,
                    to: activeMemory
                )
            }

            // Session remains the transcript source of truth. When no session is supplied,
            // the default memory keeps user/assistant turns available for subsequent runs.

            _ = resultBuilder.setMetadata(RuntimeMetadata.runtimeEngineKey, .string(RuntimeMetadata.nativeRuntimeEngineName))
            let result = resultBuilder.build()
            if configuration.autoPreviousResponseId, let session {
                let response = makeResponse(from: result, responseID: responseID)
                await runEnvironment.responseTracker.recordResponse(response, sessionId: session.sessionId)
            }
            await tracing.traceComplete(result: result, tokenUsage: resultBuilder.ownTokenUsage())

            // Notify observer of agent completion
            await observer?.onAgentEnd(context: nil, agent: self, result: result)

            if let endMemorySession = memoryHooks.endMemorySession {
                await endMemorySession()
            }
            if let defaultMemoryRunKey {
                await runEnvironment.defaultMemorySessionTracker.endRun(for: defaultMemoryRunKey)
            }
            return InternalRunResult(agentResult: result, structuredOutput: toolLoopOutcome.structuredOutput)
        } catch {
            let normalizedError = normalizeCancellation(error)
            // Notify observer of error
            await observer?.onError(context: nil, agent: self, error: normalizedError)
            await tracing.traceError(normalizedError)
            if let endMemorySession = memoryHooks.endMemorySession {
                await endMemorySession()
            }
            if let defaultMemoryRunKey {
                await runEnvironment.defaultMemorySessionTracker.endRun(for: defaultMemoryRunKey)
            }
            throw normalizedError
        }
    }

    // MARK: - Inference Provider Resolution

    private func resolvedInferenceProvider() async throws -> any InferenceProvider {
        try await AgentDependencyResolver.inferenceProvider(
            privacyRequired: configuration.inferencePolicy?.privacyRequired == true,
            explicitProvider: inferenceProvider,
            environment: AgentEnvironmentValues.current,
            runEnvironment: runEnvironment
        )
    }

    func resolvedMembraneAdapter() -> (any MembraneAgentAdapter)? {
        AgentDependencyResolver.membraneAdapter(in: AgentEnvironmentValues.current)
    }

    private func runtimeEnvironment(for provider: any InferenceProvider) -> AgentEnvironment {
        AgentDependencyResolver.runtimeEnvironment(AgentEnvironmentValues.current, addingTokenCounterFrom: provider)
    }

    func resolvedMemory() -> (any Memory)? {
        AgentDependencyResolver.memory(
            explicitMemory: memory,
            environmentMemory: AgentEnvironmentValues.current.memory,
            defaultMemory: defaultMemory
        )
    }

    private func shouldPersistNoSessionTurn(to activeMemory: any Memory) -> Bool {
        guard let defaultMemory else {
            return false
        }

        return memoriesAreSameInstance(activeMemory, defaultMemory)
    }

    private func persistNoSessionTurn(
        userMessage: MemoryMessage,
        transcriptMessages: [MemoryMessage],
        to memory: any Memory
    ) async {
        let messages = ([userMessage] + transcriptMessages).filter { message in
            message.role == .user || message.role == .assistant
        }

        for message in messages {
            await memory.add(message)
        }
    }

    /// Creates the package default memory for agents that do not pass one explicitly.
    ///
    /// With the Integrations trait: ContextCore+Wax ``DefaultAgentMemory``.
    /// Without Integrations (lean default): ``SlidingWindowMemory``.
    /// Prefer this over constructing integration types from macros or client code so
    /// trait gating stays inside the Swarm module.
    /// - Parameter waxStoreURL: Explicit location of the durable Wax store.
    ///   When `nil`, the store lands under the installed ephemeral root
    ///   (``SwarmDefaultStoreLocation/installEphemeralRoot(_:)``) when one is
    ///   present, and in the durable Application-Support location otherwise.
    public static func makeDefaultMemory(waxStoreURL: URL? = nil) throws -> any Memory {
        #if SWARM_INTEGRATIONS && canImport(ContextCore)
        let resolvedWaxStoreURL = waxStoreURL ?? SwarmDefaultStoreLocation.installedEphemeralRoot.map {
            WaxMemory.makeEphemeralStoreURL(under: $0)
        }
        guard let resolvedWaxStoreURL else {
            return try DefaultAgentMemory()
        }
        return try DefaultAgentMemory(configuration: DefaultAgentMemory.Configuration(
            waxStoreURL: resolvedWaxStoreURL
        ))
        #else
        // Lean builds, or Integrations on non-Apple (no ContextCore link).
        return SlidingWindowMemory()
        #endif
    }

    private func resolvedToolRegistry() async throws -> ToolRegistry {
        try await AgentDependencyResolver.toolRegistry(
            baseTools: await toolRegistry.allTools,
            taskLocalWebSearch: AgentEnvironmentValues.current.webSearch,
            runEnvironment: runEnvironment
        )
    }

    func resolvedInferenceOptions(
        session: (any Session)?,
        provider: any InferenceProvider
    ) async -> InferenceOptions {
        await AgentDependencyResolver.inferenceOptions(
            configuration: configuration,
            capabilities: providerCapabilities(for: provider),
            sessionID: session?.sessionId,
            responseTracker: runEnvironment.responseTracker
        )
    }

    func providerCapabilities(for provider: any InferenceProvider) -> InferenceProviderCapabilities {
        AgentDependencyResolver.providerCapabilities(for: provider)
    }

    private func responseID(from result: AgentResult) -> String {
        if case let .string(value)? = result.metadata[Self.responseIDMetadataKey], !value.isEmpty {
            return value
        }
        return UUID().uuidString
    }

    private func makeResponse(from result: AgentResult, responseID: String) -> AgentResponse {
        let toolCallsById = Dictionary(uniqueKeysWithValues: result.toolCalls.map { ($0.id, $0) })
        let toolCallRecords: [ToolCallRecord] = result.toolResults.compactMap { toolResult in
            guard let toolCall = toolCallsById[toolResult.callId] else {
                Log.agents.warning("Tool result missing matching call: \(toolResult.callId)")
                return nil
            }

            return ToolCallRecord(
                toolName: toolCall.toolName,
                arguments: toolCall.arguments,
                duration: toolResult.duration,
                timestamp: toolCall.timestamp,
                outcome: ToolCallRecord.Outcome(toolResult.outcome)
            )
        }

        return AgentResponse(
            responseId: responseID,
            output: result.output,
            agentName: configuration.name,
            metadata: result.metadata,
            toolCalls: toolCallRecords,
            usage: result.tokenUsage,
            iterationCount: result.iterationCount
        )
    }

    private func applyStructuredOutputMetadata(
        _ structuredOutput: StructuredOutputResult?,
        to resultBuilder: AgentResult.Builder
    ) {
        guard let structuredOutput else { return }

        _ = resultBuilder.setMetadata(Self.structuredOutputJSONMetadataKey, .string(structuredOutput.rawJSON))
        _ = resultBuilder.setMetadata(Self.structuredOutputSourceMetadataKey, .string(structuredOutput.source.rawValue))
        _ = resultBuilder.setMetadata(
            Self.structuredOutputFormatMetadataKey,
            .string(Self.structuredOutputFormatDescription(structuredOutput.format))
        )
    }

    private static func structuredOutputFormatDescription(_ format: StructuredOutputFormat) -> String {
        switch format {
        case .jsonObject:
            return "json_object"
        case .jsonSchema(let name, _):
            return "json_schema:\(name)"
        }
    }

    /// Runs `operation` bounded by the remaining run timeout.
    ///
    /// Delegates to the shared ``withTimeoutRace`` settlement primitive, so
    /// outcomes recorded before the continuation installs are replayed and
    /// worker tasks registered after settlement are cancelled. Owned-loop-gate
    /// deactivation rides on the race's `onSettle` hook: the gate is
    /// deactivated exactly when settlement fails with `CancellationError` or
    /// `AgentError.timeout` (see `shouldDeactivateOwnedLoop`), never on
    /// success or unrelated failures.
    ///
    /// The remaining budget is computed from `startTime` and consumed through
    /// the injected `SwarmClock`, keeping the sleep on the same fake-clock
    /// seam used by resilience code.
    ///
    /// - Parameters:
    ///   - startTime: Run start instant used to compute the remaining budget.
    ///   - executionGate: Optional owned-loop gate deactivated on cancellation/timeout.
    ///   - clock: Clock driving the timeout suspension; inject a fake clock in tests.
    ///   - operation: The work to bound.
    func executeWithinRemainingTimeout<T: Sendable>(
        startTime: ContinuousClock.Instant,
        executionGate: ProviderOwnedLoopGate? = nil,
        clock: any SwarmClock = LiveSwarmClock.live,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try Task.checkCancellation()

        let remaining = configuration.timeout - (ContinuousClock.now - startTime)
        if remaining <= .zero {
            throw AgentError.timeout(duration: configuration.timeout)
        }

        return try await withTimeoutRace(
            timeout: remaining,
            clock: clock,
            timeoutError: AgentError.timeout(duration: configuration.timeout),
            onSettle: { error in
                guard let error, Self.shouldDeactivateOwnedLoop(for: error) else { return }
                executionGate?.deactivate()
            },
            operation: operation
        )
    }

    /// Owned-loop gates deactivate only when a run dies by cancellation or
    /// timeout; ordinary inference/tool failures must leave the gate armed.
    private static func shouldDeactivateOwnedLoop(for error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if case .timeout = error as? AgentError {
            return true
        }
        return false
    }

    func normalizeCancellation(_ error: Error) -> Error {
        if error is CancellationError {
            return AgentError.cancelled
        }
        if let agentError = error as? AgentError, agentError == .cancelled {
            return agentError
        }
        return error
    }

    /// Serializes a non-string tool result as canonical JSON so downstream
    /// consumers (Membrane pointerization, transcript replay, model context)
    /// receive a parsable contract rather than `SendableValue.description`'s
    /// JSON-ish format which does not escape quotes, backslashes, or newlines.
    ///
    /// Plain-string results pass through unchanged. Falls back to
    /// `description` if the value contains a non-finite double — `JSONSerialization`
    /// raises an Objective-C `NSException` (not a Swift error) on NaN/Infinity,
    /// so we must screen the value before serializing rather than relying on
    /// `do/catch`.
    static func toolOutputText(for output: SendableValue) -> String {
        if let string = output.stringValue {
            return string
        }

        guard !containsNonFiniteDouble(output) else {
            return output.description
        }

        do {
            let object = output.toJSONObject()
            let data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys, .fragmentsAllowed]
            )
            if let text = String(data: data, encoding: .utf8) {
                return text
            }
        } catch {
            Log.agents.warning("Tool output JSON serialization failed; falling back to description: \(error)")
        }

        return output.description
    }

    private static func containsNonFiniteDouble(_ value: SendableValue) -> Bool {
        switch value {
        case let .double(number):
            return !number.isFinite
        case let .array(values):
            return values.contains(where: containsNonFiniteDouble)
        case let .dictionary(values):
            return values.values.contains(where: containsNonFiniteDouble)
        case .null, .bool, .int, .string:
            return false
        }
    }

    func optionsWithMembraneRuntimeSettings(_ base: InferenceOptions) -> InferenceOptions {
        guard let membrane = AgentEnvironmentValues.current.membrane, membrane.isEnabled else {
            return base
        }

        let flags = membrane.configuration.runtimeFeatureFlags
        let allowlist = membrane.configuration.runtimeModelAllowlist

        if flags.isEmpty, allowlist.isEmpty {
            return base
        }

        var updated = base
        var settings = updated.providerSettings ?? [:]

        for (key, isEnabled) in flags {
            let prefix = "conduit.runtime."
            guard key.hasPrefix(prefix) else { continue }
            let feature = String(key.dropFirst(prefix.count))
            settings["conduit.runtime.policy.\(feature).enabled"] = .bool(isEnabled)
        }

        if !allowlist.isEmpty {
            let uniqueSorted = Array(Set(allowlist)).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            settings["conduit.runtime.policy.model_allowlist"] = .array(uniqueSorted.map { .string($0) })
        }

        updated.providerSettings = settings.isEmpty ? nil : settings
        return updated
    }

}

// MARK: Agent.Builder

public extension Agent {
    /// Builder for creating Agent instances with a fluent API.
    ///
    /// Uses value semantics (struct) for Swift 6 concurrency safety.
    ///
    /// Example:
    /// ```swift
    /// let agent = Agent.Builder()
    ///     .tools([WeatherTool(), CalculatorTool()])
    ///     .instructions("You are a helpful assistant.")
    ///     .configuration(.default.maxIterations(5))
    ///     .build()
    /// ```
    struct Builder: Sendable {
        // MARK: Public

        // MARK: - Initialization

        /// Creates a new builder.
        public init() {}

        // MARK: - Builder Methods

        /// Sets the tools.
        /// - Parameter tools: The tools to use.
        /// - Returns: A new builder with the tools set.
        @discardableResult
        @available(*, deprecated, message: "Use tools(_:) with typed Tool values or Agent.withTools(@ToolBuilder:) for canonical typed tools.")
        public func tools(_ tools: [any AnyJSONTool]) -> Builder {
            var copy = self
            copy._tools = tools
            return copy
        }

        /// Sets the tools from typed tool instances.
        /// - Parameter tools: The typed tools to use.
        /// - Returns: A new builder with the tools set.
        @discardableResult
        public func tools(_ tools: [some Tool]) -> Builder {
            var copy = self
            copy._tools = tools.map { AnyJSONToolAdapter($0) }
            return copy
        }

        /// Adds a tool (concrete type preferred; Swift resolves `some` before opening `any`).
        /// - Parameter tool: The tool to add.
        /// - Returns: A new builder with the tool added.
        @discardableResult
        @available(*, deprecated, message: "Use addTool(_:) with a typed Tool, or wrap raw tools in a clearly marked advanced adapter.")
        public func addTool(_ tool: some AnyJSONTool) -> Builder {
            var copy = self
            copy._tools.append(tool)
            return copy
        }

        /// Adds a tool from an existential (use when the concrete type is not available at the call site).
        /// - Parameter tool: The tool to add.
        /// - Returns: A new builder with the tool added.
        @discardableResult
        @available(*, deprecated, message: "Use addTool(_:) with a typed Tool, or wrap raw tools in a clearly marked advanced adapter.")
        public func addTool(_ tool: any AnyJSONTool) -> Builder {
            var copy = self
            copy._tools.append(tool)
            return copy
        }

        /// Adds a typed tool.
        /// - Parameter tool: The typed tool to add.
        /// - Returns: A new builder with the tool added.
        @discardableResult
        public func addTool(_ tool: some Tool) -> Builder {
            var copy = self
            copy._tools.append(AnyJSONToolAdapter(tool))
            return copy
        }

        /// Adds built-in tools.
        /// - Returns: A new builder with built-in tools added.
        @discardableResult
        public func withBuiltInTools() -> Builder {
            var copy = self
            copy._tools.append(contentsOf: BuiltInTools.all)
            return copy
        }

        /// Sets the instructions.
        /// - Parameter instructions: The system instructions.
        /// - Returns: A new builder with the instructions set.
        @discardableResult
        public func instructions(_ instructions: String) -> Builder {
            var copy = self
            copy._instructions = instructions
            return copy
        }

        /// Sets the configuration.
        /// - Parameter configuration: The agent configuration.
        /// - Returns: A new builder with the configuration set.
        @discardableResult
        public func configuration(_ configuration: AgentConfiguration) -> Builder {
            var copy = self
            copy._configuration = configuration
            return copy
        }

        /// Sets the memory system.
        /// - Parameter memory: The memory to use.
        /// - Returns: A new builder with the memory set.
        @discardableResult
        public func memory(_ memory: any Memory) -> Builder {
            var copy = self
            copy._memory = memory
            return copy
        }

        /// Sets the inference provider.
        /// - Parameter provider: The provider to use.
        /// - Returns: A new builder with the provider set.
        @discardableResult
        public func inferenceProvider(_ provider: any InferenceProvider) -> Builder {
            var copy = self
            copy._inferenceProvider = provider
            return copy
        }

        /// Sets the tracer for observability.
        /// - Parameter tracer: The tracer to use.
        /// - Returns: A new builder with the tracer set.
        @discardableResult
        public func tracer(_ tracer: any Tracer) -> Builder {
            var copy = self
            copy._tracer = tracer
            return copy
        }

        /// Sets the input guardrails.
        /// - Parameter guardrails: The input guardrails to use.
        /// - Returns: A new builder with the guardrails set.
        @discardableResult
        public func inputGuardrails(_ guardrails: [any InputGuardrail]) -> Builder {
            var copy = self
            copy._inputGuardrails = guardrails
            return copy
        }

        /// Adds an input guardrail.
        /// - Parameter guardrail: The guardrail to add.
        /// - Returns: A new builder with the guardrail added.
        @discardableResult
        public func addInputGuardrail(_ guardrail: any InputGuardrail) -> Builder {
            var copy = self
            copy._inputGuardrails.append(guardrail)
            return copy
        }

        /// Sets the output guardrails.
        /// - Parameter guardrails: The output guardrails to use.
        /// - Returns: A new builder with the guardrails set.
        @discardableResult
        public func outputGuardrails(_ guardrails: [any OutputGuardrail]) -> Builder {
            var copy = self
            copy._outputGuardrails = guardrails
            return copy
        }

        /// Adds an output guardrail.
        /// - Parameter guardrail: The guardrail to add.
        /// - Returns: A new builder with the guardrail added.
        @discardableResult
        public func addOutputGuardrail(_ guardrail: any OutputGuardrail) -> Builder {
            var copy = self
            copy._outputGuardrails.append(guardrail)
            return copy
        }

        /// Sets the guardrail runner configuration.
        /// - Parameter configuration: The guardrail runner configuration.
        /// - Returns: A new builder with the updated configuration.
        @discardableResult
        public func guardrailRunnerConfiguration(_ configuration: GuardrailRunnerConfiguration) -> Builder {
            var copy = self
            copy._guardrailRunnerConfiguration = configuration
            return copy
        }

        /// Sets the handoff configurations.
        /// - Parameter handoffs: The handoff configurations to use.
        /// - Returns: A new builder with the updated handoffs.
        @discardableResult
        public func handoffs(_ handoffs: [AnyHandoffConfiguration]) -> Builder {
            var copy = self
            copy._handoffs = handoffs
            return copy
        }

        /// Adds a handoff configuration.
        /// - Parameter handoff: The handoff configuration to add.
        /// - Returns: A new builder with the handoff added.
        @discardableResult
        public func addHandoff(_ handoff: AnyHandoffConfiguration) -> Builder {
            var copy = self
            copy._handoffs.append(handoff)
            return copy
        }

        /// Adds a handoff target using typed options.
        ///
        /// This is the canonical front-facing handoff API.
        ///
        /// - Parameters:
        ///   - target: The target agent.
        ///   - configure: Optional typed options transformer.
        /// - Returns: A new builder with the handoff added.
        @discardableResult
        public func handoff<Target: AgentRuntime>(
            to target: Target,
            configure: (HandoffOptions<Target>) -> HandoffOptions<Target> = { $0 }
        ) -> Builder {
            var copy = self
            let options = configure(HandoffOptions())
            copy._handoffs.append(options.erasedConfiguration(for: target))
            return copy
        }

        /// Adds multiple handoff targets using Swift parameter packs.
        ///
        /// Example:
        /// ```swift
        /// let agent = try Agent.Builder()
        ///     .handoffs(billingAgent, supportAgent, salesAgent)
        ///     .build()
        /// ```
        @discardableResult
        public func handoffs<each Target: AgentRuntime>(_ targets: repeat each Target) -> Builder {
            var copy = self
            repeat copy._handoffs.append(AnyHandoffConfiguration(targetAgent: each targets))
            return copy
        }

        /// Builds the agent.
        /// - Returns: A new Agent instance.
        /// - Throws: `ToolRegistryError.duplicateToolName` if duplicate tool names are provided.
        public func build() throws -> Agent {
            try Agent(
                tools: _tools,
                instructions: _instructions,
                configuration: _configuration,
                memory: _memory,
                inferenceProvider: _inferenceProvider,
                tracer: _tracer,
                inputGuardrails: _inputGuardrails,
                outputGuardrails: _outputGuardrails,
                guardrailRunnerConfiguration: _guardrailRunnerConfiguration,
                handoffs: _handoffs
            )
        }

        // MARK: Private

        private var _tools: [any AnyJSONTool] = []
        private var _instructions: String = ""
        private var _configuration: AgentConfiguration = .default
        private var _memory: (any Memory)?
        private var _inferenceProvider: (any InferenceProvider)?
        private var _tracer: (any Tracer)?
        private var _inputGuardrails: [any InputGuardrail] = []
        private var _outputGuardrails: [any OutputGuardrail] = []
        private var _guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default
        private var _handoffs: [AnyHandoffConfiguration] = []
    }
}

// MARK: - Convenience Initializers

public extension Agent {
    /// Creates a new Agent with a name as the first parameter.
    ///
    /// This convenience initializer mirrors the OpenAI Agent SDK pattern
    /// where the agent name is a top-level parameter rather than nested
    /// inside configuration.
    ///
    /// Example:
    /// ```swift
    /// let agent = Agent(name: "Triage", instructions: "Route requests", tools: [weatherTool])
    /// ```
    ///
    /// - Parameters:
    ///   - name: The display name of the agent.
    ///   - instructions: System instructions defining agent behavior. Default: ""
    ///   - tools: Tools available to the agent. Default: []
    ///   - inferenceProvider: Optional custom inference provider. Default: nil
    ///   - memory: Optional explicit memory override. Default: ContextCore+Wax `DefaultAgentMemory` when Integrations is enabled; otherwise `SlidingWindowMemory`
    ///   - tracer: Optional tracer for observability. Default: nil
    ///   - configuration: Additional agent configuration settings. Default: .default
    ///   - inputGuardrails: Input validation guardrails. Default: []
    ///   - outputGuardrails: Output validation guardrails. Default: []
    ///   - guardrailRunnerConfiguration: Configuration for guardrail runner. Default: .default
    ///   - handoffs: Handoff configurations for multi-agent orchestration. Default: []
    /// - Throws: `ToolRegistryError.duplicateToolName` if duplicate tool names are provided.
    init(
        name: String,
        instructions: String = "",
        tools: [any AnyJSONTool] = [],
        inferenceProvider: (any InferenceProvider)? = nil,
        memory: (any Memory)? = nil,
        tracer: (any Tracer)? = nil,
        configuration: AgentConfiguration = .default,
        inputGuardrails: [any InputGuardrail] = [],
        outputGuardrails: [any OutputGuardrail] = [],
        guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default,
        handoffs: [AnyHandoffConfiguration] = []
    ) throws {
        // Merge the name into the configuration
        var config = configuration
        config.name = name
        try self.init(
            tools: tools,
            instructions: instructions,
            configuration: config,
            memory: memory,
            inferenceProvider: inferenceProvider,
            tracer: tracer,
            inputGuardrails: inputGuardrails,
            outputGuardrails: outputGuardrails,
            guardrailRunnerConfiguration: guardrailRunnerConfiguration,
            handoffs: handoffs
        )
    }
}

// MARK: - Simplified Handoff Declaration

public extension Agent {
    /// Creates an Agent with agents directly as handoff targets.
    ///
    /// This convenience initializer eliminates the need to wrap each agent
    /// in `AnyHandoffConfiguration`, inspired by the OpenAI SDK pattern
    /// where you pass agents directly: `Agent(handoffs=[billing, support])`.
    ///
    /// Example:
    /// ```swift
    /// let triage = Agent(
    ///     name: "Triage",
    ///     instructions: "Route requests",
    ///     handoffAgents: [billingAgent, supportAgent]
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - name: The display name of the agent.
    ///   - instructions: System instructions. Default: ""
    ///   - tools: Tools available to the agent. Default: []
    ///   - inferenceProvider: Optional inference provider. Default: nil
    ///   - memory: Optional explicit memory override. Default: ContextCore+Wax `DefaultAgentMemory` when Integrations is enabled; otherwise `SlidingWindowMemory`
    ///   - tracer: Optional tracer. Default: nil
    ///   - configuration: Additional configuration. Default: .default
    ///   - inputGuardrails: Input guardrails. Default: []
    ///   - outputGuardrails: Output guardrails. Default: []
    ///   - guardrailRunnerConfiguration: Guardrail runner config. Default: .default
    ///   - handoffAgents: Agents to use as handoff targets.
    /// - Throws: `ToolRegistryError.duplicateToolName` if duplicate tool names are provided.
    init(
        name: String,
        instructions: String = "",
        tools: [any AnyJSONTool] = [],
        inferenceProvider: (any InferenceProvider)? = nil,
        memory: (any Memory)? = nil,
        tracer: (any Tracer)? = nil,
        configuration: AgentConfiguration = .default,
        inputGuardrails: [any InputGuardrail] = [],
        outputGuardrails: [any OutputGuardrail] = [],
        guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default,
        handoffAgents: [any AgentRuntime]
    ) throws {
        let handoffs = handoffAgents.map { agent in
            AnyHandoffConfiguration(targetAgent: agent)
        }
        try self.init(
            name: name,
            instructions: instructions,
            tools: tools,
            inferenceProvider: inferenceProvider,
            memory: memory,
            tracer: tracer,
            configuration: configuration,
            inputGuardrails: inputGuardrails,
            outputGuardrails: outputGuardrails,
            guardrailRunnerConfiguration: guardrailRunnerConfiguration,
            handoffs: handoffs
        )
    }
}

// MARK: - V3 Canonical Init with Explicit Provider

public extension Agent {
    /// V3 convenience init with an explicit, non-optional inference provider.
    ///
    /// This overload avoids the optional wrapping when a provider is always known:
    /// ```swift
    /// let agent = try Agent("You are helpful.", provider: .foundationModels()) {
    ///     WeatherTool()
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - instructions: System instructions defining agent behavior.
    ///   - provider: The inference provider to use.
    ///   - tools: A `@ToolBuilder` closure producing the agent's tools. Default: empty.
    /// - Throws: `ToolRegistryError.duplicateToolName` if duplicate tool names are provided.
    init(
        _ instructions: String,
        provider: some InferenceProvider,
        @ToolBuilder tools: () -> ToolCollection = { .empty }
    ) throws {
        try self.init(
            tools: tools().storage,
            instructions: instructions,
            inferenceProvider: provider
        )
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
