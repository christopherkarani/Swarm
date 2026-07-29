# Getting Started

Integrate ContextCore into an agent loop in under five minutes.

## 1. Access ContextCore via Swarm Integrations

ContextCore ships as an **in-tree** internal module under Swarm
(`Sources/ContextCore`). Enable the Swarm `Integrations` trait; do not add a
separate ContextCore package dependency.

```swift
// Consumer Package.swift
.package(
    url: "https://github.com/christopherkarani/Swarm.git",
    from: "0.6.0",
    traits: ["Integrations"]
)

// Target dependencies
"Swarm"
```

Within Swarm sources, `import ContextCore` works when Integrations is on.
External apps typically use Swarm's memory APIs (`DefaultAgentMemory`) rather
than depending on the internal ContextCore target directly.

## 2. Create an ``AgentContext``

Use the default configuration first, then tune for your workload.

```swift
import ContextCore

let context = try AgentContext()
```

## 3. Begin a Session

Start each user interaction session explicitly.

```swift
try await context.beginSession(systemPrompt: "You are a helpful coding assistant.")
```

## 4. Append Turns in Your Loop

Append every user and assistant turn so episodic memory stays current.

```swift
try await context.append(turn: Turn(role: .user, content: userMessage))
try await context.append(turn: Turn(role: .assistant, content: assistantMessage))
```

## 5. Build the Context Window Before Model Calls

Call `buildWindow` with the current task and token budget.

```swift
let window = try await context.buildWindow(
    currentTask: userMessage,
    maxTokens: 4096
)
```

## 6. Format and Send to the Model

Choose a formatter compatible with your model prompt format.

```swift
let prompt = window.formatted(style: .chatML)
// send `prompt` to your model runtime
```

## 7. End Session and Checkpoint

End sessions when complete, and checkpoint for persistence.

```swift
try await context.endSession()
try await context.checkpoint(to: URL(fileURLWithPath: "./context-checkpoint.json"))
```
