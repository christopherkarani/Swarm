# Building Graphs

Construct workflow graphs with the imperative graph builder, validate them, and export visualizations.

## Overview

A compiled graph is the executable representation of a workflow. It contains nodes, edges, routers, and join barriers validated by the compiler. Build graphs explicitly with ``HiveGraphBuilder``.

## HiveGraphBuilder

``HiveGraphBuilder`` provides the imperative API for constructing graphs:

```swift
var builder = HiveGraphBuilder<Schema>(
    start: [HiveNodeID("A")]
)

builder.addNode(HiveNodeID("A")) { input in
    HiveNodeOutput(
        writes: [AnyHiveWrite(key, value)],
        next: .useGraphEdges
    )
}

builder.addNode(HiveNodeID("B")) { _ in
    HiveNodeOutput(next: .end)
}

builder.addEdge(from: HiveNodeID("A"), to: HiveNodeID("B"))
```

### Join edges

Join barriers wait for all parent nodes to complete before firing:

```swift
builder.addJoinEdge(
    parents: [HiveNodeID("W1"), HiveNodeID("W2")],
    target: HiveNodeID("Gate")
)
```

### Routers

Routers provide dynamic routing based on post-commit state:

```swift
builder.addRouter(from: HiveNodeID("A")) { storeView in
    .to([HiveNodeID("B")])
}
```

## Compilation

Call `compile()` to produce a validated, immutable ``CompiledHiveGraph``:

```swift
let graph = try builder.compile()
```

### Validation rules

`compile()` validates:

- No duplicate node IDs
- All edge targets reference existing nodes
- Start nodes exist in the graph
- No cycles in static edges (throws `staticGraphCycleDetected`)
- Router-only cycles are allowed (they're dynamic)

## CompiledHiveGraph

The compiled graph is immutable and `Sendable`:

```swift
public struct CompiledHiveGraph<Schema: HiveSchema>: Sendable {
    public let start: [HiveNodeID]
    public let staticLayersByNodeID: [HiveNodeID: Int]
    public let maxStaticDepth: Int
}
```

## Graph description

`graphDescription()` produces a deterministic JSON representation with a SHA-256 version hash. Identical graphs always produce identical JSON — enabling golden tests:

```swift
let description = graph.graphDescription()
// description.versionHash is a stable SHA-256
```

## Mermaid export

``HiveGraphMermaidExporter`` converts a graph description to a Mermaid flowchart for visualization:

```swift
let mermaid = HiveGraphMermaidExporter.export(description)
```

Produces output like:

```
flowchart TD
    Start --> WorkerA
    Start --> WorkerB
    WorkerA --> Gate
    WorkerB --> Gate
    Gate --> Finalize
```

## Static layer analysis

The compiler computes static layer depths via topological ordering. This enables optimizations and visualization of the graph's parallel structure. Access via `staticLayersByNodeID` and `maxStaticDepth` on the compiled graph.
