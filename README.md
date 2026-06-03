<div align="center">
  <img alt="Swarm Swift Agent Framework" src="docs/public/banner.svg" />

  <p><strong>A Swift framework for building agents and multi-agent workflows.</strong></p>

  <p>
    <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.2-orange.svg" alt="Swift 6.2" /></a>
    <a href="https://swift.org"><img src="https://img.shields.io/badge/Platforms-iOS%2026%2B%20|%20macOS%2026%2B%20|%20Linux-blue.svg" alt="Platforms" /></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT" /></a>
    <a href="https://swift.org/package-manager/"><img src="https://img.shields.io/badge/SPM-compatible-brightgreen.svg" alt="SPM Compatible" /></a>
    <a href="https://discord.gg/NHgNh7HJ6M"><img src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fdiscord.com%2Fapi%2Fv10%2Finvites%2FNHgNh7HJ6M%3Fwith_counts%3Dtrue&query=%24.approximate_presence_count&suffix=%20online&logo=discord&label=Discord&color=5865F2&style=flat" alt="Discord" /></a>
  </p>
</div>

```swift
let result = try await Workflow()
    .step(researchAgent)
    .step(writerAgent)
    .run("Summarize the latest WWDC session on Swift concurrency.")
```

<div align="center">
  <img alt="Swarm API Flow" src="docs/public/api-flow.gif" width="600" />
</div>

Two agents, one pipeline, compiled to a DAG with crash recovery and Swift concurrency safety.

## Install

```swift
.package(url: "https://github.com/christopherkarani/Swarm.git", from: "0.6.0")
```


## Quick Start

```swift
import Swarm

// The @Tool macro generates the JSON schema at compile time
@Tool("Looks up the current stock price")
struct PriceTool {
    @Parameter("Ticker symbol") var ticker: String
    func execute() async throws -> String { "182.50" }
}

// Create an agent with unlabeled instructions first and tools in the trailing @ToolBuilder closure
let agent = try Agent("Answer finance questions using real data.",
    configuration: .init(name: "Analyst"),
    inferenceProvider: .anthropic(key: "sk-...")) {
    PriceTool()
    CalculatorTool()
}

let result = try await agent.run("What is AAPL trading at?")
print(result.output) // "Apple (AAPL) is currently trading at $182.50."
```

That is a working agent with type-safe tool calling. Swarm also supports **AGENTS.md** and **SKILL.md** for declarative agent specs and reusable skills — see the [Getting Started guide](docs/guide/getting-started.md) for the full workspace layout.

## Why Swarm

- **Swift concurrency is part of the surface.** Swift 6.2 `StrictConcurrency` is enabled across the package.
- **Tools stay type-safe.** The `@Tool` macro generates JSON schemas from Swift structs.
- **Workflows can survive crashes.** Durable workflow checkpointing lets you resume from an explicit checkpoint ID.
- **Cloud and on-device models use the same abstractions.** Foundation Models, Anthropic, OpenAI, Ollama, Gemini, MiniMax, OpenRouter, and MLX all fit the same shape.
- **It is written in Swift all the way down.** `AsyncThrowingStream`, actors, result builders, and macros are first-class here.

## Examples

### Capability matrix showcase

Swarm now ships with an in-repo capability showcase that exercises the stable surface area in one deterministic matrix:

- agents and tools
- streaming
- conversation plus session persistence
- sequential, parallel, routed, and repeat-until workflows
- handoffs
- memory
- on-device workspace loading
- guardrails
- resilience helpers
- durable checkpoint and resume
- observability
- MCP discovery and tool bridging
- provider selection

Run it locally:

```bash
swift run SwarmCapabilityShowcase list
swift run SwarmCapabilityShowcase matrix
swift run SwarmCapabilityShowcase run handoff
swift run SwarmCapabilityShowcase smoke
```

The deterministic matrix is CI-safe. Live-provider smoke coverage is opt-in through environment variables. See [docs/guide/capability-showcase.md](docs/guide/capability-showcase.md) for the scenario catalog and smoke-mode details.

### Optional demos

Demo executables are opt-in so the default library graph stays focused on the framework products:

```bash
SWARM_INCLUDE_DEMO=1 swift build
SWARM_INCLUDE_DEMO=1 swift run SwarmDemo
SWARM_INCLUDE_DEMO=1 swift run SwarmMCPServerDemo
```

### Multi-agent pipeline

```swift
let researcher = try Agent("Research the topic and extract key facts.",
    inferenceProvider: .anthropic(key: "sk-...")) {
    WebSearchTool()
}

let writer = try Agent("Write a concise summary from the research.",
    inferenceProvider: .anthropic(key: "sk-..."))

let result = try await Workflow()
    .step(researcher)
    .step(writer)
    .run("Latest advances in on-device ML")
```

Each agent resolves its own provider. Pass `inferenceProvider:` per agent (as above), or call `await Swarm.configure(provider: .anthropic(apiKey: "..."))` once at app startup to share a default across every agent that doesn't specify one.

### Parallel fan-out

```swift
let result = try await Workflow()
    .parallel([bullAgent, bearAgent, analystAgent], merge: .structured)
    .run("Evaluate Apple's Q4 earnings.")
// Three perspectives, merged into one output.
```

### Dynamic routing

```swift
let result = try await Workflow()
    .route { input in
        if input.contains("$") { return mathAgent }
        if input.contains("weather") { return weatherAgent }
        return generalAgent
    }
    .run("What is 15% of $240?")
```

### Streaming

```swift
for try await event in agent.stream("Summarize the changelog.") {
    switch event {
    case .output(.token(let t)):           print(t, terminator: "")
    case .tool(.completed(let call, _)):   print("\n[tool: \(call.toolName)]")
    case .lifecycle(.completed(let r)):     print("\nDone in \(r.duration)")
    case .lifecycle(.failed(let error)):    print("\nError: \(error)")
    default: break // Other events include .output(.thinking(...)), .handoff(...), .observation(...), and .lifecycle(.iterationStarted(...)).
    }
}
```

<details>
<summary><strong>More examples</strong></summary>

#### Semantic memory

```swift
let agent = try Agent("You remember past conversations.",
    inferenceProvider: .anthropic(key: "sk-..."),
    memory: .vector(embeddingProvider: myEmbedder, similarityThreshold: 0.75)) {
    // tools
}
```

#### Guardrails

```swift
let agent = try Agent("You are a helpful assistant.",
    inputGuardrails: [InputGuard.maxLength(5000), InputGuard.notEmpty()],
    outputGuardrails: [OutputGuard.maxLength(2000)])
```

#### Closure tools

```swift
let reverse = FunctionTool(
    name: "reverse",
    description: "Reverses a string",
    parameters: [ToolParameter(name: "text", description: "Text to reverse", type: .string, isRequired: true)]
) { args in
    let text = try args.require("text", as: String.self)
    return .string(String(text.reversed()))
}

let agent = try Agent("Text utilities.", tools: [reverse])
```

#### Crash-resumable workflows

```swift
let workflow = Workflow()
    .step(monitor)
    .durable.checkpoint(id: "monitor-v1", policy: .everyStep)
    .durable.checkpointing(.fileSystem(directory: checkpointsURL))

let resumed = try await workflow.durable.execute("watch", resumeFrom: "monitor-v1")
```

#### Provider switching

```swift
// On-device, private, no API key needed
let local = try Agent("Be helpful.", inferenceProvider: .foundationModels())

// Cloud
let cloud = try Agent("Be helpful.", inferenceProvider: .anthropic(key: k))

// Or swap at runtime via environment
let modified = agent.environment(\.inferenceProvider, .ollama(model: "mistral"))
```

#### Conversation

```swift
let conversation = Conversation(with: agent)

let response1 = try await conversation.send("What's the weather?")
let response2 = try await conversation.send("And tomorrow?") // Context preserved

for message in await conversation.messages {
    print("\(message.role): \(message.text)")
}
```

</details>

## How Swarm Compares

| | **Swarm** | LangChain | AutoGen |
|---|---|---|---|
| **Language** | Swift 6.2 | Python | Python |
| **Data race safety** | Compile-time | Runtime | Runtime |
| **On-device LLM** | Foundation Models | n/a | n/a |
| **Execution model** | Typed `Workflow` graph | Loop-based | Loop-based |
| **Crash recovery** | Checkpoints | n/a | Partial |
| **Type-safe tools** | `@Tool` macro (compile-time) | Decorators (runtime) | Runtime |
| **Streaming** | `AsyncThrowingStream` | Callbacks | Callbacks |
| **iOS / macOS native** | First-class | n/a | n/a |

## What's Included

| | |
|---|---|
| **Agents** | `Agent` struct with `@ToolBuilder` trailing closure, `AgentRuntime` protocol |
| **Workflows** | `Workflow`: `.step()`, `.parallel()`, `.route()`, `.repeatUntil()`, `.timeout()` |
| **Tools** | `@Tool` macro, `FunctionTool`, `@ToolBuilder`, parallel execution |
| **Memory** | `.conversation(maxMessages:)`, `.vector(embeddingProvider:similarityThreshold:maxResults:)`, `.slidingWindow(maxTokens:)`, `.summary(configuration:summarizer:)`, `.hybrid(configuration:summarizer:)` |
| **Guardrails** | `InputGuard.maxLength()`, `InputGuard.notEmpty()`, `InputGuard.custom()`, `OutputGuard.maxLength()`, `OutputGuard.custom()` |
| **Conversation** | `Conversation` actor for stateful multi-turn dialogue |
| **Resilience** | 7 backoff strategies, circuit breaker, fallback chains, rate limiting |
| **Observability** | `AgentObserver`, `Tracer`, `SwiftLogTracer`, per-agent token metrics |
| **MCP** | Model Context Protocol client and server support |
| **Providers** | Foundation Models, Anthropic, OpenAI, Ollama, Gemini, MiniMax, OpenRouter, MLX via [Conduit](https://github.com/christopherkarani/Conduit) |
| **Macros** | `@Tool`, `@Parameter`, `@Traceable`, `#Prompt` |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Your Application                       │
│          iOS 26+  ·  macOS 26+  ·  Linux (Ubuntu 22.04+)   │
├─────────────────────────────────────────────────────────────┤
│     Workflow  ·  Conversation  ·  .run()  ·  .stream()      │
├─────────────────────────────────────────────────────────────┤
│  Agents              Memory              Tools              │
│  Agent (struct)      Memory factories    @Tool macro        │
│  AgentRuntime        Conversation        FunctionTool       │
│                      (dot-syntax)        @ToolBuilder       │
├─────────────────────────────────────────────────────────────┤
│  InputGuard · OutputGuard · Resilience · Observability · MCP│
├─────────────────────────────────────────────────────────────┤
│              Durable Graph Runtime (internal)               │
│   Workflow Graph  ·  Checkpointing  ·  Deterministic retry │
├─────────────────────────────────────────────────────────────┤
│              InferenceProvider (pluggable)                   │
│ Foundation Models · Anthropic · OpenAI · Ollama · OpenRouter│
└─────────────────────────────────────────────────────────────┘
```

## Requirements

| Platform | Minimum |
|----------|---------|
| Swift    | 6.2+    |
| iOS      | 26.0+   |
| macOS    | 26.0+   |
| tvOS     | 26.0+   |
| Linux    | Ubuntu 22.04+ with Swift 6.2 |

The default Swarm graph is CI-tested on Ubuntu with Swift 6.2. Apple-only features such as Foundation Models, SwiftData, OSLog, and some built-in tool behavior are unavailable or different on Linux; cloud providers and Ollama use the shared `InferenceProvider` surface.

## Documentation

| | |
|---|---|
| [Getting Started](docs/guide/getting-started.md) | Installation, first agent, workflows |
| [OpenTelemetry Tracing](docs/guide/opentelemetry-tracing.md) | Export agent and LLM spans, with optional trace header injection for provider HTTP requests |
| [API Reference](docs/reference/api-catalog.md) | Every type, protocol, and API |
| [Front-Facing API](docs/reference/front-facing-api.md) | Public API surface |
| [Why Swarm?](docs/guide/why-swarm.md) | Design philosophy and architecture |

## Contributing

1. Fork → branch → `swift test` → PR
2. All public types must be `Sendable`; the compiler enforces it
3. Format with `swiftformat Sources Tests --lint --config .swiftformat`

Bug reports and feature requests: [GitHub Issues](https://github.com/christopherkarani/Swarm/issues)

## Community

[GitHub Issues](https://github.com/christopherkarani/Swarm/issues) · [Discussions](https://github.com/christopherkarani/Swarm/discussions) · [@ckarani7](https://x.com/ckarani7)

If Swarm saves you time, [a star](https://github.com/christopherkarani/Swarm) helps others find it.

## License

Released under the [MIT License](LICENSE).
