# Understanding the Store

Learn how Hive manages state through global stores, task-local overlays, and merged read-only views.

## Overview

Hive's store model separates shared state from per-task state and presents nodes with a unified read-only view. This architecture enables deterministic concurrent execution — nodes in the same superstep all read from the same pre-commit snapshot while their writes accumulate independently.

## Store architecture

```
                +---------------------+
                |   HiveSchemaRegistry |
                |   (channel specs)    |
                +----------+----------+
                           |
                +----------v----------+
                |  HiveInitialCache    |
                |  (default values)    |
                +----+-------+--------+
                     |       |
      +--------------+       +-------------+
      |                                    |
+-----v-----------+          +-------------v-----------+
|  HiveGlobalStore |          |  HiveTaskLocalStore      |
|  (global channels)|         |  (task-local overlays)   |
+-----+-----------+          +-------------+-----------+
      |                                    |
      +--+------+--------------------------+
         |      |
+--------v------v--------+
|    HiveStoreView        |
|  (read-only merged)     |
|  given to node closures |
+-------------------------+
```

## HiveGlobalStore

``HiveGlobalStore`` holds the current value for every global-scoped channel. One instance exists per thread. All tasks in a superstep see the same pre-commit snapshot.

```swift
public struct HiveGlobalStore<Schema: HiveSchema>: Sendable {
    public func get<Value: Sendable>(
        _ key: HiveChannelKey<Schema, Value>
    ) throws -> Value
}
```

During the atomic commit phase, the runtime:

1. Collects all writes, grouped by channel ID
2. Sorts writes deterministically by `(taskOrdinal, emissionIndex)`
3. Reduces using each channel's ``HiveReducer``
4. Resets `.ephemeral` channels to `initial()` after all reductions

## HiveTaskLocalStore

``HiveTaskLocalStore`` is a sparse overlay for task-local channels. Each spawned task carries its own instance, isolated from siblings.

```swift
public struct HiveTaskLocalStore<Schema: HiveSchema>: Sendable {
    public static var empty: HiveTaskLocalStore<Schema>
    public func get<Value: Sendable>(
        _ key: HiveChannelKey<Schema, Value>
    ) throws -> Value?
}
```

Key differences from the global store:

- `get` returns `Optional<Value>` — `nil` means use the initial value
- Only stores channels that have been explicitly written
- The channel's scope must be `.taskLocal`

## HiveStoreView

``HiveStoreView`` is a read-only merged view composed from the global store, task-local overlay, and initial cache. Every node receives one via `input.store`.

```swift
public struct HiveStoreView<Schema: HiveSchema>: Sendable {
    public func get<Value: Sendable>(
        _ key: HiveChannelKey<Schema, Value>
    ) throws -> Value
}
```

Resolution logic:

- **Global channels** — delegate to ``HiveGlobalStore``
- **Task-local channels** — check the overlay first, fall back to the initial cache

## Initial cache

The initial cache eagerly evaluates and caches `initial()` for every channel at construction time. It provides fallback values for task-local channels and reset values for ephemeral channels.

## Fingerprinting

The task-local fingerprint computes a SHA-256 digest of the effective task-local state (overlay merged with initial values). The runtime uses this to detect identical task-local states and deduplicate frontier entries.

## Code examples

### Reading from the store in a node

```swift
Node("worker") { input in
    let results: [String] = try input.store.get(MySchema.Channels.results)
    let item: String = try input.store.get(MySchema.Channels.item)
    return Effects {
        Set(MySchema.Channels.results, [item.uppercased()])
        End()
    }
}
```

### Fan-out with task-local state

```swift
SpawnEach(["a", "b", "c"], node: "worker") { item in
    var local = HiveTaskLocalStore<Schema>.empty
    try! local.set(MySchema.Channels.item, item)
    return local
}
```

### Accessing final state after a run

```swift
guard let store = await runtime.getLatestStore(
    threadID: threadID
) else { return }
let finalResults = try store.get(MySchema.Channels.results)
```
