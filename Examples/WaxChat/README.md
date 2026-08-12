# WaxChat

Standalone on-device chat AI app built on **Swarm**. Separate package from the Swarm library targets.

## Capabilities

| Capability | How |
|---|---|
| **Foundation Models** | Live path uses `FoundationModelsInferenceProvider` when Apple Intelligence is available |
| **Web search** | Explicit `WebSearchTool` (`websearch`) on the agent; live when `TAVILY_API_KEY` is set |
| **Wax memory** | Explicit `WaxMemory` store (durable `.mv2s`). Multi-turn uses `InMemorySession` + `syncSessionTurnsToWax` so conversation turns are stored/recalled on the Wax path (Swarm does not auto-persist explicit memory without a session) |
| **Demo mode** | `--demo` uses a scripted provider so CI/sandbox runs without Apple Intelligence |

## Layout

```
WaxChat/
├── Package.swift          # path-depends on local Swarm (../../)
├── Sources/
│   ├── WaxChatCore/       # testable agent factory + session orchestration
│   └── WaxChat/           # CLI entry point
└── Tests/
    └── WaxChatCoreTests/
```

## Run

From this directory:

```bash
# Deterministic walkthrough (no Apple Intelligence / no API keys required)
swift run WaxChat --demo

# Live on-device Foundation Models (requires Apple Intelligence)
swift run WaxChat
swift run WaxChat "What's the weather story for Kyoto this week?"

# Optional live websearch backend
export TAVILY_API_KEY=tvly-...
swift run WaxChat "Search for Swarm Foundation Models agents"
```

## Tests

```bash
swift test --package-path .
# or from this directory:
swift test
```

Tests drive the shipped `ChatAgentFactory` / `ChatSession` path: websearch registration, Wax store→recall, and demo orchestration markers.

## Environment

| Variable | Required | Purpose |
|---|---|---|
| `TAVILY_API_KEY` | No | Enables live Tavily websearch; without it, websearch still runs (local/empty results) |

Requires **macOS 26+** and a path dependency on the Swarm package at `../../`.
