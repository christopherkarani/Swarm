# HiveCore

[![Discord](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fdiscord.com%2Fapi%2Fv10%2Finvites%2FNHgNh7HJ6M%3Fwith_counts%3Dtrue&query=%24.approximate_presence_count&suffix=%20online&logo=discord&label=Discord&color=5865F2)](https://discord.gg/NHgNh7HJ6M)

HiveCore provides the schema, graph builder, and deterministic runtime for Hive.

## Mental Model
- Channels are typed state slots declared in a `HiveSchema`.
- Reducers define how multiple writes to a channel merge within a superstep.
- Supersteps run the current frontier of tasks, then commit writes and schedule the next frontier.
- Send and join: tasks emit writes and routing decisions; join edges wait until all parents have run since the last join before scheduling the target.
- Checkpoint/resume persists global state, frontier, and join barriers so a thread can resume with an interrupt payload.

## Define a Schema
```swift
import HiveCore

enum DemoSchema: HiveSchema {
    typealias Context = Void
    typealias Input = String

    enum Channels {
        static let messages = HiveChannelKey<DemoSchema, [String]>(HiveChannelID("messages"))
    }

    static let channelSpecs: [AnyHiveChannelSpec<DemoSchema>] = [
        AnyHiveChannelSpec(
            HiveChannelSpec(
                key: Channels.messages,
                scope: .global,
                reducer: .append(),
                updatePolicy: .multi,
                initial: { [] },
                persistence: .untracked
            )
        )
    ]

    static func inputWrites(
        _ input: String,
        inputContext: HiveInputContext
    ) throws -> [AnyHiveWrite<DemoSchema>] {
        [AnyHiveWrite(Channels.messages, [input])]
    }
}
```

Notes:
- Task-local channels must be `checkpointed` and require a `HiveCodec`.
- Global channels require a codec when `persistence: .checkpointed`.

## Build a Graph
```swift
var builder = HiveGraphBuilder<DemoSchema>(start: [HiveNodeID("Start")])

builder.addNode(HiveNodeID("Start")) { input in
    let messages = try input.store.get(DemoSchema.Channels.messages)
    return HiveNodeOutput(
        writes: [AnyHiveWrite(DemoSchema.Channels.messages, messages + ["done"])],
        next: .end
    )
}

let graph = try builder.compile()
```

To model joins, add a join edge:
`builder.addJoinEdge(parents: [HiveNodeID("A"), HiveNodeID("B")], target: HiveNodeID("Join"))`

## Export a Graph Description
Generate a deterministic description of a compiled graph for tooling and inspection.

```swift
let description = graph.graphDescription()
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let json = try encoder.encode(description)
```

Determinism rules:
- Node listing order: lexicographic UTF-8 by `nodeID.rawValue`.
- Router listing order: lexicographic UTF-8 by `nodeID.rawValue`.
- Edge listing order: preserves builder insertion order for static and join edges.

## Generate Mermaid
Render a compiled graph to Mermaid `flowchart` syntax.

```swift
let mermaid = HiveGraphMermaidExporter.export(graph.graphDescription())
print(mermaid)
```

## Run in an App
Provide `HiveClock` and `HiveLogger` implementations from your app/runtime.

```swift
let environment = HiveEnvironment<DemoSchema>(
    context: (),
    clock: appClock,
    logger: appLogger,
    checkpointStore: nil
)

let runtime = HiveRuntime(graph: graph, environment: environment)
let handle = await runtime.run(
    threadID: HiveThreadID("thread-1"),
    input: "hello",
    options: HiveRunOptions(maxSteps: 50)
)

Task {
    for try await event in handle.events {
        // Inspect `event.kind` for step/task/write/checkpoint updates.
    }
}

let outcome = try await handle.outcome.value
```

Checkpoint/resume flow:
- Provide a `HiveCheckpointStore` in `HiveEnvironment` and enable a checkpoint policy in `HiveRunOptions`.
- On `.interrupted`, resume with `runtime.resume(threadID:interruptID:payload:options:)` using the provided `HiveInterruptID`.
- `HiveRuntime.validateRunOptions(_:)` is available as a public preflight API and is used by `run`, `resume`, and `applyExternalWrites`.

## Runtime State Snapshot
Use `getState(threadID:)` for a typed deterministic state snapshot:

```swift
let state = try await runtime.getState(threadID: HiveThreadID("thread-1"))
```

`HiveRuntimeStateSnapshot` includes:
- `threadID`, `runID`, `stepIndex`
- interruption metadata (`interruptID` + payload hash)
- `checkpointID`
- `globalChannelPayloadHashesByID`
- `frontierSummary` for deterministic comparisons
- typed `store` projection for channel reads

## Checkpoint Inspection
Some checkpoint stores support optional history and load-by-id operations.

Using `HiveRuntime` helpers:
```swift
let history = try await runtime.getCheckpointHistory(threadID: HiveThreadID("thread-1"), limit: 10)
let checkpoint = try await runtime.getCheckpoint(threadID: HiveThreadID("thread-1"), id: history[0].id)
```

Use `runtime.checkpointCapabilities()` to discover query support.
If the configured store does not support query operations, these calls throw typed unsupported errors:
- `HiveCheckpointQueryError.unsupported(operation: .listCheckpoints)`
- `HiveCheckpointQueryError.unsupported(operation: .loadCheckpointByID)`

## Transcript + Hash Utilities
Use `HiveEventTranscript` and `HiveTranscriptHasher` for deterministic replay checks:

```swift
let transcript = HiveEventTranscript(events: events)
let transcriptHash = try transcript.transcriptHash()
let stateHash = HiveTranscriptHasher.finalStateHash(stateSnapshot: state)
let diff = transcript.firstDiff(comparedTo: baseline)
```

`HiveEventTranscript` normalizes volatile identifiers by default so seeded repeated runs can be compared across attempts.

## Event Schema Versioning
Every event carries `HiveEvent.schemaVersion` (`HiveEventSchemaVersion`), and replay compatibility can be validated with:
- `HiveEventTranscript.validateReplayCompatibility(expected:)`

## Stream Views
`HiveEventStreamViews` provides typed, filtered views over a `HiveEvent` stream.

Progress UI (steps):
```swift
let views = HiveEventStreamViews(handle.events)
for try await event in views.steps() {
    // event.kind: .started(stepIndex:, frontierCount:) or .finished(stepIndex:, nextFrontierCount:)
}
```

Debug stream:
```swift
let views = HiveEventStreamViews(handle.events)
for try await event in views.debug() {
    // event.kind: .customDebug(name:) or .streamBackpressure(droppedDebugEvents:)
}
```

## Examples
- `../../Examples/README.md`
- `../../Tests/HiveCoreTests/Runtime/HiveRuntimeStepAlgorithmTests.swift`
- `../../Tests/HiveCoreTests/Runtime/HiveRuntimeCheckpointTests.swift`
- `../../Tests/HiveCoreTests/Runtime/HiveRuntimeInterruptResumeExternalWritesTests.swift`
