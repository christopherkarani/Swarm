---
layout: home

hero:
  name: Swarm
  text: Multi-Agent Workflows for Swift
  tagline: Chain LLMs, tools, and memory into production workflows -- with compile-time safety, crash recovery, and on-device inference.
  actions:
    - theme: brand
      text: Get Started
      link: /guide/getting-started
    - theme: alt
      text: View on GitHub
      link: https://github.com/christopherkarani/Swarm

features:
  - icon: "\U0001F517"
    title: Compose Workflows Fluently
    details: Build sequential, parallel, and routed workflows with `Workflow().step(...).parallel(...).route(...)`.
    link: /guide/getting-started
    linkText: Learn workflows

  - icon: "\U0001F6E1\uFE0F"
    title: Data Races Are Compile Errors
    details: Swift 6.2 StrictConcurrency on every target. Non-Sendable types crossing actor boundaries won't build.
    link: /reference/front-facing-api
    linkText: See the API

  - icon: "\U0001F4BE"
    title: Workflows Survive Crashes
    details: Advanced workflows can checkpoint and resume with explicit checkpoint stores and deterministic IDs.
    link: /reference/overview
    linkText: Explore checkpointing

  - icon: "\U0001F9E0"
    title: Semantic Memory -- On-Device
    details: VectorMemory performs local similarity search; embedding privacy depends on the provider you configure.
    link: /reference/front-facing-api
    linkText: Memory factories

  - icon: "\U0001F50C"
    title: Foundation Models First
    details: Built-in Apple Foundation Models. Inject any `InferenceProvider` for custom backends via `inferenceProvider:`.
    link: /reference/front-facing-api
    linkText: Configure providers

  - icon: "\u26A1"
    title: Production Resilience
    details: Retry with 7 backoff strategies, circuit breakers, fallback agents, rate limiting, and per-step timeouts.
    link: /reference/overview
    linkText: Add resilience
---

## Install

```swift
.package(url: "https://github.com/christopherkarani/Swarm.git", from: "0.6.0")
```

## Quick Start

```swift
import Swarm

@Tool("Looks up the current stock price")
struct PriceTool {
    @Parameter("Ticker symbol") var ticker: String
    func execute() async throws -> String { "182.50" }
}

let agent = try Agent(
    "Answer finance questions using real data.",
    configuration: .default.name("Analyst"),
    inferenceProvider: .foundationModels()
) {
    PriceTool()
}

let result = try await agent.run("What is AAPL trading at?")
```

## Multi-Agent Workflow

```swift
let result = try await Workflow()
    .step(researchAgent)
    .step(writerAgent)
    .run("Write about Swift concurrency.")
```

## How Swarm Compares

| | **Swarm** | LangChain | AutoGen |
|---|---|---|---|
| Language | **Swift 6.2** | Python | Python |
| Data race safety | **Compile-time** | Runtime | Runtime |
| On-device LLM | **Foundation Models** | -- | -- |
| Execution model | **Typed `Workflow` graph** | Loop-based | Loop-based |
| Crash recovery | **Explicit checkpoints** | -- | Partial |
| Type-safe tools | **@Tool macro** | Decorators | Runtime |
| Streaming | **AsyncThrowingStream** | Callbacks | Callbacks |
| iOS / macOS | **First-class** | -- | -- |
