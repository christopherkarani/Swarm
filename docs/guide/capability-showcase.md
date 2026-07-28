# Capability Showcase

The capability showcase is the quickest way to verify that Swarm's stable feature families still work together after changes to the runtime.

It lives entirely in-package:

- `Sources/SwarmCapabilityShowcaseSupport`
- `Sources/SwarmCapabilityShowcase`
- `Tests/SwarmCapabilityShowcaseTests`

## Commands

The full matrix (including durable Hive checkpointing) requires the
`Integrations` SwiftPM trait. Lean default builds omit `durable`.

```bash
swift run --traits Integrations SwarmCapabilityShowcase list
swift run --traits Integrations SwarmCapabilityShowcase matrix
swift run --traits Integrations SwarmCapabilityShowcase run <scenario-id>
swift run --traits Integrations SwarmCapabilityShowcase smoke
```

## Deterministic matrix

`swift run --traits Integrations SwarmCapabilityShowcase matrix` runs these scenarios without live network dependencies:

| Scenario | What it proves |
| --- | --- |
| `agent-tools` | `Agent`, `@Tool`, `FunctionTool`, and tool execution work together |
| `streaming` | `agent.stream` emits lifecycle and output events |
| `conversation-session` | `Conversation` and `InMemorySession` preserve multi-turn state |
| `workflow-core` | sequential, parallel, route, repeat-until, and timeout composition work |
| `handoff` | a triage agent can delegate to a specialist through handoff tool routing |
| `memory` | explicit memory can store and retrieve deterministic context |
| `workspace` | `AgentWorkspace`, `Agent.onDevice`, `Agent.spec`, and `WorkspaceWriter` load and write correctly |
| `guardrails` | input, output, and tool guardrails can pass and trip deterministically |
| `resilience` | retry, fallback, rate limiting, and circuit breaker helpers behave correctly |
| `durable` | durable workflow checkpoint and resume (requires `Integrations` trait) |
| `observability` | a custom tracer receives agent trace events |
| `mcp` | MCP tool discovery and MCP tool bridging both execute locally |
| `providers` | global provider config, per-agent override, and `MultiProvider` routing work |
| `foundation-models` | First-class `.foundationModels()` factories, capability reporting, availability/degrade semantics, and Agent multi-turn/tool wiring used by on-device apps |

Each scenario writes evidence into a temporary artifact directory under the system temp folder, rooted at `swarm-capability-showcase/`.

## Smoke mode

Smoke mode is for live integrations that should not gate CI.

Current smoke scenarios:

| Scenario | Environment |
| --- | --- |
| `live-provider-smoke` | Apple Foundation Models available on host |
| `live-foundation-models-smoke` | `SWARM_SHOWCASE_FOUNDATION_MODELS=1` (or `SWARM_RUN_LIVE_FOUNDATION_MODELS_TESTS=1`) |

Example:

```bash
swift run SwarmCapabilityShowcase smoke  # requires Foundation Models on host
SWARM_SHOWCASE_FOUNDATION_MODELS=1 swift run SwarmCapabilityShowcase smoke
```

If the required environment variable is missing, the smoke scenario reports `skipped` instead of failing.

The `foundation-models` **deterministic** scenario always runs in the matrix (including on Linux, where it documents graceful compile-time gating). Live on-device generation is only exercised by the opt-in smoke scenario.

## Tests

Focused verification:

```bash
swift test --filter CapabilityShowcaseTests
```

That target checks:

- every required capability family is represented in the registry
- the deterministic matrix passes
- CLI summary formatting stays aligned with the registered scenarios
