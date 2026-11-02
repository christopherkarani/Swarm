# Durable Execution

Durable workflows persist progress to a checkpoint store and resume from a
checkpoint ID after a crash, process restart, or an explicit
``DurableWorkflow/resume(_:from:)``.
Checkpoint/resume requires the **`Integrations`** SwiftPM trait
(`--traits Integrations` or `.package(..., traits: ["Integrations"])`).

```swift
let durable = Workflow()
    .step(fetchAgent)
    .step(analyzeAgent)
    .durable
    .configured(
        id: WorkflowCheckpointID("weekly-report"),
        store: .fileSystem(directory: checkpointsURL),
        policy: .everyStep
    )

let result = try await durable.execute("Create this week's report")
let again = try await durable.resume("Create this week's report", from: WorkflowCheckpointID("weekly-report"))
```

The deprecated `checkpoint` / `checkpointing` / `execute(_:resumeFrom:)` builders remain
available for existing call sites. Prefer ``DurableWorkflow`` for new code.

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

## Checkpoint file permissions

Checkpoint files and the manifest are written owner-only (`0600` files;
directories created by the store are `0700`, pre-existing directories keep
their permissions) because they may contain prompt and tool-result content.
Files written before this hardening keep their original permissions; migrate
a pre-existing directory in place, or delete and re-run:

```swift
let hardened = try WorkflowCheckpointing.hardenFilePermissions(in: checkpointsURL)
```

See the [Secret Storage guide](secret-storage.md) for memory-store
permissions and the full migration notes.

## What is not checkpointed

Agent session history, memory backends, and in-flight tool calls are **not**
part of a workflow checkpoint. Rebuild those independently, or keep step bodies
idempotent so a re-run is safe.

## Tool approvals (human-in-the-loop)

A tool that declares `ToolExecutionSemantics(approvalRequirement: .always)`
pauses a durable run instead of executing. `DurableWorkflow.execute(_:)` throws
`WorkflowApprovalRequired` carrying the tool name, arguments, paused step
cursor, and checkpoint/interrupt IDs; the tool has not run and the checkpoint
holds the paused step cursor. There is no timeout on the wait.

```swift
do {
    return try await durable.execute("Tear down staging")
} catch let required as WorkflowApprovalRequired {
    print("Approve \(required.toolName) at step \(required.stepCursor)")
}
// Later — same process or a fresh one sharing the checkpoint store:
let result = try await durable.resume(decision: .approve, from: checkpointID)
```

`.approve` executes the paused call and continues the run; `.reject` fails with
`WorkflowError.humanApprovalRejected` without executing. There is no
edited-arguments resume: approval runs the call exactly as requested. A resumed
step that reaches another approval-required tool pauses again with its own
`WorkflowApprovalRequired`.

Decisions are durable and one-shot:

- A rejection is committed to the checkpoint as a terminal state. A later
  `resume(decision: .approve, from:)` on that checkpoint throws (no paused
  approval) instead of running the rejected call, and a plain `resume(_:from:)`
  rethrows `WorkflowError.humanApprovalRejected`.
- An approval authorizes one execution of the exact call (tool name and
  arguments). If the step calls the same tool with the same arguments again,
  that second call pauses for its own approval.

Only one resume of a paused run executes. A second `resume` of the same
checkpoint while the first is running throws `WorkflowResumeConflict` instead
of running the tool again. In one process this is an in-memory guard per
checkpoint store; across processes sharing a checkpoint directory, an approval
resume first claims the pause with a compare-and-swap checkpoint save (the
file store holds an advisory `flock` on the directory for the swap). A claim
left behind by a crashed process expires after 10 minutes, after which the
pause can be resumed again. A resume that fails before committing (for
example an inference error) releases its claim, so it can be retried
immediately.

The resumed run replays the paused step from its start, but tool calls do not
execute twice:

- Every tool call that executes inside a durable step is recorded in a
  per-step journal, which is stored in the approval interrupt payload. This
  covers successes and failures, and approval-gated and ordinary tools alike.
- On replay, a call that matches a journal entry (same tool name and exact
  arguments, earliest unused entry first) returns the recorded output instead
  of executing. The call and result still appear in the step's `AgentResult`.
  Observers and tracing are not notified again, and the agent's memory is not
  written a second time.
- A call that does not match a journal entry runs normally. That includes a
  call whose arguments changed because the model answered differently on
  replay. Calls recorded during the current replay are not reused within it,
  so a repeated identical call runs, or pauses, on its own.
- Cancelled calls are not journaled, and neither are handoffs or Membrane
  internal tools.
- If a replay keeps pausing on other calls and never reaches the call that was
  just approved (the model keeps asking for something different), the third
  approve in a row throws `WorkflowApprovalReplayDiverged` instead of asking
  again. Nothing is executed and the run stays paused: reject it, or make the
  step deterministic.

Direct (non-durable) runs never pause. Observe pauses on the `AgentEvent` stream via
`AgentEvent.Tool.approvalRequested` (or
`AgentObserver.onToolApprovalRequested`).
