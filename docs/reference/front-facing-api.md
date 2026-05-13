# Front-Facing API Reference

This document describes the V3 public API surface of Swarm.

## 1) Entry point and global configuration

```swift
import Swarm

public enum Swarm {
    public static let version: String
    public static let minimumMacOSVersion: String
    public static let minimumiOSVersion: String
}

await Swarm.configure(provider: some InferenceProvider)
await Swarm.configure(cloudProvider: some InferenceProvider)
await Swarm.reset()

let defaultProvider = await Swarm.defaultProvider
let cloudProvider = await Swarm.cloudProvider
```

## 2) Core runtime protocol

```swift
public protocol AgentRuntime: Sendable {
    var name: String { get }
    var tools: [any AnyJSONTool] { get }
    var instructions: String { get }
    var configuration: AgentConfiguration { get }
    var memory: (any Memory)? { get }
    var inferenceProvider: (any InferenceProvider)? { get }
    var tracer: (any Tracer)? { get }
    var handoffs: [AnyHandoffConfiguration] { get }
    var inputGuardrails: [any InputGuardrail] { get }
    var outputGuardrails: [any OutputGuardrail] { get }

    func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult
    nonisolated func stream(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) -> AsyncThrowingStream<AgentEvent, Error>

    func cancel() async
}
```

Convenience extensions:

```swift
run(_ input: String, observer: (any AgentObserver)? = nil)
stream(_ input: String, observer: (any AgentObserver)? = nil)
observed(by: some AgentObserver) -> some AgentRuntime
environment(_ keyPath:, _ value:) -> EnvironmentAgent
```

## 3) Agent (struct, primary init)

The concrete agent type. Creates an immutable configuration; execution state lives in `run()`.

```swift
public struct Agent: AgentRuntime
```

### Canonical initializer

```swift
try Agent(
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
)
```

### Provider-first convenience

```swift
try Agent(
    _ inferenceProvider: any InferenceProvider,
    tools: [any AnyJSONTool] = [],
    instructions: String = "",
    ...
)
```

### Typed-tools convenience

```swift
try Agent(
    tools: [some Tool] = [],
    instructions: String = "",
    ...
)
```

### Handoff-agents convenience

```swift
try Agent(
    tools: [any AnyJSONTool] = [],
    instructions: String = "",
    ...,
    handoffAgents: [any AgentRuntime]
)
```

## 4) Agent (V3 canonical init with @ToolBuilder)

The recommended path for creating agents in V3. Takes an unlabeled instructions string and a `@ToolBuilder` trailing closure for tools. All other parameters are init arguments, not modifier methods.

```swift
try Agent(
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
)
```

### Example usage

```swift
let agent = try Agent("You are a helpful assistant.") {
    WeatherTool()
    CalculatorTool()
}
```

### With additional init parameters

```swift
let agent = try Agent(
    "You are a helpful assistant.",
    configuration: .init(name: "Assistant"),
    memory: .conversation(maxMessages: 50),
    inferenceProvider: .anthropic(key: "sk-..."),
    inputGuardrails: [MaxInputLengthGuardrail(maxLength: 5000)],
    handoffs: [AnyHandoffConfiguration(targetAgent: supportAgent)]
) {
    WeatherTool()
    CalculatorTool()
}
```

### Init parameters

| Parameter | Type | Default | Purpose |
|-----------|------|---------|---------|
| `_ instructions` | `String` | (required) | System instructions defining agent behavior |
| `configuration` | `AgentConfiguration` | `.default` | Agent configuration (name, max iterations, etc.) |
| `memory` | `(any Memory)?` | `nil` | Memory strategy for conversation history |
| `inferenceProvider` | `(any InferenceProvider)?` | `nil` | LLM provider (resolved via provider chain if nil) |
| `tracer` | `(any Tracer)?` | `nil` | Observability tracer |
| `inputGuardrails` | `[any InputGuardrail]` | `[]` | Input validation guardrails |
| `outputGuardrails` | `[any OutputGuardrail]` | `[]` | Output validation guardrails |
| `guardrailRunnerConfiguration` | `GuardrailRunnerConfiguration` | `.default` | Guardrail runner settings |
| `handoffs` | `[AnyHandoffConfiguration]` | `[]` | Handoff targets for multi-agent orchestration |
| `tools` | `@ToolBuilder () -> ToolCollection` | `{ .empty }` | Trailing closure producing the agent's tools |

### Runtime modifiers (on AgentRuntime)

Only `.environment()` and `.memory()` exist as modifier methods, provided by `AgentRuntime` extensions:

```swift
agent.environment(\.inferenceProvider, myProvider)  // returns EnvironmentAgent
agent.observed(by: myObserver)                      // returns some AgentRuntime
```

## 5) Tool and FunctionTool

### `@Tool` macro (recommended)

```swift
@Tool("Looks up the current stock price")
struct PriceTool {
    @Parameter("Ticker symbol") var ticker: String

    func execute() async throws -> String { "182.50" }
}
```

### `FunctionTool` (closure shorthand)

```swift
let greet = FunctionTool(
    name: "greet",
    description: "Greets a user",
    parameters: [ToolParameter(name: "name", description: "User name", type: .string, isRequired: true)]
) { args in
    let name = try args.require("name", as: String.self)
    return .string("Hello, \(name)!")
}
```

### `@ToolBuilder` result builder

Used as the trailing closure in the canonical `Agent` init. No brackets, no commas:

```swift
Agent("instructions") {
    PriceTool()
    greet
}
```

The builder produces an opaque `ToolCollection`; callers supply concrete `Tool` values or `[any Tool]`, and Swarm handles the internal type erasure.

## 6) Conversation

Stateful multi-turn conversation wrapper.

```swift
public actor Conversation {
    public struct Message: Sendable, Equatable {
        public enum Role: String, Sendable { case user, assistant }
        public let role: Role
        public let text: String
    }

    public init(with agent: some AgentRuntime, session: (any Session)? = nil, observer: (any AgentObserver)? = nil)
    public var messages: [Message] { get }

    @discardableResult
    public func send(_ input: String) async throws -> AgentResult

    public nonisolated func stream(_ input: String) -> AsyncThrowingStream<AgentEvent, Error>

    @discardableResult
    public func streamText(_ input: String) async throws -> String
}
```

## 7) Workflow

Fluent multi-agent pipeline composition.

```swift
public struct Workflow: Sendable {
    public enum MergeStrategy: @unchecked Sendable {
        case structured
        case indexed
        case first
        case custom(@Sendable ([AgentResult]) -> String)
    }

    public init()

    // Composition
    public func step(_ agent: some AgentRuntime) -> Workflow
    public func parallel(
        _ agents: [any AgentRuntime],
        merge: MergeStrategy = .structured,
        customMergeSignature: String? = nil,
        fileID: StaticString = #fileID,
        line: UInt = #line
    ) -> Workflow
    public func route(
        _ condition: @escaping @Sendable (String) -> (any AgentRuntime)?,
        signature: String? = nil,
        fileID: StaticString = #fileID,
        line: UInt = #line
    ) -> Workflow
    public func route(
        signature: String,
        fileID: StaticString = #fileID,
        line: UInt = #line,
        _ condition: @escaping @Sendable (String) -> (any AgentRuntime)?
    ) -> Workflow
    public func repeatUntil(
        maxIterations: Int = 100,
        _ condition: @escaping @Sendable (AgentResult) -> Bool,
        signature: String? = nil,
        fileID: StaticString = #fileID,
        line: UInt = #line
    ) -> Workflow
    public func repeatUntil(
        maxIterations: Int = 100,
        signature: String,
        fileID: StaticString = #fileID,
        line: UInt = #line,
        _ condition: @escaping @Sendable (AgentResult) -> Bool
    ) -> Workflow
    public func timeout(_ duration: Duration) -> Workflow
    public func observed(by observer: some AgentObserver) -> Workflow

    // Execution (unlabeled input parameter)
    public func run(_ input: String) async throws -> AgentResult
    public func stream(_ input: String) -> AsyncThrowingStream<AgentEvent, Error>

    // Durable namespace
    public var durable: Durable { get }
}
```

### Durable namespace

```swift
public extension Workflow {
    struct Durable: Sendable {
        enum CheckpointPolicy: Sendable { case onCompletion, everyStep }

        func checkpoint(id: String, policy: CheckpointPolicy = .onCompletion) -> Workflow
        func checkpointing(_ checkpointing: WorkflowCheckpointing) -> Workflow
        func fallback(primary: some AgentRuntime, to backup: some AgentRuntime, retries: Int = 0) -> Workflow
        func execute(_ input: String, resumeFrom checkpointID: String? = nil) async throws -> AgentResult
    }
}

WorkflowCheckpointing.inMemory()
WorkflowCheckpointing.fileSystem(directory: URL)
```

## 8) InputGuard and OutputGuard

Concrete guardrails with static factories. Used as init parameters on `Agent`.

```swift
public struct InputGuard: InputGuardrail, Sendable {
    public static func maxLength(_ maxLength: Int, name: String = "MaxLengthGuardrail") -> InputGuard
    public static func notEmpty(name: String = "NotEmptyGuardrail") -> InputGuard
    public static func custom(_ name: String, _ validate: @escaping @Sendable (String) async throws -> GuardrailResult) -> InputGuard
}

public struct OutputGuard: OutputGuardrail, Sendable {
    public static func maxLength(_ maxLength: Int, name: String = "MaxOutputLengthGuardrail") -> OutputGuard
    public static func custom(_ name: String, _ validate: @escaping @Sendable (String) async throws -> GuardrailResult) -> OutputGuard
}
```

### Guardrail protocols (for advanced use)

```swift
public protocol InputGuardrail: Sendable {
    func validate(_ input: String, context: AgentContext?) async throws -> GuardrailResult
}

public protocol OutputGuardrail: Sendable {
    func validate(_ output: String, agent: any AgentRuntime, context: AgentContext?) async throws -> GuardrailResult
}
```

## 9) Memory factories

Dot-syntax memory factories used with the `memory` init parameter.

```swift
Memory.conversation(maxMessages: 100)
Memory.slidingWindow(maxTokens: 4000)
Memory.summary(configuration: .default, summarizer: TruncatingSummarizer.shared)
Memory.hybrid(configuration: .default, summarizer: TruncatingSummarizer.shared)
Memory.persistent(backend: InMemoryBackend(), conversationId: UUID().uuidString, maxMessages: 0)
Memory.vector(embeddingProvider: embedder, similarityThreshold: 0.7, maxResults: 10)
```

## 10) HandoffTool

Agents passed via the `handoffs` or `handoffAgents` init parameters are automatically wrapped as tool calls. The LLM can invoke them to delegate control.

```swift
// Via V3 canonical init
let agent = try Agent("Route requests to the right specialist.") {
    // tools
}

// With handoff agents (convenience init)
let triage = try Agent(
    instructions: "Route requests.",
    handoffAgents: [billingAgent, supportAgent, salesAgent]
)
```

## 11) Inference providers

```swift
public protocol InferenceProvider: Sendable {
    func generate(prompt: String, options: InferenceOptions) async throws -> String

    func stream(
        prompt: String,
        options: InferenceOptions
    ) -> AsyncThrowingStream<String, Error>

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse
}

public protocol ConversationInferenceProvider: InferenceProvider {
    func generate(
        messages: [InferenceMessage],
        options: InferenceOptions
    ) async throws -> String

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse
}
```

### Provider factories (dot-syntax)

```swift
.anthropic(key: "sk-...")
.openAI(key: "sk-...")
.ollama(model: "llama3")
.foundationModels()     // On-device, iOS 26 / macOS 26 when FoundationModels is available
```

## 12) Events and results

```swift
public enum AgentEvent: Sendable {
    case lifecycle(Lifecycle)
    case tool(Tool)
    case output(Output)
    case handoff(Handoff)
    case observation(Observation)

    public enum Lifecycle: Sendable {
        case started(input: String)
        case completed(result: AgentResult)
        case failed(error: AgentError)
        case cancelled
        case guardrailFailed(error: GuardrailError)
        case iterationStarted(number: Int)
        case iterationCompleted(number: Int)
    }

    public enum Tool: Sendable {
        case started(call: ToolCall)
        case partial(update: PartialToolCallUpdate)
        case completed(call: ToolCall, result: ToolResult)
        case failed(call: ToolCall, error: AgentError)
    }

    public enum Output: Sendable {
        case token(String)
        case chunk(String)
        case thinking(thought: String)
        case thinkingPartial(String)
    }
}

public struct AgentResult: Sendable {
    public let output: String
    public let toolCalls: [ToolCall]
    public let toolResults: [ToolResult]
    public let iterationCount: Int
    public let duration: Duration
    public let tokenUsage: TokenUsage?
}
```

## 13) Public macros

| Macro | Applied To | Effect |
|-------|-----------|--------|
| `@Tool("description")` | `struct` | Synthesizes `AnyJSONTool` conformance + JSON schema from `@Parameter` properties |
| `@Parameter("description")` | `var` inside `@Tool` struct | Marks property as a schema parameter with description |
| `@Traceable` | `struct` conforming to `AnyJSONTool` | Injects tracing around `execute()` |
| `#Prompt(...)` | call site | Type-safe interpolated prompt string |

## 14) Naming guarantees

- Observer APIs use the `observer` label.
- Handoff callback naming is `onTransfer` / `transform` / `when`.
- Every public type conforms to `Sendable`.
- Agent is a struct (value type). Execution state lives in `run()`.
- `Workflow` is the single coordination primitive.
- No legacy types: `AgentBuilder`, `AnyAgent`, `AnyTool`, `ClosureInputGuardrail`, `ClosureOutputGuardrail`, `AgentBlueprint`, `AgentLoop`.
