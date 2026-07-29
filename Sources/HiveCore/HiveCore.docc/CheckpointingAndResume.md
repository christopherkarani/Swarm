# Checkpointing and Resume

Save workflow state, resume from interrupts, and implement persistent checkpoint stores.

## Overview

Hive's checkpointing system captures complete runtime state snapshots — store values, frontier tasks, join barriers, and pending interrupts. Combined with the interrupt/resume protocol, this enables long-running workflows that pause for human approval and resume with typed payloads.

## Checkpoint format

``HiveCheckpoint`` captures a complete runtime state snapshot:

| Field | Type | Purpose |
|-------|------|---------|
| `id` | ``HiveCheckpointID`` | Deterministic identifier |
| `threadID` | ``HiveThreadID`` | Thread this belongs to |
| `stepIndex` | `Int` | Superstep index at save time |
| `globalDataByChannelID` | `[String: Data]` | Encoded global store values |
| `frontier` | `[HiveCheckpointTask]` | Persisted frontier tasks |
| `joinBarrierSeenByJoinID` | `[String: [String]]` | Join barrier state |
| `interruption` | `HiveInterrupt?` | Pending interrupt |
| `channelVersionsByChannelID` | `[String: UInt64]` | Version counters |

## Checkpoint store protocol

Implement ``HiveCheckpointStore`` to persist checkpoints:

```swift
public protocol HiveCheckpointStore: Sendable {
    associatedtype Schema: HiveSchema
    func save(_ checkpoint: HiveCheckpoint<Schema>) async throws
    func loadLatest(
        threadID: HiveThreadID
    ) async throws -> HiveCheckpoint<Schema>?
}
```

For history browsing, ``HiveCheckpointQueryableStore`` adds `listCheckpoints` and `loadCheckpoint`.

`fork` uses these capabilities as follows:
- Explicit checkpoint fork (`from: checkpointID`) requires `loadCheckpoint` support.
- Latest-checkpoint fork (`from: nil`) uses `loadLatest`.
- If query support is unavailable for explicit ID lookup, fork fails with typed runtime error.

## Checkpoint policies

``HiveCheckpointPolicy`` controls when checkpoints are saved:

```swift
public enum HiveCheckpointPolicy: Sendable {
    case disabled
    case everyStep
    case every(steps: Int)
    case onInterrupt
}
```

## Interrupt flow

1. A node returns a ``HiveInterruptRequest`` with a typed payload
2. The runtime selects the interrupt from the lowest-ordinal task (deterministic)
3. A checkpoint is saved with the interrupt embedded
4. The run outcome is `.interrupted` with a ``HiveInterruption``

```swift
Node("review") { _ in
    Effects { Interrupt("Approve results?") }
}

// Handle the interrupt
let handle = await runtime.run(
    threadID: tid, input: (), options: opts
)
let outcome = try await handle.outcome.value
guard case let .interrupted(interruption) = outcome else { return }
```

## Resume flow

1. Call `runtime.resume(threadID:interruptID:payload:options:)`
2. The runtime loads the latest checkpoint and verifies the interrupt ID matches
3. A ``HiveResume`` is delivered to nodes via `input.run.resume`
4. Execution continues from the saved frontier

```swift
let resumed = await runtime.resume(
    threadID: tid,
    interruptID: interruption.interrupt.id,
    payload: "approved",
    options: opts
)
let final = try await resumed.outcome.value
```

## Interrupt type system

| Type | Direction | Purpose |
|------|-----------|---------|
| ``HiveInterruptRequest`` | Node to runtime | Request to pause |
| ``HiveInterrupt`` | Persisted | Saved in checkpoint (id + payload) |
| ``HiveResume`` | Runtime to node | Resume data for next execution |
| ``HiveInterruption`` | Run outcome | Interrupt + checkpoint ID |

## Fork contract

Use `runtime.fork(threadID:to:from:options:)` to branch a new thread lineage from checkpoint state.

API-level guarantees:
- deterministic checkpoint selection (`from` explicit ID or latest)
- explicit source/target thread identity in ``HiveForkResult``
- optional durable target checkpoint when `options?.checkpointPolicy != .disabled`
- independent target lineage (future target writes do not mutate source)

Failure semantics (fail-closed, typed errors):
- `forkCheckpointStoreMissing`
- `forkSourceCheckpointMissing`
- `forkCheckpointQueryUnsupported`
- `forkTargetThreadConflict`
- `forkSchemaGraphMismatch`
- `forkMalformedCheckpoint`
