# Defining a Schema

Declare typed state channels with reducers, scopes, codecs, and persistence levels.

## Overview

Every Hive workflow is parameterized by a schema — an enum conforming to ``HiveSchema`` — that declares the typed channels nodes read from and write to. The schema defines what data flows through the graph, how concurrent writes merge, and what state survives checkpointing.

## The HiveSchema protocol

```swift
public protocol HiveSchema: Sendable {
    associatedtype Context: Sendable = Void
    associatedtype Input: Sendable = Void
    associatedtype InterruptPayload: Codable & Sendable = String
    associatedtype ResumePayload: Codable & Sendable = String

    static var channelSpecs: [AnyHiveChannelSpec<Self>] { get }
    static func inputWrites(_ input: Input, inputContext: HiveInputContext) throws -> [AnyHiveWrite<Self>]
}
```

| Associated Type | Purpose |
|----------------|---------|
| `Context` | User-defined context passed to every node via ``HiveEnvironment`` |
| `Input` | Typed input for `runtime.run()` — converted to writes before step 0 |
| `InterruptPayload` | Data type attached to interrupt requests |
| `ResumePayload` | Data type provided when resuming from an interrupt |

## Channel specs

Each channel is declared via ``HiveChannelSpec``:

```swift
public struct HiveChannelSpec<Schema: HiveSchema, Value: Sendable>: Sendable {
    public let key: HiveChannelKey<Schema, Value>
    public let scope: HiveChannelScope
    public let reducer: HiveReducer<Value>
    public let updatePolicy: HiveUpdatePolicy
    public let initial: @Sendable () -> Value
    public let codec: HiveAnyCodec<Value>?
    public let persistence: HiveChannelPersistence
}
```

## Channel keys

``HiveChannelKey`` provides type-safe references to channels:

```swift
let messages = HiveChannelKey<MySchema, [String]>(HiveChannelID("messages"))
let score = HiveChannelKey<MySchema, Int>(HiveChannelID("score"))
```

## Scopes

| Scope | Store | Visibility |
|-------|-------|-----------|
| `.global` | ``HiveGlobalStore`` | Shared across all tasks in a thread |
| `.taskLocal` | ``HiveTaskLocalStore`` | Isolated per spawned task (fan-out) |

## Persistence modes

| Level | Checkpointed? | Reset behavior |
|-------|--------------|----------------|
| `.checkpointed` | Yes | Survives across interrupt/resume |
| `.untracked` | No | Preserved across supersteps, not saved |
| `.ephemeral` | No | Reset to `initial()` after each superstep |

## Reducers

When multiple nodes write to the same channel in one superstep, the ``HiveReducer`` defines how writes merge:

| Reducer | Constraint | Behavior |
|---------|-----------|----------|
| `.lastWriteWins()` | Any | Replaces current with update |
| `.append()` | `RangeReplaceableCollection` | Appends update to current |
| `.appendNonNil()` | Optional collection | Nil-safe append |
| `.setUnion()` | `Set<Hashable>` | Union of current and update |
| `.dictionaryMerge(valueReducer:)` | `[String: V]` | Merges dicts, resolving via inner reducer |
| `.sum()` | `Numeric` | Adds current + update |
| `.min()` | `Comparable` | Keeps the lesser value |
| `.max()` | `Comparable` | Keeps the greater value |
| `.binaryOp(_:)` | Any | Custom binary operator |

You can also provide a fully custom reducer:

```swift
HiveReducer { current, update in
    // your merge logic
}
```

## Codecs

Channels that are checkpointed or task-local require a ``HiveCodec`` for serialization:

```swift
public protocol HiveCodec: Sendable {
    associatedtype Value: Sendable
    var id: String { get }
    func encode(_ value: Value) throws -> Data
    func decode(_ data: Data) throws -> Value
}
```

The built-in ``HiveJSONCodec`` provides JSON serialization for any `Codable` type. ``HiveAnyCodec`` wraps any concrete codec with type erasure.

## Type erasure

``AnyHiveChannelSpec`` erases the `Value` generic from `HiveChannelSpec<Schema, Value>`, allowing heterogeneous channel specs in the `channelSpecs` array. It uses boxed closures to maintain type safety at runtime.

## Complete example

```swift
enum MySchema: HiveSchema {
    typealias Input = String
    typealias InterruptPayload = String
    typealias ResumePayload = String

    enum Channels {
        static let messages = HiveChannelKey<MySchema, [String]>(
            HiveChannelID("messages")
        )
        static let item = HiveChannelKey<MySchema, String>(
            HiveChannelID("item")
        )
    }

    static var channelSpecs: [AnyHiveChannelSpec<MySchema>] {
        [
            AnyHiveChannelSpec(HiveChannelSpec(
                key: Channels.messages,
                scope: .global,
                reducer: .append(),
                updatePolicy: .multi,
                initial: { [] },
                codec: HiveAnyCodec(HiveJSONCodec<[String]>()),
                persistence: .checkpointed
            )),
            AnyHiveChannelSpec(HiveChannelSpec(
                key: Channels.item,
                scope: .taskLocal,
                reducer: .lastWriteWins(),
                updatePolicy: .single,
                initial: { "" },
                codec: HiveAnyCodec(HiveJSONCodec<String>()),
                persistence: .checkpointed
            )),
        ]
    }

    static func inputWrites(
        _ input: String,
        inputContext: HiveInputContext
    ) throws -> [AnyHiveWrite<MySchema>] {
        [AnyHiveWrite(Channels.messages, [input])]
    }
}
```
