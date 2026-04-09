// Agent.swift
// Swarm Framework
//
// Tool-calling agent that uses structured LLM tool calling APIs.

import Foundation
import MembraneCore

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
/// 1. An explicit provider passed to `Agent(...)` (including `Agent(_:)`)
/// 2. A provider set via `.environment(\.inferenceProvider, ...)`
/// 3. `Swarm.defaultProvider` (set via `Swarm.configure(provider:)`)
/// 4. `Swarm.cloudProvider` (set via `Swarm.configure(cloudProvider:)`, when tool calling is required)
/// 5. Apple Foundation Models (on-device), if available, including prompt-based tool emulation
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
    /// If no explicit memory is set, Swarm still uses a composite default memory
    /// internally: ContextCore for working context and Wax for durable recall.
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
    /// 1. Explicit provider passed to ``Agent`` initialization
    /// 2. Provider set via `.environment(\.inferenceProvider, ...)`
    /// 3. ``Swarm/defaultProvider`` (configured via `Swarm.configure(provider:)`)
    /// 4. ``Swarm/cloudProvider`` (configured via `Swarm.configure(cloudProvider:)`)
    /// 5. Apple Foundation Models (on-device), if available
    /// 6. Throws ``AgentError/inferenceProviderUnavailable``
    ///
    /// ## Usage
    /// Set a specific provider when you want this agent to use a different LLM than
    /// the globally configured one.
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

    /// The configuration for the guardrail runner.
    ///
    /// This configuration controls how input and output guardrails are executed,
    /// including timeout settings and error handling behavior.
    ///
    /// ## Default Behavior
    /// If not specified, uses ``GuardrailRunnerConfiguration/default`` which runs
    /// guardrails with a 30-second timeout and stops on the first failure.
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
    ///   - memory: Optional explicit memory override. Default: composite ContextCore + Wax memory
    ///   - inferenceProvider: Optional custom inference provider. Default: nil
    ///   - tracer: Optional tracer for observability. Default: nil
    ///   - inputGuardrails: Input validation guardrails. Default: []
    ///   - outputGuardrails: Output validation guardrails. Default: []
    ///   - guardrailRunnerConfiguration: Configuration for guardrail runner. Default: .default
    ///   - handoffs: Handoff configurations for multi-agent orchestration. Default: []
    /// - Throws: `ToolRegistryError.duplicateToolName` if duplicate tool names are provided.
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
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
        self.guardrailRunnerConfiguration = guardrailRunnerConfiguration
        _handoffs = handoffs
        toolRegistry = try ToolRegistry(tools: tools)
    }

    /// Convenience initializer that takes an unlabeled inference provider.
    ///
    /// This enables an opinionated, easy setup:
    /// ```swift
    /// let agent = Agent(.anthropic(key: "..."))
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
    ///   - memory: Optional explicit memory override. Default: composite ContextCore + Wax memory
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
    ///   - memory: Optional explicit memory override. Default: composite ContextCore + Wax memory
    ///   - inferenceProvider: Optional custom inference provider. Default: nil
    ///   - tracer: Optional tracer for observability. Default: nil
    ///   - inputGuardrails: Input validation guardrails. Default: []
    ///   - outputGuardrails: Output validation guardrails. Default: []
    ///   - guardrailRunnerConfiguration: Configuration for guardrail runner. Default: .default
    ///   - handoffAgents: Agents to hand off to, automatically wrapped as handoff configurations.
    /// - Throws: `ToolRegistryError.duplicateToolName` if duplicate tool names are provided.
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
    ///   - memory: Optional explicit memory override. Default: composite ContextCore + Wax memory
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
        return StreamHelper.makeTrackedStream { continuation in
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
                return """
                [Tool Result - \(toolName)]: The following content is the real output from a tool that already ran successfully. Use it directly when answering; do not claim you cannot browse or access external information.
                \(result)
                """
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

    private struct ToolLoopOutcome: Sendable {
        let output: String
        let structuredOutput: StructuredOutputResult?
        let transcriptMessages: [MemoryMessage]
    }

    private struct FinalAssistantResponse: Sendable {
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
        private var completed = false

        func install(continuation: CheckedContinuation<T, Error>) {
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }

        func setOperationTask(_ task: Task<Void, Never>) {
            lock.lock()
            operationTask = task
            lock.unlock()
        }

        func setTimeoutTask(_ task: Task<Void, Never>) {
            lock.lock()
            timeoutTask = task
            lock.unlock()
        }

        func finish(returning value: T) {
            complete { continuation in
                continuation.resume(returning: value)
            }
        }

        func finish(throwing error: Error) {
            complete { continuation in
                continuation.resume(throwing: error)
            }
        }

        func cancelPending(with error: Error) {
            let pendingState = takePendingState()
            pendingState.operationTask?.cancel()
            pendingState.timeoutTask?.cancel()
            pendingState.continuation?.resume(throwing: error)
        }

        private func complete(_ resume: (CheckedContinuation<T, Error>) -> Void) {
            let pendingState = takePendingState()
            pendingState.operationTask?.cancel()
            pendingState.timeoutTask?.cancel()
            guard let continuation = pendingState.continuation else { return }
            resume(continuation)
        }

        private func takePendingState() -> (
            continuation: CheckedContinuation<T, Error>?,
            operationTask: Task<Void, Never>?,
            timeoutTask: Task<Void, Never>?
        ) {
            lock.lock()
            defer { lock.unlock() }

            guard completed == false else {
                return (nil, nil, nil)
            }

            completed = true
            let pendingContinuation = continuation
            let pendingOperationTask = operationTask
            let pendingTimeoutTask = timeoutTask
            continuation = nil
            operationTask = nil
            timeoutTask = nil
            return (pendingContinuation, pendingOperationTask, pendingTimeoutTask)
        }
    }

    private actor DefaultMemorySessionTracker {
        private var sessionIDs: [ObjectIdentifier: String] = [:]

        func didSwitchSession(for memory: AnyObject, sessionID: String) -> Bool {
            let key = ObjectIdentifier(memory)
            let previous = sessionIDs[key]
            sessionIDs[key] = sessionID
            return previous != sessionID
        }
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

        let activeTracer = tracer
            ?? AgentEnvironmentValues.current.tracer
            ?? (configuration.defaultTracingEnabled ? SwiftLogTracer(minimumLevel: .debug) : nil)
        let activeMemory = resolvedMemory()
        let lifecycleMemory = activeMemory as? any MemorySessionLifecycle

        if let session,
           let activeMemory,
           let defaultMemory
        {
            let activeMemoryObject = activeMemory as AnyObject
            let defaultMemoryObject = defaultMemory as AnyObject
            if activeMemoryObject === defaultMemoryObject,
               await Self.defaultMemorySessionTracker.didSwitchSession(for: activeMemoryObject, sessionID: session.sessionId)
            {
                await activeMemory.clear()
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

        if let lifecycleMemory {
            await lifecycleMemory.beginMemorySession()
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

            // Seed memory with session history once (only if memory is empty and the memory allows it).
            let importPolicy = activeMemory as? any MemorySessionImportPolicy
            let allowsSessionSeeding = importPolicy?.allowsAutomaticSessionSeeding ?? true
            if let activeMemory, allowsSessionSeeding, !sessionHistory.isEmpty, await activeMemory.isEmpty {
                if let replayAware = activeMemory as? any MemorySessionReplayAware {
                    await replayAware.importSessionHistory(sessionHistory)
                } else {
                    for message in sessionHistory {
                        await activeMemory.add(message)
                    }
                }
            }

            // Create user message for this turn
            let userMessage = SwarmTranscriptCodec.encodeMessage(role: .user, content: input)

            // Execute the tool calling loop with session context
            let provider = try await resolvedInferenceProvider(toolRegistry: runtimeToolRegistry)
            let runtimeEnvironment = runtimeEnvironment(for: provider)
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
                    structuredOutputRequest: structuredOutputRequest
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
            }

            // Memory provides additional context (RAG, summaries) - NOT for conversation storage
            // This avoids duplication: session stores conversation, memory provides context
            // Note: If using memory for conversation context, populate it from session on demand

            _ = resultBuilder.setMetadata(RuntimeMetadata.runtimeEngineKey, .string(RuntimeMetadata.graphRuntimeEngineName))
            let result = resultBuilder.build()
            if configuration.autoPreviousResponseId, let session {
                let response = makeResponse(from: result, responseID: responseID)
                await Self.autoResponseTracker.recordResponse(response, sessionId: session.sessionId)
            }
            await tracing.traceComplete(result: result)

            // Notify observer of agent completion
            await observer?.onAgentEnd(context: nil, agent: self, result: result)

            if let lifecycleMemory {
                await lifecycleMemory.endMemorySession()
            }
            return InternalRunResult(agentResult: result, structuredOutput: toolLoopOutcome.structuredOutput)
        } catch {
            let normalizedError = normalizeCancellation(error)
            // Notify observer of error
            await observer?.onError(context: nil, agent: self, error: normalizedError)
            await tracing.traceError(normalizedError)
            if let lifecycleMemory {
                await lifecycleMemory.endMemorySession()
            }
            throw normalizedError
        }
    }

    // MARK: - Inference Provider Resolution

    private func resolvedInferenceProvider(toolRegistry: ToolRegistry) async throws -> any InferenceProvider {
        // 1. Explicit provider on Agent
        if let inferenceProvider {
            return inferenceProvider
        }

        // 2. TaskLocal via .environment()
        if let environmentProvider = AgentEnvironmentValues.current.inferenceProvider {
            return environmentProvider
        }

        // 3. Swarm.defaultProvider (global)
        if let globalProvider = await Swarm.defaultProvider {
            return globalProvider
        }

        // 4. Swarm.cloudProvider (if tool calling is required)
        let hasEnabledTools = await !toolRegistry.schemas.isEmpty
        let needsToolCallingProvider = hasEnabledTools || !_handoffs.isEmpty
        if needsToolCallingProvider, let cloudProvider = await Swarm.cloudProvider {
            return cloudProvider
        }

        // 5. Foundation Models (if available, on Apple platform)
        if let foundationModelsProvider = DefaultInferenceProviderFactory.makeFoundationModelsProviderIfAvailable() {
            return foundationModelsProvider
        }

        // 6. No provider available
        throw AgentError.inferenceProviderUnavailable(
            reason: """
            No inference provider configured and Apple Foundation Models are unavailable.

            Configure a provider globally via `await Swarm.configure(provider: ...)` \
            or pass one explicitly to Agent(...).
            """
        )
    }

    func resolvedMembraneAdapter(profile: ContextProfile) -> (any MembraneAgentAdapter)? {
        let membrane = AgentEnvironmentValues.current.membrane ?? .enabled
        guard membrane.isEnabled else {
            return nil
        }
        if let adapter = membrane.adapter {
            return adapter
        }
        return Self.makeDefaultMembraneAdapter(
            configuration: membrane.configuration,
            profile: profile
        )
    }

    static func makeDefaultMembraneAdapter(
        configuration: MembraneFeatureConfiguration,
        profile: ContextProfile
    ) -> any MembraneAgentAdapter {
        let environment = MembraneEnvironment.contextCoreSession(
            configuration: membraneConfiguration(configuration, for: profile),
            budget: membraneBudget(for: profile)
        )
        return environment.adapter ?? DefaultMembraneAgentAdapter(configuration: configuration)
    }

    static func membraneConfiguration(
        _ configuration: MembraneFeatureConfiguration,
        for profile: ContextProfile
    ) -> MembraneFeatureConfiguration {
        guard profile.preset == .strict4k else {
            return configuration
        }

        return MembraneFeatureConfiguration(
            jitMinToolCount: min(4, configuration.jitMinToolCount),
            defaultJITLoadCount: min(2, configuration.defaultJITLoadCount),
            pointerThresholdBytes: min(100, configuration.pointerThresholdBytes),
            pointerSummaryMaxChars: min(120, configuration.pointerSummaryMaxChars),
            runtimeFeatureFlags: configuration.runtimeFeatureFlags,
            runtimeModelAllowlist: configuration.runtimeModelAllowlist
        )
    }

    static func membraneBudget(for profile: ContextProfile) -> MembraneCore.ContextBudget {
        if profile.preset == .strict4k, let caps = profile.bucketCaps {
            return MembraneCore.ContextBudget(
                totalTokens: profile.maxTotalContextTokens,
                profile: .custom(buckets: [
                    .system: caps.system,
                    .history: caps.history,
                    .memory: 0,
                    .tools: caps.toolIO,
                    .retrieval: caps.memory,
                    .toolIO: 0,
                    .outputReserve: profile.outputReserveTokens,
                    .protocolOverhead: profile.protocolOverheadReserveTokens,
                    .safetyMargin: profile.safetyMarginTokens,
                ])
            )
        }

        let totalTokens = profile.maxTotalContextTokens
        let budgetProfile: MembraneCore.BudgetProfile =
            if totalTokens <= 4096 {
                .foundationModels4K
            } else if totalTokens <= 8192 {
                .openModel8K
            } else {
                .cloud200K
            }

        return MembraneCore.ContextBudget(totalTokens: totalTokens, profile: budgetProfile)
    }

    private func runtimeEnvironment(for provider: any InferenceProvider) -> AgentEnvironment {
        var environment = AgentEnvironmentValues.current
        if let tokenCounter = provider as? any PromptTokenCountingInferenceProvider {
            environment.promptTokenCounter = tokenCounter
        }
        return environment
    }

    private func resolvedMemory() -> (any Memory)? {
        memory ?? AgentEnvironmentValues.current.memory ?? defaultMemory
    }

    private static func makeDefaultMemory() throws -> any Memory {
        try DefaultAgentMemory()
    }

    private func resolvedToolRegistry() async throws -> ToolRegistry {
        let baseTools = await toolRegistry.allTools
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
                result: toolResult.output,
                duration: toolResult.duration,
                timestamp: toolCall.timestamp,
                isSuccess: toolResult.isSuccess,
                errorMessage: toolResult.errorMessage
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

    private func finalizeAssistantResponse(
        content: String,
        request: StructuredOutputRequest?,
        provider: any InferenceProvider
    ) throws -> FinalAssistantResponse {
        guard let request else {
            return FinalAssistantResponse(content: content, structuredOutput: nil)
        }

        let source: StructuredOutputResult.Source = providerCapabilities(for: provider).contains(.structuredOutputs)
            ? .providerNative
            : .promptFallback
        let structuredOutput = try StructuredOutputParser.parse(content, request: request, source: source)
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
        structuredOutputRequest: StructuredOutputRequest?
    ) async throws -> ToolLoopOutcome {
        var iteration = 0
        let startTime = ContinuousClock.now
        var inferenceOptions = await resolvedInferenceOptions(session: session, provider: provider)
        if let structuredOutputRequest {
            inferenceOptions.structuredOutput = structuredOutputRequest
        }

        // Retrieve relevant context from memory (enables RAG for VectorMemory)
        let activeMemory = resolvedMemory()
        var memoryContext = ""
        if let mem = activeMemory {
            let contextProfile = configuration.effectiveContextProfile
            let tokenLimit = contextProfile.memoryTokenLimit
            if let policyAwareMemory = mem as? any MemoryRetrievalPolicyAware {
                memoryContext = await policyAwareMemory.context(
                    for: MemoryQuery(
                        text: input,
                        tokenLimit: tokenLimit,
                        maxItems: contextProfile.maxRetrievedItems,
                        maxItemTokens: contextProfile.maxRetrievedItemTokens
                    )
                )
            } else {
                memoryContext = await mem.context(for: input, tokenLimit: tokenLimit)
            }
        }

        let profile = configuration.effectiveContextProfile
        let inlineSystemMemoryContext = profile.preset == .strict4k ? "" : memoryContext
        var conversationHistory = try buildInitialConversationHistory(
            sessionHistory: sessionHistory,
            input: input,
            memory: activeMemory,
            memoryContext: inlineSystemMemoryContext
        )
        var transcriptMessages: [MemoryMessage] = []
        let systemMessage = buildSystemMessage(memory: activeMemory, memoryContext: inlineSystemMemoryContext)

        let enableStreaming = configuration.enableStreaming && observer != nil
        let structuredToolStreamingProvider = provider as? any ToolCallStreamingConversationInferenceProvider
        let promptToolStreamingProvider = provider as? any ToolCallStreamingInferenceProvider
        let providerSupportsStreamingToolCalls = providerCapabilities(for: provider).contains(.streamingToolCalls)
        let useToolStreaming = enableStreaming &&
            providerSupportsStreamingToolCalls &&
            (structuredToolStreamingProvider != nil || promptToolStreamingProvider != nil)
        let membraneEnvironment = AgentEnvironmentValues.current.membrane ?? .enabled
        let membraneAdapter = resolvedMembraneAdapter(profile: profile)
        var duplicateToolLoopState = DuplicateToolLoopState()
        var issuedToolResultRecoveryPrompt = false

        if profile.preset == .strict4k,
           let explicitPlanOutcome = try await executeExplicitWebsearchPlanIfNeeded(
               input: input,
               provider: provider,
               toolRegistry: toolRegistry,
               conversationHistory: &conversationHistory,
               transcriptMessages: &transcriptMessages,
               duplicateToolLoopState: &duplicateToolLoopState,
               resultBuilder: resultBuilder,
               observer: observer,
               tracing: tracing,
               membraneAdapter: membraneAdapter,
               request: structuredOutputRequest,
               startTime: startTime
           )
        {
            return explicitPlanOutcome
        }

        while iteration < configuration.maxIterations {
            iteration += 1
            _ = resultBuilder.incrementIteration()
            await observer?.onIterationStart(context: nil, agent: self, number: iteration)

            do {
                try checkCancellationAndTimeout(startTime: startTime)

                let rawPrompt: String
                if profile.preset == .strict4k {
                    // Use ContextCore's intelligent windowing if available.
                    // DefaultAgentMemory wraps ContextCoreMemory internally.
                    let historyBudget = profile.budget.workingTokens
                    var windowedContext = memoryContext
                    if windowedContext.isEmpty {
                        let lastMsg = conversationHistory.last
                        let query: String
                        switch lastMsg {
                        case .assistant(let content, _):
                            query = content
                        case .toolResult(_, let output, _):
                            query = String(output.prefix(200))
                        default:
                            query = input
                        }
                        if let defaultMem = activeMemory as? DefaultAgentMemory {
                            windowedContext = await defaultMem.context(for: query, tokenLimit: historyBudget)
                        } else if let ccMemory = activeMemory as? ContextCoreMemory {
                            windowedContext = await ccMemory.context(for: query, tokenLimit: historyBudget)
                        }
                    }
                    if !windowedContext.isEmpty {
                        let liveBudget = profile.bucketCaps.map { $0.system + $0.history } ?? historyBudget
                        let livePrompt = await buildStrict4kLivePrompt(
                            from: conversationHistory,
                            maxTokens: liveBudget,
                            systemTokenLimit: profile.bucketCaps?.system ?? max(128, liveBudget / 4)
                        )
                        rawPrompt = """
                        [Retrieved Context]
                        \(windowedContext)

                        [Current Conversation]
                        \(livePrompt)
                        """
                    } else {
                        // Fallback: manual pruning with summarization.
                        var capped = conversationHistory
                        for i in capped.indices {
                            if case .toolResult(let toolName, let output, let toolCallID) = capped[i], output.count > 400 {
                                capped[i] = .toolResult(toolName: toolName, result: String(output.prefix(400)) + "\n[... truncated ...]", toolCallID: toolCallID)
                            }
                            if case .assistant(let content, let toolCalls) = capped[i], !toolCalls.isEmpty {
                                let nameOnlyCalls = toolCalls.map { tc in
                                    InferenceResponse.ParsedToolCall(id: tc.id, name: tc.name, arguments: [:])
                                }
                                capped[i] = .assistant(content, toolCalls: nameOnlyCalls)
                            }
                        }
                        if capped.count > 6 {
                            let head = capped.prefix(2)
                            let tail = capped.suffix(3)
                            let middle = capped.dropFirst(2).dropLast(3)
                            var summaryParts: [String] = []
                            for msg in middle {
                                switch msg {
                                case .assistant(_, let toolCalls) where !toolCalls.isEmpty:
                                    summaryParts.append("called " + toolCalls.map(\.name).joined(separator: ", "))
                                case .toolResult(let toolName, let output, _):
                                    summaryParts.append("\(toolName): \(output.prefix(40).replacingOccurrences(of: "\n", with: " "))")
                                default:
                                    break
                                }
                            }
                            var pruned = Array(head)
                            pruned.append(.assistant("[summary: \(summaryParts.joined(separator: "; "))]", toolCalls: []))
                            pruned.append(contentsOf: tail)
                            rawPrompt = buildPrompt(from: pruned)
                        } else if capped.count > 5 {
                            var pruned = Array(capped.prefix(2))
                            pruned.append(.assistant("[... truncated ...]", toolCalls: []))
                            pruned.append(contentsOf: capped.suffix(3))
                            rawPrompt = buildPrompt(from: pruned)
                        } else {
                            rawPrompt = buildPrompt(from: capped)
                        }
                    }
                } else {
                    rawPrompt = buildPrompt(from: conversationHistory)
                }
                let unplannedSchemas = await buildToolSchemasWithHandoffs(toolRegistry: toolRegistry)
                var plannedPrompt = rawPrompt
                var plannedSchemas = MembraneInternalTools.sortedSchemas(unplannedSchemas)

                if let membraneAdapter,
                   (!unplannedSchemas.isEmpty || membraneEnvironment.adapter != nil)
                {
                    do {
                        let plan: MembranePlannedBoundary
                        if let structuredAdapter = membraneAdapter as? any StructuredMembranePlanningAdapter {
                            plan = try await structuredAdapter.plan(
                                request: makeMembranePlanningRequest(
                                    rawPrompt: rawPrompt,
                                    systemPrompt: systemMessage,
                                    input: input,
                                    conversationHistory: conversationHistory,
                                    memoryContext: memoryContext
                                ),
                                toolSchemas: unplannedSchemas,
                                profile: configuration.effectiveContextProfile
                            )
                        } else {
                            plan = try await membraneAdapter.plan(
                                prompt: rawPrompt,
                                toolSchemas: unplannedSchemas,
                                profile: configuration.effectiveContextProfile
                            )
                        }
                        plannedPrompt = plan.prompt
                        plannedSchemas = MembraneInternalTools.sortedSchemas(plan.toolSchemas)
                        _ = resultBuilder.setMetadata("membrane.mode", .string(plan.mode))
                    } catch {
                        _ = resultBuilder.setMetadata("membrane.fallback.used", .bool(true))
                        _ = resultBuilder.setMetadata("membrane.fallback.error", .string(fallbackDiagnosticMessage(for: error)))
                        plannedPrompt = rawPrompt
                        plannedSchemas = MembraneInternalTools.sortedSchemas(unplannedSchemas)
                    }
                }

                let prompt = await PromptEnvelope.enforce(
                    prompt: plannedPrompt,
                    profile: configuration.effectiveContextProfile
                )
                let toolSchemas: [ToolSchema] = {
                    var schemas = MembraneInternalTools.sortedSchemas(plannedSchemas)
                    // For strict4k, strip tool descriptions to save ~120 tokens.
                    if profile.preset == .strict4k {
                        schemas = schemas.map { ToolSchema(name: $0.name, description: $0.name, parameters: $0.parameters) }
                    }
                    return schemas
                }()
                let structuredMessages: [InferenceMessage]? = if profile.preset == .strict4k {
                    nil
                } else if prompt == rawPrompt {
                    conversationHistory.map(\.inferenceMessage)
                } else {
                    nil
                }

                // If no tools defined, generate without tool calling
                if toolSchemas.isEmpty {
                    let loopInferenceOptions = inferenceOptions
                    let response = try await executeWithinRemainingTimeout(startTime: startTime) {
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
                let response = if useToolStreaming {
                    try await executeWithinRemainingTimeout(startTime: startTime) {
                        try await generateWithToolsStreaming(
                            provider: provider,
                            prompt: prompt,
                            messages: structuredMessages,
                            tools: toolSchemas,
                            inferenceOptions: loopInferenceOptions,
                            systemPrompt: systemMessage,
                            observer: observer
                        )
                    }
                } else {
                    try await executeWithinRemainingTimeout(startTime: startTime) {
                        try await generateWithTools(
                            provider: provider,
                            prompt: prompt,
                            messages: structuredMessages,
                            tools: toolSchemas,
                            inferenceOptions: loopInferenceOptions,
                            systemPrompt: systemMessage,
                            observer: observer,
                            emitOutputTokens: enableStreaming
                        )
                    }
                }

                if response.hasToolCalls {
                    let executableToolCalls = sanitizeToolCallsIfNeeded(
                        response.toolCalls,
                        input: input,
                        conversationHistory: conversationHistory
                    )

                    if executableToolCalls.isEmpty {
                        let synthesizedResponse = try await finalizeFromSuppressedToolCalls(
                            input: input,
                            provider: provider,
                            systemPrompt: systemMessage,
                            inferenceOptions: loopInferenceOptions,
                            observer: observer,
                            request: structuredOutputRequest,
                            conversationHistory: conversationHistory
                        )
                        transcriptMessages.append(
                            SwarmTranscriptCodec.encodeMessage(
                                role: .assistant,
                                content: synthesizedResponse.content,
                                toolCalls: [],
                                structuredOutput: synthesizedResponse.structuredOutput
                            )
                        )
                        await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                        return ToolLoopOutcome(
                            output: synthesizedResponse.content,
                            structuredOutput: synthesizedResponse.structuredOutput,
                            transcriptMessages: transcriptMessages
                        )
                    }

                    let sanitizedResponse = InferenceResponse(
                        content: response.content,
                        toolCalls: executableToolCalls,
                        finishReason: .toolCall,
                        usage: response.usage
                    )
                    let handoffResult = try await processToolCallsWithHandoffs(
                        response: sanitizedResponse,
                        toolRegistry: toolRegistry,
                        conversationHistory: &conversationHistory,
                        transcriptMessages: &transcriptMessages,
                        duplicateToolLoopState: &duplicateToolLoopState,
                        resultBuilder: resultBuilder,
                        observer: observer,
                        tracing: tracing,
                        membraneAdapter: membraneAdapter,
                        startTime: startTime
                    )
                    // If a handoff occurred, return the target agent's result
                    if let handoffOutput = handoffResult {
                        await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                        return ToolLoopOutcome(
                            output: handoffOutput.content,
                            structuredOutput: handoffOutput.structuredOutput,
                            transcriptMessages: transcriptMessages
                        )
                    }
                } else {
                    let fallbackPlannedCalls = plannedWebsearchFallbackCalls(
                        input: input,
                        conversationHistory: conversationHistory
                    )
                    if !fallbackPlannedCalls.isEmpty {
                        let fallbackResponse = InferenceResponse(
                            content: nil,
                            toolCalls: fallbackPlannedCalls,
                            finishReason: .toolCall,
                            usage: response.usage
                        )
                        let handoffResult = try await processToolCallsWithHandoffs(
                            response: fallbackResponse,
                            toolRegistry: toolRegistry,
                            conversationHistory: &conversationHistory,
                            transcriptMessages: &transcriptMessages,
                            duplicateToolLoopState: &duplicateToolLoopState,
                            resultBuilder: resultBuilder,
                            observer: observer,
                            tracing: tracing,
                            membraneAdapter: membraneAdapter,
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
                        continue
                    }

                    guard let content = response.content else {
                        throw AgentError.generationFailed(reason: "Model returned no content or tool calls")
                    }
                    if hasCompletedExplicitWebsearchPlan(input: input, conversationHistory: conversationHistory) {
                        let finalResponse = try finalizeAssistantResponse(
                            content: deterministicWebsearchFallback(from: conversationHistory),
                            request: structuredOutputRequest,
                            provider: provider
                        )
                        transcriptMessages.append(
                            SwarmTranscriptCodec.encodeMessage(
                                role: .assistant,
                                content: finalResponse.content,
                                toolCalls: [],
                                structuredOutput: finalResponse.structuredOutput
                            )
                        )
                        await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                        return ToolLoopOutcome(
                            output: finalResponse.content,
                            structuredOutput: finalResponse.structuredOutput,
                            transcriptMessages: transcriptMessages
                        )
                    }
                    let ignoredToolResult = shouldRetryAfterIgnoringToolResult(
                        content: content,
                        conversationHistory: conversationHistory,
                        alreadyIssuedRecovery: issuedToolResultRecoveryPrompt
                    )
                    if ignoredToolResult {
                        if issuedToolResultRecoveryPrompt,
                           let fallback = fallbackAnswerFromToolResults(
                               input: input,
                               conversationHistory: conversationHistory
                           )
                        {
                            let finalResponse = try finalizeAssistantResponse(
                                content: fallback,
                                request: structuredOutputRequest,
                                provider: provider
                            )
                            transcriptMessages.append(
                                SwarmTranscriptCodec.encodeMessage(
                                    role: .assistant,
                                    content: finalResponse.content,
                                    toolCalls: [],
                                    structuredOutput: finalResponse.structuredOutput
                                )
                            )
                            await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                            return ToolLoopOutcome(
                                output: finalResponse.content,
                                structuredOutput: finalResponse.structuredOutput,
                                transcriptMessages: transcriptMessages
                            )
                        }

                        issuedToolResultRecoveryPrompt = true
                        conversationHistory.append(.user("""
                        System correction: a tool result is already present above. Use that tool result directly to answer the original request. Do not say you cannot browse, search, or access external information. Do not emit JSON unless you are making a real tool call, and do not call another tool unless you genuinely need a new query or URL.
                        """))
                        continue
                    }
                    let finalContent = substituteWeakWebsearchAnswerIfNeeded(
                        content,
                        conversationHistory: conversationHistory
                    )
                    let finalResponse = try finalizeAssistantResponse(
                        content: finalContent,
                        request: structuredOutputRequest,
                        provider: provider
                    )
                    transcriptMessages.append(
                        SwarmTranscriptCodec.encodeMessage(
                            role: .assistant,
                            content: finalResponse.content,
                            toolCalls: [],
                            structuredOutput: finalResponse.structuredOutput
                        )
                    )
                    await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                    return ToolLoopOutcome(
                        output: finalResponse.content,
                        structuredOutput: finalResponse.structuredOutput,
                        transcriptMessages: transcriptMessages
                    )
                }

                await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
            } catch {
                await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                throw normalizeCancellation(error)
            }
        }

        throw AgentError.maxIterationsExceeded(iterations: iteration)
    }

    private func executeExplicitWebsearchPlanIfNeeded(
        input: String,
        provider: any InferenceProvider,
        toolRegistry: ToolRegistry,
        conversationHistory: inout [ConversationMessage],
        transcriptMessages: inout [MemoryMessage],
        duplicateToolLoopState: inout DuplicateToolLoopState,
        resultBuilder: AgentResult.Builder,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        membraneAdapter: (any MembraneAgentAdapter)?,
        request: StructuredOutputRequest?,
        startTime: ContinuousClock.Instant
    ) async throws -> ToolLoopOutcome? {
        let pendingCalls = pendingExplicitWebsearchCalls(
            input: input,
            conversationHistory: conversationHistory
        )
        guard pendingCalls.count > 1 else {
            return nil
        }

        let response = InferenceResponse(
            content: nil,
            toolCalls: pendingCalls,
            finishReason: .toolCall,
            usage: nil
        )
        _ = try await processToolCallsWithHandoffs(
            response: response,
            toolRegistry: toolRegistry,
            conversationHistory: &conversationHistory,
            transcriptMessages: &transcriptMessages,
            duplicateToolLoopState: &duplicateToolLoopState,
            resultBuilder: resultBuilder,
            observer: observer,
            tracing: tracing,
            membraneAdapter: membraneAdapter,
            startTime: startTime
        )

        let finalResponse = try finalizeAssistantResponse(
            content: deterministicWebsearchFallback(from: conversationHistory),
            request: request,
            provider: provider
        )
        transcriptMessages.append(
            SwarmTranscriptCodec.encodeMessage(
                role: .assistant,
                content: finalResponse.content,
                toolCalls: [],
                structuredOutput: finalResponse.structuredOutput
            )
        )

        return ToolLoopOutcome(
            output: finalResponse.content,
            structuredOutput: finalResponse.structuredOutput,
            transcriptMessages: transcriptMessages
        )
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

    private func executeWithinRemainingTimeout<T: Sendable>(
        startTime: ContinuousClock.Instant,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try Task.checkCancellation()

        let remaining = configuration.timeout - (ContinuousClock.now - startTime)
        if remaining <= .zero {
            throw AgentError.timeout(duration: configuration.timeout)
        }

        let coordinator = TimedOperationCoordinator<T>()

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
        messages: [InferenceMessage]?,
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
            let result: StructuredOutputResult
            if let messages,
               let nativeProvider = provider as? any StructuredOutputConversationInferenceProvider
            {
                result = try await nativeProvider.generateStructured(messages: messages, request: request, options: options)
            } else if let messages,
                      let conversationProvider = provider as? any ConversationInferenceProvider
            {
                result = try await conversationProvider.generateStructured(messages: messages, request: request, options: options)
            } else if let nativeProvider = provider as? any StructuredOutputInferenceProvider {
                result = try await nativeProvider.generateStructured(prompt: prompt, request: request, options: options)
            } else {
                result = try await provider.generateStructured(prompt: prompt, request: request, options: options)
            }
            content = result.rawJSON
            structuredOutput = result
        } else if enableStreaming {
            var streamedContent = ""
            streamedContent.reserveCapacity(1024)
            let stream: AsyncThrowingStream<String, Error>
            if let messages,
               let conversationProvider = provider as? any StreamingConversationInferenceProvider {
                stream = conversationProvider.stream(messages: messages, options: options)
            } else {
                stream = provider.stream(prompt: prompt, options: options)
            }
            for try await token in stream {
                if !token.isEmpty {
                    streamedContent += token
                }
                await observer?.onOutputToken(context: nil, agent: self, token: token)
            }
            content = streamedContent
            structuredOutput = nil
        } else {
            if let messages,
               let conversationProvider = provider as? any ConversationInferenceProvider {
                content = try await conversationProvider.generate(messages: messages, options: options)
            } else {
                content = try await provider.generate(
                    prompt: prompt,
                    options: options
                )
            }
            structuredOutput = nil
        }

        await observer?.onLLMEnd(context: nil, agent: self, response: content, usage: nil)
        return FinalAssistantResponse(content: content, structuredOutput: structuredOutput)
    }

    /// Processes tool calls from the model response.
    private func processToolCalls(
        response: InferenceResponse,
        toolRegistry: ToolRegistry,
        conversationHistory: inout [ConversationMessage],
        transcriptMessages: inout [MemoryMessage],
        duplicateToolLoopState: inout DuplicateToolLoopState,
        resultBuilder: AgentResult.Builder,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        membraneAdapter: (any MembraneAgentAdapter)?
    ) async throws {
        let toolCallSummary = response.toolCalls.map { "Calling tool: \($0.name)" }.joined(separator: ", ")
        let assistantContent = response.content ?? toolCallSummary
        conversationHistory.append(.assistant(assistantContent, toolCalls: response.toolCalls))
        transcriptMessages.append(
            SwarmTranscriptCodec.encodeMessage(
                role: .assistant,
                content: assistantContent,
                toolCalls: response.toolCalls
            )
        )

        for parsedCall in response.toolCalls {
            try await executeSingleToolCall(
                parsedCall: parsedCall,
                toolRegistry: toolRegistry,
                conversationHistory: &conversationHistory,
                transcriptMessages: &transcriptMessages,
                duplicateToolLoopState: &duplicateToolLoopState,
                resultBuilder: resultBuilder,
                observer: observer,
                tracing: tracing,
                membraneAdapter: membraneAdapter,
                startTime: ContinuousClock.now
            )
        }
    }

    /// Executes a single tool call and updates conversation history.
    private func executeSingleToolCall(
        parsedCall: InferenceResponse.ParsedToolCall,
        toolRegistry: ToolRegistry,
        conversationHistory: inout [ConversationMessage],
        transcriptMessages: inout [MemoryMessage],
        duplicateToolLoopState: inout DuplicateToolLoopState,
        resultBuilder: AgentResult.Builder,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        membraneAdapter: (any MembraneAgentAdapter)?,
        startTime: ContinuousClock.Instant
    ) async throws {
        let activeMemory = resolvedMemory()
        let callSignature = toolCallSignature(for: parsedCall)

        if let duplicateMessage = duplicateToolLoopState.registerOrReject(signature: callSignature) {
            conversationHistory.append(.toolResult(
                toolName: parsedCall.name,
                result: duplicateMessage,
                toolCallID: parsedCall.id
            ))
            transcriptMessages.append(
                SwarmTranscriptCodec.encodeMessage(
                    role: .tool,
                    content: duplicateMessage,
                    toolName: parsedCall.name,
                    toolCallID: parsedCall.id
                )
            )
            if let activeMemory {
                await activeMemory.add(.tool(duplicateMessage, toolName: parsedCall.name))
            }
            return
        }

        if let membraneAdapter,
           MembraneInternalTools.isInternalTool(parsedCall.name) {
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
                    result: "[TOOL ERROR] Execution failed: \(message). Please try a different approach or tool.",
                    toolCallID: parsedCall.id
                ))
                transcriptMessages.append(
                    SwarmTranscriptCodec.encodeMessage(
                        role: .tool,
                        content: "[TOOL ERROR] Execution failed: \(message). Please try a different approach or tool.",
                        toolName: parsedCall.name,
                        toolCallID: parsedCall.id
                    )
                )
                if let activeMemory {
                    await activeMemory.add(.tool("Error - \(message)", toolName: parsedCall.name))
                }
                return
            }
        }

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
            let rawToolOutputText = outcome.result.output.stringValue ?? outcome.result.output.description
            var toolOutputText = rawToolOutputText
            let compiledWebsearchEvidence: CompiledWebSearchEvidence? = if parsedCall.name == "websearch" {
                WebSearchEvidenceCompiler.compile(
                    rawPayload: rawToolOutputText,
                    queryFallback: parsedCall.arguments["query"]?.stringValue
                        ?? parsedCall.arguments["goal"]?.stringValue
                )
            } else {
                nil
            }
            if let membraneAdapter {
                do {
                    let currentToolOutput = rawToolOutputText
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

            let conversationToolOutput: String = {
                if let compiledWebsearchEvidence {
                    return compiledWebsearchEvidence.compactTranscript
                }
                if parsedCall.name == "websearch" {
                    return compactWebsearchConversationResult(from: rawToolOutputText)
                }
                return toolOutputText
            }()

            conversationHistory.append(.toolResult(
                toolName: parsedCall.name,
                result: conversationToolOutput,
                toolCallID: parsedCall.id
            ))
            transcriptMessages.append(
                SwarmTranscriptCodec.encodeMessage(
                    role: .tool,
                    content: conversationToolOutput,
                    toolName: parsedCall.name,
                    toolCallID: parsedCall.id
                )
            )
            if let activeMemory {
                if parsedCall.name == "websearch",
                   let compiledWebsearchEvidence,
                   let websearchMemory = activeMemory as? any WebSearchEvidenceMemory
                {
                    await websearchMemory.addWebSearchResult(
                        rawPayload: rawToolOutputText,
                        evidence: compiledWebsearchEvidence.record
                    )
                } else {
                    // Keep the compact Membrane rendering in the live transcript, but retain
                    // the full tool payload in memory so retrieval can surface facts later.
                    await activeMemory.add(.tool(rawToolOutputText, toolName: parsedCall.name))
                }
            }
        } else {
            let errorMessage = outcome.result.errorMessage ?? "Unknown error"
            let failureMessage = toolFailureConversationMessage(
                toolName: parsedCall.name,
                errorMessage: errorMessage,
                conversationHistory: conversationHistory
            )
            conversationHistory.append(.toolResult(
                toolName: parsedCall.name,
                result: failureMessage,
                toolCallID: parsedCall.id
            ))
            transcriptMessages.append(
                SwarmTranscriptCodec.encodeMessage(
                    role: .tool,
                    content: failureMessage,
                    toolName: parsedCall.name,
                    toolCallID: parsedCall.id
                )
            )
            if let activeMemory {
                await activeMemory.add(.tool("Error - \(errorMessage)", toolName: parsedCall.name))
            }

            if configuration.stopOnToolError {
                throw AgentError.toolExecutionFailed(toolName: parsedCall.name, underlyingError: errorMessage)
            }
        }
    }

    // MARK: - Handoff Tool Schema Integration

    /// Builds tool schemas including handoff tool schemas.
    ///
    /// This merges regular tool schemas with handoff-generated schemas,
    /// allowing handoffs to appear as callable tools in the LLM prompt.
    private func buildToolSchemasWithHandoffs(toolRegistry: ToolRegistry) async -> [ToolSchema] {
        var schemas = await toolRegistry.schemas

        for handoff in _handoffs {
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
        duplicateToolLoopState: inout DuplicateToolLoopState,
        resultBuilder: AgentResult.Builder,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        membraneAdapter: (any MembraneAgentAdapter)?,
        startTime: ContinuousClock.Instant
    ) async throws -> FinalAssistantResponse? {
        let handoffMap = Dictionary(
            uniqueKeysWithValues: _handoffs.map { ($0.effectiveToolName, $0) }
        )

        let toolCallSummary = response.toolCalls.map { "Calling tool: \($0.name)" }.joined(separator: ", ")
        let assistantContent = response.content ?? toolCallSummary
        conversationHistory.append(.assistant(assistantContent, toolCalls: response.toolCalls))
        transcriptMessages.append(
            SwarmTranscriptCodec.encodeMessage(
                role: .assistant,
                content: assistantContent,
                toolCalls: response.toolCalls
            )
        )

        for parsedCall in response.toolCalls {
            // Check if this is a handoff tool call
            if let handoffConfig = handoffMap[parsedCall.name] {
                let reason = parsedCall.arguments["reason"]?.stringValue ?? ""
                let targetAgent = handoffConfig.targetAgent

                let handoffStart = ContinuousClock.now
                let spanId = await tracing?.traceToolCall(name: parsedCall.name, arguments: parsedCall.arguments)
                await observer?.onHandoff(context: nil, fromAgent: self, toAgent: targetAgent)

                // Find the last user message to use as handoff input
                let lastUserMessage = conversationHistory.last(where: {
                    if case .user = $0 { return true }
                    return false
                })
                let handoffInput: String = if case let .user(content) = lastUserMessage {
                    content
                } else {
                    reason.isEmpty ? "Continue the conversation" : reason
                }

                let result = try await executeWithinRemainingTimeout(startTime: startTime) {
                    try await targetAgent.run(handoffInput, session: nil, observer: observer)
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

                if let spanId {
                    let handoffDuration = ContinuousClock.now - handoffStart
                    await tracing?.traceToolResult(spanId: spanId, name: parsedCall.name, result: result.output, duration: handoffDuration)
                }

                // Merge handoff result metadata into current agent's result builder
                // This preserves token counts, tool calls, and metadata from the target agent
                for toolCall in result.toolCalls {
                    _ = resultBuilder.addToolCall(toolCall)
                }
                for toolResult in result.toolResults {
                    _ = resultBuilder.addToolResult(toolResult)
                }
                if let usage = result.tokenUsage {
                    _ = resultBuilder.setTokenUsage(usage)
                }
                for (key, value) in result.metadata {
                    _ = resultBuilder.setMetadata(key, value)
                }

                // Return the handoff output to be used as the final result
                return FinalAssistantResponse(content: result.output, structuredOutput: nil)
            }

            // Regular tool call
            try await executeSingleToolCall(
                parsedCall: parsedCall,
                toolRegistry: toolRegistry,
                conversationHistory: &conversationHistory,
                transcriptMessages: &transcriptMessages,
                duplicateToolLoopState: &duplicateToolLoopState,
                resultBuilder: resultBuilder,
                observer: observer,
                tracing: tracing,
                membraneAdapter: membraneAdapter,
                startTime: startTime
            )
        }

        return nil
    }

    private func toolCallSignature(for parsedCall: InferenceResponse.ParsedToolCall) -> String {
        if parsedCall.name == "websearch" {
            let mode = parsedCall.arguments["mode"]?.stringValue?.lowercased() ?? "search"
            let query = parsedCall.arguments["query"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = parsedCall.arguments["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let artifactID = parsedCall.arguments["artifact_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let bundleID = parsedCall.arguments["bundle_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)

            switch mode {
            case "fetch", "refresh":
                if let url, !url.isEmpty {
                    return "websearch|\(mode)|url=\(url)"
                }
                return "websearch|\(mode)|missing-url"
            case "expand":
                if let bundleID, !bundleID.isEmpty {
                    return "websearch|expand|bundle=\(bundleID)"
                }
                if let artifactID, !artifactID.isEmpty {
                    return "websearch|expand|artifact=\(artifactID)"
                }
                return "websearch|expand|missing-target"
            default:
                if let query, !query.isEmpty {
                    return "websearch|\(mode)|query=\(query)"
                }
                return "websearch|\(mode)|missing-query"
            }
        }

        let preferredKeys = [
            "query",
            "url",
            "goal",
            "artifact_id",
            "bundle_id",
            "section_ids",
            "domains",
            "recencyDays",
            "mode",
        ]

        let keys = preferredKeys.filter { parsedCall.arguments[$0] != nil }
        let selectedKeys = keys.isEmpty ? parsedCall.arguments.keys.sorted() : keys
        let sortedArguments = selectedKeys.map { key in
            "\(key)=\(parsedCall.arguments[key]?.description ?? "null")"
        }.joined(separator: "&")
        return "\(parsedCall.name)|\(sortedArguments)"
    }

    private func toolFailureConversationMessage(
        toolName: String,
        errorMessage: String,
        conversationHistory: [ConversationMessage]
    ) -> String {
        let base = "[TOOL ERROR] Execution failed: \(errorMessage). Please try a different approach or tool."
        guard toolName == "websearch" else {
            return base
        }

        let hasUsablePriorWebsearchResult = conversationHistory.contains { message in
            guard case let .toolResult(name, result, _) = message else {
                return false
            }
            guard name == "websearch" else {
                return false
            }
            return !result.hasPrefix("[TOOL ERROR]") && !result.hasPrefix("[TOOL REUSE NOTICE]")
        }

        let normalizedError = errorMessage.lowercased()
        let isRecoverableWebsearchFailure = normalizedError.contains("requires non-empty query")
            || normalizedError.contains("requires non-empty url")
            || normalizedError.contains("requires bundle_id or artifact_id")
            || normalizedError.contains("invalid url")

        guard hasUsablePriorWebsearchResult, isRecoverableWebsearchFailure else {
            return base
        }

        return """
        [TOOL ERROR] Invalid websearch request: \(errorMessage).
        A usable websearch result is already present in the conversation.
        Do not call websearch again unless you have a genuinely new query or URL; answer using the existing result.
        """
    }

    private func sanitizeToolCallsIfNeeded(
        _ toolCalls: [InferenceResponse.ParsedToolCall],
        input: String,
        conversationHistory: [ConversationMessage]
    ) -> [InferenceResponse.ParsedToolCall] {
        guard !toolCalls.isEmpty else {
            return toolCalls
        }

        return toolCalls.filter { parsedCall in
            shouldSuppressWebsearchCall(
                parsedCall,
                input: input,
                conversationHistory: conversationHistory
            ) == false
        }
    }

    private func shouldSuppressWebsearchCall(
        _ parsedCall: InferenceResponse.ParsedToolCall,
        input: String? = nil,
        conversationHistory: [ConversationMessage]
    ) -> Bool {
        guard parsedCall.name == "websearch" else {
            return false
        }

        let mode = parsedCall.arguments["mode"]?.stringValue?.lowercased() ?? "search"
        guard mode == "search" else {
            return false
        }

        let successfulSearchCount = successfulWebsearchCount(in: conversationHistory)
        let maxAllowedSearches = explicitWebsearchPlan(from: input ?? "")?.count ?? 3
        return successfulSearchCount >= maxAllowedSearches
    }

    private func shouldRetryAfterIgnoringToolResult(
        content: String,
        conversationHistory: [ConversationMessage],
        alreadyIssuedRecovery _: Bool
    ) -> Bool {
        let hasUsableToolResult = conversationHistory.contains { message in
            guard case let .toolResult(_, result, _) = message else {
                return false
            }
            return !result.hasPrefix("[TOOL ERROR]") && !result.hasPrefix("[TOOL REUSE NOTICE]")
        }

        guard hasUsableToolResult else {
            return false
        }

        let normalized = content.lowercased()
        let refusalMarkers = [
            "i cannot access external information",
            "i can't access external information",
            "i'm unable to access external information",
            "i am unable to access external information",
            "i'm unable to perform external searches",
            "i am unable to perform external searches",
            "i cannot perform web searches",
            "i'm unable to perform web searches",
            "i cannot browse the web",
            "i'm unable to browse the web",
            "i do not have browsing capability",
            "i'm unable to perform external searches or browse the web",
            "no tool call is needed",
            "the information is directly available in the retrieved context",
            "sorry, i can't assist with that",
            "i'm sorry, but i can't assist with that request",
            "i'm sorry, but i can't assist with that",
            "resulted in an error",
            "preventing retrieval",
            "unable to retrieve",
            "available tools:",
            "[... truncated to fit fm context window ...]",
        ]

        if refusalMarkers.contains(where: { normalized.contains($0) }) {
            return true
        }

        let copiedPlaceholderEnvelope = normalized.contains("\"swarm_tool_call\"")
            && normalized.contains("\"tool\"")
            && normalized.contains("tool_name")

        if copiedPlaceholderEnvelope {
            return true
        }

        return false
    }

    private func plannedWebsearchFallbackCalls(
        input: String,
        conversationHistory: [ConversationMessage]
    ) -> [InferenceResponse.ParsedToolCall] {
        Array(pendingExplicitWebsearchCalls(input: input, conversationHistory: conversationHistory).prefix(1))
    }

    private func pendingExplicitWebsearchCalls(
        input: String,
        conversationHistory: [ConversationMessage]
    ) -> [InferenceResponse.ParsedToolCall] {
        guard let plan = explicitWebsearchPlan(from: input), !plan.isEmpty else {
            return []
        }

        let completedSearches = successfulWebsearchCount(in: conversationHistory)
        guard completedSearches < plan.count else {
            return []
        }

        return Array(plan.enumerated().dropFirst(completedSearches)).map { index, nextQuery in
            let explicitDomains = plannedWebsearchDomains(for: nextQuery)
            let maxResults = explicitDomains.isEmpty ? 1 : 2
            return InferenceResponse.ParsedToolCall(
                id: "planned_websearch_\(index + 1)",
                name: "websearch",
                arguments: [
                    "query": .string(nextQuery),
                    "mode": .string("search"),
                    "maxResults": .int(maxResults),
                    "detail": .string("compact"),
                    "preferCached": .bool(true),
                    "domains": .array(explicitDomains.map { .string($0) }),
                ]
            )
        }
    }

    private func hasCompletedExplicitWebsearchPlan(
        input: String,
        conversationHistory: [ConversationMessage]
    ) -> Bool {
        guard let plan = explicitWebsearchPlan(from: input), !plan.isEmpty else {
            return false
        }
        return successfulWebsearchCount(in: conversationHistory) >= plan.count
    }

    private func successfulWebsearchCount(in conversationHistory: [ConversationMessage]) -> Int {
        conversationHistory.reduce(into: 0) { count, message in
            guard case let .toolResult(toolName, result, _) = message,
                  toolName == "websearch",
                  result.hasPrefix("[TOOL ERROR]") == false
            else {
                return
            }
            count += 1
        }
    }

    private func explicitWebsearchPlan(from input: String) -> [String]? {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            return nil
        }

        let lowercased = normalized.lowercased()
        guard lowercased.contains("websearch") || lowercased.contains("search for") else {
            return nil
        }

        let lines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        let numberedPlan = lines.compactMap { explicitWebsearchQuery(from: $0) }
        if numberedPlan.isEmpty == false {
            return numberedPlan
        }

        if let singleSearch = lines.compactMap(explicitSingleWebsearchQuery(from:)).first {
            return [singleSearch]
        }

        return nil
    }

    private func explicitWebsearchQuery(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"^\d+\.\s*(.+)$"#) else {
            return nil
        }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              let contentRange = Range(match.range(at: 1), in: trimmed)
        else {
            return nil
        }
        return explicitSingleWebsearchQuery(from: String(trimmed[contentRange]))
    }

    private func plannedWebsearchDomains(for query: String) -> [String] {
        let lowered = query.lowercased()

        let explicitHosts = [
            "developer.apple.com",
            "machinelearning.apple.com",
            "matthewcassinelli.com",
            "omni-automation.com",
        ].filter { lowered.contains($0) }

        if explicitHosts.isEmpty == false {
            return explicitHosts
        }

        let docsHeavySignals = [
            "foundation models",
            "foundationmodels",
            "language model session",
            "context window",
            "prompt engineering",
            "tool calling",
            "streaming tool",
            "technote",
            "developer",
        ]

        guard docsHeavySignals.contains(where: lowered.contains) else {
            return []
        }

        return docsRefinementDomains(for: query)
    }

    private func explicitSingleWebsearchQuery(from line: String) -> String? {
        var candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "search for ",
            "search ",
            "find ",
            "look up ",
            "websearch for ",
            "use the websearch tool to search for ",
            "use websearch to search for ",
        ]

        let lowered = candidate.lowercased()
        guard prefixes.contains(where: { lowered.hasPrefix($0) }) else {
            return nil
        }

        if let matchedPrefix = prefixes.first(where: { lowered.hasPrefix($0) }) {
            candidate.removeFirst(matchedPrefix.count)
        }

        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        if candidate.hasSuffix(" then answer in 4 short bullets with the findings and cite the urls you used") {
            candidate = candidate.replacingOccurrences(
                of: " then answer in 4 short bullets with the findings and cite the urls you used",
                with: "",
                options: [.caseInsensitive]
            )
        }
        return candidate.isEmpty ? nil : candidate
    }

    private struct DuplicateToolLoopState {
        private(set) var lastSignature: String?
        private(set) var consecutiveCount = 0
        let maxConsecutiveDuplicates = 1

        mutating func registerOrReject(signature: String) -> String? {
            if lastSignature == signature {
                consecutiveCount += 1
            } else {
                lastSignature = signature
                consecutiveCount = 1
            }

            guard consecutiveCount > maxConsecutiveDuplicates else {
                return nil
            }

            return """
            [TOOL REUSE NOTICE] The same tool call was requested repeatedly. Reuse the earlier tool result already present in the conversation instead of issuing the identical request again.
            """
        }
    }

    private func fallbackAnswerFromToolResults(
        input: String,
        conversationHistory: [ConversationMessage]
    ) -> String? {
        let usableToolResults = conversationHistory.compactMap { message -> (toolName: String, result: String)? in
            guard case let .toolResult(toolName, result, _) = message else {
                return nil
            }
            guard !result.hasPrefix("[TOOL ERROR]"), !result.hasPrefix("[TOOL REUSE NOTICE]") else {
                return nil
            }
            return (toolName, result)
        }

        guard !usableToolResults.isEmpty else {
            return nil
        }

        if usableToolResults.contains(where: { $0.toolName == "websearch" }) {
            let deterministic = deterministicWebsearchFallback(from: conversationHistory)
            if deterministic.contains("http") {
                return """
                \(deterministic)

                Some follow-up tool calls were invalid or inconclusive, so this answer is limited to the successfully retrieved evidence.
                """
            }
        }

        let primary = usableToolResults[0]
        let excerpt = summarizeToolResult(primary.result)
        let additionalFailures = conversationHistory.reduce(into: 0) { count, message in
            if case let .toolResult(_, result, _) = message, result.hasPrefix("[TOOL ERROR]") {
                count += 1
            }
        }

        let limitation: String
        if additionalFailures > 0 {
            limitation = "Some follow-up tool calls were invalid or inconclusive, so this answer is limited to the successfully retrieved evidence."
        } else {
            limitation = "The answer is limited to the retrieved search snippet and may not fully resolve the original question."
        }

        return """
        Based on the successfully retrieved tool result for "\(input)", the strongest available evidence is: \(excerpt)
        \(limitation)
        """
    }

    private func summarizeToolResult(_ result: String) -> String {
        let normalized = normalizeWebsearchResultText(result)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let titleStart = normalized.range(of: "["),
           let titleEnd = normalized.range(of: "]", range: titleStart.upperBound..<normalized.endIndex),
           let urlStart = normalized.range(of: "(", range: titleEnd.upperBound..<normalized.endIndex),
           let urlEnd = normalized.range(of: ")", range: urlStart.upperBound..<normalized.endIndex)
        {
            let title = String(normalized[titleStart.upperBound..<titleEnd.lowerBound])
            let url = String(normalized[urlStart.upperBound..<urlEnd.lowerBound])
            let snippetStart = normalized[urlEnd.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = String(snippetStart.prefix(220))
            return "\(title) (\(url)) — \(snippet)"
        }

        return String(normalized.prefix(280))
    }

    private func finalizeFromSuppressedToolCalls(
        input: String,
        provider: any InferenceProvider,
        systemPrompt: String,
        inferenceOptions: InferenceOptions,
        observer: (any AgentObserver)?,
        request: StructuredOutputRequest?,
        conversationHistory: [ConversationMessage]
    ) async throws -> FinalAssistantResponse {
        let evidence = compactWebsearchEvidence(from: conversationHistory)
        let synthesisPrompt = """
        The required websearch calls are already complete. Do not call any tools.
        Use only the evidence below to answer the user's request directly.
        If the evidence does not establish a fact, say that clearly.
        Keep the answer concise and cite URLs inline when available.

        [User Request]
        \(input)

        [Evidence]
        \(evidence)
        """

        do {
            let response = try await generateWithoutTools(
                provider: provider,
                prompt: synthesisPrompt,
                messages: nil,
                systemPrompt: systemPrompt,
                inferenceOptions: inferenceOptions,
                enableStreaming: false,
                observer: observer
            )
            if shouldUseDeterministicWebsearchFallback(response.content, evidence: evidence) {
                return FinalAssistantResponse(
                    content: deterministicWebsearchFallback(from: conversationHistory),
                    structuredOutput: nil
                )
            }
            return try finalizeAssistantResponse(
                content: response.content,
                request: request,
                provider: provider
            )
        } catch {
            return FinalAssistantResponse(
                content: deterministicWebsearchFallback(from: conversationHistory),
                structuredOutput: nil
            )
        }
    }

    private func compactWebsearchConversationResult(from result: String) -> String {
        if let compiled = WebSearchEvidenceCompiler.compile(rawPayload: result, queryFallback: nil) {
            return compiled.compactTranscript
        }
        let lines = normalizeWebsearchResultText(result)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let firstLine = lines.first else {
            return String(result.prefix(400))
        }

        let query = extractWebsearchQuery(from: firstLine) ?? "websearch"
        let firstResult = extractFirstWebsearchResult(from: lines)
        var compactLines = ["Found 1 ranked result for '\(query)'."]
        if let firstResult {
            compactLines.append("[\(firstResult.title)](\(firstResult.url))")
            if let snippet = firstResult.snippet {
                compactLines.append(snippet)
            }
        } else {
            compactLines.append(String(firstLine.prefix(220)))
        }
        return compactLines.joined(separator: "\n")
    }

    private func compactWebsearchEvidence(from conversationHistory: [ConversationMessage]) -> String {
        let entries = conversationHistory.compactMap { message -> String? in
            guard case let .toolResult(toolName, result, _) = message,
                  toolName == "websearch",
                  result.hasPrefix("[TOOL ERROR]") == false
            else {
                return nil
            }

            let lines = normalizeWebsearchResultText(result)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else {
                return nil
            }

            let extracted = extractStructuredWebsearchEvidence(from: lines)
            let query = extracted?.query ?? extractWebsearchQuery(from: lines[0]) ?? "websearch"
            let summaryLine = extracted.map { "\($0.title) — \($0.url)" } ?? "No ranked result captured."
            let snippetLine = extracted?.snippet.map { "Snippet: \($0)" }

            return (["Query: \(query)", summaryLine, snippetLine].compactMap { $0 }).joined(separator: "\n")
        }

        if entries.isEmpty {
            return "No successful websearch evidence is available."
        }

        return entries.enumerated().map { index, entry in
            "[Search \(index + 1)]\n\(entry)"
        }.joined(separator: "\n\n")
    }

    private func deterministicWebsearchFallback(from conversationHistory: [ConversationMessage]) -> String {
        var seenDomains: [String: Int] = [:]
        let entries = conversationHistory.compactMap { message -> String? in
            guard case let .toolResult(toolName, result, _) = message,
                  toolName == "websearch",
                  result.hasPrefix("[TOOL ERROR]") == false
            else {
                return nil
            }

            let lines = normalizeWebsearchResultText(result)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard let firstLine = lines.first else {
                return nil
            }

            let query = extractStructuredWebsearchEvidence(from: lines)?.query
                ?? extractWebsearchQuery(from: firstLine)
                ?? "websearch"
            if let chosen = selectStructuredWebsearchCandidate(from: lines, query: query, seenDomains: &seenDomains) {
                let snippet = chosen.snippet.map { " — \($0)" } ?? ""
                return "- \(query): \(chosen.title) (\(chosen.url))\(snippet)"
            }
            if let firstResult = extractFirstWebsearchResult(from: lines) {
                let snippet = firstResult.snippet.map { " — \($0)" } ?? ""
                return "- \(query): \(firstResult.title) (\(firstResult.url))\(snippet)"
            }
            return "- \(query): no ranked result captured."
        }

        if entries.isEmpty {
            return "I completed the search loop, but no successful websearch results were available to summarize."
        }

        return entries.joined(separator: "\n")
    }

    private func shouldUseDeterministicWebsearchFallback(_ content: String, evidence: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }
        guard evidence.contains("http") else {
            return false
        }
        if trimmed.contains("http") == false {
            return true
        }

        let lowered = trimmed.lowercased()
        let failureMarkers = [
            "no information is available",
            "no ranked results",
            "no results captured",
            "unable to answer",
            "don't have enough information",
            "cannot determine from the provided evidence",
            "i'm unable to assist with that request",
            "i am unable to assist with that request",
            "i apologize",
            "i cannot assist with that request",
        ]
        return failureMarkers.contains(where: lowered.contains)
    }

    private func substituteWeakWebsearchAnswerIfNeeded(
        _ content: String,
        conversationHistory: [ConversationMessage]
    ) -> String {
        let successfulWebsearches = conversationHistory.contains { message in
            guard case let .toolResult(toolName, result, _) = message else {
                return false
            }
            return toolName == "websearch" && result.hasPrefix("[TOOL ERROR]") == false
        }

        guard successfulWebsearches else {
            return content
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = deterministicWebsearchFallback(from: conversationHistory)
        guard fallback.contains("http") else {
            return content
        }
        let lowered = trimmed.lowercased()
        let usesPlaceholderSearchLinks = lowered.contains("search.apple.com/search") || lowered.contains("no results available")
        let weakAnswerMarkers = [
            "i apologize",
            "i'm unable to assist",
            "i am unable to assist",
            "i cannot assist with that request",
            "however, i can still help guide you",
            "the previous interactions led to errors",
        ]
        guard trimmed.contains("http") == false
            || usesPlaceholderSearchLinks
            || weakAnswerMarkers.contains(where: lowered.contains)
        else {
            return content
        }

        return fallback
    }

    private func normalizeWebsearchResultText(_ result: String) -> String {
        let withoutEnvelope = WebSearchEvidenceCompiler.stripEnvelopeMarker(from: result)
        let trimmed = withoutEnvelope.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data)
        {
            return decoded
        }

        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
            let unquoted = String(trimmed.dropFirst().dropLast())
            return unquoted
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\t", with: "\t")
        }

        return trimmed
    }

    private func extractWebsearchQuery(from firstLine: String) -> String? {
        guard let range = firstLine.range(of: "for '") else {
            return nil
        }
        let afterStart = firstLine[range.upperBound...]
        guard let end = afterStart.firstIndex(of: "'") else {
            return nil
        }
        return String(afterStart[..<end])
    }

    private func extractFirstWebsearchResult(from lines: [String]) -> (title: String, url: String, snippet: String?)? {
        guard let resultLine = lines.first(where: { $0.contains("](") && $0.contains("http") }) else {
            return nil
        }

        let pattern = #"\[(.+?)\]\((https?://[^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let nsRange = NSRange(resultLine.startIndex..<resultLine.endIndex, in: resultLine)
        guard let match = regex.firstMatch(in: resultLine, range: nsRange),
              let titleRange = Range(match.range(at: 1), in: resultLine),
              let urlRange = Range(match.range(at: 2), in: resultLine)
        else {
            return nil
        }

        let title = String(resultLine[titleRange])
        let url = String(resultLine[urlRange])
        let lineIndex = lines.firstIndex(of: resultLine) ?? lines.startIndex
        let snippet = lines.indices.contains(lineIndex + 1) ? lines[lineIndex + 1] : nil
        return (title, url, snippet)
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

        let descriptor = memory as? any MemoryPromptDescriptor
        let title = descriptor?.memoryPromptTitle ?? "Relevant Context from Memory"
        let priority = descriptor?.memoryPriority
        let guidance = descriptor?.memoryPromptGuidance ?? {
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

    private func makeMembranePlanningRequest(
        rawPrompt: String,
        systemPrompt: String,
        input: String,
        conversationHistory: [ConversationMessage],
        memoryContext: String
    ) -> MembranePlanningRequest {
        let historySlices = conversationHistory.compactMap { message -> MembranePlanningSlice? in
            switch message {
            case .system:
                return nil
            case let .user(content):
                return MembranePlanningSlice(
                    content: "[User]: \(content)",
                    source: .history,
                    tokenCount: estimatedTokenCount(for: content),
                    importance: 1.0
                )
            case let .assistant(content, toolCalls):
                let rendered = ConversationMessage.assistant(content, toolCalls: toolCalls).formatted
                return MembranePlanningSlice(
                    content: rendered,
                    source: .history,
                    tokenCount: estimatedTokenCount(for: rendered),
                    importance: toolCalls.isEmpty ? 0.85 : 0.95
                )
            case let .toolResult(toolName, result, _):
                let rendered = compactConversationToolEvidence(toolName: toolName, result: result)
                return MembranePlanningSlice(
                    content: rendered,
                    source: .history,
                    tokenCount: estimatedTokenCount(for: rendered),
                    importance: toolName == "websearch" ? 1.1 : 0.95
                )
            }
        }
        _ = memoryContext
        let retrievalSlices = memoryPlanningSlices(from: memoryContext)

        return MembranePlanningRequest(
            prompt: rawPrompt,
            systemPrompt: systemPrompt,
            basePrompt: input,
            userInput: input,
            history: historySlices,
            memories: [],
            retrieval: retrievalSlices,
            recallQuery: input
        )
    }

    private func memoryPlanningSlices(from memoryContext: String) -> [MembranePlanningSlice] {
        let trimmed = memoryContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let rawBlocks = trimmed
            .components(separatedBy: "\n\n[")
            .enumerated()
            .map { index, block in
                index == 0 ? block : "[\(block)"
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return rawBlocks.map { block in
            let importance = block.contains("Web Search Evidence") ? 1.15 : 1.0
            return MembranePlanningSlice(
                content: block,
                source: .retrieval,
                tokenCount: estimatedTokenCount(for: block),
                importance: importance
            )
        }
    }

    private func extractStructuredWebsearchEvidence(
        from lines: [String]
    ) -> (query: String, title: String, url: String, snippet: String?)? {
        guard lines.contains("[Websearch Evidence]") else {
            return nil
        }

        let query = lines.first(where: { $0.hasPrefix("Query: ") })
            .map { String($0.dropFirst("Query: ".count)) }
            ?? "websearch"
        guard let bestLine = lines.first(where: { $0.hasPrefix("Best: ") }) else {
            return nil
        }
        let bestPayload = String(bestLine.dropFirst("Best: ".count))
        guard let best = extractFirstWebsearchResult(from: [bestPayload]) else {
            return nil
        }
        let snippet = lines.first(where: { $0.hasPrefix("Snippet: ") })
            .map { String($0.dropFirst("Snippet: ".count)) }
        return (query, best.title, best.url, snippet)
    }

    private func selectStructuredWebsearchCandidate(
        from lines: [String],
        query: String,
        seenDomains: inout [String: Int]
    ) -> (title: String, url: String, snippet: String?)? {
        guard lines.contains("[Websearch Evidence]") else {
            return nil
        }

        var candidates: [(title: String, url: String, snippet: String?)] = []
        if let best = extractStructuredWebsearchEvidence(from: lines) {
            candidates.append((best.title, best.url, best.snippet))
        }

        let summarySnippet = lines.first(where: { $0.hasPrefix("Summary: ") })
            .map { String($0.dropFirst("Summary: ".count)) }
        for line in lines where line.hasPrefix("Support ") {
            guard let separator = line.range(of: ": ") else {
                continue
            }
            let payload = String(line[separator.upperBound...])
            if let support = extractFirstWebsearchResult(from: [payload]) {
                candidates.append((support.title, support.url, summarySnippet))
            }
        }

        let ranked: [(candidate: (title: String, url: String, snippet: String?), score: Double)] = candidates.enumerated().map { index, candidate in
            let score = structuredWebsearchCandidateScore(
                title: candidate.title,
                url: candidate.url,
                snippet: candidate.snippet,
                query: query,
                priorSelectionsForDomain: seenDomains[URL(string: candidate.url)?.host?.lowercased() ?? "", default: 0],
                position: index
            )
            return (candidate, score)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.candidate.url < rhs.candidate.url
            }
            return lhs.score > rhs.score
        }

        guard let selected = ranked.first?.candidate else {
            return nil
        }

        if let host = URL(string: selected.url)?.host?.lowercased() {
            seenDomains[host, default: 0] += 1
        }
        return selected
    }

    private func structuredWebsearchCandidateScore(
        title: String,
        url: String,
        snippet: String?,
        query: String,
        priorSelectionsForDomain: Int,
        position: Int
    ) -> Double {
        let loweredQuery = query.lowercased()
        let tokens = loweredQuery
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 4 }
        let titleLower = title.lowercased()
        let urlLower = url.lowercased()
        let snippetLower = snippet?.lowercased() ?? ""

        let tokenCoverage = Double(Set(tokens.filter { token in
            titleLower.contains(token) || urlLower.contains(token) || snippetLower.contains(token)
        }).count) / Double(max(1, tokens.count))
        let exactPhraseBonus = (titleLower.contains(loweredQuery) || urlLower.contains(loweredQuery) || snippetLower.contains(loweredQuery)) ? 0.3 : 0
        let genericPenalty: Double = {
            let markers = ["/whats-new", "/news", "/blog", "what’s new", "what's new", "release notes"]
            let isGeneric = markers.contains { urlLower.contains($0) || titleLower.contains($0) }
            guard isGeneric else { return 0 }
            if tokenCoverage >= 0.75 { return 0.1 }
            if tokenCoverage >= 0.4 { return 0.25 }
            return 0.45
        }()
        let domainReusePenalty = Double(priorSelectionsForDomain) * 0.2
        let positionPenalty = Double(position) * 0.04
        return tokenCoverage + exactPhraseBonus - genericPenalty - domainReusePenalty - positionPenalty
    }

    private func estimatedTokenCount(for text: String) -> Int {
        max(1, text.count / 4)
    }

    private func compactConversationToolEvidence(toolName: String, result: String) -> String {
        guard toolName == "websearch" else {
            return ConversationMessage.toolResult(toolName: toolName, result: result).formatted
        }
        return compactWebsearchConversationResult(from: result)
    }

    private func buildStrict4kLivePrompt(
        from history: [ConversationMessage],
        maxTokens: Int,
        systemTokenLimit: Int
    ) async -> String {
        guard maxTokens > 0 else {
            return ""
        }

        let counter = PromptTokenBudgeting.counter()
        let fullPrompt = buildPrompt(from: history)
        if await PromptTokenBudgeting.countTokens(in: fullPrompt, using: counter) <= maxTokens {
            return fullPrompt
        }

        let systemMessage = history.first.flatMap { message -> ConversationMessage? in
            if case .system = message {
                return message
            }
            return nil
        }
        let systemText = if let systemMessage {
            await PromptTokenBudgeting.prefix(
                systemMessage.formatted,
                maxTokens: min(systemTokenLimit, maxTokens),
                using: counter
            )
        } else {
            ""
        }

        let separator = systemText.isEmpty ? "" : "\n\n"
        let systemAndSeparatorTokens = await PromptTokenBudgeting.countTokens(
            in: systemText + separator,
            using: counter
        )
        let tailBudget = max(maxTokens - systemAndSeparatorTokens, 0)
        let tailSource = systemMessage == nil ? history : Array(history.dropFirst())
        var selectedTail: [ConversationMessage] = []

        for message in tailSource.reversed() {
            let candidateTail = [message] + selectedTail
            let candidatePrompt = buildPrompt(from: candidateTail)
            if await PromptTokenBudgeting.countTokens(in: candidatePrompt, using: counter) <= tailBudget {
                selectedTail = candidateTail
            }
        }

        var tailPrompt = buildPrompt(from: selectedTail)
        let omittedCount = max(tailSource.count - selectedTail.count, 0)
        if omittedCount > 0 {
            let summaryMessage = ConversationMessage.assistant(
                "[summary: \(omittedCount) earlier messages omitted; rely on retrieved context for older details.]",
                toolCalls: []
            )
            let candidatePrompt = buildPrompt(from: [summaryMessage] + selectedTail)
            if await PromptTokenBudgeting.countTokens(in: candidatePrompt, using: counter) <= tailBudget {
                tailPrompt = candidatePrompt
            }
        }

        if systemText.isEmpty {
            return tailPrompt
        }
        if tailPrompt.isEmpty {
            return systemText
        }
        return systemText + separator + tailPrompt
    }

    // MARK: - Response Generation

    private func generateWithTools(
        provider: any InferenceProvider,
        prompt: String,
        messages: [InferenceMessage]?,
        tools: [ToolSchema],
        inferenceOptions: InferenceOptions,
        systemPrompt: String,
        observer: (any AgentObserver)? = nil,
        emitOutputTokens: Bool = false
    ) async throws -> InferenceResponse {
        var options = inferenceOptions
        options = optionsWithMembraneRuntimeSettings(options)

        // Notify observer of LLM start
        await observer?.onLLMStart(context: nil, agent: self, systemPrompt: systemPrompt, inputMessages: [MemoryMessage.user(prompt)])

        let response: InferenceResponse
        if let messages,
           let conversationProvider = provider as? any ConversationInferenceProvider {
            response = try await conversationProvider.generateWithToolCalls(
                messages: messages,
                tools: tools,
                options: options
            )
        } else {
            response = try await provider.generateWithToolCalls(
                prompt: prompt,
                tools: tools,
                options: options
            )
        }

        if emitOutputTokens, response.toolCalls.isEmpty, let content = response.content, !content.isEmpty {
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
        messages: [InferenceMessage]?,
        tools: [ToolSchema],
        inferenceOptions: InferenceOptions,
        systemPrompt: String,
        observer: (any AgentObserver)? = nil
    ) async throws -> InferenceResponse {
        var options = inferenceOptions
        options = optionsWithMembraneRuntimeSettings(options)

        await observer?.onLLMStart(context: nil, agent: self, systemPrompt: systemPrompt, inputMessages: [MemoryMessage.user(prompt)])

        var content = ""
        content.reserveCapacity(1024)
        var parsedToolCalls: [InferenceResponse.ParsedToolCall] = []
        var usage: TokenUsage?
        var stopStreaming = false

        let stream: AsyncThrowingStream<InferenceStreamUpdate, Error>
        if let messages,
           let structuredProvider = provider as? any ToolCallStreamingConversationInferenceProvider {
            stream = structuredProvider.streamWithToolCalls(
                messages: messages,
                tools: tools,
                options: options
            )
        } else if let promptProvider = provider as? any ToolCallStreamingInferenceProvider {
            stream = promptProvider.streamWithToolCalls(prompt: prompt, tools: tools, options: options)
        } else {
            throw AgentError.generationFailed(reason: "Provider does not support tool-call streaming")
        }

        for try await update in stream {
            switch update {
            case let .outputChunk(chunk):
                if !chunk.isEmpty { content += chunk }
                await observer?.onOutputToken(context: nil, agent: self, token: chunk)

            case let .toolCallPartial(partial):
                await observer?.onToolCallPartial(context: nil, agent: self, update: partial)

            case let .toolCallsCompleted(calls):
                parsedToolCalls = calls
                // Tool call streaming is primarily used to reduce latency to tool execution.
                // Once we have completed calls, stop consuming the stream and execute tools.
                stopStreaming = true

            case let .usage(u):
                usage = u
            }

            if stopStreaming { break }
        }

        await observer?.onLLMEnd(context: nil, agent: self, response: content, usage: usage)

        return InferenceResponse(
            content: content.isEmpty ? nil : content,
            toolCalls: parsedToolCalls,
            finishReason: parsedToolCalls.isEmpty ? .completed : .toolCall,
            usage: usage
        )
    }

    private func optionsWithMembraneRuntimeSettings(_ base: InferenceOptions) -> InferenceOptions {
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
        public func addTool(_ tool: some AnyJSONTool) -> Builder {
            var copy = self
            copy._tools.append(tool)
            return copy
        }

        /// Adds a tool from an existential (use when the concrete type is not available at the call site).
        /// - Parameter tool: The tool to add.
        /// - Returns: A new builder with the tool added.
        @discardableResult
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
    ///   - memory: Optional explicit memory override. Default: composite ContextCore + Wax memory
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
    ///   - memory: Optional explicit memory override. Default: composite ContextCore + Wax memory
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
    /// let agent = try Agent("You are helpful.", provider: .anthropic(key: apiKey)) {
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
    func withTools(_ tools: [any Tool]) -> Agent {
        var copy = self
        let bridged = tools.map { bridgeToolToAnyJSON($0) }
        copy.tools = bridged
        copy.toolRegistry = (try? ToolRegistry(tools: bridged)) ?? ToolRegistry()
        return copy
    }

    /// Replaces the tool set using a `@ToolBuilder` closure.
    @discardableResult
    func withTools(@ToolBuilder _ builder: () -> ToolCollection) -> Agent {
        var copy = self
        let storage = builder().storage
        copy.tools = storage
        copy.toolRegistry = (try? ToolRegistry(tools: storage)) ?? ToolRegistry()
        return copy
    }

    /// Sets the agent configuration.
    @discardableResult
    func withConfiguration(_ config: AgentConfiguration) -> Agent {
        var copy = self
        copy.configuration = config
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
