# OnDeviceChat

Minimal end-to-end Swarm demo for **Apple Foundation Models**.

## What it shows

- `Agent` with `@Tool` + `FunctionTool`
- Streaming via `agent.stream`
- Multi-turn `Conversation`
- First-class `.foundationModels()` / `FoundationModelsInferenceProvider.ifAvailable()`
- Deterministic `--demo` mode (no Apple Intelligence required)

## Run

```bash
# From this directory
swift run OnDeviceChat --demo          # always works; scripted provider
swift run OnDeviceChat                 # live on-device when Apple Intelligence is available
swift run OnDeviceChat "Hello"         # custom prompt (live path)
```

Requires macOS 26+ and a path dependency on the Swarm package (`../../`).

No API keys. Live mode needs a device where `FoundationModelsInferenceProvider.isAvailable` is true.
