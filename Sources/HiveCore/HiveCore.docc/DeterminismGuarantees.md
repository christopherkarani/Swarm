# Determinism Guarantees

Understand how Hive ensures reproducible execution for golden testing and debugging.

## Overview

Hive's core invariant is that **the same input always produces the same output and the same event trace**. This article explains the mechanisms that achieve this guarantee and how to leverage them for testing.

## Ordering guarantees

### Lexicographic node ordering

Frontier nodes execute in sorted order by ``HiveNodeID``. This means task ordinals are assigned deterministically — node `"A"` always gets ordinal 0 before node `"B"` at ordinal 1. Use lexicographically sortable names for predictable ordering.

### Deterministic write application

All writes within a superstep are sorted by `(taskOrdinal, emissionIndex)` before reduction. This means the order in which reducers see values is always the same, regardless of which task finishes first at the concurrency level.

### Sorted channel iteration

`registry.sortedChannelSpecs` ensures channels are processed in a consistent order during commit, reset, and checkpoint operations.

## Deterministic identifiers

Hive computes all identifiers deterministically using SHA-256:

| Identifier | Formula |
|-----------|---------|
| Task ID | SHA-256 of `(runID, stepIndex, nodeID, ordinal, fingerprint)` |
| Interrupt ID | SHA-256 of `"HINT1" + taskID` |
| Checkpoint ID | SHA-256 of `"HCP1" + runID + stepIndex` |

This means that replaying the same workflow produces the same IDs, enabling checkpoint compatibility across runs.

## Atomic superstep commits

All writes from a superstep apply together in a single atomic commit. No node ever sees a partially committed state — it reads the full pre-commit snapshot from the previous step.

## Deterministic stream buffering

When `deterministicStreamBuffering` is enabled in ``HiveRunOptions``, custom stream events are buffered per-task and replayed in ordinal order. This ensures that even with concurrent nodes, the event stream is deterministic.

## Golden testing

Graph descriptions produce immutable JSON with SHA-256 version hashes:

```swift
let description = graph.graphDescription()
// description.versionHash is a stable SHA-256
```

Identical graphs always produce identical JSON. Use this for regression testing:

```swift
#expect(description.versionHash == "expected-hash")
```

## Writing deterministic tests

When writing tests, assert **exact event ordering**, not just presence:

```swift
let taskStarts = events.compactMap { e -> HiveNodeID? in
    guard case let .taskStarted(n, _) = e.kind else { return nil }
    return n
}
#expect(taskStarts == [HiveNodeID("A"), HiveNodeID("B")])
```

Two parallel writers produce a deterministic append order because `"A"` sorts before `"B"`:

```swift
#expect(try store.get(valuesKey) == [1, 2, 3])
// A writes [1, 2], B writes [3] — A before B (lexicographic)
```

## Reducers and determinism

Built-in reducers are associative and produce deterministic results when writes are applied in order:

- `.lastWriteWins()` — the last write in `(taskOrdinal, emissionIndex)` order wins
- `.append()` — elements appear in sorted task order
- `.setUnion()` — set union is commutative, so order doesn't matter
- `.sum()`, `.min()`, `.max()` — commutative operations

Custom reducers should be designed to produce deterministic output when given deterministic input ordering.
