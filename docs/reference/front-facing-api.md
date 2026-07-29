# Front-Facing API Reference

This document describes the V3 public API surface of Swarm.

## Integrations trait

Default package consumption is **lean** (Integrations off): core Swarm + Apple
Foundation Models. Opt in for durable Hive workflows, ContextCore+Wax default
memory, Membrane adapters, and web helpers:

```swift
.package(
    url: "https://github.com/christopherkarani/Swarm.git",
    from: "0.6.0",
    traits: ["Integrations"]
)
```

| Surface | Lean default | With Integrations |
|---------|--------------|-------------------|
| `Agent.makeDefaultMemory()` | `SlidingWindowMemory` | `DefaultAgentMemory` (ContextCore + Wax) |
| Durable execute with checkpoint / `resumeFrom` | Throws | Full Hive durable engine |
| Membrane / web helpers | Unavailable or no-op | Linked and active |

HiveCore, Membrane, and ContextCore are native in-tree `Sources/` targets
(internal modules, not separate products), linked only with Integrations.
Wax remains a remote package + trait-gated product. Lean resolve does not pull
Hive/Membrane/ContextCore package identities, but still resolves Wax, MetalANNS
(→ GRDB), swift-crypto, swift-mutex, and swift-collections unless
`SWARM_CORE_ONLY=1`. ContextCore / full Membrane session stack are Apple-only
(Metal/CoreML); Linux Integrations keeps Hive + MembraneCore + web helpers.
`DefaultAgentMemory` (ContextCore + Wax) uses fallback pseudo-embeddings when
the optional CoreML `minilm-l6-v2.mlpackage` is not present. See README Install.

## 1) Entry point and global configuration

```swift
import Swarm

public enum Swarm {
    public static let version: String
    public static let minimumMacOSVersion: String
    public static let minimumiOSVersion: String
}

await Swarm.configure(provider: some InferenceProvider)
await Swarm.reset()

let defaultProvider = await Swarm.defaultProvider
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

### Low-level compatibility initializer

This initializer remains public for compatibility and generated collections. Most application code should prefer the V3 initializer in section 4, which takes unlabeled instructions and a trailing `@ToolBuilder` closure.

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
    inferenceProvider: .foundationModels(),
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

### Runtime wrappers (on AgentRuntime)

Core runtime wrappers are provided by `AgentRuntime` extensions:

```swift
agent.environment(\.inferenceProvider, myProvider)      // returns EnvironmentAgent
agent.memory(.conversation(maxMessages: 50))            // returns EnvironmentAgent
agent.promptTokenCounter(myCounter)                     // returns EnvironmentAgent
agent.webSearch(WebSearchTool.Configuration(enabled: false))
agent.observed(by: myObserver)                          // returns some AgentRuntime
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

    public func branch() async throws -> Conversation
}
```

`send(_:)` appends the user message and final assistant result to the transcript.
`stream(_:)` exposes raw events and does not mutate transcript history; use
`streamText(_:)` when you want streamed text collected and appended. `branch()`
creates an isolated conversation with the current transcript and, when supported
by the runtime or session, branched execution state.

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

Requires the **`Integrations`** SwiftPM trait (`traits: ["Integrations"]` or
`--traits Integrations`) for real checkpoint/resume at **execute** time.

With checkpoint/resume configured (or `resumeFrom` set), lean builds throw that
durable execution requires Integrations. Without that configuration, bare
execute still runs as a non-durable workflow. Checkpoint factories and
`.durable.checkpoint` / `.checkpointing` remain type-checkable in lean mode
(configuration-only); the trait gate is enforced when execute needs the durable
engine.

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

// Configuration-only in lean builds; durable engine requires Integrations at execute
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

Dot-syntax memory factories are contextual. Use them where Swift can infer a
specific memory type, such as the `memory:` init parameter, or assign to the
concrete memory actor type. Do not call these as static members on the
`Memory` protocol.

### Package default (`Agent.makeDefaultMemory()`)

When an agent is created without an explicit `memory:` argument, Swarm uses
`Agent.makeDefaultMemory()`:

```swift
// Trait-aware package default (prefer over constructing integration types yourself)
public static func makeDefaultMemory() throws -> any Memory
// Integrations on  → DefaultAgentMemory (ContextCore + Wax)
// Integrations off → SlidingWindowMemory
```

Pass an explicit factory when you want a fixed backend regardless of traits:

```swift
let agent = try Agent(
    "Remember recent context.",
    memory: .conversation(maxMessages: 100)
)

let sliding: SlidingWindowMemory = .slidingWindow(maxTokens: 4000)
let summary: SummaryMemory = .summary(configuration: .default, summarizer: TruncatingSummarizer.shared)
let hybrid: HybridMemory = .hybrid(configuration: .default, summarizer: TruncatingSummarizer.shared)
let persistent: PersistentMemory = .persistent(
    backend: InMemoryBackend(),
    conversationId: UUID().uuidString,
    maxMessages: 0
)
let vector: VectorMemory = .vector(
    embeddingProvider: embedder,
    similarityThreshold: 0.7,
    maxResults: 10
)
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

Built-in inference is Apple Foundation Models only. Custom backends implement
``InferenceProvider`` and are passed explicitly (or via
`await Swarm.configure(provider:)`).

```swift
.foundationModels()                 // On-device first-class provider
.foundationModels(profile: profile) // Dynamic profile re-resolved each turn
// Custom: pass any InferenceProvider value
```

| Factory family | Return type | Notes |
|----------------|-------------|-------|
| `.foundationModels()` | `FoundationModelsInferenceProvider` | Built-in on-device path; native tool calling via Apple's Tool protocol |
| `.foundationModels(profile:)` | `FoundationModelsInferenceProvider` | Same, driven by Swarm ``DynamicProfile`` (WWDC 2026–aligned; re-resolves each turn) |
| Custom `InferenceProvider` | your type | Implement the protocol for non-FM backends |

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

    public enum Handoff: Sendable {
        case requested(from: String, to: String, reason: String?)
        case completed(from: String, to: String)
        case started(from: String, to: String, input: String)
        case completedWithResult(from: String, to: String, result: AgentResult)
        case skipped(from: String, to: String, reason: String)
    }

    public enum Observation: Sendable {
        case decision(String, options: [String]?)
        case planUpdated(String, stepCount: Int)
        case guardrailStarted(name: String, type: GuardrailType)
        case guardrailPassed(name: String, type: GuardrailType)
        case guardrailTriggered(name: String, type: GuardrailType, message: String?)
        case memoryAccessed(operation: MemoryOperation, count: Int)
        case llmStarted(model: String?, promptTokens: Int?)
        case llmCompleted(model: String?, promptTokens: Int?, completionTokens: Int?, duration: TimeInterval)
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
| `@Tool("description")` | `struct` | Synthesizes `Tool` and `Sendable` conformance, typed `Input`/`Output`, argument decoding, and JSON schema from `@Parameter` properties |
| `@Parameter("description")` | `var` inside `@Tool` struct | Marks property as a schema parameter with description |
| `@Traceable` | `struct` conforming to `AnyJSONTool` | Injects tracing around `execute()` |
| `#Prompt(...)` | call site | Type-safe interpolated prompt string |
| `#Tool("name", "description")` | call site | Creates an inline `Tool` from a closure with labeled parameters |
| `@Builder` | `struct` | Generates fluent setters for stored `var` properties |

Inline tool example:

```swift
let greet = #Tool("greet", "Greets a person") { (name: String) in
    "Hello, \(name)!"
}
```

## 14) Companion products

The package exports four public library products:

| Product | Source surface | Public entry points |
|---------|----------------|---------------------|
| `Swarm` | `Sources/Swarm` | Agents, tools, workflows, memory, guardrails, providers, MCP client/bridge, workspace, resilience, observability, macros |
| `SwarmOpenTelemetry` | `Sources/SwarmOpenTelemetry` | `OpenTelemetryInferenceProvider`, `InferenceProvider.instrumentedWithOpenTelemetry(...)`, `AgentRuntime.instrumentedWithOpenTelemetry(...)`, and `SwarmRuntimeTracer` |
| `SwarmMembrane` | `Sources/SwarmMembrane` | Re-export product for Swarm's Membrane integration. The target is `@_exported import Swarm`, so public Membrane symbols are the `MembraneEnvironment`, `MembraneFeatureConfiguration`, `MembraneAgentAdapter`, and `DefaultMembraneAgentAdapter` APIs cataloged under `Sources/Swarm/Integration/Membrane/`. |
| `SwarmMCP` | `Sources/SwarmMCP` | `SwarmMCPServerService`, `SwarmMCPToolCatalog`, `SwarmMCPToolExecutor`, `SwarmMCPToolExecutionError`, and `SwarmMCPToolRegistryAdapter` |

### OpenTelemetry wrappers

```swift
import Swarm
import SwarmOpenTelemetry

let tracedAgent = try Agent(
    "Answer briefly.",
    inferenceProvider: .foundationModels()
).instrumentedWithOpenTelemetry()

let tracedProvider = myCustomProvider.instrumentedWithOpenTelemetry()
```

See [OpenTelemetry Tracing](../guide/opentelemetry-tracing.md) for SDK setup and
URLSession instrumentation policy.

### MCP server adapter

The core `Swarm` product includes MCP client-side primitives:

```swift
let server = try HTTPMCPServer(
    url: URL(string: "https://mcp.example.com/api")!,
    name: "example-server",
    apiKey: "sk-..."
)

let client = MCPClient()
try await client.addServer(server)
let tools = try await client.getAllTools()

let bridge = MCPToolBridge(server: server)
let bridgedTools = try await bridge.bridgeTools()
```

`HTTPMCPServer(url:name:apiKey:timeout:maxRetries:session:)` is the remote HTTP
client. `MCPClient` aggregates multiple MCP servers and `MCPToolBridge` exposes
remote MCP tools as Swarm JSON tools.

`SwarmMCPServerService` exposes a `SwarmMCPToolCatalog` and
`SwarmMCPToolExecutor` over the MCP Swift SDK transport. For a Swarm
`ToolRegistry`, use `SwarmMCPToolRegistryAdapter` as both catalog and executor:

```swift
import Swarm
import SwarmMCP

let registry = try ToolRegistry(tools: [WeatherTool()])
let adapter = SwarmMCPToolRegistryAdapter(registry: registry)
let service = SwarmMCPServerService(
    toolCatalog: adapter,
    toolExecutor: adapter
)

try await service.startStdio()
await service.waitUntilCompleted()
```

`SwarmMCPServerService` instances are single-use; create a fresh service to
restart after `stop()`.

## 15) Naming guarantees

- Observer APIs use the `observer` label.
- Handoff callback naming is `onTransfer` / `transform` / `when`.
- Every public type conforms to `Sendable`.
- Agent is a struct (value type). Execution state lives in `run()`.
- `Workflow` is the single coordination primitive.
- No legacy types: `AgentBuilder`, `AnyAgent`, `AnyTool`, `ClosureInputGuardrail`, `ClosureOutputGuardrail`, `AgentBlueprint`, `AgentLoop`.
