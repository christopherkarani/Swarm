# Foundation Models: Capture vs Provider-Owned Tool Loop

Swarm's built-in inference path is Apple Foundation Models. Tool calling has two
adapters on one type. **Capture is the default** (``.foundationModels()``).
A provider-owned tool loop is a **separate factory**.

## How to opt in

```swift
let agent = try Agent(
    "You are a private on-device assistant.",
    inferenceProvider: .foundationModelsOwningToolLoop()
) {
    WeatherTool()
}

let result = try await agent.run("What's the weather in Tokyo?")
```

Agent reads ``InferenceProviderCapabilities/providerOwnedToolLoop``. It does not
choose the loop on ``AgentConfiguration``. Capture-mode behavior does not change
unless you construct ``InferenceProvider/foundationModelsOwningToolLoop()``.

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
| Token streaming with tools | No | Not yet — the owned-loop generate path returns a finished turn |
| Per-iteration memory injection | Yes | **No** — memory is injected when the native session starts |
| Swarm `maxIterations` cap | Yes | **No** — Apple owns the inner loop |
| Mid-loop checkpoints | Yes | **No** |
| Per-turn guardrail interception | Yes (wraps Swarm's loop) | **No** — input/tool guardrails run **inside** each tool body |

On OS 27, set ``FoundationModelsProviderConfiguration/reasoningLevel`` to
``FoundationModelsReasoningLevel/light``, ``moderate``, or ``deep``. Owned-loop
`respond` / `streamResponse` pass Apple `ContextOptions(reasoningLevel:)`.
Capture ignores the overlay for now. The Swarm enum is not Apple's
`ContextOptions` type.

Apple `GenerationOptions.ToolCallingMode` is `allowed` / `disallowed` /
`required` only. ``ToolChoice/specific(toolName:)`` has no Apple case — Swarm
keeps the prompt sentence that names the tool and maps the generation mode to
`.allowed`.

Native mode exists so you can take Apple's session loop for multi-round tools
and transcript reuse. Capture stays the default because Swarm-side control
(guardrails, checkpoints, memory injection) is the framework's differentiator.
Capture now recovers every tool call in the first parallel group of a turn
(previously only the first call) and keeps any assistant text that accompanied
those calls.

## Structured outputs

When the requested JSON Schema maps onto `GenerationSchema`, capture-mode
`generateStructured` uses `LanguageModelSession.respond(to:schema:)` and labels
the result `.providerNative`. `.jsonObject` and unmappable schemas stay
prompt-instruction + parse (`.promptFallback`).

Native mode windows the conversation to the model's `contextSize` (4096 on
OS 26.0…26.3 back-deploy). The provider seam is a role-tagged
`[InferenceMessage]` array via `PromptEnvelope.enforce(messages:)`, not a
flattened envelope string.

## What native mode cannot honor

Foundation Models has no timeout API on OS 26. OS 27 `LanguageModelError.timeout`
maps to ``AgentError/generationFailed(reason:)``. Swarm still wraps the native `respond` /
`streamResponse` call in ``AgentConfiguration/timeout``; if Apple's call ignores
task cancellation until it returns, the timeout surfaces when that call ends.
`maxIterations` is not applied inside Apple's loop. Mid-loop workflow
checkpoints do not fire.

## Availability

Requires macOS/iOS 26+ with Apple Intelligence available. Check
``FoundationModelsInferenceProvider/isAvailable(_:)`` against the
`SystemLanguageModel` you will use (default or `SystemLanguageModel(useCase:)`).
That type is Apple's, not Swarm ``DynamicProfile``. Linux and CI use
``OpenAICompatibleProvider`` (see [Remote Providers](remote-providers.md)) or
capture-equivalent mock providers. ``.foundationModelsOwningToolLoop()`` still
constructs; the first ``generateWithToolCalls`` / ``streamWithToolCalls``
throws ``AgentError/modelNotAvailable(model:)`` if the selected model is off.

On OS 27 you can pass any Apple `LanguageModel`, including
`PrivateCloudComputeLanguageModel`, to ``InferenceProvider/foundationModels(model:)``
or ``FoundationModelsInferenceProvider/ifAvailable(model:)``.
`ifAvailable(model:)` returns `nil` when that model's `availability` is not
`.available`. It does **not** silently construct
`SystemLanguageModel.default` — build an on-device provider yourself when PCC
is offline or over quota. Swarm ``DynamicProfile`` is still the `profile:`
argument, not `model:`.

PCC uses a 32K context window and a daily quota.
`PrivateCloudComputeLanguageModel.Error.quotaLimitReached` maps to
``AgentError/rateLimitExceeded(retryAfter:)``.

Live on-device tests:

```bash
SWARM_FM_LIVE_TESTS=1 swift test --no-parallel --traits Integrations \
  --filter FoundationModelsNativeSessionLiveTests
```

`SWARM_RUN_LIVE_FOUNDATION_MODELS_TESTS=1` is also accepted.
