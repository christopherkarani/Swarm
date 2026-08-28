# Getting Started

Get a working Swarm agent in under a minute.

## Installation

### Swift Package Manager

Add Swarm to your `Package.swift`:

```swift
// Lean default (core + Foundation Models). No Integrations trait.
dependencies: [
    .package(url: "https://github.com/christopherkarani/Swarm.git", from: "0.6.2")
],
targets: [
    .target(name: "YourApp", dependencies: ["Swarm"])
]
```

### Upgrading / Integrations trait

The **`Integrations`** SwiftPM trait is **off by default**. A trait-free
`.package(...)` is the lean link: core Swarm + on-device Foundation Models.

Enable Integrations when you need any of:

| Capability | Without Integrations (lean) | With `traits: ["Integrations"]` |
|------------|----------------------------|----------------------------------|
| Default agent memory | `SlidingWindowMemory` | ContextCore + Wax `DefaultAgentMemory` |
| Durable Hive checkpoint/resume | Configuration type-checks; factories warn immediately; execute with checkpoint/resume configured throws | Full durable engine |
| Membrane adapters | No-op / unavailable backends | Real Membrane session adapters (`import Swarm`; do not take a `SwarmMembrane` dependency — that product is deprecated and will be removed in 0.7.0) |
| Web helpers (`websearch`, page fetch/HTML parse) | Not injected / gated | Full web tool support |

```swift
.package(
    url: "https://github.com/christopherkarani/Swarm.git",
    from: "0.6.2",
    traits: ["Integrations"]
)
```

HiveCore, Membrane, and ContextCore are native in-tree modules under Swarm
`Sources/` (internal targets, not separate products). Wax remains an external
package and is linked only with Integrations. Omitting the trait does **not**
link Integrations modules into your app. Lean resolve never pulls
Hive/Membrane/ContextCore/Conduit **package identities**, and trait-gated
product edges also keep Wax, MetalANNS→GRDB, swift-crypto, swift-mutex, and
SwiftSoup off the lean pin list. Default remotes remain (swift-syntax via the
default-on **Macros** trait, swift-log, MCP sdk, OTel, plus NIO transitives —
including `swift-collections` via NIO). Disable Macros with `traits: []` to
drop swift-syntax. `SWARM_CORE_ONLY=1` drops the integration package block entirely.

**Platform note:** ContextCore and the full Membrane session stack need Apple
frameworks (Metal/CoreML/Accelerate). On Linux, Integrations still enables Hive
durable workflows, MembraneCore, and web helpers; default memory falls back to
`SlidingWindowMemory` when ContextCore is unavailable.

**Embeddings:** the CoreML MiniLM model is not bundled with Swarm. Call
`SemanticEmbeddingAvailability.ensureModelAvailable()` to download it on
demand (SHA-256 verified, compiled into `~/Library/Application Support/Swarm/Embeddings/`).
Without it, Integrations `DefaultAgentMemory` uses deterministic
pseudo-embeddings, logs a once-per-process warning naming that API, and
`isSemanticMemoryAvailable` is `false`. Set
`downloadsEmbeddingModelAutomatically` on the memory configuration to opt in
to auto-download (default `off`). A failed auto-download logs a warning and
starts the session with fallback embeddings; call `ensureModelAvailable()` to
retry. Simulator uses CoreML CPU inference; it is not a special-case fallback.

### Disabling the Macros trait

The **`Macros`** SwiftPM trait is **on by default**. It pulls `swift-syntax` so
`@Tool`, `@Parameter`, `#Prompt`, and `@Traceable` work. Specifying traits on
the package dependency replaces defaults, so `traits: ["Integrations"]` still
keeps macros (Integrations enables Macros). To drop `swift-syntax` entirely:

```swift
.package(
    url: "https://github.com/christopherkarani/Swarm.git",
    from: "0.6.2",
    traits: []
)
```

You lose `@Tool`, `@Parameter`, `#Prompt`, and `@Traceable`. Everything else
stays: agents, workflows, memory, and ``FunctionTool``.

```swift
import Swarm

let echo = FunctionTool(
    name: "echo",
    description: "Echoes a message",
    parameters: [
        ToolParameter(name: "message", description: "Text to echo", type: .string)
    ]
) { args in
    let message = try args.require("message", as: String.self)
    return .string(message)
}

let agent = try Agent(
    "Repeat the user's text.",
    inferenceProvider: .foundationModels()
) {
    echo
}
```

### Xcode

**File → Add Package Dependencies →** `https://github.com/christopherkarani/Swarm.git`

## Your First Agent

The primary way to create an agent is with the `Agent` struct initializer. The canonical init takes an unlabeled instructions string and a `@ToolBuilder` trailing closure for tools.

### On-device (recommended on Apple platforms)

```swift
import Swarm

@Tool("Looks up a canned stock price")
struct PriceTool {
    @Parameter("Ticker symbol") var ticker: String

    func execute() async throws -> String { "182.50" }
}

// No API key. Requires macOS/iOS 26+ with Apple Intelligence available.
// Parameter order: configuration → memory → inferenceProvider → guardrails → tools
let agent = try Agent(
    "Answer finance questions using tools when needed.",
    configuration: .default.name("Analyst"),
    memory: .conversation(maxMessages: 50),
    inferenceProvider: .foundationModels(),
    inputGuardrails: [InputGuard.maxLength(5000), InputGuard.notEmpty()]
) {
    PriceTool()
}

let result = try await agent.run("What is AAPL trading at?")
print(result.output)
```

If the system model might be missing (Simulator, Linux CI, older OS), prefer the safe factory:

```swift
guard let provider = FoundationModelsInferenceProvider.ifAvailable() else {
    // Inject a custom InferenceProvider, or fail with a clear user message.
    throw AgentError.inferenceProviderUnavailable(reason: "Foundation Models unavailable")
}
let agent = try Agent("You are helpful.", inferenceProvider: provider)
```

### OpenAI-compatible remote provider (Linux / no Apple Intelligence)

Same agent loop, `URLSession` only. Prompt content is sent to `baseURL` —
contrast with on-device Foundation Models.

```swift
let agent = try Agent(
    "Answer finance questions using real data.",
    configuration: .default.name("Analyst"),
    memory: .conversation(maxMessages: 50),
    inferenceProvider: .openAICompatible(.ollama(model: "llama3.2")),
    inputGuardrails: [InputGuard.maxLength(5000), InputGuard.notEmpty()]
) {
    PriceTool()
}
```

Factories: `.openAI(apiKey:model:)`, `.azureOpenAI(resource:deployment:apiKey:)`,
`.openRouter(apiKey:model:)`, `.ollama(model:)`, `.lmStudio(model:)`. See
[Remote Providers](remote-providers.md).

### Custom `InferenceProvider`

For non–Foundation Models / non–OpenAI-compatible backends, implement or inject
any type that conforms to `InferenceProvider` and pass it explicitly (or via
`await Swarm.configure(provider:)`):

```swift
let agent = try Agent(
    "Answer finance questions using real data.",
    configuration: .default.name("Analyst"),
    memory: .conversation(maxMessages: 50),
    inferenceProvider: myCustomProvider,
    inputGuardrails: [InputGuard.maxLength(5000), InputGuard.notEmpty()]
) {
    PriceTool()
    CalculatorTool()
}
```

### Working example apps

```bash
cd Examples/OnDeviceChat && swift run OnDeviceChat --demo
cd Examples/MultiAgentPipeline && swift run MultiAgentPipeline --demo
```

## Creating Tools

### `@Tool` macro (recommended)

Define a struct with `@Tool` and annotate parameters with `@Parameter`:

```swift
@Tool("Searches the web for information")
struct WebSearchTool {
    @Parameter("The search query") var query: String
    @Parameter("Max results to return") var limit: Int = 5

    func execute() async throws -> String {
        // Your search implementation
        "Results for \(query)"
    }
}
```

Supported parameter types are `String`, `Int`, `Double`/`Float`, `Bool`, arrays of those, and `Optional` thereof. Dictionaries and other types are compile errors — use `FunctionTool` for `.any` or object schemas.

### `FunctionTool` (one-off closures)

For quick inline tools that do not need a full struct:

```swift
let reverse = FunctionTool(
    name: "reverse",
    description: "Reverses a string",
    parameters: [
        ToolParameter(name: "s", description: "String to reverse", type: .string, isRequired: true)
    ]
) { args in
    let s = try args.require("s", as: String.self)
    return .string(String(s.reversed()))
}
```

Use `FunctionTool` inside a `@ToolBuilder` closure:

```swift
let agent = try Agent("You are a helpful text utility.",
    inferenceProvider: .foundationModels()
) {
    FunctionTool(
        name: "reverse",
        description: "Reverses a string",
        parameters: [
            ToolParameter(name: "s", description: "String to reverse", type: .string, isRequired: true)
        ]
    ) { args in
        let s = try args.require("s", as: String.self)
        return .string(String(s.reversed()))
    }
    FunctionTool(
        name: "uppercase",
        description: "Uppercases a string",
        parameters: [
            ToolParameter(name: "s", description: "String to uppercase", type: .string, isRequired: true)
        ]
    ) { args in
        let s = try args.require("s", as: String.self)
        return .string(s.uppercased())
    }
}
```

## Running Agents

### Single-turn `run()`

Returns an `AgentResult` with the agent's final output, tool call records, duration,
and optional token usage. `tokenUsage` is populated only when the inference provider
reports it on ``InferenceResponse/usage``. Apple Foundation Models does not expose a
token-count API, so that path leaves `tokenUsage` as `nil` — Swarm does not fabricate
counts. After a handoff, the parent `AgentResult` still reports the combined cost;
`MetricsCollector` attributes tokens per agent span so nested runs are not counted twice.

```swift
let result = try await agent.run("What is 2 + 2?")
print(result.output)       // "4"
print(result.duration)     // Duration
print(result.tokenUsage)   // TokenUsage(...) when the provider reports usage; else nil
```

### Streaming with `stream()`

`Agent.stream` runs the same loop as `run` and forwards `AgentEvent` values
through an observer — lifecycle, tool, and output events as they occur.

`.output(.token)` is an incremental text chunk when the provider streams
(Foundation Models does). If the provider only has a completion API, that
event is the full response in one chunk. This is not a separate token-level
decoder sitting in front of `run`.

```swift
for try await event in agent.stream("Tell me about Swift concurrency.") {
    switch event {
    case .output(.token(let token)):
        print(token, terminator: "")
    case .tool(.started(let call)):
        print("\n[tool: \(call.toolName)]")
    case .lifecycle(.completed(let result)):
        print("\nDone in \(result.duration)")
    default:
        break
    }
}
```

### Multi-turn `Conversation`

`Conversation` wraps an agent for stateful multi-turn chat:

```swift
let conversation = Conversation(with: agent)

let first = try await conversation.send("What is Swift?")
let followUp = try await conversation.send("How does its concurrency model work?")

// Full transcript
for message in await conversation.messages {
    print("\(message.role): \(message.text)")
}
```

## Multi-Agent Workflows

### Sequential pipeline

Compose multi-agent execution with `Workflow`:

```swift
let result = try await Workflow()
    .step(researchAgent)
    .step(analyzeAgent)
    .step(writerAgent)
    .run("Summarize the WWDC session on Swift concurrency.")
```

### Parallel fan-out

Run multiple agents in parallel and merge their results:

```swift
let result = try await Workflow()
    .parallel([bullAgent, bearAgent, analystAgent], merge: .structured)
    .run("Evaluate Apple's Q4 earnings.")
```

### Routing

Route to different agents based on input content:

```swift
let result = try await Workflow()
    .route { input in
        if input.contains("$") { return mathAgent }
        if input.contains("weather") { return weatherAgent }
        return generalAgent
    }
    .run("What is 15% of $240?")
```

### Durable: checkpoint and resume

Durable Hive checkpoint/resume requires the **`Integrations`** SwiftPM trait
(`--traits Integrations` or `.package(..., traits: ["Integrations"])`).

Without Integrations:

- `.durable.checkpoint` / `.checkpointing` and `WorkflowCheckpointing.*` still
  type-check (configuration-only APIs) and emit a once-per-process warning
  naming the missing trait and the rebuild remedy
  (`--traits Integrations` / `traits: ["Integrations"]`).
- `execute` / `.durable.execute` **throws** `WorkflowError.durableRuntimeUnavailable`
  when checkpointing is configured or `resumeFrom` is non-nil, with the same
  remedy in the error message.
- Bare workflow `run` / `execute` **without** durable configuration still runs as
  a non-durable workflow.

```swift
// Requires Integrations trait for checkpoint/resume at execute time.
// Lean builds warn at `.checkpoint` / `.checkpointing` and throw on execute.
let result = try await Workflow()
    .step(fetchAgent)
    .step(analyzeAgent)
    .durable
    .checkpoint(id: "report-v1", policy: .everyStep)
    .durable
    .checkpointing(.fileSystem(directory: checkpointsURL))
    .durable
    .execute("Summarize the WWDC session", resumeFrom: nil)
```

See [Durable Execution](./durable-execution.md) for step-granularity semantics
(a mid-step crash re-runs the whole step), signature stability rules, and
file-store pruning (keep-latest-16 per run by default).

## Choosing a Provider

Built-in inference is **Apple Foundation Models only**. Pass a provider via the
`inferenceProvider:` init parameter, or implement ``InferenceProvider`` for a
custom backend:

```swift
// On-device Apple Foundation Models (private, native tool calling)
let agent = try Agent("You are helpful.", inferenceProvider: .foundationModels())

// Dynamic profiles (WWDC 2026–aligned): switch instructions/tools/history per phase
enum Phase { case brainstorm, review }
let mode = ProfileMode(Phase.brainstorm)
let profile = ModeSwitchingDynamicProfile(mode: mode) { phase in
    switch phase {
    case .brainstorm:
        Profile(
            id: "brainstorm",
            instructions: "Ideate freely.",
            generation: .init(temperature: 1.0)
        )
    case .review:
        Profile(
            id: "review",
            instructions: "Be precise and concise.",
            history: .dropToolTranscriptAndKeepLast(count: 12),
            generation: .init(temperature: 0.2)
        )
    }
}
let profiled = try Agent(
    "You are helpful.",
    inferenceProvider: .foundationModels(profile: profile)
)
// Later, from a handoff tool or UI: mode.current = .review

// Custom backend
let agent = try Agent("You are helpful.", inferenceProvider: myCustomProvider)
```

Or using the `.environment()` modifier on any `AgentRuntime`:

```swift
agent.environment(\.inferenceProvider, myCustomProvider)
```

### Capture vs provider-owned tool loop (experimental)

By default Swarm **captures** Foundation Models tool calls (including a parallel
group in one turn) and executes them in the agent loop (guardrails, checkpoints,
per-iteration memory). Construct ``InferenceProvider/foundationModelsOwningToolLoop()``
for a provider-owned tool loop — Agent reads Capabilities and does not type-cast
the provider. See [Foundation Models](foundation-models.md) for the trade-off table.

```swift
let agent = try Agent(
    "Be helpful.",
    inferenceProvider: .foundationModelsOwningToolLoop()
) {
    WeatherTool()
}
```

### Resilience (opt-in)

By default agents do not retry inference. Attach policies through configuration:

```swift
let config = AgentConfiguration.default
    .resilience(ResilienceConfiguration(
        retryPolicy: .standard,
        circuitBreaker: CircuitBreakerSettings(failureThreshold: 5)
    ))
```

Retries wrap **provider calls only** (not tools), share the run's remaining timeout, and skip permanent failures such as guardrail rejection. See ``InferenceRetryability``.

### Structured output

`runStructured` uses Foundation Models guided generation when the JSON Schema
maps onto `GenerationSchema` (result `source` is `.providerNative`). `.jsonObject`
and unmappable schemas stay prompt-instruction + parse (`.promptFallback`).

### Provider resolution order

1. When `inferencePolicy.privacyRequired` is true: Foundation Models first, then only providers that report `privateInference` (explicit → environment → `Swarm.defaultProvider`); otherwise `AgentError.inferenceProviderUnavailable`
2. Explicit provider on the agent  
3. Task-local / environment override  
4. `Swarm.defaultProvider` from `await Swarm.configure(provider:)`  
5. Foundation Models when the system model is available  
6. Else `AgentError.inferenceProviderUnavailable`

## Requirements

| | Minimum |
|---|---|
| Swift | 6.2+ |
| iOS | 26.0+ |
| macOS | 26.0+ |
| Linux | Ubuntu 22.04+ with Swift 6.2 |

::: tip
The default Swarm graph is CI-tested on Ubuntu with Swift 6.2. Apple-only features such as Foundation Models, SwiftData, OSLog, and some built-in tool behavior are unavailable or different on Linux; use ``OpenAICompatibleProvider`` or inject a mock.
:::

## Next Steps

- **[Agents](../reference/front-facing-api.md#3-agent-struct-primary-init)** -- Agent types, configuration, tool calling
- **[Foundation Models](foundation-models.md)** -- Capture vs experimental native session mode
- **[Remote Providers](remote-providers.md)** -- OpenAI-compatible HTTP (OpenAI, Azure, OpenRouter, Ollama, LM Studio)
- **[Tools](../reference/front-facing-api.md#5-tool-and-functiontool)** -- `@Tool` macro, `FunctionTool`, `ToolCollection`, and `@ToolBuilder`
- **[Workflow](../reference/front-facing-api.md#7-workflow)** -- Sequential, parallel, and routed execution
- **[Memory](../reference/front-facing-api.md#9-memory-factories)** -- Conversation, vector, summary, persistent
