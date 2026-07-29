# Integrating With Wax

Use Wax as durable long-term memory and ContextCore as the real-time context curation layer.

## Integration Pattern

1. Keep durable memories in Wax's long-term store.
2. On each loop, fetch candidate facts from Wax and inject into ContextCore via ``AgentContext/remember(_:)``.
3. Append live turns to ``AgentContext``.
4. Build the final context window with ``AgentContext/buildWindow(currentTask:maxTokens:)``.
5. Send the formatted window to the model runtime.

## Bridging Example

```swift
import ContextCore

func runLoopStep(
    waxFacts: [String],
    userMessage: String,
    context: AgentContext
) async throws -> String {
    for fact in waxFacts {
        try await context.remember(fact)
    }

    try await context.append(turn: Turn(role: .user, content: userMessage))

    let window = try await context.buildWindow(
        currentTask: userMessage,
        maxTokens: 4096
    )

    return window.formatted(style: .chatML)
}
```

## Operational Guidance

- Keep Wax as the source of truth for durable memory.
- Use ContextCore for per-call relevance ranking, compression, and ordering.
- Periodically checkpoint ContextCore with ``AgentContext/checkpoint(to:)`` for fast restart.
