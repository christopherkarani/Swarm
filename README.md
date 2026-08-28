<div align="center">
  <a href="https://trendshift.io/repositories/21798?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-21798" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/21798/daily?language=Swift" alt="christopherkarani%2FSwarm | Trendshift" width="250" height="55"/></a>
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

Two agents, one pipeline, compiled to a DAG. Crash recovery is opt-in — enable the Integrations trait and durable checkpointing — and Swift concurrency safety is enforced at compile time.

## Install

Default **link** is **lean**: core Swarm + on-device Foundation Models. Graph/memory/web/Hive paths are trait-gated (off by default) and are not linked into Swarm unless you enable Integrations.

HiveCore, Membrane, and ContextCore are **native in-tree** `Sources/` targets (internal modules — not separate library products). Enabling Integrations **links** those modules plus Wax (still remote) and SwiftSoup; omitting the trait does not link them into Swarm. Lean resolve never pulls Hive/Membrane/ContextCore/Conduit **package identities**, and (with trait-gated product edges) also does **not** pin Wax, MetalANNS→GRDB, swift-crypto, swift-mutex, or SwiftSoup. Default remotes remain (swift-syntax via the default-on **Macros** trait, swift-log, MCP sdk, OTel, plus NIO transitives — including `swift-collections` via NIO). Disable Macros with `traits: []` to drop swift-syntax; use `FunctionTool` instead of `@Tool`. `SWARM_CORE_ONLY=1` drops the integration package block entirely. ContextCore / full Membrane session stack require Apple platforms (Metal/CoreML); Linux Integrations still builds Hive + MembraneCore + web helpers. DefaultAgentMemory uses a CoreML MiniLM model that is **not** bundled — call `SemanticEmbeddingAvailability.ensureModelAvailable()` to download it on demand. Without the model, ContextCore falls back to deterministic pseudo-embeddings, logs a once-per-process warning naming that API, and `DefaultAgentMemory.isSemanticMemoryAvailable` reports `false`.

**Root-package note:** bare `swift build` / `swift test` on this repo compile every registered target, so integration modules need either `--traits Integrations` or the lean CI helper (`scripts/ci/lean-build-test.sh`). App consumers only build reachable targets and stay lean without that helper.

```swift
// Lean default link (recommended for most apps). Macros are on by default.
.package(url: "https://github.com/christopherkarani/Swarm.git", from: "0.6.2")

// Full integrations: durable Hive workflows, ContextCore+Wax default memory,
// Membrane adapters, and web helpers. Integrations also enables Macros.
.package(
    url: "https://github.com/christopherkarani/Swarm.git",
    from: "0.6.2",
    traits: ["Integrations"]
)

// Macro-free lean: drops swift-syntax. You lose @Tool, @Parameter, #Prompt,
// and @Traceable — use FunctionTool instead.
.package(
    url: "https://github.com/christopherkarani/Swarm.git",
    from: "0.6.2",
    traits: []
)
```

```swift
// FunctionTool compiles without the Macros trait
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
```

From a checkout of this package:

```bash
# Lean (root package): product-scoped build, or scripts/ci/lean-build-test.sh
swift build --product Swarm --product SwarmMCP --product SwarmOpenTelemetry \
  --product SwarmMembrane --product SwarmCapabilityShowcase
# SwarmMembrane is a deprecated hollow re-export of Swarm; import Swarm
# instead. The product will be removed in 0.7.0.
# Full graph
swift build --traits Integrations
swift test --no-parallel --traits Integrations
swift run --traits Integrations SwarmCapabilityShowcase matrix
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
// Built-in backend: Apple Foundation Models (no API key on supported devices)
let agent = try Agent("Answer finance questions using real data.",
    configuration: .default.name("Analyst"),
    inferenceProvider: .foundationModels()) {
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
- **Workflows can survive crashes.** Durable checkpointing (Integrations trait) lets you resume from an explicit checkpoint ID.
- **Built-in inference is on-device Foundation Models, plus an OpenAI-compatible remote provider.** Linux and machines without Apple Intelligence use `.openAICompatible(...)`; the agent loop stays the same.
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
# Capability showcase matrix covers durable workflows; enable Integrations
swift run --traits Integrations SwarmCapabilityShowcase list
swift run --traits Integrations SwarmCapabilityShowcase matrix
swift run --traits Integrations SwarmCapabilityShowcase run handoff
swift run --traits Integrations SwarmCapabilityShowcase smoke
```

The deterministic matrix is CI-safe. Live-provider smoke coverage is opt-in through environment variables. See [docs/guide/capability-showcase.md](docs/guide/capability-showcase.md) for the scenario catalog and smoke-mode details.

### End-to-end example apps

Two minimal, buildable apps under `Examples/` stress the public API:

| Example | What it proves |
| --- | --- |
| [`Examples/OnDeviceChat`](Examples/OnDeviceChat) | Foundation Models chat with `@Tool`, streaming, and multi-turn `Conversation` (zero API keys; `--demo` for CI) |
| [`Examples/MultiAgentPipeline`](Examples/MultiAgentPipeline) | Sequential + parallel workflows and durable checkpoint/resume (`--demo` for CI; requires Integrations) |
| [`Examples/WaxChat`](Examples/WaxChat) | Wax durable memory + websearch chat (`--demo` for CI; requires Integrations) |
| [`Examples/CodeReviewer`](Examples/CodeReviewer) | Lightweight CLI that links Swarm and prints a deterministic review plan |

```bash
cd Examples/OnDeviceChat && swift run OnDeviceChat --demo
cd Examples/MultiAgentPipeline && swift run MultiAgentPipeline --demo
cd Examples/WaxChat && swift run WaxChat --demo
```

### Optional demos

Package-root demo executables are opt-in so the default library graph stays focused on the framework products:

```bash
SWARM_INCLUDE_DEMO=1 swift build
SWARM_INCLUDE_DEMO=1 swift run SwarmDemo
SWARM_INCLUDE_DEMO=1 swift run SwarmMCPServerDemo
```

## Foundation Models First

For Apple platforms, use the built-in on-device path — no API keys:

```swift
import Swarm

// Requires macOS/iOS 26+ and Apple Intelligence available on the device.
let agent = try Agent(
    "You are a private on-device assistant.",
    inferenceProvider: .foundationModels()
) {
    // @Tool structs or FunctionTool values
}

let result = try await agent.run("Summarize my notes.")
```

Notes that matter in production:

- **Availability**: use `FoundationModelsInferenceProvider.ifAvailable()` or check `FoundationModelsInferenceProvider.isAvailable` before assuming the system model is ready.
- **Tool calling**: Swarm bridges `@Tool` / `ToolSchema` to Apple's `FoundationModels.Tool` and executes tools in the agent loop with guardrails intact (capture mode, default — all tool calls from a parallel group are recovered). Opt in to experimental [native session mode](docs/guide/foundation-models.md) for Apple's inner tool loop and token streaming with tools.
- **Streaming tool calls**: not advertised as token-level tool streaming; `Agent.stream` observes the same `run` loop via `AgentEvent` (lifecycle, tools, and `.output(.token)` chunks). Foundation Models yields incremental text deltas; providers without a streaming API emit the full response as a single chunk.
- **Structured outputs**: `runStructured` uses Foundation Models guided generation when the JSON Schema maps onto `GenerationSchema` (`source: .providerNative`); otherwise it is prompt instruction + parse (`source: .promptFallback`). `.jsonObject` always uses the fallback path.
- **Dynamic profiles**: `.foundationModels(profile:)` re-resolves instructions/tools/history every turn (WWDC 2026–aligned Swarm API).
- **Linux / CI**: Foundation Models is compile-time gated. Use `.openAICompatible(.ollama(model:))` (or any OpenAI-compatible host), inject a mock, or use the deterministic `--demo` modes in `Examples/`.

### OpenAI-compatible remote provider

No Apple Intelligence required. Same agent loop, `URLSession` only:

```swift
// Local (Ollama). Data stays on loopback HTTP — not on-device Foundation Models.
let local = try Agent(
    "Be helpful.",
    inferenceProvider: .openAICompatible(.ollama(model: "llama3.2"))
)

// Cloud. Prompt content leaves the device.
let cloud = try Agent(
    "Be helpful.",
    inferenceProvider: .openAICompatible(
        .openAI(apiKey: "sk-...", model: "gpt-4o")
    )
)
```

| Host | Factory | Leaves the device? |
|---|---|---|
| OpenAI | `.openAI(apiKey:model:)` | Yes — to OpenAI |
| Azure OpenAI | `.azureOpenAI(resource:deployment:apiKey:)` | Yes — to Azure |
| OpenRouter | `.openRouter(apiKey:model:)` | Yes — to OpenRouter |
| Ollama | `.ollama(model:)` | Yes — to `localhost` HTTP |
| LM Studio | `.lmStudio(model:)` | Yes — to `localhost` HTTP |

See [Remote Providers](docs/guide/remote-providers.md) for full snippets, structured-output honesty, and live Ollama test setup.

### Multi-agent pipeline

```swift
// WebSearchTool requires the Integrations trait and an API key
// (lean builds compile this initializer, warn immediately, and throw on execute).
let researcher = try Agent("Research the topic and extract key facts.",
    inferenceProvider: .foundationModels()) {
    WebSearchTool(apiKey: "YOUR_API_KEY")
}

let writer = try Agent("Write a concise summary from the research.",
    inferenceProvider: .foundationModels())

let result = try await Workflow()
    .step(researcher)
    .step(writer)
    .run("Latest advances in on-device ML")
```

Each agent resolves its own provider. Pass `inferenceProvider:` per agent (as above), or call `await Swarm.configure(provider: myProvider)` once at app startup to share a default across every agent that doesn't specify one.

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

`Agent.stream` runs the same agent loop as `run`, forwarding `AgentEvent` values through an observer. You get lifecycle, tool, and output events as they happen — not a separate token decoder.

`.output(.token)` is an incremental text chunk when the provider streams (Foundation Models does). If the provider only has a completion API, that event is the full response in one chunk. Tool calls still complete as capture-then-execute turns unless the provider implements tool-call streaming.

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
    memory: .vector(embeddingProvider: myEmbedder, similarityThreshold: 0.75),
    inferenceProvider: .foundationModels()) {
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

let agent = try Agent("Text utilities.") {
    reverse
}
```

#### Crash-resumable workflows

```swift
let workflow = Workflow()
    .step(monitor)
    .durable.checkpoint(id: "monitor-v1", policy: .everyStep)
    .durable.checkpointing(.fileSystem(directory: checkpointsURL))

let resumed = try await workflow.durable.execute("watch", resumeFrom: "monitor-v1")
```

A mid-step crash re-runs that whole step. File stores keep the newest 16
checkpoints per run (configurable) and identify steps by kind, position, and
optional `signature:` — not source line numbers. See
[Durable Execution](docs/guide/durable-execution.md).

#### Provider selection

```swift
// Built-in: on-device Foundation Models (no API key)
let local = try Agent("Be helpful.", inferenceProvider: .foundationModels())

// Built-in: OpenAI-compatible remote / local HTTP (Linux-friendly)
let remote = try Agent(
    "Be helpful.",
    inferenceProvider: .openAICompatible(.ollama(model: "llama3.2"))
)

// Custom backend: any type conforming to InferenceProvider
let custom = try Agent("Be helpful.", inferenceProvider: myCustomProvider)

// Or swap at runtime via environment
let modified = agent.environment(\.inferenceProvider, myCustomProvider)
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
| **Crash recovery** | Checkpoints (Integrations) | n/a | Partial |
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
| **Observability** | `AgentObserver`, `Tracer`, `SwiftLogTracer`, per-agent token metrics when the provider reports usage (Foundation Models does not) |
| **MCP** | Model Context Protocol client and server support |
| **Providers** | Built-in Apple Foundation Models (on-device) and `OpenAICompatibleProvider` (OpenAI / Azure / OpenRouter / Ollama / LM Studio); inject any `InferenceProvider` for other backends |
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
│ Foundation Models · OpenAI-compatible · custom provider     │
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

The default Swarm graph is CI-tested on Ubuntu with Swift 6.2. Apple-only features such as Foundation Models, SwiftData, OSLog, and some built-in tool behavior are unavailable or different on Linux; use ``OpenAICompatibleProvider`` (stubbed in CI, live against Ollama when `SWARM_OLLAMA_LIVE_TESTS=1`) or inject a mock.

## Documentation

| | |
|---|---|
| [Getting Started](docs/guide/getting-started.md) | Installation, first agent, workflows |
| [Remote Providers](docs/guide/remote-providers.md) | OpenAI-compatible provider (OpenAI, Azure, OpenRouter, Ollama, LM Studio) |
| [OpenTelemetry Tracing](docs/guide/opentelemetry-tracing.md) | OTLP/HTTP JSON export of agent and LLM spans, plus W3C `traceparent` on outbound HTTP |
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
