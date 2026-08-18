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

Non-Foundation-Models providers **ignore** the flag. Agent always calls
``generateWithToolCalls`` / ``streamWithToolCalls`` on ``InferenceProvider``;
it does not type-cast the provider. The Foundation Models adapter reads the
opt-in from the run environment and, when Apple Intelligence is available,
executes a provider-owned tool loop that returns a finished turn. Capture-mode
behavior does not change unless you set
``FoundationModelsExecutionMode/nativeSession``.

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
| Tool loop owner | Swarm agent loop | InferenceProvider (Apple `LanguageModelSession`) |
| Parallel tool calls | Yes (first `ToolCalls` group per turn) | Yes (Apple's session loop) |
| Transcript / KV reuse | No (session rebuilt every Swarm iteration) | Transcript copied across `Agent.run` turns; Apple owns the inner loop |
| Token streaming with tools | No | Yes (`Agent.stream` yields incremental tokens) |
| Per-iteration memory injection | Yes | **No** — memory is injected when the native session starts |
| Swarm `maxIterations` cap | Yes | **No** — Apple owns the inner loop |
| Mid-loop checkpoints | Yes | **No** |
| Per-turn guardrail interception | Yes (wraps Swarm's loop) | **No** — input/tool guardrails run **inside** each tool body |

Native mode exists so you can take Apple's session loop when you want multi-round
tools and real streaming. Capture stays the default because Swarm-side control
(guardrails, checkpoints, memory injection) is the framework's differentiator.
Capture now recovers every tool call in the first parallel group of a turn
(previously only the first call) and keeps any assistant text that accompanied
those calls.

## Structured outputs

When the requested JSON Schema maps onto `GenerationSchema`, capture-mode
`generateStructured` uses `LanguageModelSession.respond(to:schema:)` and labels
the result `.providerNative`. `.jsonObject` and unmappable schemas stay
prompt-instruction + parse (`.promptFallback`).

Under `strict4k`, native mode sends the same windowed/`PromptEnvelope` string
capture uses — not the raw conversation history.

## What native mode cannot honor

Foundation Models has no timeout API. Swarm still wraps the native `respond` /
`streamResponse` call in ``AgentConfiguration/timeout``; if Apple's call ignores
task cancellation until it returns, the timeout surfaces when that call ends.
`maxIterations` is not applied inside Apple's loop. Mid-loop workflow
checkpoints do not fire.

## Availability

Requires macOS/iOS 26+ with Apple Intelligence available. Linux and CI use
``OpenAICompatibleProvider`` (see [Remote Providers](remote-providers.md)) or
capture-equivalent mock providers; the native-session flag is ignored there.

Live on-device tests:

```bash
SWARM_FM_LIVE_TESTS=1 swift test --no-parallel --traits Integrations \
  --filter FoundationModelsNativeSessionLiveTests
```

`SWARM_RUN_LIVE_FOUNDATION_MODELS_TESTS=1` is also accepted.
