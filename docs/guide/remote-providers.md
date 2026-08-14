# Remote Providers

Swarm's built-in **on-device** path is Apple Foundation Models. When that is
unavailable — Linux, CI, or a machine without Apple Intelligence — use
``OpenAICompatibleProvider``. It speaks the OpenAI Chat Completions wire format
over `URLSession` (no extra package dependencies).

## Privacy

Prompt text, tool schemas, tool results, and structured-output schemas are
**sent to `baseURL`**. That is the opposite of
``FoundationModelsInferenceProvider``, which keeps inference on-device when
Apple Intelligence is available.

Use Foundation Models when the data must stay on the device. Use the
OpenAI-compatible provider when you need a remote or local HTTP model.

## Configuration

Every host is `baseURL` + optional `apiKey` + `model` + extra headers:

```swift
import Swarm

let provider: any InferenceProvider = .openAICompatible(
    baseURL: URL(string: "https://api.openai.com/v1")!,
    model: "gpt-4o",
    apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
)

let agent = try Agent("Be helpful.", inferenceProvider: provider)
```

Convenience factories fill those fields for common hosts.

### OpenAI

```swift
let provider: any InferenceProvider = .openAICompatible(
    .openAI(apiKey: "sk-...", model: "gpt-4o")
)
```

`baseURL` is `https://api.openai.com/v1`. Auth is `Authorization: Bearer`.
Structured outputs use native `response_format` (`source: .providerNative`).

### Azure OpenAI

```swift
let provider: any InferenceProvider = .openAICompatible(
    .azureOpenAI(
        resource: "contoso",
        deployment: "gpt-4o",
        apiKey: "azure-key",
        apiVersion: "2024-10-21"
    )
)
```

`baseURL` is `https://{resource}.openai.azure.com/openai/deployments/{deployment}`.
Auth is the `api-key` header. `api-version` is a query item.

### OpenRouter

```swift
let provider: any InferenceProvider = .openAICompatible(
    .openRouter(
        apiKey: "sk-or-...",
        model: "openai/gpt-4o-mini",
        httpHeaders: [
            "HTTP-Referer": "https://example.com",
            "X-Title": "Swarm",
        ]
    )
)
```

`baseURL` is `https://openrouter.ai/api/v1`. Auth is Bearer. Extra headers are
optional but recommended by OpenRouter.

### Ollama (local)

```swift
let provider: any InferenceProvider = .openAICompatible(
    .ollama(model: "llama3.2")
)
```

`baseURL` defaults to `http://127.0.0.1:11434/v1`. No API key. Structured
outputs use labeled prompt-parse fallback (`source: .promptFallback`) because
Ollama does not reliably honor `response_format.json_schema`.

### LM Studio (local)

```swift
let provider: any InferenceProvider = .openAICompatible(
    .lmStudio(model: "local-model")
)
```

`baseURL` defaults to `http://127.0.0.1:1234/v1`. API key is optional. Structured
outputs default to prompt-parse fallback; switch
``OpenAICompatibleStructuredOutputMode/nativeJSONSchema`` if your build
supports it.

## When to use which provider

| Provider | Use when | Data leaves the device? |
|---|---|---|
| ``FoundationModelsInferenceProvider`` | Apple platforms with Apple Intelligence | No |
| OpenAI / Azure / OpenRouter | Cloud models, Linux, or no Apple Intelligence | Yes — to that host |
| Ollama / LM Studio | Local HTTP models, Linux CI, offline labs | Yes — to `localhost` (still HTTP) |
| Your own `InferenceProvider` | A non–OpenAI-compatible backend | Depends on the implementation |

## Capabilities

The provider implements the conversation seams the agent loop prefers:

- Chat Completions with roles, `tool_calls`, and `tool_call_id`
- SSE streaming (`data:` lines, `[DONE]`, multi-event deltas)
- Token usage from `usage.prompt_tokens` / `usage.completion_tokens`
- W3C `traceparent` / `tracestate` via ``TraceContextHeaders``
- HTTP errors classified for ``InferenceRetryability`` (429 / 5xx / network
  retryable; 400 / 401 / 403 not)

## Live Ollama tests

Gated behind `SWARM_OLLAMA_LIVE_TESTS=1`. They are skipped in CI.

```bash
# Install: https://ollama.com
ollama pull llama3.2
ollama serve   # listens on 127.0.0.1:11434

SWARM_OLLAMA_LIVE_TESTS=1 \
SWARM_OLLAMA_MODEL=llama3.2 \
swift test --filter OpenAICompatibleOllamaLiveTests
```

Optional: `SWARM_OLLAMA_BASE_URL` (default `http://127.0.0.1:11434/v1`).
