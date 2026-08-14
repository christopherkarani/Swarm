# Durable Execution

Durable workflows persist progress to a checkpoint store and resume from a
checkpoint ID after a crash, process restart, or explicit `resumeFrom`.
Checkpoint/resume requires the **`Integrations`** SwiftPM trait
(`--traits Integrations` or `.package(..., traits: ["Integrations"])`).

```swift
let result = try await Workflow()
    .step(fetchAgent)
    .step(analyzeAgent)
    .durable
    .checkpoint(id: "weekly-report", policy: .everyStep)
    .durable
    .checkpointing(.fileSystem(directory: checkpointsURL))
    .durable
    .execute("Create this week's report", resumeFrom: nil)
```

This page is the contract for what resume does — and what it does not do.

## Step-granularity semantics

A durable checkpoint is written **after a workflow step completes**, not in the
middle of that step.

- If the process dies **mid-step**, resume re-runs the **entire** step from its
  original input. Partial side effects from the failed attempt are not rolled
  back.
- If the process dies **after** the checkpoint write, resume continues at the
  next step. The completed step is not re-executed.
- If the process dies **after** the step finishes but **before** the checkpoint
  is persisted, resume treats the step as incomplete and re-runs it.

Side effects inside a step (HTTP calls, file writes, tool invocations) must be
**idempotent** or **externalized** behind an idempotency key. Swarm does not
checkpoint agent session state or memory this quarter — only workflow cursor,
last step result, and the workflow signature.

`.everyStep` records progress after each step. `.onCompletion` records a single
checkpoint when the workflow finishes.

## Signature stability

Resume matches the saved workflow against the current definition. The signature
is derived from:

1. Step **kind** and **position** (`single`, `parallel`, `route`, `fallback`,
   `repeat`)
2. Stable agent identifiers (type, name, instructions, configuration, tools)
3. An explicit `signature:` / `customMergeSignature:` when you provide one

`#fileID` and `#line` are **not** part of identity. Editing source so a builder
moves to a different line does not break resume.

```swift
// Same signature at any line number:
.route { input in input.contains("risk") ? riskAgent : summaryAgent }

// Bump this when the closure behavior changes, or resume will keep matching:
.route({ input in input.contains("risk") ? riskAgent : summaryAgent }, signature: "risk-router-v2")
```

| Builder | Implicit identity (no `signature:`) | When to pass `signature:` |
|---|---|---|
| `.step` | Agent configuration | You change the agent’s name, instructions, tools, or config |
| `.parallel` + built-in merge | Agents + merge kind | You change the agent set or merge strategy |
| `.parallel` + `.custom` | Kind + position | The merge closure behavior changes |
| `.route` | Kind + position | The routing closure behavior changes |
| `.repeatUntil` | Kind + `repeat` position | The stop predicate changes |

Durable execute emits a **one-time** warning when a workflow relies on implicit
identity for route / custom merge / repeat. The warning is informational —
resume still works — but you should add an explicit signature before changing
those closures.

### Migration from fileID:line identity

Older checkpoints stored opaque-step identity as `fileID:line` (`:source:` in
the signature string). Those checkpoints **do not** load best-effort.

Resume throws `WorkflowError.resumeDefinitionMismatch` with a message that names
the legacy identity and tells you to start a new run. Sequential-only workflows
that never used route / custom merge / implicit repeat keep matching, because
their signature never included a source location.

## Pruning and indexed loads

`WorkflowCheckpointing.fileSystem(directory:retention:)` writes one JSON file
per checkpoint plus a directory manifest
(`workflow-checkpoints.manifest.json`).

- **Policy:** keep the newest `N` checkpoints **per durable run** (the
  checkpoint ID / thread). Default `N` is **16**.
- **Deletion:** the manifest is updated first, then pruned files are removed.
  A crash between those steps can leave an orphan file; it is not loaded.
- **Loads:** `loadLatest` reads the manifest and decodes the newest readable
  file. It does not scan or decode the whole directory.
- **Corruption:** a checkpoint file that fails to decode is skipped with a
  warning. Load continues to the previous entry. If every entry is corrupt,
  load returns `nil` instead of throwing.

```swift
let checkpointing = WorkflowCheckpointing.fileSystem(
    directory: checkpointsURL,
    retention: WorkflowCheckpointRetention(maxCheckpointsPerRun: 8)
)
```

In-memory stores are unbounded and intended for tests.

## What is not checkpointed

Agent session history, memory backends, and in-flight tool calls are **not**
part of a workflow checkpoint. Rebuild those independently, or keep step bodies
idempotent so a re-run is safe.
