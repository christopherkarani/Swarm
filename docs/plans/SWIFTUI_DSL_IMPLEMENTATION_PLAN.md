# SwiftUI-Like Agent DSL Implementation Plan

## Overview

This document outlines the implementation plan for a SwiftUI-inspired declarative API for building and composing AI agents in SwiftAgents. The design creates a **novel approach to declarative agent development** that balances structure (for visible execution flow) with modifiers (for configuration).

### Design Principles

1. **Reading Order = Execution Order**: Code reads top-to-bottom like the actual execution flow
2. **Progressive Disclosure**: Simple agents are trivially simple; complexity scales naturally
3. **Structure for Flow, Modifiers for Config**: Use structure to show data flow, modifiers for behavior configuration
4. **Agents are Loops**: Embrace that agents are fundamentally while loops (think → act → observe)
5. **Type Safety**: Leverage Swift's type system for compile-time guarantees
6. **No Custom Operators**: Standard Swift syntax only for tooling compatibility

---

## Part 1: Core Protocols

### 1.1 Agent Protocol (User-Facing DSL)

The primary protocol that developers use to define agents:

```swift
// File: Sources/SwiftAgents/DSL/Core/Agent.swift

/// The primary protocol for declaratively defining agents.
///
/// `Agent` is the user-facing protocol for the DSL, inspired by SwiftUI's View.
/// Developers define agents by implementing the `body` property.
///
/// Example:
/// ```swift
/// struct GreeterAgent: Agent {
///     var body: some AgentBehavior {
///         Agent("You are a friendly greeter.")
///     }
/// }
/// ```
public protocol Agent: Sendable {
    /// The type of behavior this agent produces.
    associatedtype Body: AgentBehavior
    
    /// The body defining this agent's behavior.
    @AgentBuilder
    var body: Body { get }
}

// MARK: - Execution Extensions

extension Agent {
    /// Executes the agent with the given input.
    public func run(_ input: String) async throws -> AgentResult {
        let context = ExecutionContext(input: input)
        return try await body.execute(input, context: context)
    }
    
    /// Executes the agent with a session for conversation continuity.
    public func run(_ input: String, session: any Session) async throws -> AgentResult {
        let context = ExecutionContext(input: input, session: session)
        return try await body.execute(input, context: context)
    }
    
    /// Streams the agent's execution.
    public func stream(_ input: String) -> AsyncThrowingStream<AgentEvent, Error> {
        let context = ExecutionContext(input: input)
        return body.stream(input, context: context)
    }
    
    /// Generates an execution flow diagram for debugging/documentation.
    public var executionFlow: ExecutionFlowDiagram {
        body.buildFlowDiagram()
    }
}
```

### 1.2 AgentCore Protocol (Runtime Implementation)

The internal protocol for executable agent implementations (renamed from existing `Agent`):

```swift
// File: Sources/SwiftAgents/Core/AgentCore.swift

/// Internal protocol for executable agent implementations.
///
/// `AgentCore` is the runtime protocol that actual agent implementations
/// conform to. The DSL `Agent` protocol builds on top of this.
///
/// Note: Most users should use the `Agent` DSL protocol instead.
public protocol AgentCore: Sendable {
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
    nonisolated var inputGuardrails: [any InputGuardrail] { get }
    
    /// Output guardrails that validate agent responses before returning.
    nonisolated var outputGuardrails: [any OutputGuardrail] { get }
    
    /// Configured handoffs for this agent.
    nonisolated var handoffs: [AnyHandoffConfiguration] { get }
    
    /// Executes the agent with the given input.
    func run(_ input: String, session: (any Session)?, hooks: (any RunHooks)?) async throws -> AgentResult
    
    /// Streams the agent's execution.
    nonisolated func stream(_ input: String, session: (any Session)?, hooks: (any RunHooks)?) -> AsyncThrowingStream<AgentEvent, Error>
    
    /// Cancels any ongoing execution.
    func cancel() async
}
```

### 1.3 AgentBehavior Protocol

The protocol for agent behavior implementations:

```swift
// File: Sources/SwiftAgents/DSL/Core/AgentBehavior.swift

/// Protocol for agent behavior implementations.
///
/// `AgentBehavior` defines how an agent executes. Built-in implementations
/// include `AgentBody` (ReAct-style), `Chat`, `ToolCallingAgent`, and
/// workflow types like `Sequential`, `Router`, and `Parallel`.
public protocol AgentBehavior: Sendable {
    /// Executes the behavior with the given input.
    func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult
    
    /// Streams the behavior's execution.
    func stream(_ input: String, context: ExecutionContext) -> AsyncThrowingStream<AgentEvent, Error>
    
    /// Builds a flow diagram for visualization.
    func buildFlowDiagram() -> ExecutionFlowDiagram
}

// MARK: - Default Implementations

extension AgentBehavior {
    /// Default streaming implementation that wraps execute().
    public func stream(_ input: String, context: ExecutionContext) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.started(input: input))
                do {
                    let result = try await execute(input, context: context)
                    continuation.yield(.completed(result: result))
                    continuation.finish()
                } catch {
                    let agentError = (error as? AgentError) ?? .internalError(reason: error.localizedDescription)
                    continuation.yield(.failed(error: agentError))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Default flow diagram implementation.
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        ExecutionFlowDiagram(name: String(describing: Self.self), stages: [])
    }
}
```

### 1.4 ExecutionContext

Runtime context with type-safe storage:

```swift
// File: Sources/SwiftAgents/DSL/Core/ExecutionContext.swift

/// Type-safe context key protocol.
public protocol ContextKey {
    associatedtype Value: Sendable
    static var defaultValue: Value { get }
}

/// Runtime context for agent execution.
///
/// `ExecutionContext` carries configuration, session, and runtime state
/// through the agent execution graph with type-safe storage.
public actor ExecutionContext {
    /// The original input.
    public let input: String
    
    /// Optional session for conversation continuity.
    public let session: (any Session)?
    
    /// Execution ID for tracing.
    public let executionId: String
    
    /// Environment values inherited from parent context.
    public private(set) var environment: AgentEnvironment
    
    /// Type-safe storage.
    private var values: [ObjectIdentifier: any Sendable] = [:]
    
    /// Execution path for debugging.
    private var executionPath: [String] = []
    
    public init(
        input: String,
        session: (any Session)? = nil,
        environment: AgentEnvironment = AgentEnvironment()
    ) {
        self.input = input
        self.session = session
        self.executionId = UUID().uuidString
        self.environment = environment
    }
    
    /// Gets a typed value from context storage.
    public func value<K: ContextKey>(for key: K.Type) -> K.Value {
        values[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue
    }
    
    /// Sets a typed value in context storage.
    public func setValue<K: ContextKey>(_ value: K.Value, for key: K.Type) {
        values[ObjectIdentifier(key)] = value
    }
    
    /// Records an agent execution in the path.
    public func recordExecution(agentName: String) {
        executionPath.append(agentName)
    }
    
    /// Gets the current execution path.
    public var path: [String] {
        executionPath
    }
    
    /// Creates a child context with the same environment.
    public func childContext(input: String) -> ExecutionContext {
        ExecutionContext(input: input, session: session, environment: environment)
    }
}

// MARK: - Standard Context Keys

/// Key for storing previous agent output.
public struct PreviousOutputKey: ContextKey {
    public static var defaultValue: AgentResult? { nil }
}

/// Key for storing retrieved context (RAG).
public struct RetrievedContextKey: ContextKey {
    public static var defaultValue: [String] { [] }
}
```

### 1.5 AgentEnvironment

Environment system for configuration propagation:

```swift
// File: Sources/SwiftAgents/DSL/Core/AgentEnvironment.swift

/// Protocol for environment keys.
public protocol AgentEnvironmentKey {
    associatedtype Value: Sendable
    static var defaultValue: Value { get }
}

/// Environment values container for configuration propagation.
///
/// Similar to SwiftUI's Environment, this allows configuration to flow
/// down the agent hierarchy without explicit parameter passing.
public struct AgentEnvironment: Sendable {
    private var values: [ObjectIdentifier: any Sendable] = [:]
    
    public init() {}
    
    /// Gets an environment value.
    public subscript<K: AgentEnvironmentKey>(key: K.Type) -> K.Value {
        get { values[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue }
        set { values[ObjectIdentifier(key)] = newValue }
    }
}

// MARK: - Standard Environment Keys

/// Environment key for inference provider.
public struct InferenceProviderKey: AgentEnvironmentKey {
    public static var defaultValue: (any InferenceProvider)? { nil }
}

/// Environment key for tracer.
public struct TracerKey: AgentEnvironmentKey {
    public static var defaultValue: (any Tracer)? { nil }
}

/// Environment key for default memory configuration.
public struct DefaultMemoryKey: AgentEnvironmentKey {
    public static var defaultValue: MemoryConfiguration? { nil }
}

// MARK: - Environment KeyPath Extensions

extension AgentEnvironment {
    /// Inference provider.
    public var inferenceProvider: (any InferenceProvider)? {
        get { self[InferenceProviderKey.self] }
        set { self[InferenceProviderKey.self] = newValue }
    }
    
    /// Tracer.
    public var tracer: (any Tracer)? {
        get { self[TracerKey.self] }
        set { self[TracerKey.self] = newValue }
    }
}
```

---

## Part 2: Agent Behavior Types

### 2.1 AgentBody (Primary Agent Type)

The main agent behavior type (formerly `ReActAgent` in the DSL):

```swift
// File: Sources/SwiftAgents/DSL/Behaviors/AgentBody.swift

/// The primary agent behavior using ReAct-style reasoning.
///
/// `AgentBody` (accessed as `Agent` in the DSL) implements the think-act-observe
/// loop that is fundamental to agent behavior.
///
/// Example:
/// ```swift
/// Agent("You are a helpful assistant.") {
///     CalculatorTool()
///     WeatherTool()
/// }
/// ```
public struct AgentBody: AgentBehavior {
    private let instructions: String
    private let tools: [any AnyJSONTool]
    private let components: [AgentBodyComponent]
    
    /// Creates an agent with instructions only (no tools).
    public init(_ instructions: String) {
        self.instructions = instructions
        self.tools = []
        self.components = []
    }
    
    /// Creates an agent with instructions and tools.
    public init(_ instructions: String, @ToolBuilder tools: () -> [any AnyJSONTool]) {
        self.instructions = instructions
        self.tools = tools()
        self.components = []
    }
    
    /// Creates an agent with instructions and body components.
    public init(_ instructions: String, @AgentComponentBuilder components: () -> [AgentBodyComponent]) {
        self.instructions = instructions
        let built = components()
        self.tools = built.compactMap { ($0 as? ToolsComponent)?.tools }.flatMap { $0 }
        self.components = built
    }
    
    public func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult {
        // Extract configuration from components
        let memoryConfig = components.first { $0 is MemoryComponent } as? MemoryComponent
        let memory = memoryConfig?.build()
        
        // Get inference provider from environment
        let provider = await context.environment.inferenceProvider
        guard let provider else {
            throw AgentError.inferenceProviderUnavailable(
                reason: "No inference provider configured. Use .environment(\\.inferenceProvider, provider)"
            )
        }
        
        // Build and execute the underlying ReAct agent
        let agent = ReActAgent(
            tools: tools,
            instructions: instructions,
            memory: memory,
            inferenceProvider: provider,
            tracer: await context.environment.tracer
        )
        
        return try await agent.run(input, session: context.session, hooks: nil)
    }
    
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        var stages: [FlowStage] = []
        stages.append(.agent(name: "Agent", tools: tools.map(\.name)))
        return ExecutionFlowDiagram(name: "Agent", stages: stages)
    }
}

// MARK: - Convenience Typealiases

/// `Agent` is the primary behavior type for DSL usage.
/// This typealias allows writing `Agent("...")` instead of `AgentBody("...")`.
public typealias Agent = AgentBody
```

### 2.2 Chat Behavior

Simple chat behavior without tools:

```swift
// File: Sources/SwiftAgents/DSL/Behaviors/ChatBehavior.swift

/// Simple chat behavior without tool calling.
///
/// Use for straightforward Q&A or conversation agents.
///
/// Example:
/// ```swift
/// Chat("You are a friendly greeter.")
/// ```
public struct Chat: AgentBehavior {
    private let instructions: String
    
    public init(_ instructions: String) {
        self.instructions = instructions
    }
    
    public func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult {
        let provider = await context.environment.inferenceProvider
        guard let provider else {
            throw AgentError.inferenceProviderUnavailable(
                reason: "No inference provider configured"
            )
        }
        
        let prompt = buildPrompt(input: input)
        let output = try await provider.generate(prompt: prompt, options: .default)
        
        return AgentResult(output: output)
    }
    
    private func buildPrompt(input: String) -> String {
        """
        \(instructions)
        
        User: \(input)
        """
    }
    
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        ExecutionFlowDiagram(name: "Chat", stages: [.chat(instructions: instructions)])
    }
}
```

### 2.3 ToolCallingAgent Behavior

Agent focused on tool calling without ReAct reasoning:

```swift
// File: Sources/SwiftAgents/DSL/Behaviors/ToolCallingBehavior.swift

/// Tool-calling agent that uses native LLM tool calling.
///
/// Unlike `Agent` (ReAct-style), this uses the model's built-in
/// tool calling capabilities without explicit reasoning steps.
public struct ToolCallingAgent: AgentBehavior {
    private let instructions: String
    private let tools: [any AnyJSONTool]
    
    public init(_ instructions: String, @ToolBuilder tools: () -> [any AnyJSONTool]) {
        self.instructions = instructions
        self.tools = tools()
    }
    
    public func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult {
        let provider = await context.environment.inferenceProvider
        guard let provider else {
            throw AgentError.inferenceProviderUnavailable(reason: "No inference provider configured")
        }
        
        let agent = SwiftAgents.ToolCallingAgent(
            tools: tools,
            instructions: instructions,
            inferenceProvider: provider
        )
        
        return try await agent.run(input, session: context.session, hooks: nil)
    }
    
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        ExecutionFlowDiagram(name: "ToolCallingAgent", stages: [
            .agent(name: "ToolCallingAgent", tools: tools.map(\.name))
        ])
    }
}
```

### 2.4 Planner Behavior

Plan-and-execute agent:

```swift
// File: Sources/SwiftAgents/DSL/Behaviors/PlannerBehavior.swift

/// Plan-and-execute agent that creates a plan before execution.
///
/// Useful for complex, multi-step tasks that benefit from upfront planning.
public struct Planner: AgentBehavior {
    private let instructions: String
    private let tools: [any AnyJSONTool]
    
    public init(_ instructions: String, @ToolBuilder tools: () -> [any AnyJSONTool]) {
        self.instructions = instructions
        self.tools = tools()
    }
    
    public func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult {
        let provider = await context.environment.inferenceProvider
        guard let provider else {
            throw AgentError.inferenceProviderUnavailable(reason: "No inference provider configured")
        }
        
        let agent = PlanAndExecuteAgent(
            tools: tools,
            instructions: instructions,
            inferenceProvider: provider
        )
        
        return try await agent.run(input, session: context.session, hooks: nil)
    }
    
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        ExecutionFlowDiagram(name: "Planner", stages: [
            .planning,
            .agent(name: "Executor", tools: tools.map(\.name))
        ])
    }
}
```

---

## Part 3: Flow Control Structures

### 3.1 Guard Component

Input and output validation:

```swift
// File: Sources/SwiftAgents/DSL/Flow/Guard.swift

/// Specifies whether a guard applies to input or output.
public enum GuardPhase: Sendable {
    case input
    case output
}

/// Validates input or output with guardrails.
///
/// Guards are structural elements that show validation in the execution flow.
///
/// Example:
/// ```swift
/// Guard(.input) {
///     ContentFilter()
///     RateLimiter(rpm: 60)
/// }
/// ```
public struct Guard: AgentBehavior {
    private let phase: GuardPhase
    private let guardrails: [any Guardrail]
    
    public init(_ phase: GuardPhase, @GuardrailBuilder guardrails: () -> [any Guardrail]) {
        self.phase = phase
        self.guardrails = guardrails()
    }
    
    public func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult {
        // Guards don't transform, they validate and pass through
        let runner = GuardrailRunner()
        
        switch phase {
        case .input:
            for guardrail in guardrails {
                if let inputGuardrail = guardrail as? any InputGuardrail {
                    let result = try await inputGuardrail.validate(input: input)
                    if !result.passed {
                        throw GuardrailError.inputTripwireTriggered(
                            guardrail: String(describing: type(of: guardrail)),
                            message: result.message ?? "Input validation failed"
                        )
                    }
                }
            }
        case .output:
            // Output guards are applied after the main agent runs
            // This is handled by the pipeline
            break
        }
        
        // Pass through - actual processing happens in the pipeline
        return AgentResult(output: input)
    }
    
    /// Returns the guardrails for pipeline integration.
    public var inputGuardrails: [any InputGuardrail] {
        phase == .input ? guardrails.compactMap { $0 as? any InputGuardrail } : []
    }
    
    public var outputGuardrails: [any OutputGuardrail] {
        phase == .output ? guardrails.compactMap { $0 as? any OutputGuardrail } : []
    }
    
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        let names = guardrails.map { String(describing: type(of: $0)) }
        return ExecutionFlowDiagram(name: "Guard(\(phase))", stages: [
            .guard(phase: phase, guardrails: names)
        ])
    }
}

// MARK: - Guardrail Protocol

/// Base protocol for all guardrails.
public protocol Guardrail: Sendable {}

// MARK: - GuardrailBuilder

@resultBuilder
public struct GuardrailBuilder {
    public static func buildBlock(_ guardrails: any Guardrail...) -> [any Guardrail] {
        guardrails
    }
    
    public static func buildOptional(_ guardrail: (any Guardrail)?) -> [any Guardrail] {
        guardrail.map { [$0] } ?? []
    }
    
    public static func buildEither(first guardrail: any Guardrail) -> [any Guardrail] {
        [guardrail]
    }
    
    public static func buildEither(second guardrail: any Guardrail) -> [any Guardrail] {
        [guardrail]
    }
    
    public static func buildArray(_ guardrails: [[any Guardrail]]) -> [any Guardrail] {
        guardrails.flatMap { $0 }
    }
}
```

### 3.2 Transform Component

Input/output transformation:

```swift
// File: Sources/SwiftAgents/DSL/Flow/Transform.swift

/// Specifies whether a transform applies to input or output.
public enum TransformPhase: Sendable {
    case input
    case output
}

/// Transforms input or output data.
///
/// Example:
/// ```swift
/// Transform(.input) { input in
///     input.lowercased().trimmingCharacters(in: .whitespace)
/// }
/// ```
public struct Transform: AgentBehavior {
    private let phase: TransformPhase
    private let transform: @Sendable (String) async throws -> String
    
    public init(_ phase: TransformPhase, _ transform: @escaping @Sendable (String) async throws -> String) {
        self.phase = phase
        self.transform = transform
    }
    
    public func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult {
        let output = try await transform(input)
        return AgentResult(output: output)
    }
    
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        ExecutionFlowDiagram(name: "Transform(\(phase))", stages: [
            .transform(phase: phase)
        ])
    }
}
```

### 3.3 Sequential Workflow

Executes agents in sequence:

```swift
// File: Sources/SwiftAgents/DSL/Flow/Sequential.swift

/// Sequential agent execution pipeline.
///
/// Executes agents in order, passing each output as input to the next.
///
/// Example:
/// ```swift
/// Sequential {
///     ClassifierAgent()
///     ProcessorAgent()
///     FormatterAgent()
/// }
/// ```
public struct Sequential: AgentBehavior {
    private let agents: [any Agent]
    
    public init(@AgentSequenceBuilder _ content: () -> [any Agent]) {
        self.agents = content()
    }
    
    public func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult {
        var currentInput = input
        var allToolCalls: [ToolCall] = []
        var allToolResults: [ToolResult] = []
        var totalIterations = 0
        let startTime = ContinuousClock.now
        
        for agent in agents {
            let childContext = await context.childContext(input: currentInput)
            let result = try await agent.body.execute(currentInput, context: childContext)
            
            allToolCalls.append(contentsOf: result.toolCalls)
            allToolResults.append(contentsOf: result.toolResults)
            totalIterations += result.iterationCount
            
            currentInput = result.output
        }
        
        return AgentResult(
            output: currentInput,
            toolCalls: allToolCalls,
            toolResults: allToolResults,
            iterationCount: totalIterations,
            duration: ContinuousClock.now - startTime
        )
    }
    
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        let stages = agents.map { FlowStage.subAgent(name: String(describing: type(of: $0))) }
        return ExecutionFlowDiagram(name: "Sequential", stages: stages)
    }
}

// MARK: - AgentSequenceBuilder

@resultBuilder
public struct AgentSequenceBuilder {
    public static func buildBlock(_ agents: any Agent...) -> [any Agent] {
        agents
    }
    
    public static func buildOptional(_ agent: (any Agent)?) -> [any Agent] {
        agent.map { [$0] } ?? []
    }
    
    public static func buildEither(first agent: any Agent) -> [any Agent] {
        [agent]
    }
    
    public static func buildEither(second agent: any Agent) -> [any Agent] {
        [agent]
    }
    
    public static func buildArray(_ agents: [[any Agent]]) -> [any Agent] {
        agents.flatMap { $0 }
    }
}
```

### 3.4 Parallel Workflow

Executes agents concurrently:

```swift
// File: Sources/SwiftAgents/DSL/Flow/Parallel.swift

/// Merge strategy for parallel execution results.
public enum MergeStrategy: Sendable {
    /// Concatenate outputs with labels.
    case concatenate
    /// Format as structured sections.
    case structured
    /// Return only the first result.
    case first
    /// Return the longest output.
    case longest
    /// Custom merge function.
    case custom(@Sendable ([(String, AgentResult)]) -> String)
}

/// Parallel agent execution.
///
/// Runs multiple agents concurrently and merges their results.
///
/// Example:
/// ```swift
/// Parallel(merge: .structured) {
///     SentimentAgent().as("sentiment")
///     SummaryAgent().as("summary")
/// }
/// ```
public struct Parallel: AgentBehavior {
    private let agents: [(String, any Agent)]
    private let strategy: MergeStrategy
    
    public init(merge strategy: MergeStrategy = .concatenate, @ParallelAgentBuilder _ content: () -> [(String, any Agent)]) {
        self.strategy = strategy
        self.agents = content()
    }
    
    public func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult {
        let startTime = ContinuousClock.now
        
        let results = try await withThrowingTaskGroup(of: (String, AgentResult).self) { group in
            for (name, agent) in agents {
                group.addTask {
                    let childContext = await context.childContext(input: input)
                    let result = try await agent.body.execute(input, context: childContext)
                    return (name, result)
                }
            }
            
            var collected: [(String, AgentResult)] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }
        
        let output = mergeResults(results)
        
        return AgentResult(
            output: output,
            toolCalls: results.flatMap { $0.1.toolCalls },
            toolResults: results.flatMap { $0.1.toolResults },
            iterationCount: results.map { $0.1.iterationCount }.reduce(0, +),
            duration: ContinuousClock.now - startTime
        )
    }
    
    private func mergeResults(_ results: [(String, AgentResult)]) -> String {
        switch strategy {
        case .concatenate:
            return results.map { "\($0.0): \($0.1.output)" }.joined(separator: "\n\n")
        case .structured:
            return results.map { "## \($0.0)\n\n\($0.1.output)" }.joined(separator: "\n\n")
        case .first:
            return results.first?.1.output ?? ""
        case .longest:
            return results.max { $0.1.output.count < $1.1.output.count }?.1.output ?? ""
        case .custom(let merger):
            return merger(results)
        }
    }
    
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        let branches = agents.map { ($0.0, $0.1.body.buildFlowDiagram()) }
        return ExecutionFlowDiagram(name: "Parallel", stages: [.parallel(branches: branches)])
    }
}

// MARK: - Named Agent Extension

extension Agent {
    /// Names this agent for parallel execution result labeling.
    public func `as`(_ name: String) -> (String, any Agent) {
        (name, self)
    }
}

// MARK: - ParallelAgentBuilder

@resultBuilder
public struct ParallelAgentBuilder {
    public static func buildBlock(_ agents: (String, any Agent)...) -> [(String, any Agent)] {
        agents
    }
    
    public static func buildArray(_ agents: [[(String, any Agent)]]) -> [(String, any Agent)] {
        agents.flatMap { $0 }
    }
}
```

### 3.5 Route Workflow

Conditional routing to different agents:

```swift
// File: Sources/SwiftAgents/DSL/Flow/Route.swift

/// How routing decisions are made.
public enum RoutingStrategy<Key: Hashable & Sendable>: Sendable {
    /// Rule-based: Deterministic conditions evaluated in order.
    case rules
    
    /// LLM-based: Language model classifies intent.
    case llm(classifier: any IntentClassifier<Key>)
    
    /// Semantic: Embedding similarity matching.
    case semantic(embedder: any EmbeddingProvider, threshold: Double = 0.8)
    
    /// Custom: User-provided routing function.
    case custom(@Sendable (String, ExecutionContext) async throws -> Key)
}

/// Conditional routing to different agents.
///
/// Routes input to different agents based on a routing strategy.
///
/// Example:
/// ```swift
/// Route(using: .llm(IntentClassifier())) {
///     When(.billing, use: BillingAgent())
///     When(.technical, use: TechnicalAgent())
///     Otherwise(use: GeneralAgent())
/// }
/// ```
public struct Route<Key: Hashable & Sendable>: AgentBehavior {
    private let strategy: RoutingStrategy<Key>
    private let routes: [Key: any Agent]
    private let defaultAgent: (any Agent)?
    private let ruleConditions: [(Key, RouteCondition)]
    
    public init(
        using strategy: RoutingStrategy<Key>,
        @RouteBuilder<Key> _ content: () -> RouteContent<Key>
    ) {
        self.strategy = strategy
        let built = content()
        self.routes = built.routes
        self.defaultAgent = built.defaultAgent
        self.ruleConditions = built.ruleConditions
    }
    
    public func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult {
        let key = try await resolveRoute(input: input, context: context)
        
        if let agent = routes[key] {
            await context.recordExecution(agentName: String(describing: key))
            let childContext = await context.childContext(input: input)
            return try await agent.body.execute(input, context: childContext)
        }
        
        if let defaultAgent {
            await context.recordExecution(agentName: "Default")
            let childContext = await context.childContext(input: input)
            return try await defaultAgent.body.execute(input, context: childContext)
        }
        
        throw OrchestrationError.routingFailed(reason: "No route matched for key: \(key)")
    }
    
    private func resolveRoute(input: String, context: ExecutionContext) async throws -> Key {
        switch strategy {
        case .rules:
            for (key, condition) in ruleConditions {
                if await condition.matches(input: input, context: nil) {
                    return key
                }
            }
            throw OrchestrationError.routingFailed(reason: "No rule matched")
            
        case .llm(let classifier):
            return try await classifier.classify(input)
            
        case .semantic(let embedder, let threshold):
            // Implementation would use embedder to find closest match
            throw OrchestrationError.routingFailed(reason: "Semantic routing not yet implemented")
            
        case .custom(let resolver):
            return try await resolver(input, context)
        }
    }
    
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        let routeNames = routes.map { (String(describing: $0.key), $0.value.body.buildFlowDiagram()) }
        let strategyName: String
        switch strategy {
        case .rules: strategyName = "Rules"
        case .llm: strategyName = "LLM"
        case .semantic: strategyName = "Semantic"
        case .custom: strategyName = "Custom"
        }
        return ExecutionFlowDiagram(name: "Route(\(strategyName))", stages: [
            .route(strategy: strategyName, branches: routeNames)
        ])
    }
}

// MARK: - Route Cases

/// Defines a route case.
public struct When<Key: Hashable & Sendable>: Sendable {
    public let key: Key
    public let agent: any Agent
    public let condition: RouteCondition?
    
    /// LLM-based routing case.
    public init(_ key: Key, use agent: any Agent) {
        self.key = key
        self.agent = agent
        self.condition = nil
    }
    
    /// Rule-based routing case with condition.
    public init(_ key: Key, matching condition: RouteCondition, use agent: any Agent) {
        self.key = key
        self.agent = agent
        self.condition = condition
    }
}

/// Defines the default route.
public struct Otherwise<Key: Hashable & Sendable>: Sendable {
    public let agent: any Agent
    
    public init(use agent: any Agent) {
        self.agent = agent
    }
}

/// Container for built route content.
public struct RouteContent<Key: Hashable & Sendable>: Sendable {
    public var routes: [Key: any Agent] = [:]
    public var defaultAgent: (any Agent)?
    public var ruleConditions: [(Key, RouteCondition)] = []
}

// MARK: - RouteBuilder

@resultBuilder
public struct RouteBuilder<Key: Hashable & Sendable> {
    public static func buildBlock(_ components: Any...) -> RouteContent<Key> {
        var content = RouteContent<Key>()
        for component in components {
            if let when = component as? When<Key> {
                content.routes[when.key] = when.agent
                if let condition = when.condition {
                    content.ruleConditions.append((when.key, condition))
                }
            } else if let otherwise = component as? Otherwise<Key> {
                content.defaultAgent = otherwise.agent
            }
        }
        return content
    }
}

// MARK: - IntentClassifier Protocol

/// Protocol for LLM-based intent classification.
public protocol IntentClassifier<Key>: Sendable {
    associatedtype Key: Hashable & Sendable
    func classify(_ input: String) async throws -> Key
}

// MARK: - RouteCondition

/// Conditions for rule-based routing.
public struct RouteCondition: Sendable {
    private let matcher: @Sendable (String) async -> Bool
    
    public init(_ matcher: @escaping @Sendable (String) async -> Bool) {
        self.matcher = matcher
    }
    
    /// Matches if input contains the substring.
    public static func contains(_ substring: String) -> RouteCondition {
        RouteCondition { $0.localizedCaseInsensitiveContains(substring) }
    }
    
    /// Matches if input matches the regex.
    public static func matches(regex: String) -> RouteCondition {
        RouteCondition { input in
            (try? Regex(regex).firstMatch(in: input)) != nil
        }
    }
    
    /// Matches if input starts with the prefix.
    public static func hasPrefix(_ prefix: String) -> RouteCondition {
        RouteCondition { $0.hasPrefix(prefix) }
    }
    
    public func matches(input: String, context: AgentContext?) async -> Bool {
        await matcher(input)
    }
}
```

---

## Part 4: Body Components

### 4.1 Component Protocol and Semantics

```swift
// File: Sources/SwiftAgents/DSL/Components/AgentBodyComponent.swift

/// Protocol for components that can appear in an agent body.
public protocol AgentBodyComponent: Sendable {}

/// Marker for components that can only appear once.
public protocol SingularComponent: AgentBodyComponent {}

/// Content composed of multiple components.
public struct ComposedBodyContent: Sendable {
    public let components: [AgentBodyComponent]
    
    public init(components: [AgentBodyComponent]) {
        // Validate singular components
        validateSingularComponents(components)
        self.components = components
    }
    
    /// Extracts all components of a specific type.
    public func extract<T: AgentBodyComponent>(_ type: T.Type) -> [T] {
        components.compactMap { $0 as? T }
    }
    
    /// Extracts the first component of a specific type.
    public func first<T: AgentBodyComponent>(_ type: T.Type) -> T? {
        components.first { $0 is T } as? T
    }
}

// MARK: - Component Validation

private func validateSingularComponents(_ components: [AgentBodyComponent]) {
    // Memory: Error if more than one
    let memoryCount = components.filter { $0 is MemoryComponent }.count
    precondition(
        memoryCount <= 1,
        """
        Agent body contains \(memoryCount) Memory components. Only one Memory is allowed.
        Use Memory(.hybrid([...])) to combine multiple memory strategies.
        """
    )
}

// MARK: - Component Semantics Documentation
/*
 Component Duplicate Behavior:
 
 | Component   | Behavior    | Rationale                           |
 |-------------|-------------|-------------------------------------|
 | Memory      | Error       | Agent has one memory system         |
 | Tools       | Merge       | Combining tool sets is valid        |
 | Guardrails  | Merge       | Multiple guardrails stack           |
 | Handoffs    | Merge       | Multiple handoff targets allowed    |
 */
```

### 4.2 Memory Component

```swift
// File: Sources/SwiftAgents/DSL/Components/MemoryComponent.swift

/// Memory configuration for agents.
///
/// Memory is a singular component - only one can appear per agent.
/// Use `.hybrid()` to combine multiple memory strategies.
///
/// Example:
/// ```swift
/// Agent("...") {
///     Memory(.conversation(limit: 100))
/// }
/// ```
public struct MemoryComponent: AgentBodyComponent, SingularComponent {
    public let configuration: MemoryConfiguration
    
    public init(_ configuration: MemoryConfiguration) {
        self.configuration = configuration
    }
    
    /// Builds the actual memory instance.
    public func build() -> any Memory {
        configuration.build()
    }
}

/// Memory configuration options.
public enum MemoryConfiguration: Sendable {
    /// Conversation memory with message limit.
    case conversation(limit: Int = 100)
    
    /// Sliding window memory.
    case sliding(window: Int)
    
    /// Vector-based semantic memory.
    case vector(provider: any EmbeddingProvider, limit: Int = 10)
    
    /// Summary-based compressed memory.
    case summary(summarizer: any Summarizer)
    
    /// Hybrid combining multiple strategies.
    case hybrid([MemoryConfiguration])
    
    /// Custom memory implementation.
    case custom(any Memory)
    
    func build() -> any Memory {
        switch self {
        case .conversation(let limit):
            return ConversationMemory(maxMessages: limit)
        case .sliding(let window):
            return SlidingWindowMemory(windowSize: window)
        case .vector(let provider, let limit):
            return VectorMemory(embeddingProvider: provider, retrievalLimit: limit)
        case .summary(let summarizer):
            return SummaryMemory(summarizer: summarizer)
        case .hybrid(let configs):
            let memories = configs.map { $0.build() }
            return HybridMemory(memories: memories)
        case .custom(let memory):
            return memory
        }
    }
}

// MARK: - Convenience for DSL

/// Shorthand for Memory component creation.
public func Memory(_ configuration: MemoryConfiguration) -> MemoryComponent {
    MemoryComponent(configuration)
}
```

### 4.3 Tools Component

```swift
// File: Sources/SwiftAgents/DSL/Components/ToolsComponent.swift

/// Tools configuration for agents.
///
/// Multiple Tools components are merged together.
///
/// Example:
/// ```swift
/// Agent("...") {
///     Tools {
///         CalculatorTool()
///         WeatherTool()
///     }
/// }
/// ```
public struct ToolsComponent: AgentBodyComponent {
    public let tools: [any AnyJSONTool]
    
    public init(@ToolBuilder _ content: () -> [any AnyJSONTool]) {
        self.tools = content()
    }
    
    public init(_ tools: [any AnyJSONTool]) {
        self.tools = tools
    }
}

// MARK: - ToolBuilder

@resultBuilder
public struct ToolBuilder {
    public static func buildBlock(_ tools: any AnyJSONTool...) -> [any AnyJSONTool] {
        tools
    }
    
    public static func buildOptional(_ tool: (any AnyJSONTool)?) -> [any AnyJSONTool] {
        tool.map { [$0] } ?? []
    }
    
    public static func buildEither(first tool: any AnyJSONTool) -> [any AnyJSONTool] {
        [tool]
    }
    
    public static func buildEither(second tool: any AnyJSONTool) -> [any AnyJSONTool] {
        [tool]
    }
    
    public static func buildArray(_ tools: [[any AnyJSONTool]]) -> [any AnyJSONTool] {
        tools.flatMap { $0 }
    }
}

// MARK: - Convenience

/// Shorthand for Tools component creation.
public func Tools(@ToolBuilder _ content: () -> [any AnyJSONTool]) -> ToolsComponent {
    ToolsComponent(content)
}
```

---

## Part 5: Modifiers

### 5.1 Modifier Protocol

```swift
// File: Sources/SwiftAgents/DSL/Modifiers/AgentModifier.swift

/// Protocol for agent behavior modifiers.
///
/// Modifiers wrap behavior to add cross-cutting concerns like
/// retry, timeout, and observability.
public protocol AgentModifier: Sendable {
    func modify<B: AgentBehavior>(_ behavior: B) -> ModifiedBehavior<B, Self>
}

/// A behavior wrapped with a modifier.
public struct ModifiedBehavior<Base: AgentBehavior, Modifier: AgentModifier>: AgentBehavior {
    public let base: Base
    public let modifier: Modifier
    
    public func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult {
        // Modifier-specific execution is implemented by each modifier
        try await base.execute(input, context: context)
    }
    
    public func stream(_ input: String, context: ExecutionContext) -> AsyncThrowingStream<AgentEvent, Error> {
        base.stream(input, context: context)
    }
    
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        var diagram = base.buildFlowDiagram()
        diagram.modifiers.append(String(describing: Modifier.self))
        return diagram
    }
}
```

### 5.2 Memory Modifier

```swift
// File: Sources/SwiftAgents/DSL/Modifiers/MemoryModifier.swift

extension AgentBehavior {
    /// Adds memory to the agent.
    public func memory(_ configuration: MemoryConfiguration) -> MemoryModifiedBehavior<Self> {
        MemoryModifiedBehavior(base: self, memory: configuration)
    }
}

public struct MemoryModifiedBehavior<Base: AgentBehavior>: AgentBehavior {
    let base: Base
    let memory: MemoryConfiguration
    
    public func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult {
        // Memory is injected into the execution context
        // The actual agent behavior accesses it from there
        try await base.execute(input, context: context)
    }
    
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        var diagram = base.buildFlowDiagram()
        diagram.modifiers.append("memory(\(memory))")
        return diagram
    }
}
```

### 5.3 Retry Modifier

```swift
// File: Sources/SwiftAgents/DSL/Modifiers/RetryModifier.swift

extension AgentBehavior {
    /// Adds retry behavior.
    public func retry(_ policy: RetryPolicy) -> RetryModifiedBehavior<Self> {
        RetryModifiedBehavior(base: self, policy: policy)
    }
}

public struct RetryModifiedBehavior<Base: AgentBehavior>: AgentBehavior {
    let base: Base
    let policy: RetryPolicy
    
    public func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult {
        try await policy.execute {
            try await base.execute(input, context: context)
        }
    }
    
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        var diagram = base.buildFlowDiagram()
        diagram.modifiers.append("retry(\(policy))")
        return diagram
    }
}
```

### 5.4 Timeout Modifier

```swift
// File: Sources/SwiftAgents/DSL/Modifiers/TimeoutModifier.swift

extension AgentBehavior {
    /// Adds timeout.
    public func timeout(_ duration: Duration) -> TimeoutModifiedBehavior<Self> {
        TimeoutModifiedBehavior(base: self, duration: duration)
    }
}

public struct TimeoutModifiedBehavior<Base: AgentBehavior>: AgentBehavior {
    let base: Base
    let duration: Duration
    
    public func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult {
        try await withThrowingTaskGroup(of: AgentResult.self) { group in
            group.addTask {
                try await base.execute(input, context: context)
            }
            
            group.addTask {
                try await Task.sleep(for: duration)
                throw AgentError.timeout(duration: duration)
            }
            
            guard let result = try await group.next() else {
                throw AgentError.timeout(duration: duration)
            }
            
            group.cancelAll()
            return result
        }
    }
    
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        var diagram = base.buildFlowDiagram()
        diagram.modifiers.append("timeout(\(duration))")
        return diagram
    }
}
```

### 5.5 Environment Modifier

```swift
// File: Sources/SwiftAgents/DSL/Modifiers/EnvironmentModifier.swift

extension AgentBehavior {
    /// Sets an environment value.
    public func environment<V>(
        _ keyPath: WritableKeyPath<AgentEnvironment, V>,
        _ value: V
    ) -> EnvironmentModifiedBehavior<Self> {
        EnvironmentModifiedBehavior(base: self, keyPath: keyPath, value: value)
    }
}

public struct EnvironmentModifiedBehavior<Base: AgentBehavior>: AgentBehavior {
    let base: Base
    let modification: @Sendable (inout AgentEnvironment) -> Void
    
    init<V>(base: Base, keyPath: WritableKeyPath<AgentEnvironment, V>, value: V) {
        self.base = base
        self.modification = { env in
            env[keyPath: keyPath] = value
        }
    }
    
    public func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult {
        // Apply environment modification to context
        await context.modifyEnvironment(modification)
        return try await base.execute(input, context: context)
    }
    
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        var diagram = base.buildFlowDiagram()
        diagram.modifiers.append("environment(...)")
        return diagram
    }
}

extension ExecutionContext {
    func modifyEnvironment(_ modification: @Sendable (inout AgentEnvironment) -> Void) {
        modification(&environment)
    }
}
```

### 5.6 Tracing Modifier

```swift
// File: Sources/SwiftAgents/DSL/Modifiers/TracingModifier.swift

extension AgentBehavior {
    /// Enables tracing for this behavior.
    public func traced(_ operationName: String? = nil) -> TracingModifiedBehavior<Self> {
        TracingModifiedBehavior(base: self, operationName: operationName)
    }
}

public struct TracingModifiedBehavior<Base: AgentBehavior>: AgentBehavior {
    let base: Base
    let operationName: String?
    
    public func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult {
        let tracer = await context.environment.tracer
        let name = operationName ?? String(describing: Base.self)
        
        await tracer?.traceAgentStart(name: name, input: input)
        
        do {
            let result = try await base.execute(input, context: context)
            await tracer?.traceAgentEnd(name: name, output: result.output)
            return result
        } catch {
            await tracer?.traceAgentError(name: name, error: error)
            throw error
        }
    }
    
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        var diagram = base.buildFlowDiagram()
        diagram.modifiers.append("traced")
        return diagram
    }
}
```

---

## Part 6: Result Builders

### 6.1 AgentBuilder

```swift
// File: Sources/SwiftAgents/DSL/Builders/AgentBuilder.swift

/// Result builder for agent body content.
@resultBuilder
public struct AgentBuilder {
    // Single behavior
    public static func buildBlock<B: AgentBehavior>(_ behavior: B) -> B {
        behavior
    }
    
    // Multiple behaviors become a pipeline
    public static func buildBlock(_ behaviors: any AgentBehavior...) -> PipelineBehavior {
        PipelineBehavior(behaviors: behaviors)
    }
    
    // Optional behavior
    public static func buildOptional<B: AgentBehavior>(_ behavior: B?) -> OptionalBehavior<B> {
        OptionalBehavior(behavior: behavior)
    }
    
    // Conditional - first branch
    public static func buildEither<First: AgentBehavior, Second: AgentBehavior>(
        first behavior: First
    ) -> EitherBehavior<First, Second> {
        .first(behavior)
    }
    
    // Conditional - second branch
    public static func buildEither<First: AgentBehavior, Second: AgentBehavior>(
        second behavior: Second
    ) -> EitherBehavior<First, Second> {
        .second(behavior)
    }
}

/// Pipeline of behaviors executed sequentially.
public struct PipelineBehavior: AgentBehavior {
    let behaviors: [any AgentBehavior]
    
    public func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult {
        var currentInput = input
        var lastResult: AgentResult?
        
        for behavior in behaviors {
            let result = try await behavior.execute(currentInput, context: context)
            currentInput = result.output
            lastResult = result
        }
        
        return lastResult ?? AgentResult(output: input)
    }
    
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        let stages = behaviors.flatMap { $0.buildFlowDiagram().stages }
        return ExecutionFlowDiagram(name: "Pipeline", stages: stages)
    }
}

/// Optional behavior wrapper.
public struct OptionalBehavior<Wrapped: AgentBehavior>: AgentBehavior {
    let behavior: Wrapped?
    
    public func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult {
        if let behavior {
            return try await behavior.execute(input, context: context)
        }
        return AgentResult(output: input)
    }
    
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        behavior?.buildFlowDiagram() ?? ExecutionFlowDiagram(name: "Empty", stages: [])
    }
}

/// Either behavior wrapper.
public enum EitherBehavior<First: AgentBehavior, Second: AgentBehavior>: AgentBehavior {
    case first(First)
    case second(Second)
    
    public func execute(_ input: String, context: ExecutionContext) async throws -> AgentResult {
        switch self {
        case .first(let behavior):
            return try await behavior.execute(input, context: context)
        case .second(let behavior):
            return try await behavior.execute(input, context: context)
        }
    }
    
    public func buildFlowDiagram() -> ExecutionFlowDiagram {
        switch self {
        case .first(let behavior):
            return behavior.buildFlowDiagram()
        case .second(let behavior):
            return behavior.buildFlowDiagram()
        }
    }
}
```

### 6.2 AgentComponentBuilder

```swift
// File: Sources/SwiftAgents/DSL/Builders/AgentComponentBuilder.swift

/// Result builder for agent body components (tools, memory, etc.).
@resultBuilder
public struct AgentComponentBuilder {
    public static func buildBlock(_ components: AgentBodyComponent...) -> [AgentBodyComponent] {
        components
    }
    
    public static func buildOptional(_ component: AgentBodyComponent?) -> [AgentBodyComponent] {
        component.map { [$0] } ?? []
    }
    
    public static func buildEither(first component: AgentBodyComponent) -> [AgentBodyComponent] {
        [component]
    }
    
    public static func buildEither(second component: AgentBodyComponent) -> [AgentBodyComponent] {
        [component]
    }
    
    public static func buildArray(_ components: [[AgentBodyComponent]]) -> [AgentBodyComponent] {
        components.flatMap { $0 }
    }
    
    public static func buildExpression(_ tool: any AnyJSONTool) -> AgentBodyComponent {
        ToolsComponent([tool])
    }
}
```

---

## Part 7: Execution Flow Visualization

```swift
// File: Sources/SwiftAgents/DSL/Diagnostics/ExecutionFlowDiagram.swift

/// Visual representation of agent execution flow.
public struct ExecutionFlowDiagram: Sendable, CustomStringConvertible {
    public let name: String
    public var stages: [FlowStage]
    public var modifiers: [String] = []
    
    public var description: String {
        var lines: [String] = []
        
        // Header
        lines.append("┌─────────────────────────────────────────┐")
        lines.append("│  \(name.padding(toLength: 39, withPad: " ", startingAt: 0))│")
        lines.append("└─────────────────────────────────────────┘")
        
        // Stages
        for stage in stages {
            lines.append("                   │")
            lines.append("                   ▼")
            lines.append(contentsOf: stage.render())
        }
        
        // Modifiers
        if !modifiers.isEmpty {
            lines.append("")
            lines.append("Modifiers: \(modifiers.joined(separator: ", "))")
        }
        
        return lines.joined(separator: "\n")
    }
}

/// A stage in the execution flow.
public enum FlowStage: Sendable {
    case agent(name: String, tools: [String])
    case chat(instructions: String)
    case guard(phase: GuardPhase, guardrails: [String])
    case transform(phase: TransformPhase)
    case route(strategy: String, branches: [(String, ExecutionFlowDiagram)])
    case parallel(branches: [(String, ExecutionFlowDiagram)])
    case subAgent(name: String)
    case planning
    
    func render() -> [String] {
        var lines: [String] = []
        
        switch self {
        case .agent(let name, let tools):
            lines.append("┌─────────────────────────────────────────┐")
            lines.append("│  \(name.padding(toLength: 39, withPad: " ", startingAt: 0))│")
            if !tools.isEmpty {
                lines.append("│  Tools: \(tools.joined(separator: ", ").prefix(30))...│")
            }
            lines.append("└─────────────────────────────────────────┘")
            
        case .guard(let phase, let guardrails):
            lines.append("┌─────────────────────────────────────────┐")
            lines.append("│  Guard(\(phase))".padding(toLength: 42, withPad: " ", startingAt: 0) + "│")
            for guardrail in guardrails.prefix(3) {
                lines.append("│  ├─ \(guardrail.prefix(34))│")
            }
            lines.append("└─────────────────────────────────────────┘")
            
        case .route(let strategy, let branches):
            lines.append("┌─────────────────────────────────────────┐")
            lines.append("│  Route (\(strategy))".padding(toLength: 42, withPad: " ", startingAt: 0) + "│")
            for (key, _) in branches.prefix(4) {
                lines.append("│  ├─ \(key.prefix(20)) → ...".padding(toLength: 42, withPad: " ", startingAt: 0) + "│")
            }
            lines.append("└─────────────────────────────────────────┘")
            
        default:
            lines.append("┌─────────────────────────────────────────┐")
            lines.append("│  \(String(describing: self).prefix(39))│")
            lines.append("└─────────────────────────────────────────┘")
        }
        
        return lines
    }
}
```

---

## Part 8: Usage Examples by Tier

### Tier 1: Simple Agents (80% of use cases)

```swift
// Simplest possible agent
struct GreeterAgent: Agent {
    var body: some AgentBehavior {
        Chat("You are a friendly greeter who welcomes users warmly.")
    }
}

// Agent with tools
struct CalculatorAgent: Agent {
    var body: some AgentBehavior {
        Agent("You help users with mathematical calculations.") {
            CalculatorTool()
            UnitConverterTool()
        }
    }
}

// Agent with memory
struct ConversationalAgent: Agent {
    var body: some AgentBehavior {
        Agent("You are a helpful assistant who remembers context.") {
            SearchTool()
            CalendarTool()
        }
        .memory(.conversation(limit: 100))
    }
}
```

### Tier 2: Agents with Flow Control

```swift
// Agent with input/output validation
struct SafeAssistant: Agent {
    var body: some AgentBehavior {
        Guard(.input) {
            ContentFilter()
            RateLimiter(rpm: 60)
        }
        
        Agent("You are a helpful and safe assistant.") {
            SearchTool()
        }
        
        Guard(.output) {
            ToxicityFilter()
            PIIRedactor()
        }
    }
}

// Agent with routing
struct CustomerService: Agent {
    var body: some AgentBehavior {
        Guard(.input) {
            ContentFilter()
        }
        
        Route(using: .llm(CustomerIntentClassifier())) {
            When(.billing, use: BillingAgent())
            When(.technical, use: TechnicalAgent())
            When(.sales, use: SalesAgent())
            Otherwise(use: GeneralAgent())
        }
        
        Guard(.output) {
            ToxicityFilter()
        }
    }
}
```

### Tier 3: Orchestrated Agents

```swift
// Sequential pipeline
struct AnalysisPipeline: Agent {
    var body: some AgentBehavior {
        Sequential {
            DataCleanerAgent()
            AnalyzerAgent()
            ReportGeneratorAgent()
        }
    }
}

// Parallel execution
struct MultiPerspectiveAnalysis: Agent {
    var body: some AgentBehavior {
        Parallel(merge: .structured) {
            SentimentAgent().as("sentiment")
            SummaryAgent().as("summary")
            KeywordAgent().as("keywords")
        }
    }
}

// Complex orchestration
struct EnterpriseAgent: Agent {
    var body: some AgentBehavior {
        Guard(.input) {
            AuthenticationGuardrail()
            RateLimiter(rpm: 100)
        }
        
        Transform(.input) { input in
            input.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        Route(using: .llm(EnterpriseIntentClassifier())) {
            When(.simple, use: FAQAgent())
            When(.complex, use: Sequential {
                PlannerAgent()
                ExecutorAgent()
                ValidatorAgent()
            })
            When(.analytics, use: Parallel(merge: .structured) {
                DataAgent().as("data")
                ChartAgent().as("charts")
                InsightAgent().as("insights")
            })
            Otherwise(use: GeneralAgent())
        }
        
        Guard(.output) {
            ComplianceGuardrail()
            BrandVoiceGuardrail()
        }
    }
}
```

### Tier 4: Production Configuration

```swift
// Full production setup
@main
struct MyApp {
    static func main() async throws {
        let provider = OpenRouterProvider(apiKey: ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]!)
        let tracer = ConsoleTracer()
        
        let result = try await EnterpriseAgent()
            .environment(\.inferenceProvider, provider)
            .environment(\.tracer, tracer)
            .retry(.exponential(maxAttempts: 3))
            .timeout(.seconds(60))
            .traced("enterprise-agent")
            .run("Help me analyze Q4 sales data")
        
        print(result.output)
    }
}
```

---

## Part 9: Implementation Phases

### Phase 1: Core Infrastructure (Foundation)

**Files to Create:**
- `Sources/SwiftAgents/DSL/Core/Agent.swift`
- `Sources/SwiftAgents/DSL/Core/AgentBehavior.swift`
- `Sources/SwiftAgents/DSL/Core/ExecutionContext.swift`
- `Sources/SwiftAgents/DSL/Core/AgentEnvironment.swift`

**Tasks:**
1. Define `Agent` protocol (DSL)
2. Rename existing `Agent` to `AgentCore`
3. Define `AgentBehavior` protocol
4. Implement `ExecutionContext` with typed storage
5. Implement `AgentEnvironment` for configuration propagation

**Tests:**
- Protocol conformance
- Context propagation
- Environment inheritance

### Phase 2: Agent Behaviors

**Files to Create:**
- `Sources/SwiftAgents/DSL/Behaviors/AgentBody.swift`
- `Sources/SwiftAgents/DSL/Behaviors/ChatBehavior.swift`
- `Sources/SwiftAgents/DSL/Behaviors/ToolCallingBehavior.swift`
- `Sources/SwiftAgents/DSL/Behaviors/PlannerBehavior.swift`

**Tasks:**
1. Implement `AgentBody` (primary agent type)
2. Create `Agent` typealias
3. Implement `Chat` behavior
4. Implement `ToolCallingAgent` behavior
5. Implement `Planner` behavior

**Tests:**
- Each behavior type execution
- Integration with underlying implementations

### Phase 3: Flow Control

**Files to Create:**
- `Sources/SwiftAgents/DSL/Flow/Guard.swift`
- `Sources/SwiftAgents/DSL/Flow/Transform.swift`
- `Sources/SwiftAgents/DSL/Flow/Sequential.swift`
- `Sources/SwiftAgents/DSL/Flow/Parallel.swift`
- `Sources/SwiftAgents/DSL/Flow/Route.swift`

**Tasks:**
1. Implement `Guard` with input/output phases
2. Implement `Transform`
3. Implement `Sequential` workflow
4. Implement `Parallel` workflow with merge strategies
5. Implement `Route` with multiple routing strategies

**Tests:**
- Flow execution order
- Guard validation
- Routing decision making
- Parallel execution and merging

### Phase 4: Components and Modifiers

**Files to Create:**
- `Sources/SwiftAgents/DSL/Components/AgentBodyComponent.swift`
- `Sources/SwiftAgents/DSL/Components/MemoryComponent.swift`
- `Sources/SwiftAgents/DSL/Components/ToolsComponent.swift`
- `Sources/SwiftAgents/DSL/Modifiers/*.swift`

**Tasks:**
1. Implement component protocol and validation
2. Implement Memory component (singular)
3. Implement Tools component (mergeable)
4. Implement all modifiers (memory, retry, timeout, environment, tracing)

**Tests:**
- Component merging semantics
- Singular component validation
- Modifier behavior

### Phase 5: Result Builders

**Files to Create:**
- `Sources/SwiftAgents/DSL/Builders/AgentBuilder.swift`
- `Sources/SwiftAgents/DSL/Builders/AgentComponentBuilder.swift`
- `Sources/SwiftAgents/DSL/Builders/ToolBuilder.swift`
- `Sources/SwiftAgents/DSL/Builders/GuardrailBuilder.swift`
- `Sources/SwiftAgents/DSL/Builders/RouteBuilder.swift`

**Tasks:**
1. Implement all result builders
2. Support conditionals and optionals
3. Ensure good error messages

**Tests:**
- Builder syntax compilation
- Conditional building
- Type inference

### Phase 6: Diagnostics and Documentation

**Files to Create:**
- `Sources/SwiftAgents/DSL/Diagnostics/ExecutionFlowDiagram.swift`

**Tasks:**
1. Implement flow diagram generation
2. Add comprehensive documentation
3. Create example projects
4. Write migration guide

---

## Part 10: Migration Strategy

### Backward Compatibility

The existing API continues to work unchanged:

```swift
// Old API - still works
let agent = ReActAgent(
    tools: [CalculatorTool()],
    instructions: "You are helpful."
)
let result = try await agent.run("What's 2+2?")
```

### New API Alongside

```swift
// New DSL API
struct MyAgent: Agent {
    var body: some AgentBehavior {
        Agent("You are helpful.") {
            CalculatorTool()
        }
    }
}

let result = try await MyAgent()
    .environment(\.inferenceProvider, provider)
    .run("What's 2+2?")
```

### Deprecation Timeline

1. **v1.0**: Both APIs available, DSL is recommended
2. **v2.0**: Old API marked deprecated
3. **v3.0**: Old API removed (breaking change)

---

## Part 11: Deferred Features

The following features are planned for future versions:

### Future: @Tool Macro
Zero-boilerplate tool definition with compile-time validation.

### Future: @Generable Integration
Structured output with Apple's Foundation Models on iOS 26+.

### Future: API Namespacing
`Agents.ReAct`, `Agents.Tools` etc. for better organization.

### Future: Graph-Based Workflows
Loops, cycles, and conditional edges (separate LangGraph-equivalent framework).

### Future: Visual Agent Builder
Xcode integration for visual agent design with live previews.

---

## Summary

This implementation plan provides a comprehensive roadmap for a SwiftUI-inspired agent DSL that:

1. **Uses structure for flow visibility**: Reading order = execution order
2. **Uses modifiers for configuration**: Memory, retry, timeout, tracing
3. **Renames for clarity**: `Agent` is the primary behavior, `AgentCore` is the runtime
4. **Progressive disclosure**: Simple agents are trivially simple
5. **Type-safe**: Leverages Swift's type system throughout
6. **No custom operators**: Standard Swift syntax only

The tiered approach ensures that 80% of users can be productive immediately, while power users have access to full orchestration capabilities.
