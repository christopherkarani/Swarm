# Swarm

### Build production AI agents in Swift.

Swarm is a Swift-native agent runtime for type-safe tools, on-device Apple
Foundation Models, composable workflows, memory, guardrails, and streaming.
Build for iOS, macOS, and Linux with the same agent loop.

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2026%2B%20%7C%20macOS%2026%2B%20%7C%20Linux-blue.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)

[Get started](docs/guide/getting-started.md) · [Browse examples](Examples) ·
[⭐ Star on GitHub](https://github.com/christopherkarani/Swarm)

```swift
import Swarm

@Tool("Looks up a stock price")
struct PriceTool {
    @Parameter("Ticker symbol") var ticker: String

    func execute() async throws -> String {
        "AAPL: $182.50"
    }
}

let agent = try Agent(
    "Answer finance questions using available tools.",
    configuration: .default.name("Analyst"),
    inferenceProvider: .foundationModels()
) {
    PriceTool()
}

let result = try await agent.run("What is AAPL trading at?")
print(result.output)
```

The example uses Apple Foundation Models on supported devices. Use an
OpenAI-compatible provider, Ollama, a mock provider, or the deterministic
examples when Foundation Models is unavailable.

## Install

Add Swarm with Swift Package Manager:

```swift
dependencies: [
    .package(
        url: "https://github.com/christopherkarani/Swarm.git",
        from: "0.6.2"
    )
]
```

The default package is lean: core Swarm, Foundation Models, and macros.
Lean resolve pins **swift-syntax** (via the default-on Macros trait) and
**swift-log** only — not the MCP Swift SDK or OpenTelemetry. Add traits for
optional surfaces:

```swift
// Durable graph, ContextCore/Wax memory, Membrane, web helpers
.package(
    url: "https://github.com/christopherkarani/Swarm.git",
    from: "0.6.2",
    traits: ["Integrations"]
)

// MCP server adapter (SwarmMCP + MCP Swift SDK). Also enables Macros.
.package(
    url: "https://github.com/christopherkarani/Swarm.git",
    from: "0.6.2",
    traits: ["MCP"]
)

// OpenTelemetry wrappers (SwarmOpenTelemetry). Also enables Macros.
.package(
    url: "https://github.com/christopherkarani/Swarm.git",
    from: "0.6.2",
    traits: ["OpenTelemetry"]
)
```

Macros are enabled by default. If you want a macro-free build, use
`traits: []` and define tools with `FunctionTool`. Specifying traits replaces
defaults, so combine as needed — for example
`traits: ["Integrations", "MCP", "OpenTelemetry"]`.

## Why Swarm

Swarm uses Swift 6.2 strict concurrency, so values crossing actor boundaries
must pass compiler checks.

Apple Foundation Models gives supported devices an on-device inference path.
When you need a local HTTP model or a cloud API, the same agent loop works with
Ollama, LM Studio, OpenAI-compatible providers, or your own provider.

The `@Tool` macro generates tool schemas from Swift types at compile time.
`FunctionTool` is available when you do not want macros.

`Workflow` lets you chain, parallelize, route, repeat, and time out agent work.
Add memory, guardrails, retries, fallbacks, streaming, tracing, MCP, and
optional checkpoint/resume as your application grows.

## Build a workflow

Agents compose into sequential, parallel, and routed workflows:

```swift
let researcher = try Agent(
    "Research the topic and extract key facts.",
    inferenceProvider: .foundationModels()
)

let writer = try Agent(
    "Write a concise summary from the research.",
    inferenceProvider: .foundationModels()
)

let result = try await Workflow()
    .step(researcher)
    .step(writer)
    .run("Latest advances in on-device ML")
```

For fan-out and routing:

```swift
let result = try await Workflow()
    .parallel([bullAgent, bearAgent, analystAgent], merge: .structured)
    .run("Evaluate Apple's Q4 earnings.")

let routed = try await Workflow()
    .route { input in
        input.contains("$") ? mathAgent : generalAgent
    }
    .run("What is 15% of $240?")
```

## Providers

Every agent uses a pluggable `InferenceProvider`. The agent loop stays the
same when you change models or deployment environments. Set a process-wide
default with `await Swarm.configure(provider:)` when you do not want to pass
a provider on every agent.

| Provider | Use it when |
|---|---|
| Apple Foundation Models | You want on-device inference on supported Apple devices |
| Ollama or LM Studio | You want a local HTTP model for development or private deployments |
| OpenAI, Azure, or OpenRouter | You want a cloud model through an OpenAI-compatible API |
| Custom provider | You need another model backend or an internal service |

```swift
let local = try Agent(
    "Be helpful.",
    inferenceProvider: .openAICompatible(.ollama(model: "llama3.2"))
)
```

See [Remote Providers](docs/guide/remote-providers.md) for configuration and
privacy details.

## Examples

Copy a complete example, or run one in deterministic demo mode without API
keys or Apple Intelligence:

| Example | Shows |
|---|---|
| [`OnDeviceChat`](Examples/OnDeviceChat) | Tools, streaming, and multi-turn conversation |
| [`MultiAgentPipeline`](Examples/MultiAgentPipeline) | Sequential and parallel workflows plus checkpoint/resume |
| [`WaxChat`](Examples/WaxChat) | Durable memory and web search with Integrations |
| [`CodeReviewer`](Examples/CodeReviewer) | A small CLI built on Swarm |

```bash
cd Examples/OnDeviceChat
swift run OnDeviceChat --demo
```

## More capabilities

| Capability | What it does |
|---|---|
| Conversation and memory | Preserve multi-turn state with `Conversation`; choose conversation, sliding-window, vector, summary, or hybrid memory. |
| Guardrails | Validate inputs, outputs, and tool arguments before they reach your application. |
| Streaming | Observe lifecycle, tool, thinking, and output events through `AsyncThrowingStream`. |
| Durable execution | Checkpoint workflow progress and resume after a process restart when the `Integrations` trait is enabled. |
| MCP | Discover and bridge Model Context Protocol tools. |
| Observability | Export agent and inference traces with OpenTelemetry or Swift logging. |

## Requirements

| Platform | Minimum |
|---|---|
| Swift | 6.2+ |
| iOS / macOS / tvOS | 26.0+ |
| Linux | Ubuntu 22.04+ with Swift 6.2 |

Foundation Models and some memory and platform integrations are Apple-only.
The default Swarm graph is CI-tested on Ubuntu with Swift 6.2. Apple-only features such as Foundation Models, SwiftData, OSLog, and some built-in tool behavior are unavailable or different on Linux; use an OpenAI-compatible provider, inject a mock, or run the deterministic examples.

To configure one provider globally for the default graph:

```swift
await Swarm.configure(provider: myProvider)
```

## Documentation

| Guide | Covers |
|---|---|
| [Getting Started](docs/guide/getting-started.md) | Installation and first agent |
| [Why Swarm?](docs/guide/why-swarm.md) | Design choices and architecture |
| [Remote Providers](docs/guide/remote-providers.md) | OpenAI, Azure, OpenRouter, Ollama, and LM Studio |
| [Foundation Models](docs/guide/foundation-models.md) | Capture and native session modes |
| [Durable Execution](docs/guide/durable-execution.md) | Checkpoint and resume semantics |
| [OpenTelemetry Tracing](docs/guide/opentelemetry-tracing.md) | Traces and propagation |
| [Front-Facing API](docs/reference/front-facing-api.md) | Public API overview |
| [API Catalog](docs/reference/api-catalog.md) | Complete symbol reference |

## Contributing

```bash
./scripts/ci/lean-build-test.sh
swiftformat Sources Tests --lint --config .swiftformat
```

All public types are expected to be `Sendable`. Bug reports and feature
requests belong in [GitHub Issues](https://github.com/christopherkarani/Swarm/issues).

If Swarm helps you ship, [star the repository](https://github.com/christopherkarani/Swarm)
and share what you built.

## Community and license

[Discussions](https://github.com/christopherkarani/Swarm/discussions) ·
[@ckarani7](https://x.com/ckarani7) · [MIT License](LICENSE)
