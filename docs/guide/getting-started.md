# Getting Started

Get a working Swarm agent in under a minute.

## Installation

### Swift Package Manager

Add Swarm to your `Package.swift`:

```swift
// Lean default (core + Foundation Models). No Integrations trait.
dependencies: [
    .package(url: "https://github.com/christopherkarani/Swarm.git", from: "0.6.0")
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
| Durable Hive checkpoint/resume | Configuration type-checks; execute with checkpoint/resume configured throws | Full durable engine |
| Membrane adapters | No-op / unavailable backends | Real Membrane session adapters |
| Web helpers (`websearch`, page fetch/HTML parse) | Not injected / gated | Full web tool support |

```swift
.package(
    url: "https://github.com/christopherkarani/Swarm.git",
    from: "0.6.0",
    traits: ["Integrations"]
)
```

HiveCore, Membrane, and ContextCore are native in-tree modules under Swarm
`Sources/` (internal targets, not separate products). Wax remains an external
package and is linked only with Integrations. Omitting the trait does **not**
link Integrations modules into your app, and lean resolve does not pull
Hive/Membrane/ContextCore packages.

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

### Custom `InferenceProvider`

For non–Foundation Models backends, implement or inject any type that conforms to
`InferenceProvider` and pass it explicitly (or via `await Swarm.configure(provider:)`):

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

Returns an `AgentResult` with the agent's final output, tool call records, token usage, and duration:

```swift
let result = try await agent.run("What is 2 + 2?")
print(result.output)       // "4"
print(result.duration)     // Duration
print(result.tokenUsage)   // TokenUsage(inputTokens:, outputTokens:)
```

### Streaming with `stream()`

Stream `AgentEvent` values in real time -- ideal for live UI:

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
  type-check (configuration-only APIs).
- `execute` / `.durable.execute` **throws** when checkpointing is configured or
  `resumeFrom` is non-nil.
- Bare workflow `run` / `execute` **without** durable configuration still runs as
  a non-durable workflow.

```swift
// Requires Integrations trait for checkpoint/resume at execute time
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
The default Swarm graph is CI-tested on Ubuntu with Swift 6.2. Apple-only features such as Foundation Models, SwiftData, OSLog, and some built-in tool behavior are unavailable or different on Linux; inject a mock or custom `InferenceProvider` there.
:::

## Next Steps

- **[Agents](../reference/front-facing-api.md#3-agent-struct-primary-init)** -- Agent types, configuration, tool calling
- **[Tools](../reference/front-facing-api.md#5-tool-and-functiontool)** -- `@Tool` macro, `FunctionTool`, `ToolCollection`, and `@ToolBuilder`
- **[Workflow](../reference/front-facing-api.md#7-workflow)** -- Sequential, parallel, and routed execution
- **[Memory](../reference/front-facing-api.md#9-memory-factories)** -- Conversation, vector, summary, persistent
