# Foundation Models: Capture vs Native Session

Swarm's built-in inference path is Apple Foundation Models. Tool calling has two modes.
**Capture is the default** and is unchanged. Native session mode is an **experimental
opt-in**.

## How to opt in

```swift
let config = AgentConfiguration.default
    .foundationModelsExecution(.nativeSession)

let agent = try Agent(
    "You are a private on-device assistant.",
    configuration: config,
    inferenceProvider: .foundationModels()
) {
    WeatherTool()
}

let result = try await agent.run("What's the weather in Tokyo?")
```

Non-Foundation-Models providers **ignore** the flag. Capture-mode behavior does
not change unless you set ``FoundationModelsExecutionMode/nativeSession``.

You can also register a user-authored `FoundationModels.Tool` next to `@Tool`
macros and `FunctionTool` values:

```swift
let agent = try Agent("Be helpful.", configuration: config,
    inferenceProvider: .foundationModels()) {
    WeatherTool()
    LookupTool() // FoundationModels.Tool — wrapped automatically
}
```

## Comparison

| | Capture (default) | Native session (experimental) |
|---|---|---|
| Tool loop owner | Swarm agent loop | `LanguageModelSession` |
| Parallel tool calls | No (one captured call per turn) | Yes (Apple's session loop) |
| Transcript / KV reuse | No (session rebuilt every Swarm iteration) | Transcript copied across `Agent.run` turns; Apple owns the inner loop |
| Token streaming with tools | No | Yes (`Agent.stream` yields incremental tokens) |
| Per-iteration memory injection | Yes | **No** — memory is injected when the native session starts |
| Swarm `maxIterations` cap | Yes | **No** — Apple owns the inner loop |
| Mid-loop checkpoints | Yes | **No** |
| Per-turn guardrail interception | Yes (wraps Swarm's loop) | **No** — input/tool guardrails run **inside** each tool body |

Native mode exists so you can take Apple's session loop when you want parallel
tools and real streaming. Capture stays the default because Swarm-side control
(guardrails, checkpoints, memory injection) is the framework's differentiator.

## What native mode cannot honor

Foundation Models has no timeout API. Swarm still wraps the native `respond` /
`streamResponse` call in ``AgentConfiguration/timeout``; if Apple's call ignores
task cancellation until it returns, the timeout surfaces when that call ends.
`maxIterations` is not applied inside Apple's loop. Mid-loop workflow
checkpoints do not fire.

## Availability

Requires macOS/iOS 26+ with Apple Intelligence available. Linux and CI use
capture-equivalent mock providers; the flag is ignored there.

Live on-device tests:

```bash
SWARM_FM_LIVE_TESTS=1 swift test --no-parallel --traits Integrations \
  --filter FoundationModelsNativeSessionLiveTests
```

`SWARM_RUN_LIVE_FOUNDATION_MODELS_TESTS=1` is also accepted.
