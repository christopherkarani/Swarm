# Getting Started

Get a working Swarm agent in under a minute.

## Installation

### Swift Package Manager

Add Swarm to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/christopherkarani/Swarm.git", from: "0.4.0")
],
targets: [
    .target(name: "YourApp", dependencies: ["Swarm"])
]
```

### Xcode

**File → Add Package Dependencies →** `https://github.com/christopherkarani/Swarm.git`

## Your First Agent

The primary way to create an agent is with the `Agent` struct initializer. The canonical init takes an unlabeled instructions string and a `@ToolBuilder` trailing closure for tools:

```swift
import Swarm

// 1. Define a tool — the @Tool macro generates the JSON schema
@Tool("Looks up the current stock price")
struct PriceTool {
    @Parameter("Ticker symbol") var ticker: String

    func execute() async throws -> String { "182.50" }
}

// 2. Create an agent with tools
let agent = try Agent("Answer finance questions using real data.",
    configuration: .default.name("Analyst"),
    inferenceProvider: .anthropic(key: "sk-..."),
    memory: .conversation(limit: 50),
    inputGuardrails: [.maxInput(5000), .inputNotEmpty]
) {
    PriceTool()
    CalculatorTool()
}

// 3. Run it
let result = try await agent.run("What is AAPL trading at?")
print(result.output) // "Apple (AAPL) is currently trading at $182.50."
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
    inferenceProvider: .anthropic(key: "sk-...")
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
    case .outputToken(let token):
        print(token, terminator: "")
    case .toolCallStarted(let call):
        print("\n[tool: \(call.toolName)]")
    case .completed(let result):
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

For checkpoint/resume and other power features, use the `.durable` namespace:

```swift
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

Swarm supports multiple inference providers. Pass via the `inferenceProvider:` init parameter:

```swift
// On-device (private, no network)
let agent = try Agent("You are helpful.", inferenceProvider: .foundationModels)

// Anthropic
let agent = try Agent("You are helpful.", inferenceProvider: .anthropic(key: "sk-..."))

// OpenAI
let agent = try Agent("You are helpful.", inferenceProvider: .openAI(key: "sk-..."))

// Ollama (local)
let agent = try Agent("You are helpful.", inferenceProvider: .ollama())
```

Or using the `.environment()` modifier on any `AgentRuntime`:

```swift
agent.environment(\.inferenceProvider, .anthropic(key: "sk-..."))
```

## Requirements

| | Minimum |
|---|---|
| Swift | 6.2+ |
| iOS | 26.0+ |
| macOS | 26.0+ |
| Linux | Ubuntu 22.04+ with Swift 6.2 |

::: tip
Foundation Models require iOS 26 / macOS 26. Cloud providers (Anthropic, OpenAI, Ollama) work on any Swift 6.2 platform including Linux.
:::

## Next Steps

- **[Agents](../reference/front-facing-api.md#3-agent-struct-primary-init)** -- Agent types, configuration, tool calling
- **[Tools](../reference/front-facing-api.md#5-tool-and-functiontool)** -- `@Tool` macro, `FunctionTool`, tool chains
- **[Workflow](../reference/front-facing-api.md#7-workflow)** -- Sequential, parallel, and routed execution
- **[Memory](../reference/front-facing-api.md#10-memoryoption)** -- Conversation, vector, summary, persistent
