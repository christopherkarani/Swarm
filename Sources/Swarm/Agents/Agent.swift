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
        self.tools = tools
        self.instructions = instructions
        self.configuration = configuration
        self.memory = memory
        self.defaultMemory = try memory == nil ? Self.makeDefaultMemory() : nil
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
        await cancellationState.begin(runID: runID, task: task)

        do {
            let result = try await withTaskCancellationHandler(
                operation: {
                    try await task.value.agentResult
                },
                onCancel: {
                    task.cancel()
                }
            )
            await cancellationState.finish(runID: runID)
            return result
        } catch {
            task.cancel()
            await cancellationState.finish(runID: runID)
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
        await cancellationState.begin(runID: runID, task: task)

        do {
            let result = try await withTaskCancellationHandler(
                operation: {
                    try await task.value
                },
                onCancel: {
                    task.cancel()
                }
            )
            await cancellationState.finish(runID: runID)

            guard let structuredOutput = result.structuredOutput else {
                throw AgentError.generationFailed(reason: "Structured output request completed without a structured result")
            }

            return StructuredAgentResult(agentResult: result.agentResult, structuredOutput: structuredOutput)
        } catch {
            task.cancel()
            await cancellationState.finish(runID: runID)
            throw normalizeCancellation(error)
        }
    }

    /// Cancels any ongoing execution.
    ///
    public func cancel() async {
        await cancellationState.cancelCurrent()
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

    // MARK: - Conversation History

    private enum ConversationMessage: Sendable {
        case system(String)
        case user(String)
        case assistant(String, toolCalls: [InferenceResponse.ParsedToolCall] = [])
        case toolResult(toolName: String, result: String, toolCallID: String? = nil)

        var formatted: String {
            switch self {
            case let .system(content):
                return "[System]: \(content)"
            case let .user(content):
                return "[User]: \(content)"
            case let .assistant(content, toolCalls):
                if toolCalls.isEmpty {
                    return "[Assistant]: \(content)"
                }

                let summary = toolCalls.map { "Calling tool: \($0.name)" }.joined(separator: ", ")
                if content.isEmpty {
                    return "[Assistant]: \(summary)"
                }

                return "[Assistant]: \(content)\n[Assistant Tool Calls]: \(summary)"
            case let .toolResult(toolName, result, _):
                return "[Tool Result - \(toolName)]: \(result)"
            }
        }

        var inferenceMessage: InferenceMessage {
            switch self {
            case let .system(content):
                return .system(content)
            case let .user(content):
                return .user(content)
            case let .assistant(content, toolCalls):
                return .assistant(content, toolCalls: toolCalls.map(InferenceMessage.ToolCall.init))
            case let .toolResult(toolName, result, toolCallID):
                return .tool(name: toolName, content: result, toolCallID: toolCallID)
            }
        }
    }

    private var _handoffs: [AnyHandoffConfiguration]

    // MARK: - Internal State

    private var toolRegistry: ToolRegistry
    private let cancellationState = ActiveRunCancellationState()
    /// Created from ``AgentConfiguration/resilience`` at init. Copies of this value share the actor.
    let inferenceCircuitBreaker: CircuitBreaker?
    /// Created from ``AgentConfiguration/resilience`` at init. Copies of this value share the actor.
    let inferenceRateLimiter: RateLimiter?
    private static let autoResponseTracker = ResponseTracker()
    private static let defaultMemorySessionTracker = DefaultMemorySessionTracker()
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

    struct ToolLoopOutcome: Sendable {
        let output: String
        let structuredOutput: StructuredOutputResult?
        let transcriptMessages: [MemoryMessage]
    }

    struct FinalAssistantResponse: Sendable {
        let content: String
        let structuredOutput: StructuredOutputResult?
    }

    private actor ActiveRunCancellationState {
        private var activeRunID: UUID?
        private var activeTask: Task<InternalRunResult, Error>?

        func begin(runID: UUID, task: Task<InternalRunResult, Error>) {
            activeRunID = runID
            activeTask = task
        }

        func finish(runID: UUID) {
            guard activeRunID == runID else { return }
            activeRunID = nil
            activeTask = nil
        }

        func cancelCurrent() {
            activeTask?.cancel()
        }
    }

    private final class TimedOperationCoordinator<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Error>?
        private var operationTask: Task<Void, Never>?
        private var timeoutTask: Task<Void, Never>?
        private var ownedLoopGate: ProviderOwnedLoopGate?
        private var completed = false

        func setOwnedLoopGate(_ gate: ProviderOwnedLoopGate?) {
            lock.lock()
            defer { lock.unlock() }
            ownedLoopGate = gate
        }

        func install(continuation: CheckedContinuation<T, Error>) {
            lock.lock()
            defer { lock.unlock() }
            self.continuation = continuation
        }

        func setOperationTask(_ task: Task<Void, Never>) {
            lock.lock()
            defer { lock.unlock() }
            operationTask = task
        }

        func setTimeoutTask(_ task: Task<Void, Never>) {
            lock.lock()
            defer { lock.unlock() }
            timeoutTask = task
        }

        func finish(returning value: T) {
            complete(deactivateOwnedLoop: false) { continuation in
                continuation.resume(returning: value)
            }
        }

        func finish(throwing error: Error) {
            complete(deactivateOwnedLoop: Self.shouldDeactivateOwnedLoop(for: error)) { continuation in
                continuation.resume(throwing: error)
            }
        }

        func cancelPending(with error: Error) {
            let pendingState = takePendingState()
            if Self.shouldDeactivateOwnedLoop(for: error) {
                pendingState.ownedLoopGate?.deactivate()
            }
            pendingState.operationTask?.cancel()
            pendingState.timeoutTask?.cancel()
            pendingState.continuation?.resume(throwing: error)
        }

        private func complete(
            deactivateOwnedLoop: Bool,
            _ resume: (CheckedContinuation<T, Error>) -> Void
        ) {
            let pendingState = takePendingState()
            if deactivateOwnedLoop {
                pendingState.ownedLoopGate?.deactivate()
            }
            pendingState.operationTask?.cancel()
            pendingState.timeoutTask?.cancel()
            guard let continuation = pendingState.continuation else { return }
            resume(continuation)
        }

        private static func shouldDeactivateOwnedLoop(for error: Error) -> Bool {
            if error is CancellationError {
                return true
            }
            if case .timeout = error as? AgentError {
                return true
            }
            return false
        }

        private func takePendingState() -> (
            continuation: CheckedContinuation<T, Error>?,
            operationTask: Task<Void, Never>?,
            timeoutTask: Task<Void, Never>?,
            ownedLoopGate: ProviderOwnedLoopGate?
        ) {
            lock.lock()
            defer { lock.unlock() }

            guard completed == false else {
                return (nil, nil, nil, nil)
            }

            completed = true
            let pendingContinuation = continuation
            let pendingOperationTask = operationTask
            let pendingTimeoutTask = timeoutTask
            let pendingGate = ownedLoopGate
            continuation = nil
            operationTask = nil
            timeoutTask = nil
            ownedLoopGate = nil
            return (pendingContinuation, pendingOperationTask, pendingTimeoutTask, pendingGate)
        }
    }

    private actor DefaultMemorySessionTracker {
        private var sessionIDs: [ObjectIdentifier: String] = [:]
        private var activeSessionIDs: [ObjectIdentifier: String] = [:]
        private var activeCounts: [ObjectIdentifier: Int] = [:]
        // Waiters are keyed by a per-call UUID so a cancellation can target the
        // exact parked task without disturbing siblings. `endRun()` resumes any
        // remaining waiters with success; cancellation resumes the targeted
        // waiter with `CancellationError` and removes it from the map.
        private var waiters: [ObjectIdentifier: [UUID: CheckedContinuation<Void, Error>]] = [:]

        func beginRun(for key: ObjectIdentifier, sessionID: String) async throws -> Bool {
            while let activeSessionID = activeSessionIDs[key],
                  activeSessionID != sessionID
            {
                try Task.checkCancellation()
                try await waitForSessionRelease(key: key)
            }

            // Final cancellation check after exiting the wait loop. Closes the
            // race where `endRun` resumes the continuation just as the parent
            // task is cancelled — without this, the resumed task would proceed
            // to claim the slot and trigger memory-clear side effects.
            try Task.checkCancellation()

            let previous = sessionIDs[key]
            sessionIDs[key] = sessionID
            activeSessionIDs[key] = sessionID
            activeCounts[key, default: 0] += 1
            return previous != sessionID
        }

        func endRun(for key: ObjectIdentifier) {
            let remaining = (activeCounts[key] ?? 1) - 1
            if remaining > 0 {
                activeCounts[key] = remaining
                return
            }

            activeCounts[key] = nil
            activeSessionIDs[key] = nil
            let pendingWaiters = waiters.removeValue(forKey: key) ?? [:]
            for (_, continuation) in pendingWaiters {
                continuation.resume()
            }
        }

        /// Park the calling task until either the active session releases (success)
        /// or the calling task is cancelled (throws `CancellationError`). Without
        /// the cancellation arm, a cancelled task would stay parked until the
        /// holder of the active session calls `endRun()`, then wake up and claim
        /// the slot — performing memory clears and other side effects before the
        /// cancellation surfaces deeper in execution.
        private func waitForSessionRelease(key: ObjectIdentifier) async throws {
            let waiterID = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    waiters[key, default: [:]][waiterID] = continuation
                }
            } onCancel: {
                Task { await self.cancelWaiter(key: key, id: waiterID) }
            }
        }

        private func cancelWaiter(key: ObjectIdentifier, id: UUID) {
            if let continuation = waiters[key]?.removeValue(forKey: id) {
                if waiters[key]?.isEmpty == true {
                    waiters[key] = nil
                }
                continuation.resume(throwing: CancellationError())
            }
        }
    }

    private func resolvedActiveTracer() -> (any Tracer)? {
        let configured = tracer ?? AgentEnvironmentValues.current.tracer
        let fallback = configuration.defaultTracingEnabled
            ? SwiftLogTracer(minimumLevel: .debug)
            : nil
        let base = configured ?? fallback

        guard configuration.autoAttachMetricsCollector, let collector = metricsCollector else {
            return base
        }

        if let base {
            if let existing = base as? MetricsCollector, existing === collector {
                return collector
            }
            return CompositeTracer(tracers: [base, collector])
        }
        return collector
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
            if try await Self.defaultMemorySessionTracker.beginRun(for: memoryKey, sessionID: session.sessionId) {
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
                try await executeToolCallingLoop(
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
                await Self.autoResponseTracker.recordResponse(response, sessionId: session.sessionId)
            }
            await tracing.traceComplete(result: result, tokenUsage: resultBuilder.ownTokenUsage())

            // Notify observer of agent completion
            await observer?.onAgentEnd(context: nil, agent: self, result: result)

            if let endMemorySession = memoryHooks.endMemorySession {
                await endMemorySession()
            }
            if let defaultMemoryRunKey {
                await Self.defaultMemorySessionTracker.endRun(for: defaultMemoryRunKey)
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
                await Self.defaultMemorySessionTracker.endRun(for: defaultMemoryRunKey)
            }
            throw normalizedError
        }
    }

    // MARK: - Inference Provider Resolution

    private func resolvedInferenceProvider() async throws -> any InferenceProvider {
        if configuration.inferencePolicy?.privacyRequired == true {
            return try await resolvedPrivateInferenceProvider()
        }

        // 1. Explicit provider on Agent
        if let inferenceProvider {
            return transformedInferenceProvider(inferenceProvider)
        }

        // 2. TaskLocal via .environment()
        if let environmentProvider = AgentEnvironmentValues.current.inferenceProvider {
            return transformedInferenceProvider(environmentProvider)
        }

        // 3. Swarm.defaultProvider (global)
        if let globalProvider = await Swarm.defaultProvider {
            return transformedInferenceProvider(globalProvider)
        }

        // 4. Foundation Models (if available, on Apple platform)
        if let foundationModelsProvider = DefaultInferenceProviderFactory.makeFoundationModelsProviderIfAvailable() {
            return transformedInferenceProvider(foundationModelsProvider)
        }

        // 5. No provider available
        throw AgentError.inferenceProviderUnavailable(
            reason: """
            No inference provider configured and Apple Foundation Models are unavailable.

            Configure a provider globally via `await Swarm.configure(provider: ...)` \
            or pass one explicitly to Agent(...).
            """
        )
    }

    private func resolvedPrivateInferenceProvider() async throws -> any InferenceProvider {
        if let foundationModelsProvider = DefaultInferenceProviderFactory.makeFoundationModelsProviderIfAvailable() {
            return transformedInferenceProvider(foundationModelsProvider)
        }

        if let provider = privateInferenceProvider(inferenceProvider) {
            return transformedInferenceProvider(provider)
        }

        if let provider = privateInferenceProvider(AgentEnvironmentValues.current.inferenceProvider) {
            return transformedInferenceProvider(provider)
        }

        if let globalProvider = await Swarm.defaultProvider,
           let provider = privateInferenceProvider(globalProvider)
        {
            return transformedInferenceProvider(provider)
        }

        throw AgentError.inferenceProviderUnavailable(
            reason: """
            AgentConfiguration.inferencePolicy.privacyRequired is true, but no private inference provider is available.

            Use Apple Foundation Models on a supported device, or configure a provider that reports \
            InferenceProviderCapabilities.privateInference via `await Swarm.configure(provider: ...)`.
            """
        )
    }

    private func privateInferenceProvider(_ provider: (any InferenceProvider)?) -> (any InferenceProvider)? {
        guard let provider else {
            return nil
        }

        let capabilities = InferenceProviderCapabilities.resolved(for: provider)
        guard capabilities.contains(.privateInference) else {
            return nil
        }
        return provider
    }

    private func transformedInferenceProvider(_ provider: any InferenceProvider) -> any InferenceProvider {
        guard let transform = AgentEnvironmentValues.current.inferenceProviderTransform else {
            return provider
        }
        return transform(provider)
    }

    private func resolvedMembraneAdapter() -> (any MembraneAgentAdapter)? {
        let membrane = AgentEnvironmentValues.current.membrane ?? .enabled
        guard membrane.isEnabled else {
            return nil
        }
        if let adapter = membrane.adapter {
            return adapter
        }
        return DefaultMembraneAgentAdapter(configuration: membrane.configuration)
    }

    private func runtimeEnvironment(for provider: any InferenceProvider) -> AgentEnvironment {
        var environment = AgentEnvironmentValues.current
        if let tokenCounter = provider.promptTokenCounter {
            environment.promptTokenCounter = tokenCounter
        }
        return environment
    }

    private func resolvedMemory() -> (any Memory)? {
        memory ?? AgentEnvironmentValues.current.memory ?? defaultMemory
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
    public static func makeDefaultMemory() throws -> any Memory {
        #if SWARM_INTEGRATIONS && canImport(ContextCore)
        if SwarmRuntimeEnvironment.isRunningTests {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("SwarmDefaultMemoryTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return try DefaultAgentMemory(configuration: DefaultAgentMemory.Configuration(
                waxStoreURL: root.appendingPathComponent("wax-memory.mv2s")
            ))
        }
        return try DefaultAgentMemory()
        #else
        // Lean builds, or Integrations on non-Apple (no ContextCore link).
        return SlidingWindowMemory()
        #endif
    }

    private func resolvedToolRegistry() async throws -> ToolRegistry {
        let baseTools = await toolRegistry.allTools
        #if SWARM_INTEGRATIONS
        guard !baseTools.contains(where: { $0.name == "websearch" }) else {
            return try ToolRegistry(tools: baseTools)
        }

        let taskLocalWeb = AgentEnvironmentValues.current.webSearch
        let ambientWeb = if let taskLocalWeb { taskLocalWeb } else { await Swarm.webConfiguration }
        guard let ambientWeb,
              ambientWeb.enabled
        else {
            return try ToolRegistry(tools: baseTools)
        }

        var tools = baseTools
        tools.append(WebSearchTool(configuration: ambientWeb))
        return try ToolRegistry(tools: tools)
        #else
        return try ToolRegistry(tools: baseTools)
        #endif
    }

    private func resolvedInferenceOptions(
        session: (any Session)?,
        provider: any InferenceProvider
    ) async -> InferenceOptions {
        var options = configuration.inferenceOptions

        let capabilities = providerCapabilities(for: provider)
        guard capabilities.contains(.responseContinuation) else {
            options.previousResponseId = nil
            return options
        }

        if let explicit = configuration.previousResponseId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            options.previousResponseId = explicit
            return options
        }

        guard configuration.autoPreviousResponseId, let session else {
            return options
        }

        if let latestResponseID = await Self.autoResponseTracker.getLatestResponseId(for: session.sessionId) {
            options.previousResponseId = latestResponseID
        }

        return options
    }

    private func providerCapabilities(for provider: any InferenceProvider) -> InferenceProviderCapabilities {
        InferenceProviderCapabilities.resolved(for: provider)
    }

    private func responseID(from result: AgentResult) -> String {
        if case let .string(value)? = result.metadata[Self.responseIDMetadataKey], !value.isEmpty {
            return value
        }
        return UUID().uuidString
    }

    private func recordUsage(_ usage: TokenUsage?, on resultBuilder: AgentResult.Builder) {
        guard let usage else { return }
        _ = resultBuilder.addTokenUsage(usage)
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

    func finalizeAssistantResponse(
        content: String,
        request: StructuredOutputRequest?,
        provider _: any InferenceProvider
    ) throws -> FinalAssistantResponse {
        guard let request else {
            return FinalAssistantResponse(content: content, structuredOutput: nil)
        }

        // Text remaining after a tool loop (or native session) was produced
        // without `respond(to:schema:)`. Label it prompt-fallback even when the
        // provider advertises `.structuredOutputs` — native guided generation
        // reports `.providerNative` from `generateStructured` itself.
        let structuredOutput = try StructuredOutputParser.parse(
            content,
            request: request,
            source: .promptFallback
        )
        return FinalAssistantResponse(content: structuredOutput.rawJSON, structuredOutput: structuredOutput)
    }

    private static func structuredOutputFormatDescription(_ format: StructuredOutputFormat) -> String {
        switch format {
        case .jsonObject:
            return "json_object"
        case .jsonSchema(let name, _):
            return "json_schema:\(name)"
        }
    }

    // MARK: - Tool Calling Loop Implementation

    private func executeToolCallingLoop(
        input: String,
        toolRegistry: ToolRegistry,
        provider: any InferenceProvider,
        sessionHistory: [MemoryMessage] = [],
        session: (any Session)?,
        resultBuilder: AgentResult.Builder,
        observer: (any AgentObserver)? = nil,
        tracing: TracingHelper? = nil,
        structuredOutputRequest: StructuredOutputRequest?,
        executionContext: AgentContext,
        executionGate: ProviderOwnedLoopGate?,
        pendingHandoff: OwnedLoopPendingHandoff
    ) async throws -> ToolLoopOutcome {
        var iteration = 0
        let startTime = ContinuousClock.now
        var inferenceOptions = await resolvedInferenceOptions(session: session, provider: provider)
        if let structuredOutputRequest {
            inferenceOptions.structuredOutput = structuredOutputRequest
        }
        inferenceOptions.conversationId = session?.sessionId ?? UUID().uuidString

        // Retrieve relevant context from memory (enables RAG for VectorMemory)
        let activeMemory = resolvedMemory()
        var memoryContext = ""
        if let mem = activeMemory {
            let contextProfile = configuration.effectiveContextProfile
            let tokenLimit = contextProfile.memoryTokenLimit
            memoryContext = try await executeWithinRemainingTimeout(startTime: startTime) {
                let hooks = MemoryHooks.resolved(from: mem)
                if let contextForQuery = hooks.contextForQuery {
                    return await contextForQuery(
                        MemoryQuery(
                            text: input,
                            tokenLimit: tokenLimit,
                            maxItems: contextProfile.maxRetrievedItems,
                            maxItemTokens: contextProfile.maxRetrievedItemTokens
                        )
                    )
                }
                return await mem.context(for: input, tokenLimit: tokenLimit)
            }
        }

        var conversationHistory = try buildInitialConversationHistory(
            sessionHistory: sessionHistory,
            input: input,
            memory: activeMemory,
            memoryContext: memoryContext
        )
        var transcriptMessages: [MemoryMessage] = []
        let systemMessage = buildSystemMessage(memory: activeMemory, memoryContext: memoryContext)
        await executionContext.recordExecution(agentName: name)

        let enableStreaming = configuration.enableStreaming && observer != nil
        let capabilities = providerCapabilities(for: provider)
        let useToolStreaming = enableStreaming && capabilities.contains(.streamingToolCalls)
        let membraneAdapter = resolvedMembraneAdapter()

        while iteration < configuration.maxIterations {
            iteration += 1
            _ = resultBuilder.incrementIteration()
            await observer?.onIterationStart(context: nil, agent: self, number: iteration)

            do {
                try checkCancellationAndTimeout(startTime: startTime)

                let unplannedSchemas = await buildToolSchemasWithHandoffs(
                    toolRegistry: toolRegistry,
                    context: executionContext
                )
                var plannedSchemas = MembraneInternalTools.sortedSchemas(unplannedSchemas)
                let historyPrompt = buildPrompt(from: conversationHistory)

                if let membraneAdapter {
                    do {
                        let plan = try await membraneAdapter.plan(
                            prompt: historyPrompt,
                            toolSchemas: unplannedSchemas,
                            profile: configuration.effectiveContextProfile
                        )
                        plannedSchemas = MembraneInternalTools.sortedSchemas(plan.toolSchemas)
                        _ = resultBuilder.setMetadata("membrane.mode", .string(plan.mode))
                    } catch {
                        _ = resultBuilder.setMetadata("membrane.fallback.used", .bool(true))
                        _ = resultBuilder.setMetadata("membrane.fallback.error", .string(fallbackDiagnosticMessage(for: error)))
                        plannedSchemas = MembraneInternalTools.sortedSchemas(unplannedSchemas)
                    }
                }

                let toolSchemas: [ToolSchema] = {
                    var schemas = MembraneInternalTools.sortedSchemas(plannedSchemas)
                    // For strict4k, strip tool descriptions to save ~120 tokens.
                    if configuration.effectiveContextProfile.preset == .strict4k {
                        schemas = schemas.map { ToolSchema(name: $0.name, description: $0.name, parameters: $0.parameters) }
                    }
                    return schemas
                }()
                let structuredMessages: [InferenceMessage] = await PromptEnvelope.enforce(
                    messages: conversationHistory.map(\.inferenceMessage),
                    profile: configuration.effectiveContextProfile
                )
                let prompt = InferenceMessage.flattenPrompt(structuredMessages)
                let useProviderOwnedToolLoop = provider.capabilities.contains(.providerOwnedToolLoop)
                try AgentTurnKernel.requireOwnedLoopGate(
                    useProviderOwnedToolLoop: useProviderOwnedToolLoop,
                    hasExecutionGate: executionGate != nil
                )
                let toolExecutor: ToolCallExecutor?
                if useProviderOwnedToolLoop, let executionGate {
                    toolExecutor = makeToolCallExecutor(
                        toolRegistry: toolRegistry,
                        resultBuilder: resultBuilder,
                        observer: observer,
                        tracing: tracing,
                        executionContext: executionContext,
                        executionGate: executionGate,
                        pendingHandoff: pendingHandoff
                    )
                } else {
                    toolExecutor = nil
                }

                let inferenceKind = AgentTurnKernel.inferenceKind(
                    toolSchemasEmpty: toolSchemas.isEmpty,
                    useProviderOwnedToolLoop: useProviderOwnedToolLoop,
                    streamingToolCalls: useToolStreaming
                )

                // If no tools defined, generate without tool calling unless the
                // adapter owns the tool loop (empty tool list).
                if inferenceKind == .withoutTools {
                    let loopInferenceOptions = inferenceOptions
                    let response = try await executeProviderInference(
                        startTime: startTime,
                        observer: observer,
                        tracing: tracing
                    ) {
                        try await generateWithoutTools(
                            provider: provider,
                            prompt: prompt,
                            messages: structuredMessages,
                            systemPrompt: systemMessage,
                            inferenceOptions: loopInferenceOptions,
                            enableStreaming: enableStreaming,
                            observer: observer
                        )
                    }
                    transcriptMessages.append(
                        SwarmTranscriptCodec.encodeMessage(
                            role: .assistant,
                            content: response.content,
                            toolCalls: [],
                            structuredOutput: response.structuredOutput
                        )
                    )
                    await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                    return ToolLoopOutcome(
                        output: response.content,
                        structuredOutput: response.structuredOutput,
                        transcriptMessages: transcriptMessages
                    )
                }

                // Generate response with tool calls
                let loopInferenceOptions = inferenceOptions
                // Owned-loop tools run inside inference; retrying would replay them.
                let ownedLoopInferenceRetryPolicy = AgentTurnKernel.ownedLoopInferenceRetryPolicy(
                    useProviderOwnedToolLoop: useProviderOwnedToolLoop,
                    hasToolSchemas: !toolSchemas.isEmpty
                )
                let response: InferenceResponse
                do {
                    let streamToolCalls = inferenceKind == .withTools(streaming: true)
                    response = if streamToolCalls {
                        try await executeProviderInference(
                            startTime: startTime,
                            observer: observer,
                            tracing: tracing,
                            retryPolicy: ownedLoopInferenceRetryPolicy,
                            executionGate: executionGate
                        ) {
                            try await generateWithToolsStreaming(
                                provider: provider,
                                prompt: prompt,
                                messages: structuredMessages,
                                tools: toolSchemas,
                                inferenceOptions: loopInferenceOptions,
                                systemPrompt: systemMessage,
                                observer: observer,
                                toolExecutor: toolExecutor
                            )
                        }
                    } else {
                        try await executeProviderInference(
                            startTime: startTime,
                            observer: observer,
                            tracing: tracing,
                            retryPolicy: ownedLoopInferenceRetryPolicy,
                            executionGate: executionGate
                        ) {
                            try await generateWithTools(
                                provider: provider,
                                prompt: prompt,
                                messages: structuredMessages,
                                tools: toolSchemas,
                                inferenceOptions: loopInferenceOptions,
                                systemPrompt: systemMessage,
                                observer: observer,
                                emitOutputTokens: enableStreaming,
                                toolExecutor: toolExecutor
                            )
                        }
                    }
                } catch let request as OwnedLoopHandoffRequest {
                    pendingHandoff.take()
                    let handoffOutcome = try await completeOwnedLoopHandoff(
                        request,
                        toolRegistry: toolRegistry,
                        conversationHistory: conversationHistory,
                        transcriptMessages: &transcriptMessages,
                        resultBuilder: resultBuilder,
                        observer: observer,
                        tracing: tracing,
                        context: executionContext,
                        startTime: startTime
                    )
                    await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                    return handoffOutcome
                } catch {
                    if let pending = pendingHandoff.take() {
                        let handoffOutcome = try await completeOwnedLoopHandoff(
                            OwnedLoopHandoffRequest(name: pending.name, arguments: pending.arguments),
                            toolRegistry: toolRegistry,
                            conversationHistory: conversationHistory,
                            transcriptMessages: &transcriptMessages,
                            resultBuilder: resultBuilder,
                            observer: observer,
                            tracing: tracing,
                            context: executionContext,
                            startTime: startTime
                        )
                        await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                        return handoffOutcome
                    }
                    throw error
                }
                recordUsage(response.usage, on: resultBuilder)

                switch AgentTurnKernel.afterInference(
                    useProviderOwnedToolLoop: useProviderOwnedToolLoop,
                    response: response
                ) {
                case .failMissingContent:
                    throw AgentError.generationFailed(reason: "Model returned no content or tool calls")

                case let .finishAssistant(content):
                    let finalResponse = try finalizeAssistantResponse(
                        content: content,
                        request: structuredOutputRequest,
                        provider: provider
                    )
                    appendOwnedLoopTranscript(
                        response.transcriptMessages,
                        finalized: finalResponse,
                        to: &transcriptMessages
                    )
                    await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                    return ToolLoopOutcome(
                        output: finalResponse.content,
                        structuredOutput: finalResponse.structuredOutput,
                        transcriptMessages: transcriptMessages
                    )

                case .processHostToolCalls:
                    let handoffResult = try await processToolCallsWithHandoffs(
                        response: response,
                        toolRegistry: toolRegistry,
                        conversationHistory: &conversationHistory,
                        transcriptMessages: &transcriptMessages,
                        resultBuilder: resultBuilder,
                        observer: observer,
                        tracing: tracing,
                        membraneAdapter: membraneAdapter,
                        context: executionContext,
                        startTime: startTime
                    )
                    if let handoffOutput = handoffResult {
                        await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                        return ToolLoopOutcome(
                            output: handoffOutput.content,
                            structuredOutput: handoffOutput.structuredOutput,
                            transcriptMessages: transcriptMessages
                        )
                    }
                    await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                }
            } catch {
                await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                throw normalizeCancellation(error)
            }
        }

        throw AgentError.maxIterationsExceeded(iterations: iteration)
    }

    /// Builds the initial conversation history from session history and user input.
    private func buildInitialConversationHistory(
        sessionHistory: [MemoryMessage],
        input: String,
        memory: (any Memory)?,
        memoryContext: String = ""
    ) throws -> [ConversationMessage] {
        let transcript = SwarmTranscript(memoryMessages: sessionHistory)
        try transcript.validateReplayCompatibility()

        var history: [ConversationMessage] = []
        history.append(.system(buildSystemMessage(memory: memory, memoryContext: memoryContext)))

        for entry in transcript.entries {
            switch entry.role {
            case .user:
                history.append(.user(entry.content))
            case .assistant:
                history.append(.assistant(
                    entry.content,
                    toolCalls: entry.toolCalls.map {
                        InferenceResponse.ParsedToolCall(id: $0.id, name: $0.name, arguments: $0.arguments)
                    }
                ))
            case .system:
                history.append(.system(entry.content))
            case .tool:
                history.append(.toolResult(
                    toolName: entry.toolName ?? "previous",
                    result: entry.content,
                    toolCallID: entry.toolCallID
                ))
            }
        }

        history.append(.user(input))
        return history
    }

    /// Checks for cancellation and timeout conditions.
    private func checkCancellationAndTimeout(startTime: ContinuousClock.Instant) throws {
        // Use Task.checkCancellation() for reliable cancellation detection
        // This is the standard Swift concurrency pattern
        try Task.checkCancellation()

        let elapsed = ContinuousClock.now - startTime
        if elapsed > configuration.timeout {
            throw AgentError.timeout(duration: configuration.timeout)
        }
    }

    func executeWithinRemainingTimeout<T: Sendable>(
        startTime: ContinuousClock.Instant,
        executionGate: ProviderOwnedLoopGate? = nil,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try Task.checkCancellation()

        let remaining = configuration.timeout - (ContinuousClock.now - startTime)
        if remaining <= .zero {
            throw AgentError.timeout(duration: configuration.timeout)
        }

        let coordinator = TimedOperationCoordinator<T>()
        coordinator.setOwnedLoopGate(executionGate)

        return try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                    coordinator.install(continuation: continuation)

                    let operationTask = Task {
                        do {
                            coordinator.finish(returning: try await operation())
                        } catch {
                            coordinator.finish(throwing: error)
                        }
                    }
                    coordinator.setOperationTask(operationTask)

                    let timeoutTask = Task { [timeout = configuration.timeout, remaining] in
                        do {
                            try await Task.sleep(for: remaining)
                            operationTask.cancel()
                            coordinator.finish(throwing: AgentError.timeout(duration: timeout))
                        } catch is CancellationError {
                            return
                        } catch {
                            coordinator.finish(throwing: error)
                        }
                    }
                    coordinator.setTimeoutTask(timeoutTask)
                }
            },
            onCancel: {
                coordinator.cancelPending(with: CancellationError())
            }
        )
    }

    private func normalizeCancellation(_ error: Error) -> Error {
        if error is CancellationError {
            return AgentError.cancelled
        }
        if let agentError = error as? AgentError, agentError == .cancelled {
            return agentError
        }
        return error
    }

    private func fallbackDiagnosticMessage(for error: Error) -> String {
        let described = String(describing: error)
        if described != String(describing: type(of: error)) {
            return described
        }

        let localized = error.localizedDescription
        if !localized.isEmpty {
            return localized
        }

        return String(describing: type(of: error))
    }

    /// Generates a response without tool calling.
    private func generateWithoutTools(
        provider: any InferenceProvider,
        prompt: String,
        messages: [InferenceMessage],
        systemPrompt: String,
        inferenceOptions: InferenceOptions,
        enableStreaming: Bool = false,
        observer: (any AgentObserver)?
    ) async throws -> FinalAssistantResponse {
        await observer?.onLLMStart(context: nil, agent: self, systemPrompt: systemPrompt, inputMessages: [MemoryMessage.user(prompt)])

        let options = optionsWithMembraneRuntimeSettings(inferenceOptions)
        let content: String
        let structuredOutput: StructuredOutputResult?
        if let request = options.structuredOutput {
            let result = try await provider.generateStructured(
                messages: messages,
                request: request,
                options: options
            )
            content = result.rawJSON
            structuredOutput = result
        } else if enableStreaming {
            var streamedContent = ""
            streamedContent.reserveCapacity(1024)
            let stream = provider.stream(messages: messages, options: options)
            for try await token in stream {
                if !token.isEmpty {
                    streamedContent += token
                }
                await observer?.onOutputToken(context: nil, agent: self, token: token)
            }
            content = streamedContent
            structuredOutput = nil
        } else {
            content = try await provider.generate(messages: messages, options: options)
            structuredOutput = nil
        }

        await observer?.onLLMEnd(context: nil, agent: self, response: content, usage: nil)
        return FinalAssistantResponse(content: content, structuredOutput: structuredOutput)
    }

    /// Executes a single tool call and updates conversation history.
    private func executeSingleToolCall(
        parsedCall: InferenceResponse.ParsedToolCall,
        toolRegistry: ToolRegistry,
        conversationHistory: inout [ConversationMessage],
        transcriptMessages: inout [MemoryMessage],
        resultBuilder: AgentResult.Builder,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        kind: AgentTurnKernel.HostToolCallKind,
        membraneAdapter: (any MembraneAgentAdapter)?,
        startTime: ContinuousClock.Instant
    ) async throws {
        let activeMemory = resolvedMemory()

        // Handoff I/O lives in `processToolCallsWithHandoffs`. A `.handoff` kind
        // here is the missing-configuration fallback and must not take the
        // Membrane internal path.
        switch (kind, membraneAdapter) {
        case (.membraneInternal, let membraneAdapter?):
            let call = ToolCall(
                providerCallId: parsedCall.id,
                toolName: parsedCall.name,
                arguments: parsedCall.arguments
            )
            _ = resultBuilder.addToolCall(call)
            await observer?.onToolStart(context: nil, agent: self, call: call)

            let spanID = await tracing?.traceToolCall(name: parsedCall.name, arguments: parsedCall.arguments)
            let toolStartTime = ContinuousClock.now

            do {
                let output = try await executeWithinRemainingTimeout(startTime: startTime) {
                    try await membraneAdapter.handleInternalToolCall(
                        name: parsedCall.name,
                        arguments: parsedCall.arguments
                    ) ?? "ok"
                }

                let duration = ContinuousClock.now - toolStartTime
                let result = ToolResult.success(callId: call.id, output: .string(output), duration: duration)
                _ = resultBuilder.addToolResult(result)
                conversationHistory.append(.toolResult(
                    toolName: parsedCall.name,
                    result: output,
                    toolCallID: parsedCall.id
                ))
                transcriptMessages.append(
                    SwarmTranscriptCodec.encodeMessage(
                        role: .tool,
                        content: output,
                        toolName: parsedCall.name,
                        toolCallID: parsedCall.id
                    )
                )
                if let activeMemory {
                    await activeMemory.add(.tool(output, toolName: parsedCall.name))
                }
                if let spanID {
                    await tracing?.traceToolResult(
                        spanId: spanID,
                        name: parsedCall.name,
                        result: output,
                        duration: duration
                    )
                }
                await observer?.onToolEnd(context: nil, agent: self, result: result)
                return
            } catch {
                let duration = ContinuousClock.now - toolStartTime
                let message = error.localizedDescription
                let result = ToolResult.failure(callId: call.id, error: message, duration: duration)
                _ = resultBuilder.addToolResult(result)
                if let spanID {
                    await tracing?.traceToolError(spanId: spanID, name: parsedCall.name, error: error)
                }
                await observer?.onToolEnd(context: nil, agent: self, result: result)
                if configuration.stopOnToolError {
                    throw AgentError.toolExecutionFailed(toolName: parsedCall.name, underlyingError: message)
                }
                conversationHistory.append(.toolResult(
                    toolName: parsedCall.name,
                    result: AgentTurnKernel.toolFailureConversationText(message: message),
                    toolCallID: parsedCall.id
                ))
                transcriptMessages.append(
                    SwarmTranscriptCodec.encodeMessage(
                        role: .tool,
                        content: AgentTurnKernel.toolFailureConversationText(message: message),
                        toolName: parsedCall.name,
                        toolCallID: parsedCall.id
                    )
                )
                if let activeMemory {
                    await activeMemory.add(.tool(
                        AgentTurnKernel.memoryToolErrorText(message: message),
                        toolName: parsedCall.name
                    ))
                }
                return
            }

        case (.handoff, _), (.regular, _), (.membraneInternal, nil):
            let engine = ToolExecutionEngine()
            let outcome = try await executeWithinRemainingTimeout(startTime: startTime) {
                try await engine.execute(
                    parsedCall,
                    registry: toolRegistry,
                    agent: self,
                    context: nil,
                    resultBuilder: resultBuilder,
                    observer: observer,
                    tracing: tracing,
                    stopOnToolError: false
                )
            }

            if outcome.result.isSuccess {
                var toolOutputText = Self.toolOutputText(for: outcome.result.output)
                if let membraneAdapter {
                    do {
                        let currentToolOutput = toolOutputText
                        let transformed = try await executeWithinRemainingTimeout(startTime: startTime) {
                            try await membraneAdapter.transformToolResult(
                                toolName: parsedCall.name,
                                output: currentToolOutput,
                                profile: configuration.effectiveContextProfile
                            )
                        }
                        toolOutputText = transformed.textForConversation
                        if let pointerID = transformed.pointerID {
                            _ = resultBuilder.setMetadata("membrane.pointerized", .bool(true))
                            _ = resultBuilder.setMetadata("membrane.pointer.last_id", .string(pointerID))
                        }
                    } catch {
                        _ = resultBuilder.setMetadata("membrane.fallback.used", .bool(true))
                        _ = resultBuilder.setMetadata("membrane.fallback.error", .string(fallbackDiagnosticMessage(for: error)))
                    }
                }

                conversationHistory.append(.toolResult(
                    toolName: parsedCall.name,
                    result: toolOutputText,
                    toolCallID: parsedCall.id
                ))
                transcriptMessages.append(
                    SwarmTranscriptCodec.encodeMessage(
                        role: .tool,
                        content: toolOutputText,
                        toolName: parsedCall.name,
                        toolCallID: parsedCall.id
                    )
                )
                if let activeMemory {
                    await activeMemory.add(.tool(toolOutputText, toolName: parsedCall.name))
                }
            } else {
                let errorMessage = outcome.result.errorMessage ?? "Unknown error"
                conversationHistory.append(.toolResult(
                    toolName: parsedCall.name,
                    result: AgentTurnKernel.toolFailureConversationText(message: errorMessage),
                    toolCallID: parsedCall.id
                ))
                transcriptMessages.append(
                    SwarmTranscriptCodec.encodeMessage(
                        role: .tool,
                        content: AgentTurnKernel.toolFailureConversationText(message: errorMessage),
                        toolName: parsedCall.name,
                        toolCallID: parsedCall.id
                    )
                )
                if let activeMemory {
                    await activeMemory.add(.tool(
                        AgentTurnKernel.memoryToolErrorText(message: errorMessage),
                        toolName: parsedCall.name
                    ))
                }

                if configuration.stopOnToolError {
                    throw AgentError.toolExecutionFailed(toolName: parsedCall.name, underlyingError: errorMessage)
                }
            }
        }
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

    // MARK: - Handoff Tool Schema Integration

    /// Builds tool schemas including handoff tool schemas.
    ///
    /// This merges regular tool schemas with handoff-generated schemas,
    /// allowing handoffs to appear as callable tools in the LLM prompt.
    private func buildToolSchemasWithHandoffs(
        toolRegistry: ToolRegistry,
        context: AgentContext
    ) async -> [ToolSchema] {
        var schemas = await toolRegistry.schemas

        for handoff in await activeHandoffs(context: context) {
            let handoffSchema = ToolSchema(
                name: handoff.effectiveToolName,
                description: handoff.effectiveToolDescription,
                parameters: [
                    ToolParameter(
                        name: "reason",
                        description: "Reason for the handoff",
                        type: .string,
                        isRequired: false
                    ),
                ]
            )
            schemas.append(handoffSchema)
        }

        return MembraneInternalTools.sortedSchemas(schemas)
    }

    private func activeHandoffs(context: AgentContext) async -> [AnyHandoffConfiguration] {
        var active: [AnyHandoffConfiguration] = []

        for handoff in _handoffs {
            if let when = handoff.when, await !when(context, handoff.targetAgent) {
                continue
            }
            active.append(handoff)
        }

        return active
    }

    /// Processes tool calls, handling both regular tools and handoff tools.
    ///
    /// When a tool call matches a handoff's `effectiveToolName`, the target agent
    /// is executed with the original user input and its result is returned.
    /// Returns the handoff output if a handoff was executed, nil otherwise.
    private func processToolCallsWithHandoffs(
        response: InferenceResponse,
        toolRegistry: ToolRegistry,
        conversationHistory: inout [ConversationMessage],
        transcriptMessages: inout [MemoryMessage],
        resultBuilder: AgentResult.Builder,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        membraneAdapter: (any MembraneAgentAdapter)?,
        context: AgentContext,
        startTime: ContinuousClock.Instant
    ) async throws -> FinalAssistantResponse? {
        let handoffMap = Dictionary(
            uniqueKeysWithValues: _handoffs.map { ($0.effectiveToolName, $0) }
        )

        let assistantContent = AgentTurnKernel.assistantContent(for: response)
        conversationHistory.append(.assistant(assistantContent, toolCalls: response.toolCalls))
        transcriptMessages.append(
            SwarmTranscriptCodec.encodeMessage(
                role: .assistant,
                content: assistantContent,
                toolCalls: response.toolCalls
            )
        )

        for parsedCall in response.toolCalls {
            let kind = AgentTurnKernel.hostToolCallKind(
                isHandoffTool: handoffMap[parsedCall.name] != nil,
                isMembraneInternal: membraneAdapter != nil
                    && MembraneInternalTools.isInternalTool(parsedCall.name)
            )

            switch kind {
            case .handoff:
                guard let handoffConfig = handoffMap[parsedCall.name] else {
                    try await executeSingleToolCall(
                        parsedCall: parsedCall,
                        toolRegistry: toolRegistry,
                        conversationHistory: &conversationHistory,
                        transcriptMessages: &transcriptMessages,
                        resultBuilder: resultBuilder,
                        observer: observer,
                        tracing: tracing,
                        kind: .regular,
                        membraneAdapter: membraneAdapter,
                        startTime: startTime
                    )
                    continue
                }
                if let when = handoffConfig.when, await !when(context, handoffConfig.targetAgent) {
                    let message = "Handoff is not enabled"
                    let handoffCall = ToolCall(
                        providerCallId: parsedCall.id,
                        toolName: parsedCall.name,
                        arguments: parsedCall.arguments
                    )
                    _ = resultBuilder.addToolCall(handoffCall)
                    let result = ToolResult.failure(callId: handoffCall.id, error: message, duration: .zero)
                    _ = resultBuilder.addToolResult(result)

                    if configuration.stopOnToolError {
                        throw AgentError.toolExecutionFailed(toolName: parsedCall.name, underlyingError: message)
                    }

                    let toolError = AgentTurnKernel.toolFailureConversationText(message: message)
                    conversationHistory.append(.toolResult(
                        toolName: parsedCall.name,
                        result: toolError,
                        toolCallID: parsedCall.id
                    ))
                    transcriptMessages.append(
                        SwarmTranscriptCodec.encodeMessage(
                            role: .tool,
                            content: toolError,
                            toolName: parsedCall.name,
                            toolCallID: parsedCall.id
                        )
                    )
                    continue
                }

                let reason = parsedCall.arguments["reason"]?.stringValue ?? ""
                let targetAgent = handoffConfig.targetAgent

                let handoffStart = ContinuousClock.now
                let spanId = await tracing?.traceToolCall(name: parsedCall.name, arguments: parsedCall.arguments)
                let handoffCall = ToolCall(
                    providerCallId: parsedCall.id,
                    toolName: parsedCall.name,
                    arguments: parsedCall.arguments
                )
                _ = resultBuilder.addToolCall(handoffCall)
                await observer?.onHandoff(context: context, fromAgent: self, toAgent: targetAgent)

                // Find the last user message to use as handoff input
                let lastUserMessage = conversationHistory.last(where: {
                    if case .user = $0 { return true }
                    return false
                })
                let lastUserText: String? = if case let .user(content) = lastUserMessage {
                    content
                } else {
                    nil
                }
                let handoffInput = AgentTurnKernel.handoffInput(
                    lastUserText: lastUserText,
                    reason: reason
                )

                let initialHandoffData = HandoffInputData(
                    sourceAgentName: name,
                    targetAgentName: targetAgent.name,
                    input: handoffInput,
                    context: await context.snapshot,
                    metadata: reason.isEmpty ? [:] : ["reason": .string(reason)]
                )

                if let onTransfer = handoffConfig.onTransfer {
                    do {
                        try await onTransfer(context, initialHandoffData)
                    } catch {
                        Log.agents.warning("Handoff onTransfer callback failed for \(parsedCall.name): \(error)")
                    }
                }

                let handoffData = HandoffInputData(
                    sourceAgentName: initialHandoffData.sourceAgentName,
                    targetAgentName: initialHandoffData.targetAgentName,
                    input: initialHandoffData.input,
                    context: await context.snapshot,
                    metadata: initialHandoffData.metadata
                )
                let transformedData = handoffConfig.transform?(handoffData) ?? handoffData
                let requestContext = transformedData.context.merging(transformedData.metadata) { _, new in new }
                let handoffContext = await context.copy(additionalValues: requestContext)
                await applyContextValues(requestContext, to: handoffContext)
                await preserveExecutionPath(from: context, in: handoffContext)
                if handoffConfig.nestHandoffHistory {
                    await addNestedHandoffHistory(
                        conversationHistory,
                        to: handoffContext,
                        skippingToolCallID: parsedCall.id
                    )
                }

                let handoffRequest = HandoffRequest(
                    sourceAgentName: transformedData.sourceAgentName,
                    targetAgentName: transformedData.targetAgentName,
                    input: transformedData.input,
                    reason: reason.isEmpty ? nil : reason,
                    context: requestContext
                )

                let result: AgentResult
                do {
                    result = try await executeWithinRemainingTimeout(startTime: startTime) {
                        if let receiver = targetAgent as? any HandoffReceiver {
                            return try await receiver.handleHandoff(handoffRequest, context: handoffContext)
                        } else {
                            let handoffSession = try await makeNestedHandoffSession(
                                from: handoffContext,
                                enabled: handoffConfig.nestHandoffHistory
                            )
                            return try await targetAgent.run(
                                transformedData.input,
                                session: handoffSession,
                                observer: observer
                            )
                        }
                    }
                } catch {
                    let handoffDuration = ContinuousClock.now - handoffStart
                    _ = resultBuilder.addToolResult(
                        ToolResult.failure(
                            callId: handoffCall.id,
                            error: error.localizedDescription,
                            duration: handoffDuration
                        )
                    )
                    if let spanId {
                        await tracing?.traceToolError(spanId: spanId, name: parsedCall.name, error: error)
                    }
                    throw error
                }
                conversationHistory.append(.toolResult(
                    toolName: parsedCall.name,
                    result: result.output,
                    toolCallID: parsedCall.id
                ))
                transcriptMessages.append(
                    SwarmTranscriptCodec.encodeMessage(
                        role: .tool,
                        content: result.output,
                        toolName: parsedCall.name,
                        toolCallID: parsedCall.id
                    )
                )

                let handoffDuration = ContinuousClock.now - handoffStart
                _ = resultBuilder.addToolResult(
                    ToolResult.success(
                        callId: handoffCall.id,
                        output: .string(result.output),
                        duration: handoffDuration
                    )
                )
                if let spanId {
                    await tracing?.traceToolResult(spanId: spanId, name: parsedCall.name, result: result.output, duration: handoffDuration)
                }

                // Merge handoff tool calls, results, and combined token totals into
                // this agent's AgentResult. Nested usage is traced on the child span.
                for toolCall in result.toolCalls {
                    _ = resultBuilder.addToolCall(toolCall)
                }
                for toolResult in result.toolResults {
                    _ = resultBuilder.addToolResult(toolResult)
                }
                if let usage = result.tokenUsage {
                    _ = resultBuilder.addNestedTokenUsage(usage)
                }
                for (key, value) in result.metadata {
                    _ = resultBuilder.setMetadata(key, value)
                }

                // Return the handoff output to be used as the final result
                return FinalAssistantResponse(content: result.output, structuredOutput: nil)

            case .membraneInternal, .regular:
                try await executeSingleToolCall(
                    parsedCall: parsedCall,
                    toolRegistry: toolRegistry,
                    conversationHistory: &conversationHistory,
                    transcriptMessages: &transcriptMessages,
                    resultBuilder: resultBuilder,
                    observer: observer,
                    tracing: tracing,
                    kind: kind,
                    membraneAdapter: membraneAdapter,
                    startTime: startTime
                )
            }
        }

        return nil
    }

    private func applyContextValues(
        _ values: [String: SendableValue],
        to context: AgentContext
    ) async {
        for (key, value) in values {
            await context.set(key, value: value)
        }
    }

    private func preserveExecutionPath(from source: AgentContext, in target: AgentContext) async {
        let executionPath = await source.getExecutionPath()
        for agentName in executionPath {
            await target.recordExecution(agentName: agentName)
        }
    }

    private func makeNestedHandoffSession(
        from context: AgentContext,
        enabled: Bool
    ) async throws -> (any Session)? {
        guard enabled else {
            return nil
        }

        let messages = await context.getMessages()
        guard !messages.isEmpty else {
            return nil
        }

        let session = InMemorySession()
        try await session.addItems(messages)
        return session
    }

    private func addNestedHandoffHistory(
        _ conversationHistory: [ConversationMessage],
        to context: AgentContext,
        skippingToolCallID skippedToolCallID: String?
    ) async {
        for message in conversationHistory {
            switch message {
            case let .system(content):
                await context.addMessage(SwarmTranscriptCodec.encodeMessage(role: .system, content: content))
            case let .user(content):
                await context.addMessage(SwarmTranscriptCodec.encodeMessage(role: .user, content: content))
            case let .assistant(content, toolCalls):
                let nestedToolCalls = toolCalls.filter { $0.id != skippedToolCallID }
                guard toolCalls.isEmpty || !nestedToolCalls.isEmpty else {
                    continue
                }
                await context.addMessage(
                    SwarmTranscriptCodec.encodeMessage(
                        role: .assistant,
                        content: content,
                        toolCalls: nestedToolCalls
                    )
                )
            case let .toolResult(toolName, result, toolCallID):
                guard toolCallID != skippedToolCallID else {
                    continue
                }
                await context.addMessage(
                    SwarmTranscriptCodec.encodeMessage(
                        role: .tool,
                        content: result,
                        toolName: toolName,
                        toolCallID: toolCallID
                    )
                )
            }
        }
    }

    // MARK: - Prompt Building

    private func buildSystemMessage(
        memory: (any Memory)?,
        memoryContext: String = ""
    ) -> String {
        let baseInstructions = instructions.isEmpty
            ? "You are a helpful AI assistant with access to tools."
            : instructions

        if memoryContext.isEmpty {
            return baseInstructions
        }

        let hooks = memory.map { MemoryHooks.resolved(from: $0) } ?? .empty
        let title = hooks.memoryPromptTitle ?? "Relevant Context from Memory"
        let priority = hooks.memoryPriority
        let guidance = hooks.memoryPromptGuidance ?? {
            guard priority == .primary else { return nil }
            return "Use the memory context as primary source of truth before calling tools."
        }()

        let guidanceBlock = guidance.flatMap { $0.isEmpty ? nil : $0 }

        if let guidanceBlock {
            return """
            \(baseInstructions)

            \(guidanceBlock)

            \(title):
            \(memoryContext)
            """
        }

        return """
        \(baseInstructions)

        \(title):
        \(memoryContext)
        """
    }

    private func buildPrompt(from history: [ConversationMessage]) -> String {
        history.map(\.formatted).joined(separator: "\n\n")
    }

    // MARK: - Response Generation

    private func generateWithTools(
        provider: any InferenceProvider,
        prompt: String,
        messages: [InferenceMessage],
        tools: [ToolSchema],
        inferenceOptions: InferenceOptions,
        systemPrompt: String,
        observer: (any AgentObserver)? = nil,
        emitOutputTokens: Bool = false,
        toolExecutor: ToolCallExecutor? = nil
    ) async throws -> InferenceResponse {
        var options = inferenceOptions
        options = optionsWithMembraneRuntimeSettings(options)

        // Notify observer of LLM start
        await observer?.onLLMStart(context: nil, agent: self, systemPrompt: systemPrompt, inputMessages: [MemoryMessage.user(prompt)])

        let response = try await provider.generateWithToolCalls(
            messages: messages,
            tools: tools,
            options: options,
            toolExecutor: toolExecutor
        )

        if emitOutputTokens, response.transcriptMessages.isEmpty, response.toolCalls.isEmpty,
           let content = response.content, !content.isEmpty
        {
            await observer?.onOutputToken(context: nil, agent: self, token: content)
        }

        // Notify observer of LLM end
        let responseContent = response.content ?? ""
        await observer?.onLLMEnd(context: nil, agent: self, response: responseContent, usage: response.usage)

        return response
    }

    private func generateWithToolsStreaming(
        provider: any InferenceProvider,
        prompt: String,
        messages: [InferenceMessage],
        tools: [ToolSchema],
        inferenceOptions: InferenceOptions,
        systemPrompt: String,
        observer: (any AgentObserver)? = nil,
        toolExecutor: ToolCallExecutor? = nil
    ) async throws -> InferenceResponse {
        var options = inferenceOptions
        options = optionsWithMembraneRuntimeSettings(options)

        await observer?.onLLMStart(context: nil, agent: self, systemPrompt: systemPrompt, inputMessages: [MemoryMessage.user(prompt)])

        var content = ""
        content.reserveCapacity(1024)
        var parsedToolCalls: [InferenceResponse.ParsedToolCall] = []
        var usage: TokenUsage?
        var stopStreaming = false
        var finishedTurn: InferenceResponse?

        let stream = provider.streamWithToolCalls(
            messages: messages,
            tools: tools,
            options: options,
            toolExecutor: toolExecutor
        )

        for try await update in stream {
            switch update {
            case let .outputChunk(chunk):
                if !chunk.isEmpty { content += chunk }
                await observer?.onOutputToken(context: nil, agent: self, token: chunk)

            case let .toolCallPartial(partial):
                await observer?.onToolCallPartial(context: nil, agent: self, update: partial)

            case let .toolCallsCompleted(calls):
                parsedToolCalls = calls
                // Capture stops here so Agent can run tools. An owned-loop adapter
                // still has a finished turn to yield; keep reading when we passed
                // an executor.
                if toolExecutor == nil {
                    stopStreaming = true
                }

            case let .usage(u):
                usage = u

            case let .finishedTurn(response):
                finishedTurn = response
            }

            if stopStreaming { break }
        }

        await observer?.onLLMEnd(context: nil, agent: self, response: content, usage: usage)

        if let finishedTurn {
            return finishedTurn
        }

        return InferenceResponse(
            content: content.isEmpty ? nil : content,
            toolCalls: parsedToolCalls,
            finishReason: parsedToolCalls.isEmpty ? .completed : .toolCall,
            usage: usage
        )
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

    private func makeToolCallExecutor(
        toolRegistry: ToolRegistry,
        resultBuilder: AgentResult.Builder,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        executionContext: AgentContext,
        executionGate: ProviderOwnedLoopGate,
        pendingHandoff: OwnedLoopPendingHandoff
    ) -> ToolCallExecutor {
        let handoffNames = Set(_handoffs.map(\.effectiveToolName))
        let stopOnToolError = configuration.stopOnToolError
        let engine = ToolExecutionEngine()
        return ToolCallExecutor { [self] name, arguments in
            guard executionGate.isActive else {
                throw CancellationError()
            }
            if handoffNames.contains(name) {
                pendingHandoff.store(name: name, arguments: arguments)
                executionGate.deactivate()
                throw OwnedLoopHandoffRequest(name: name, arguments: arguments)
            }
            let outcome = try await engine.execute(
                toolName: name,
                arguments: arguments,
                registry: toolRegistry,
                agent: self,
                context: executionContext,
                resultBuilder: resultBuilder,
                observer: observer,
                tracing: tracing,
                stopOnToolError: stopOnToolError
            )
            if outcome.result.isSuccess {
                return outcome.result.output
            }
            return .string(outcome.result.errorMessage ?? "Tool '\(name)' failed")
        }
    }

    private func completeOwnedLoopHandoff(
        _ request: OwnedLoopHandoffRequest,
        toolRegistry: ToolRegistry,
        conversationHistory: [ConversationMessage],
        transcriptMessages: inout [MemoryMessage],
        resultBuilder: AgentResult.Builder,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        context: AgentContext,
        startTime: ContinuousClock.Instant
    ) async throws -> ToolLoopOutcome {
        var history = conversationHistory
        let response = InferenceResponse(
            content: nil,
            toolCalls: [
                InferenceResponse.ParsedToolCall(
                    id: nil,
                    name: request.name,
                    arguments: request.arguments
                ),
            ],
            finishReason: .toolCall
        )
        let handoffOutput = try await processToolCallsWithHandoffs(
            response: response,
            toolRegistry: toolRegistry,
            conversationHistory: &history,
            transcriptMessages: &transcriptMessages,
            resultBuilder: resultBuilder,
            observer: observer,
            tracing: tracing,
            membraneAdapter: resolvedMembraneAdapter(),
            context: context,
            startTime: startTime
        )
        guard let handoffOutput else {
            throw AgentError.internalError(
                reason: "Owned-loop handoff '\(request.name)' did not transfer control"
            )
        }
        return ToolLoopOutcome(
            output: handoffOutput.content,
            structuredOutput: handoffOutput.structuredOutput,
            transcriptMessages: transcriptMessages
        )
    }

    private func appendOwnedLoopTranscript(
        _ transcript: [InferenceMessage],
        finalized: FinalAssistantResponse,
        to transcriptMessages: inout [MemoryMessage]
    ) {
        if transcript.isEmpty {
            transcriptMessages.append(
                SwarmTranscriptCodec.encodeMessage(
                    role: .assistant,
                    content: finalized.content,
                    toolCalls: [],
                    structuredOutput: finalized.structuredOutput
                )
            )
            return
        }

        var owned = transcript.map(SwarmTranscriptCodec.encode)
        if let structured = finalized.structuredOutput,
           let last = owned.indices.last,
           owned[last].role == .assistant
        {
            owned[last] = SwarmTranscriptCodec.encodeMessage(
                role: .assistant,
                content: finalized.content,
                structuredOutput: structured
            )
        }
        transcriptMessages.append(contentsOf: owned)
    }
}

/// A handoff tool invoked inside a provider-owned tool loop.
struct OwnedLoopHandoffRequest: Error, Sendable {
    let name: String
    let arguments: [String: SendableValue]
}

/// Backup if Apple's session remaps the typed handoff to cancellation.
final class OwnedLoopPendingHandoff: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: (name: String, arguments: [String: SendableValue])?

    func store(name: String, arguments: [String: SendableValue]) {
        lock.lock()
        pending = (name, arguments)
        lock.unlock()
    }

    func take() -> (name: String, arguments: [String: SendableValue])? {
        lock.lock()
        defer { lock.unlock() }
        let value = pending
        pending = nil
        return value
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
