# Changelog

All notable changes to Swarm are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Releases before 0.6.0 are recorded only in git tags and GitHub releases.

## [Unreleased]

### Added

- Durable workflow inspection and replay: checkpoint history reads,
  `DurableWorkflow.inspect()` / `inspect(run:)`, and fork-from-checkpoint
  resume (#262).
- Explicit turn-step boundary API on `AgentTurnKernel` (#265).
- `ToolFailureCause` factory for turn-path errors (#267).

### Changed

- Conversation history rendering goes through one unified renderer (#266).

## [0.6.6] - 2026-09-26

### Added

- Streaming voice synthesis, including streamed ElevenLabs audio and
  cancellable network adapters (#244).

### Changed

- CI runs a fast lane on pull requests; the deep suite runs on `main`, tags,
  and releases.

### Fixed

- Tool call IDs are preserved when results are projected into responses.

## [0.6.5] - 2026-09-26

### Added

- `Job` composition: a shared notes box, app-owned sequential steps, and one
  fan-out of named helpers (#218, #214).
- Apple voice sessions (#240, #241).
- OS 27 Foundation Models support: `LanguageModel` factory, reasoning-level
  mapping, and `Transcript` rehydration for owned-loop and capture sessions
  (#245).
- Keychain-backed secrets, secret redaction, and owner-only (`0600`)
  checkpoint and memory files (#253).
- Sandboxed stdio MCP transport (#248).

### Changed

- Membrane and ContextCore ported to Linux and modularized; Wax 0.1.47 (#258).
- The agent tool loop is driven by `AgentTurnKernel`, and parallel tool
  execution is unified on `ToolExecutionEngine` (#210, #212, #213, #254).
- Durable workflow configuration requires an ID and a store together (#217).
- Retry `maxAttempts` counts total attempts and rejects values below 1 (#251).
- Typed, fail-closed decoding at the model and OpenAI-compatible wire
  boundaries (#256, #259, #260).
- God files split and complexity lint gates re-enabled as warnings (#252).

### Fixed

- Crash sites in batch collection, `Strict4kTemplate` validation, and MCP
  debug output (#249).
- Sentence-buffer scan-past and durable router error distinction (#247).
- `AgentResponse` join no longer traps on duplicate keys (#239).
- Colliding handoff tool names are rejected at `Agent` init (#227).

## [0.6.4] - 2026-08-29

### Changed

- MCP and OpenTelemetry are opt-in SwiftPM traits (`MCP`, `OpenTelemetry`).

## [0.6.3] - 2026-08-28

### Changed

- Agent internals split around `AgentTurnKernel`, with explicit `TurnMode`,
  typed `AgentContext` keys, and shared direct/durable workflow transitions
  (#142, #145, #156, #164, #186).
- `GuardrailResult` is a closed enum (#141).

### Removed

- Legacy aliases, initializers, and marker protocols (#189 to #206).

### Fixed

- `StdioMCPServer` compiles on iOS without `Foundation.Process` (#184).
- Documentation freshness contracts restored (#208).

## [0.6.2] - 2026-08-14

### Added

- OpenAI-compatible remote provider with streaming, tools, and structured
  outputs (#135).
- OTLP/HTTP export and W3C trace propagation for `SwarmOpenTelemetry` (#130).
- Resilience policies wired into `Agent.run` (#129).
- Opt-in native Foundation Models session mode (experimental) (#127).
- Download-on-demand embedding delivery and a unified `EmbeddingProvider`
  (#125).

### Changed

- `Integrations` trait is off by default; lean consumers no longer resolve
  Hive, Membrane, ContextCore, or Wax (#115).
- Macros trait on by default, relaxed dependency pins (#132).
- MCP client modernized (#131).

### Fixed

- Durable checkpoint pruning and stable workflow signatures (#134).
- Workflow environment propagation and merge semantics (#122).
- Conversation history fidelity and token usage population (#123).
- `@Tool` macro emits compile errors for unsupported types (#124).
- Unbounded SSE buffer in the OpenAI-compatible provider (#136).

## [0.6.1] - 2026-06-04

### Fixed

- Removed a stale `import MembraneHive`.

## [0.6.0] - 2026-06-03

### Added

- OpenTelemetry tracing support (#77).
- Default memory retrieval policy honored by built-in memories.

### Fixed

- Workspace memory layering and tool allowlist union (#85, #86).
- Oversized memory context gaps (#87).
- Workflow resume signatures hardened (#92).
- Swift 6 `async let` actor-isolation crash (#79).

[Unreleased]: https://github.com/christopherkarani/Swarm/compare/0.6.6...HEAD
[0.6.6]: https://github.com/christopherkarani/Swarm/compare/0.6.5...0.6.6
[0.6.5]: https://github.com/christopherkarani/Swarm/compare/0.6.4...0.6.5
[0.6.4]: https://github.com/christopherkarani/Swarm/compare/0.6.3...0.6.4
[0.6.3]: https://github.com/christopherkarani/Swarm/compare/0.6.2...0.6.3
[0.6.2]: https://github.com/christopherkarani/Swarm/compare/0.6.1...0.6.2
[0.6.1]: https://github.com/christopherkarani/Swarm/compare/0.6.0...0.6.1
[0.6.0]: https://github.com/christopherkarani/Swarm/compare/0.5.1...0.6.0
