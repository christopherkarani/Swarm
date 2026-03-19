<div align="center">
  <img alt="Swarm — Swift Agent Framework" src="docs/public/banner.svg" />

  <p><strong>The agent framework Swift has been missing.</strong></p>

  <p>
    <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.2-orange.svg" alt="Swift 6.2" /></a>
    <a href="https://swift.org"><img src="https://img.shields.io/badge/Platforms-iOS%2026%2B%20|%20macOS%2026%2B%20|%20Linux-blue.svg" alt="Platforms" /></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT" /></a>
    <a href="https://swift.org/package-manager/"><img src="https://img.shields.io/badge/SPM-compatible-brightgreen.svg" alt="SPM Compatible" /></a>
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

Two agents. One pipeline. Compiled to a DAG. Crash-resumable. Zero data races.

## Install

```swift
.package(url: "https://github.com/christopherkarani/Swarm.git", from: "0.4.0")
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

// Create an agent — unlabeled instructions first, tools in @ToolBuilder trailing closure
let agent = try Agent("Answer finance questions using real data.",
    configuration: .init(name: "Analyst"),
    inferenceProvider: .anthropic(key: "sk-...")) {
    PriceTool()
    CalculatorTool()
}

let result = try await agent.run("What is AAPL trading at?")
print(result.output) // "Apple (AAPL) is currently trading at $182.50."
```

That's a working agent with type-safe tool calling. Keep reading for multi-agent workflows, memory, guardrails, and more.

## Why Swarm

- **Data races are compile errors.** Swift 6.2 `StrictConcurrency` is on every target. Non-`Sendable` types crossing actor boundaries won't build. Period.
- **Type-safe tools at compile time.** The `@Tool` macro generates JSON schemas from your Swift structs. No runtime introspection, no string-typed arguments, no surprises.
- **Workflows survive crashes.** [Hive](https://github.com/christopherkarani/Hive) checkpointing lets you resume any workflow from an explicit checkpoint ID.
- **On-device or cloud — same code.** Foundation Models, Anthropic, OpenAI, Ollama, Gemini, MLX. Swap with one line.
- **Pure Swift.** Built on `AsyncThrowingStream`, actors, result builders, and macros. Not a Python port.

## Examples

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
    default: break
    }
}
```

<details>
<summary><strong>More examples</strong></summary>

#### Semantic memory — on-device SIMD, no cloud API

```swift
let agent = try Agent("You remember past conversations.",
    inferenceProvider: .anthropic(key: "sk-..."),
    memory: .vector(embeddingProvider: myEmbedder, threshold: 0.75)) {
    // tools
}
```

#### Guardrails

```swift
let agent = try Agent("You are a helpful assistant.",
    inputGuardrails: [GuardrailSpec.maxInput(5000), GuardrailSpec.inputNotEmpty],
    outputGuardrails: [GuardrailSpec.maxOutput(2000)])
```

#### Closure tools — no struct needed

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
// On-device, private — no API key needed
let local = try Agent("Be helpful.", inferenceProvider: .foundationModels)

// Cloud
let cloud = try Agent("Be helpful.", inferenceProvider: .anthropic(key: k))

// Or swap at runtime via environment
let modified = agent.environment(\.inferenceProvider, .ollama(model: "mistral"))
```

#### Conversation — stateful multi-turn

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
| **On-device LLM** | Foundation Models | — | — |
| **Execution engine** | Compiled DAG (Hive) | Loop-based | Loop-based |
| **Crash recovery** | Checkpoints | — | Partial |
| **Type-safe tools** | `@Tool` macro (compile-time) | Decorators (runtime) | Runtime |
| **Streaming** | `AsyncThrowingStream` | Callbacks | Callbacks |
| **iOS / macOS native** | First-class | — | — |

## What's Included

| | |
|---|---|
| **Agents** | `Agent` struct with `@ToolBuilder` trailing closure, `AgentRuntime` protocol |
| **Workflows** | `Workflow`: `.step()`, `.parallel()`, `.route()`, `.repeatUntil()`, `.timeout()` |
| **Tools** | `@Tool` macro, `FunctionTool`, `@ToolBuilder`, parallel execution |
| **Memory** | `MemoryOption.conversation(limit:)`, `MemoryOption.vector(embeddingProvider:)`, `MemoryOption.slidingWindow(count:)`, `MemoryOption.summary(summarizer:)` |
| **Guardrails** | `GuardrailSpec.maxInput()`, `GuardrailSpec.maxOutput()`, `GuardrailSpec.inputNotEmpty`, `GuardrailSpec.outputNotEmpty`, `GuardrailSpec.customInput()`, `GuardrailSpec.customOutput()` |
| **Conversation** | `Conversation` actor for stateful multi-turn dialogue |
| **Resilience** | 7 backoff strategies, circuit breaker, fallback chains, rate limiting |
| **Observability** | `AgentObserver`, `Tracer`, `SwiftLogTracer`, per-agent token metrics |
| **MCP** | Model Context Protocol — client and server |
| **Providers** | Foundation Models, Anthropic, OpenAI, Ollama, Gemini, OpenRouter, MLX via [Conduit](https://github.com/christopherkarani/Conduit) |
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
│  Agent (struct)      MemoryOption        @Tool macro        │
│  AgentRuntime        Conversation        FunctionTool       │
│                      (dot-syntax)        @ToolBuilder       │
├─────────────────────────────────────────────────────────────┤
│  GuardrailSpec  ·  Resilience  ·  Observability  ·  MCP    │
├─────────────────────────────────────────────────────────────┤
│                    Hive Runtime (optional)                   │
│   Compiled DAG  ·  Checkpointing  ·  Deterministic retry   │
├─────────────────────────────────────────────────────────────┤
│              InferenceProvider (pluggable)                   │
│   Foundation Models · Anthropic · OpenAI · Ollama · MLX     │
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

Foundation Models require iOS 26 / macOS 26. Cloud providers work on any Swift 6.2 platform including Linux.

## Documentation

| | |
|---|---|
| [Getting Started](docs/guide/getting-started.md) | Installation, first agent, workflows |
| [API Reference](docs/reference/api-catalog.md) | Every type, protocol, and API |
| [Front-Facing API](docs/reference/front-facing-api.md) | Public API surface |
| [Why Swarm?](docs/guide/why-swarm.md) | Design philosophy and architecture |

## Contributing

1. Fork → branch → `swift test` → PR
2. All public types must be `Sendable` — the compiler enforces it
3. Format with `swift package plugin --allow-writing-to-package-directory swiftformat`

Bug reports and feature requests: [GitHub Issues](https://github.com/christopherkarani/Swarm/issues)

## Community

[GitHub Issues](https://github.com/christopherkarani/Swarm/issues) · [Discussions](https://github.com/christopherkarani/Swarm/discussions) · [@ckarani7](https://x.com/ckarani7)

If Swarm saves you time, [a star](https://github.com/christopherkarani/Swarm) helps others find it.

## License

Released under the [MIT License](LICENSE).
