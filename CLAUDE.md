# CLAUDE.md

Guidance for AI coding assistants (Claude Code, Cursor, etc.) working in this
repository. This file is the canonical, in-repo briefing — read it before making
changes.

## What is Swarm?

Swarm is a Swift 6.2 framework for building **agents and multi-agent
workflows** on Apple platforms (iOS 26+, macOS 26+, tvOS 26+) and Linux. It is
built around:

- **Agents** — `Agent` struct with `@ToolBuilder` trailing closures, an
  `AgentRuntime` protocol, and pluggable inference providers.
- **Workflows** — fluent composition (`.step`, `.parallel`, `.route`,
  `.repeatUntil`) compiled to a DAG with checkpoint/resume.
- **Tools** — the `@Tool` macro generates JSON schemas from Swift structs at
  compile time; `FunctionTool` covers ad-hoc closures.
- **Memory** — conversation, sliding-window, summary, vector, and
  persistent backends.
- **Guardrails / Resilience / Observability** — first-class concerns, not
  bolt-ons.
- **Providers** — Built-in Apple Foundation Models; custom backends inject
  `InferenceProvider`. No Conduit / cloud façade ships with Swarm.
- **MCP** — Model Context Protocol client and server support.

The package uses Swift 6.2 with `StrictConcurrency` enabled across all targets.
**All public types must be `Sendable`** — the compiler enforces it.

## Repository Layout

```
Swarm/
├── Package.swift                  # SPM manifest (Swift 6.2, products)
├── README.md                      # User-facing overview
├── Sources/
│   ├── Swarm/                     # Main library (156 .swift files)
│   │   ├── Agents/                # Agent struct, workspace integration
│   │   ├── Core/                  # AgentRuntime, Conversation, Environment,
│   │   │                          #   PromptEnvelope, RuntimeMetadata, …
│   │   ├── Workflow/              # Workflow + durable engine + checkpointing
│   │   ├── Tools/                 # Tool protocol, ToolCollection, ParallelExecutor,
│   │   │                          #   built-ins, web tools, schema bridging
│   │   ├── Memory/                # Conversation, sliding window, summary, vector,
│   │   │                          #   SwiftData, ContextCore, hybrid backends
│   │   ├── Providers/             # Foundation Models, multi-provider, sessions
│   │   ├── Guardrails/            # Input/Output/Tool guardrail specs + runner
│   │   ├── Resilience/            # Retry, circuit breaker, fallback, rate limit
│   │   ├── Observability/         # AgentTracer, SwiftLog/OSLog tracers, metrics
│   │   ├── MCP/                   # MCPClient, MCPServerConnection, stdio/HTTP transports, ToolBridge
│   │   ├── Workspace/             # AgentWorkspace (AGENTS.md, .swarm/ skills)
│   │   ├── Macros/                # Public macro declarations
│   │   ├── Integration/           # Membrane and Wax integrations
│   │   └── Internal/GraphRuntime/ # Compiled DAG runtime (internal)
│   ├── HiveCore/                  # In-tree durable graph (Integrations only)
│   ├── MembraneCore/              # In-tree Membrane core (Integrations only)
│   ├── Membrane/                  # In-tree Membrane session (Integrations only)
│   ├── MembraneContextCore/       # In-tree Membrane↔ContextCore (Integrations)
│   ├── ContextCoreTypes/          # In-tree ContextCore types (Integrations)
│   ├── ContextCoreShaders/        # In-tree Metal shaders (Integrations)
│   ├── ContextCoreEngine/         # In-tree ContextCore engine (Integrations)
│   ├── ContextCore/               # In-tree ContextCore façade (Integrations)
│   ├── SwarmMacros/               # Compiler plugin (@Tool, @Parameter,
│   │                              #   @Traceable, #Prompt, builders)
│   ├── SwarmMembrane/             # Deprecated hollow re-export (remove in 0.7.0)
│   ├── SwarmMCP/                  # MCP server adapter product
│   ├── SwarmCapabilityShowcase/        # Executable: deterministic showcase CLI
│   ├── SwarmCapabilityShowcaseSupport/ # Library backing the showcase
│   ├── SwarmDemo/                 # (opt-in) demo executable
│   └── SwarmMCPServerDemo/        # (opt-in) MCP server demo
├── Tests/
│   ├── SwarmTests/                # Main test target (mirrors Sources/Swarm)
│   │   └── Mocks/                 # MockAgentRuntime, MockInferenceProvider, …
│   ├── HiveSwarmTests/            # Hive integration tests
│   ├── SwarmMacrosTests/          # Macro expansion tests
│   └── SwarmCapabilityShowcaseTests/
├── Examples/CodeReviewer/         # Standalone example SPM project
├── docs/
│   ├── guide/                     # Getting started, agent workspace, showcase
│   ├── reference/                 # API catalog, front-facing-api, audits
│   └── release/                   # release-checklist.md
└── .github/workflows/             # swift.yml, claude.yml, claude-code-review.yml,
                                   #   docs.yml
```

## Build, Test, Lint

This is a Swift Package — there is no Xcode project committed. All commands run
from the repo root.

```bash
swift package resolve         # Resolve dependencies (lean pins without Integrations)
bash scripts/ci/lean-build-test.sh   # Cold lean resolve + product build + lean tests
swift build --traits Integrations
swift test --no-parallel --traits Integrations
swift test --no-parallel --traits Integrations --filter HiveSwarmTests
swift test --filter SwarmTests.WorkflowTests   # Run a single suite
# Note: bare `swift build`/`swift test` without --traits Integrations still
# compile every registered target (orphans need trait-gated remotes). Prefer
# lean-build-test.sh or --traits Integrations on this package root.
```

### Integrations trait (off by default)

Default consumers get lean Swarm (core + Foundation Models). Enable the
`Integrations` trait for durable Hive workflows, ContextCore+Wax default
memory, Membrane adapters, and web helpers.

HiveCore, Membrane (`MembraneCore` / `Membrane` / `MembraneContextCore`), and
ContextCore (`ContextCoreTypes` / `ContextCoreShaders` / `ContextCoreEngine` /
`ContextCore`) are **native in-tree** `Sources/` targets — internal modules
only (no separate library products). They are linked into Swarm only when
Integrations is on. ContextCore / full Membrane session stack are Apple-only
(Metal/CoreML); Linux Integrations still links Hive + MembraneCore + web.
Wax remains a remote package + trait-gated product; MetalANNS stays remote for
the ContextCore chain. Lean resolve must not pull package identities `hive`,
`membrane`, `contextcore`, or `conduit`, and must not pin Wax/MetalANNS/GRDB/
crypto/mutex/SwiftSoup (trait-gated product edges). Default-on: swift-syntax
(via the Macros trait; disable with `traits: []`),
swift-log, MCP sdk, OTel (+ NIO transitives; `swift-collections` via NIO is
OK). CI: `scripts/ci/lean-build-test.sh` (cold resolve + product-scoped lean
build + `SWARM_OMIT_INTEGRATION_TARGETS=1` tests) and
`scripts/ci/verify-lean-resolve.sh`. Bare root `swift build` without
`--traits Integrations` compiles every registered target — use the lean helper
or product flags; consumers only build reachable targets.

```bash
swift build --traits Integrations
swift test --no-parallel --traits Integrations
```

Consumer `Package.swift`:

```swift
.package(url: "https://github.com/christopherkarani/Swarm.git", from: "0.6.0", traits: ["Integrations"])
```

CI (`.github/workflows/swift.yml`) runs on macOS 15 and Ubuntu with Swift 6.2.
It exercises `scripts/ci/lean-build-test.sh` (cold lean resolve deny-list +
product-scoped build + omit-target lean tests) plus a full
`--traits Integrations` lane (including `HiveSwarmTests` and the capability
showcase matrix).

The Hive integration tests live in the `HiveSwarmTests` target and require
`--traits Integrations`.

### Demo / benchmark executables

The `SwarmDemo` and `SwarmMCPServerDemo` executables are
**opt-in** — they only build when `SWARM_INCLUDE_DEMO=1` is set:

```bash
SWARM_INCLUDE_DEMO=1 swift build
SWARM_INCLUDE_DEMO=1 swift run SwarmDemo
```

### Capability showcase

`SwarmCapabilityShowcase` is always built and exercises the stable surface area
in a deterministic matrix that is CI-safe:

```bash
swift run --traits Integrations SwarmCapabilityShowcase list
swift run --traits Integrations SwarmCapabilityShowcase matrix
swift run --traits Integrations SwarmCapabilityShowcase run handoff
swift run --traits Integrations SwarmCapabilityShowcase smoke
```

See `docs/guide/capability-showcase.md` for the full scenario catalog and
smoke-mode environment variables.

### Lint / format

CI runs SwiftLint and SwiftFormat on macOS using the tracked root configs:
`.swiftlint.yml` and `.swiftformat`. Both commands are scoped to
`Sources` and `Tests` so ignored worktrees, dependency checkouts, generated
docs, and Node artifacts do not affect results. If you change Swift files,
match the surrounding style and assume both linters will run in CI.

To format using the SwiftFormat package plugin (per README):

```bash
swift package plugin --allow-writing-to-package-directory swiftformat
```

## Key Conventions

### Concurrency

- Swift 6.2 with `StrictConcurrency` is enabled on the main targets via
  `swarmSwiftSettings`. Macro and showcase targets enable
  `enableExperimentalFeature("StrictConcurrency")` directly.
- **All public types must be `Sendable`.** Don't suppress data-race diagnostics
  with `@unchecked Sendable` unless you have a documented reason.
- Use `actor` for stateful coordinators (e.g. `Conversation`,
  `InMemorySession`), `struct` for value types, and `AsyncThrowingStream` for
  streaming output.

### Agents

- The canonical initializer is `Agent(_ instructions: String, ...)` with an
  unlabeled instructions string and a trailing `@ToolBuilder` closure for
  tools. See `Sources/Swarm/Agents/Agent.swift`.
- Provider resolution order is documented at the top of `Agent.swift`:
  1. explicit provider passed in (or privacy-required FM-first path),
  2. `.environment(\.inferenceProvider, ...)`,
  3. `Swarm.defaultProvider` via `Swarm.configure(provider:)`,
  4. Foundation Models (on-device) when available,
  5. else throw `AgentError.inferenceProviderUnavailable`.
- The `Agent` struct is `Sendable`; tools are stored as `[any AnyJSONTool]`.

### Tools

- Prefer the `@Tool` macro over conforming to `AnyJSONTool` directly. The macro
  generates the JSON schema, parameter parsing, and output encoding.
- Use `@Parameter("description") var name: T` inside a `@Tool` struct.
- For one-off closure tools use `FunctionTool` with `ToolParameter` values.
- Multiple tools can be composed with `@ToolBuilder` (the trailing closure on
  `Agent.init`).

### Workflows

- `Workflow()` is a fluent builder; chain `.step`, `.parallel(_, merge:)`,
  `.route { ... }`, `.repeatUntil`, `.timeout`.
- Durable execution lives in `Workflow+Durable.swift` and
  `WorkflowDurableEngine.swift`. Use
  `.durable.checkpoint(id:policy:)` and `.durable.checkpointing(...)` to enable
  resume-from-checkpoint behavior.
- The `Internal/GraphRuntime` directory is the compiled DAG runtime — treat it
  as an implementation detail.

### Memory & Workspace

- `Memory` factory methods are the user-facing entry point:
  `.conversation(maxMessages:)`, `.slidingWindow(maxTokens:)`,
  `.summary(configuration:summarizer:)`, `.hybrid(configuration:summarizer:)`,
  `.persistent(backend:conversationId:maxMessages:)`, and
  `.vector(embeddingProvider:similarityThreshold:maxResults:)`.
- `AgentWorkspace` (in `Sources/Swarm/Workspace/`) is the on-device workspace
  layout backed by `AGENTS.md` + `.swarm/agents/<id>.md` + `.swarm/skills/` +
  `.swarm/memory/`. **Do not confuse the runtime `AGENTS.md` (workspace
  instructions consumed by Swarm) with this `CLAUDE.md` (briefing for AI coding
  assistants).** The runtime `AGENTS.md` is git-ignored at the repo root.
- Always call `try await workspace.validate()` from new tests that touch the
  workspace.

### Providers

- Built-in inference is **Apple Foundation Models only** via
  `FoundationModelsInferenceProvider` under `Sources/Swarm/Providers/`.
- Custom backends implement `InferenceProvider` and are injected on the agent
  or via `await Swarm.configure(provider:)`. There is no Conduit package
  dependency and no `LLM.*` / `cloudProvider` façade.
- Native tool calling bridges Swarm `ToolSchema` to Apple's
  `FoundationModels.Tool`.
- Swarm `DynamicProfile` / `Profile` / `DynamicInstructions` / `ProfileMode`
  mirror WWDC 2026 Foundation Models Dynamic Profiles. The Apple native API
  is not in macOS 26.2 SDK yet; Swarm profiles work today and re-resolve each
  turn via `.foundationModels(profile:)`.

### Mocks & Test Helpers

- `Tests/SwarmTests/Mocks/` contains the canonical mocks: `MockAgentRuntime`,
  `MockInferenceProvider`, `MockAgentMemory`, `MockEmbeddingProvider`,
  `MockSummarizer`, `MockTool`, plus `SwarmConfigurationTestIsolation` for
  isolating `Swarm.defaultProvider`/`Swarm.configure(...)` between tests.
- New tests should reuse these mocks rather than reinventing local stubs.
- Tests that touch `Swarm.configure` global state must use the isolation helper
  to avoid cross-test pollution under `--no-parallel`.

## Development Workflow

1. **Read before you write.** The codebase is large (≈156 source files,
   ≈150 test files). Use `Grep` / `Glob` to find call sites before changing a
   public type.
2. **Mirror the source tree in tests.** A change in
   `Sources/Swarm/Workflow/Foo.swift` should land alongside or update
   `Tests/SwarmTests/Workflow/FooTests.swift`.
3. **Keep public surfaces `Sendable` and DocC-commented.** Public types in this
   package carry rich DocC comments — match that style on anything new.
4. **Don't over-engineer.** Per the project's documentation history, prefer
   small, surgical changes that preserve the existing public API. Audit reports
   live in `docs/reference/` (`api-catalog.md`, `front-facing-api.md`,
   `documentation-*.md`) — consult them before introducing new public types.
5. **Run the deterministic matrix.** Before opening a PR, run
   `swift run SwarmCapabilityShowcase matrix` in addition to `swift test` to
   catch regressions in cross-cutting scenarios.
6. **Never push to `main` directly.** Branch, run tests, open a PR.
7. **Do not commit `Package.resolved`.** It is git-ignored intentionally —
   Swarm is a library and consumers resolve their own dependency graph.

## Things That Are Git-Ignored (and Why)

The `.gitignore` deliberately excludes a number of paths AI assistants might
otherwise want to create or check in. **Do not work around these.**

- `.claude/`, `.mcp.json`, `.agent_context.md`, `AGENTS.md` — local AI tooling
  config, except `AGENTS.md`, which is intentionally tracked as the repo-level
  guardrail for future agents.
- `.swift-version` — contributors keep this locally; CI selects Swift through
  the workflow environment.
- `Package.resolved` — library, not application.
- `docs/plans/`, `docs/prompts/`, `docs/work-packages/`, `docs/validation/`,
  `tasks/`, `scripts/`, `IMPLEMENTATION_PLAN.md`,
  `HIVE_EXTENSIBILITY_INTEGRATION_PLAN.md`, `PRODUCTION_READINESS_AUDIT.md` —
  internal planning artifacts.
- `marketing/`, `website/`, VitePress build output.
- `docs/reference/*audit-report.md`, `docs/reference/documentation-*-report.md`,
  `docs/reference/documentation-improvement-plan.md`,
  `docs/reference/api-quality-assessment.md`,
  `docs/reference/twitter-article-*.md`, `docs/swarm-hacker-news-blog.md`,
  `docs/superpowers/` — internal audit, planning, and marketing artifacts.

`CLAUDE.md` itself was previously git-ignored; it has been intentionally
un-ignored so this guidance can live in-repo.

## Public API Stability

The framework is at `0.5.1` (`Sources/Swarm/Swarm.swift`) and treats its public
surface as semi-stable. The supported public reference documents are
`docs/reference/api-catalog.md`, `docs/reference/front-facing-api.md`, and
`docs/reference/overview.md`. Prefer:

- adding new types over breaking existing ones,
- adding new initializer overloads over changing parameter labels on existing
  ones,
- documenting deprecations rather than silently removing symbols.

## When You're Stuck

- For "what does X do?" questions, search `Sources/Swarm/<Area>/` first, then
  `docs/reference/api-catalog.md`.
- For workflow examples, read `Sources/SwarmCapabilityShowcaseSupport/CapabilityShowcase.swift`
  — it touches every stable subsystem.
- For provider behaviour, look at `Sources/Swarm/Providers/FoundationModels/`
  and the `LanguageModelSession*` files.
- The `README.md` quick-start, the `docs/guide/getting-started.md` tutorial,
  and `docs/guide/agent-workspace.md` are the user-facing canonical docs —
  keep code samples consistent with them when changing surface area.
