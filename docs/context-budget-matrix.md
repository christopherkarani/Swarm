# Context Budget Matrix

This note turns the current `strict4k` implementation into a benchmarkable matrix for tool-heavy agent loops, especially `websearch`.

## Current budget contract

Swarm's `strict4k` template currently resolves to:

- `4096` total context tokens
- `3412` max input tokens after output/protocol/safety reserves
- `512` system tokens
- `1400` history tokens
- `900` memory tokens
- `600` tool-I/O tokens

Code references:

- [ContextProfile.swift](/Users/chriskarani/CodingProjects/AIStack/Agents/dex/Swarm/Sources/Swarm/Core/ContextProfile.swift)
- [PromptEnvelope.swift](/Users/chriskarani/CodingProjects/AIStack/Agents/dex/Swarm/Sources/Swarm/Core/PromptEnvelope.swift)
- [Agent.swift](/Users/chriskarani/CodingProjects/AIStack/Agents/dex/Swarm/Sources/Swarm/Agents/Agent.swift)

## What actually compacts today

`ContextCore`:

- Packs retrieved context into a hard token budget.
- Progressively compresses lower-priority chunks from full -> light -> heavy -> dropped.
- Guarantees recent turns and reranks recalled chunks before packing.

Code references:

- [AgentContext.swift](/Users/chriskarani/CodingProjects/AIStack/Agents/ContextCore/Sources/ContextCore/AgentContext.swift)
- [WindowPacker.swift](/Users/chriskarani/CodingProjects/AIStack/Agents/ContextCore/Sources/ContextCore/WindowPacker.swift)
- [ProgressiveCompressor.swift](/Users/chriskarani/CodingProjects/AIStack/Agents/ContextCore/Sources/ContextCore/ProgressiveCompressor.swift)

`Membrane` in Swarm today:

- JIT-reduces visible tool schemas when the tool set is large.
- Pointerizes large tool outputs in `strict4k` mode at `100` bytes with a short summary.
- Runs through the session-backed `MembraneSession` path by default, with strict4k-specific distillation before any hard prompt-envelope fallback.

Code references:

- [MembraneAgentAdapter.swift](/Users/chriskarani/CodingProjects/AIStack/Agents/dex/Swarm/Sources/Swarm/Integration/Membrane/MembraneAgentAdapter.swift)
- [PointerResolver.swift](/Users/chriskarani/CodingProjects/AIStack/Agents/Membrane/Sources/Membrane/Stages/Intake/PointerResolver.swift)

## Important limitation

The best current compaction is split across two different paths:

- `ContextCore` is effective for retrieved memory windows.
- `Membrane` is effective for shrinking large tool outputs.
- Swarm now defaults to the session-backed `MembraneSession` path, but the adapter protocol still only passes a distilled prompt string into Membrane planning. That means live transcript compaction is improved, not fully structured end-to-end yet.

That means `ContextCore` alone does not significantly reduce the live transcript growth caused by repeated `websearch` calls. It mainly improves what can be recovered and repacked once history starts overflowing.

## How to generate the matrix

Run:

```bash
swift scripts/context_budget_matrix.swift
```

The script prints a markdown table for two concrete scenarios:

- compact `websearch` result
- grounded/fetch-heavy result

For a measured replay benchmark instead of the static model, run:

```bash
SWARM_INCLUDE_DEMO=1 swift run ContextBenchmark
```

That harness uses fixed synthetic `websearch` payloads, a replay provider, and the same strict4k contract across:

- baseline
- ContextCore only
- Membrane only
- ContextCore + Membrane

The current measured run shows:

- Membrane reduces visible tool schemas from `21` to `6` and pointerizes all `12` large tool results in both traces.
- ContextCore-only is the first configuration that actually hits strict4k truncation in this harness:
  - compact trace: first truncation after tool call `7`
  - grounded trace: first truncation after tool call `4`
- After the strict4k integration cleanup, combined mode stays below truncation in both traces and is leaner than before:
  - compact trace: avg prompt `1316.8`, max prompt `2233`
  - grounded trace: avg prompt `1321.7`, max prompt `2241`
- Combined mode is still materially larger than Membrane-only because retrieved context and live conversation are still compacted in separate layers, but the worst duplication paths were removed.

The useful interpretation is:

- Without Membrane, a compact `websearch` result costs roughly `340` live-transcript tokens per tool call, so the `1400`-token history lane saturates at about `4` calls.
- Without Membrane, a grounded or fetch-heavy result can cost roughly `940` live-transcript tokens per tool call, so saturation happens at about `1` call.
- With Membrane pointerization, the same loop drops to roughly `85` live-transcript tokens per call, which pushes the same lane to about `16` calls.
- With ContextCore added, overflow becomes much more survivable because roughly `900` tokens of recalled evidence can be repacked back into the prompt.

## Upgrade opportunities

Highest-value upgrades:

- Make pointer storage durable. The current default adapter checkpoints pointer IDs but not pointer payloads, so restored sessions cannot truly resolve old pointers.
- Feed live history and pointer records into `MembraneContextCoreBackend`. Right now it only turns `memories + retrieval` into `ContextCore` turns, which leaves real transcript compaction on the table.
- Make `DefaultAgentMemory.context(for: MemoryQuery)` honor `maxItems` and `maxItemTokens`. Right now it only respects the token limit, so the profile's per-item retrieval controls are effectively ignored.
- Continue reducing overlap between retrieved context and live conversation in strict4k mode. The current cleanup removed the biggest prompt duplication paths, but the live transcript and recalled context are still budgeted separately.

## Recommended matrix dimensions

For a presentation-quality matrix, use:

- rows: `No optimization`, `ContextCore only`, `Membrane only`, `ContextCore + Membrane`
- columns: `inline tokens per tool call`, `calls before history saturation`, `calls before prompt truncation`, `recalled evidence retained after overflow`, `tool schema tokens shown`, `notes`

If you want a stronger claim than a model-based estimate, the next step should be an automated harness that executes synthetic `websearch` traces and records:

- prompt token count per iteration
- tool result bytes before/after pointerization
- number of calls before `PromptEnvelope` truncates
- number of evidence chunks recovered by `ContextCore`
- latency added by each path
