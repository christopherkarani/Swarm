// AgentV3.swift
// Swarm Framework
//
// V3 Agent — struct with ONE init, modifier chain, run()/stream() execution.
// Named AgentV3 during transition. Renamed to Agent in Phase 10.

import Foundation

/// An agent that executes tasks using LLM inference and tools.
///
/// Create agents with a single init — instructions are the only required parameter.
/// Configure via modifier chain. Execute via `run()` or `stream()`.
///
/// ```swift
/// // Minimal
/// let agent = AgentV3("You are a helpful assistant.")
///
/// // With tools
/// let agent = AgentV3("Research assistant") {
///     WebSearchTool()
///     CalculatorTool()
/// }
///
/// // Fully configured
/// let agent = AgentV3("Analyst", guardrails: [.maxInput(500)]) {
///     DataTool()
/// }
/// .provider(.anthropic(key: "..."))
/// .memory(.conversation(limit: 50))
/// .named("DataAnalyst")
///
/// // Execute
/// let result = try await agent.run("Analyze Q4 revenue")
/// ```
public struct AgentV3: Sendable {
    // MARK: - Public Properties

    /// The agent's display name. Default: "Agent"
    public let name: String

    /// System instructions defining agent behavior.
    public let instructions: String

    /// Tools available to this agent.
    public let tools: [any ToolV3]

    /// Guardrails for input/output validation.
    public let guardrails: [GuardrailV3]

    /// Inference provider. Nil = use default resolution.
    public let provider: (any InferenceProvider)?

    /// Memory configuration.
    public let memoryOption: MemoryOption

    /// Hooks for lifecycle events.
    public let hooks: (any RunHooks)?

    /// Tracer for execution tracing.
    public let tracer: (any Tracer)?

    // MARK: - ONE Init

    /// Creates an agent.
    ///
    /// Only `instructions` is required. Everything else defaults or is set via modifiers.
    ///
    /// - Parameters:
    ///   - instructions: System instructions defining agent behavior.
    ///   - guardrails: Validation guardrails. Default: none.
    ///   - tools: Tools available to this agent, built via @ToolBuilderV3 trailing closure.
    public init(
        _ instructions: String,
        guardrails: [GuardrailV3] = [],
        @ToolBuilderV3 tools: () -> [any ToolV3] = { [] }
    ) {
        self.name = "Agent"
        self.instructions = instructions
        self.tools = tools()
        self.guardrails = guardrails
        self.provider = nil
        self.memoryOption = .none
        self.hooks = nil
        self.tracer = nil
    }

    // MARK: - Private init for modifier chain

    private init(copying from: AgentV3,
                 name: String? = nil,
                 provider: (any InferenceProvider)? = nil,
                 memoryOption: MemoryOption? = nil,
                 hooks: (any RunHooks)? = nil,
                 tracer: (any Tracer)? = nil) {
        self.name = name ?? from.name
        self.instructions = from.instructions
        self.tools = from.tools
        self.guardrails = from.guardrails
        self.provider = provider ?? from.provider
        self.memoryOption = memoryOption ?? from.memoryOption
        self.hooks = hooks ?? from.hooks
        self.tracer = tracer ?? from.tracer
    }

    // MARK: - Modifiers

    /// Sets the agent's display name.
    public func named(_ name: String) -> AgentV3 {
        AgentV3(copying: self, name: name)
    }

    /// Sets the inference provider.
    ///
    /// ```swift
    /// agent.provider(.anthropic(key: "sk-..."))
    /// agent.provider(.openAI(key: "sk-..."))
    /// ```
    public func provider(_ provider: some InferenceProvider) -> AgentV3 {
        AgentV3(copying: self, provider: provider)
    }

    /// Sets the memory configuration.
    ///
    /// ```swift
    /// agent.memory(.conversation(limit: 50))
    /// agent.memory(.vector(dimensions: 384))
    /// ```
    public func memory(_ option: MemoryOption) -> AgentV3 {
        AgentV3(copying: self, memoryOption: option)
    }

    /// Sets lifecycle hooks.
    public func hooks(_ hooks: some RunHooks) -> AgentV3 {
        AgentV3(copying: self, hooks: hooks)
    }

    /// Sets the execution tracer.
    public func traced(by tracer: some Tracer) -> AgentV3 {
        AgentV3(copying: self, tracer: tracer)
    }
}

// MARK: - Execution

extension AgentV3 {
    /// Runs the agent to completion.
    ///
    /// ```swift
    /// let result = try await agent.run("What is 2+2?")
    /// print(result.output)  // "4"
    /// ```
    public func run(_ input: String, options: RunOptions = .default) async throws -> AgentResult {
        let legacyAgent = try buildLegacyAgent(options: options)
        return try await legacyAgent.run(input, session: nil, hooks: hooks)
    }

    /// Streams agent execution events.
    ///
    /// ```swift
    /// for try await event in agent.stream("Tell me a story") {
    ///     switch event {
    ///     case .progress(let text): print(text, terminator: "")
    ///     case .completed(let result): print("\nDone!")
    ///     default: break
    ///     }
    /// }
    /// ```
    public func stream(
        _ input: String,
        options: RunOptions = .default
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let legacyAgent = try self.buildLegacyAgent(options: options)
                    let eventStream = legacyAgent.stream(input, session: nil, hooks: self.hooks)
                    for try await event in eventStream {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private bridge

    /// Bridges V3 Agent to the existing Agent actor for execution.
    private func buildLegacyAgent(options: RunOptions) throws -> Agent {
        let bridgedTools: [any AnyJSONTool] = tools.map { $0.asAnyJSONTool() }
        let config = AgentConfiguration(
            name: name,
            maxIterations: options.maxIterations,
            timeout: options.timeout,
            temperature: options.temperature,
            maxTokens: options.maxTokens,
            enableStreaming: options.stream,
            parallelToolCalls: options.parallelTools
        )
        let resolvedMemory = memoryOption.resolve()

        return try Agent(
            tools: bridgedTools,
            instructions: instructions,
            configuration: config,
            memory: resolvedMemory,
            inferenceProvider: provider,
            tracer: tracer
        )
    }
}
