# Production Readiness Findings (Foundation Models DX)

> Historical snapshot of the 0.6.0 Foundation Models DX pass (2026-07-17).
> It is not current production guidance. For the live public surface, use
> [front-facing-api.md](../reference/front-facing-api.md), [overview.md](../reference/overview.md),
> and [api-catalog.md](../reference/api-catalog.md).

Audit and hardening pass focused on making Swarm easy to use in real apps — especially with **Apple Foundation Models** — without breaking the public API.

**Date:** 2026-07-17 · **Branch work:** `chore-polishapi` · **Framework version:** 0.6.0 (historical)

## Baseline

| Check | Result |
| --- | --- |
| Parallel `swift build` | Failed initially: Swift 6.2 linker race on `SyntaxRewriter.visitationFunc` (swift-package-manager#9495) when linking `SwarmMacros-tool` |
| `swift test --no-parallel` | 1 failure: `DocumentationFreshnessTests` (API catalog source-file count stale at 157 vs 161) |
| Live FM tool calling (`SWARM_RUN_LIVE_FOUNDATION_MODELS_TESTS=1`) | Passed on host with Apple Intelligence available |
| Capability matrix | Extended with deterministic `foundation-models` + opt-in live smoke |

## Issues found (priority order)

### Fixed

1. **Macro linker flakiness (build reliability)**  
   `InlineToolMacro` subclassed `SyntaxRewriter`, which can fail to link under parallel jobs on Swift 6.2 / swift-syntax 602.  
   **Fix:** rewrite bare parameter references with regex-based string transform (no `SyntaxRewriter` subclass).

2. **API catalog freshness**  
   Source file count under `Sources/Swarm` (excluding GraphRuntime) grew to 161 after Foundation Models files landed; catalog still said 157.  
   **Fix:** update `docs/reference/api-catalog.md` header count.

3. **Broken README Quick Start snippet**  
   `inferenceProvider: .anthropic(key: "{ENV"))` was syntactically invalid and preferred cloud without mentioning FM.  
   **Fix:** valid `apiKey:` spelling + FM-first guidance.

4. **No end-to-end apps that actually run**  
   `Examples/CodeReviewer` linked Swarm but did not exercise agents/workflows live.  
   **Fix:** add `Examples/OnDeviceChat` and `Examples/MultiAgentPipeline` with `--demo` (scripted, CI-safe) and live FM paths.

5. **Capability matrix gap for Foundation Models**  
   Providers scenario covered MultiProvider/task-local overrides only.  
   **Fix:** deterministic `foundation-models` scenario (factories, capabilities, availability, Agent tool + multi-turn wiring) and opt-in `live-foundation-models-smoke`.

6. **Doc `Agent(...)` argument order**  
   Several README/getting-started snippets put `inferenceProvider:` before `memory:`, which does not type-check against the canonical initializer.  
   **Fix:** reorder all major snippets to `configuration → memory → inferenceProvider → guardrails`; add compile tests in `ReadmeProviderCompileTests`.

7. **Ambiguous cloud factory overloads on `InferenceProvider`** *(historical; resolved by 0.6 hard break)*  
   Pre-0.6, dual `LLM` / Conduit-backed factory families made `apiKey:` / `key:` selection ambiguous.  
   **Fix (0.6):** Conduit and `LLM.*` were hard-removed. Built-in inference is Foundation Models only; custom backends inject `InferenceProvider`.

### Documented (fundamental / deferred)

| Item | Guidance |
| --- | --- |
| FM requires macOS/iOS 26+ and system model availability | Use `ifAvailable()`; demos exit with clear stderr when unavailable |
| FM does **not** advertise streaming tool calls | Text stream; tools are capture-then-execute per turn |
| On-device safety may refuse "secret/codeword" multi-turn framing | Prefer benign memory prompts (e.g. favorite color); documented in `OnDeviceChat` |
| Linux CI cannot import FoundationModels | Deterministic matrix still passes; live smoke skips honestly |
| Dynamic Profiles are Swarm-native until Apple ships SDK API | Documented in provider DocC; bridges later without call-site breaks |
| Full API catalog regeneration (all new public rows) | Header count fixed; exhaustive row-by-row regen deferred as lower priority |
| CodeReviewer still deterministic plan-only | Superseded by new examples for agent/workflow stress |

## High-impact DX wins shipped

- **Foundation Models First** section in `README.md` and getting-started on-device path first.
- Copy-pasteable demos that prove streaming, tools, conversation, workflows, and durable resume.
- Matrix scenario that keeps the FM path from regressing on factories/capabilities even when the system model is cold.
- Safer defaults messaging: prefer `apiKey:` for cloud factories in docs; keep `key:` aliases working.

## Verification commands

```bash
swift test --no-parallel
swift run SwarmCapabilityShowcase matrix
cd Examples/OnDeviceChat && swift run OnDeviceChat --demo
cd Examples/MultiAgentPipeline && swift run MultiAgentPipeline --demo
# Optional live:
SWARM_SHOWCASE_FOUNDATION_MODELS=1 swift run SwarmCapabilityShowcase smoke
SWARM_RUN_LIVE_FOUNDATION_MODELS_TESTS=1 swift test --filter liveNativeToolCalling
```

## Constraints respected

- Public API additive only (no silent removals).
- StrictConcurrency / Sendable preserved.
- Live provider smoke remains opt-in.
- No gitignored internal audit paths used as the completion artifact (this guide is tracked under `docs/guide/`).
