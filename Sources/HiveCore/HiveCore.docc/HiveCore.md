# ``HiveCore``

Core runtime for deterministic graph execution.

@Metadata {
    @DisplayName("HiveCore")
}

## Overview

HiveCore provides the schema system, graph compiler, store model, checkpoint protocols, and superstep runtime that power Hive's deterministic graph execution.

| Subsystem | Responsibility |
|-----------|---------------|
| Schema | Channel specs, keys, reducers, codecs, schema registry, type erasure |
| Store | Global store, task-local store, store view, initial cache, fingerprinting |
| Graph | Graph builder, compile, validation, versioning, Mermaid export |
| Runtime | Superstep execution, frontier computation, event streaming, interrupts, retry |
| Checkpointing | Checkpoint format, store protocol, policies |

## Topics

### Essentials

- <doc:DefiningASchema>
- <doc:UnderstandingTheStore>
- <doc:BuildingGraphs>
- <doc:RuntimeExecution>

### Schema

- ``HiveSchema``
- ``HiveChannelSpec``
- ``HiveChannelKey``
- ``HiveChannelID``
- ``HiveChannelScope``
- ``HiveChannelPersistence``
- ``HiveReducer``
- ``HiveCodec``
- ``HiveJSONCodec``
- ``HiveAnyCodec``
- ``AnyHiveChannelSpec``
- ``HiveUpdatePolicy``

### Store

- ``HiveGlobalStore``
- ``HiveTaskLocalStore``
- ``HiveStoreView``
- ``HiveSchemaRegistry``

### Graph

- ``HiveGraphBuilder``
- ``CompiledHiveGraph``
- ``HiveGraphDescription``
- ``HiveGraphMermaidExporter``
- ``HiveNodeID``

### Runtime

- <doc:RuntimeExecution>
- <doc:CheckpointingAndResume>
- ``HiveRuntime``
- ``HiveEnvironment``
- ``HiveRunHandle``
- ``HiveRunOutcome``
- ``HiveRunOptions``
- ``HiveRunOutput``
- ``HiveRunID``
- ``HiveThreadID``
- ``HiveEvent``
- ``HiveRetryPolicy``

### Checkpointing

- <doc:CheckpointingAndResume>
- ``HiveCheckpoint``
- ``HiveCheckpointID``
- ``HiveCheckpointStore``
- ``HiveCheckpointPolicy``
- ``HiveCheckpointQueryableStore``

### Interrupts

- ``HiveInterruptRequest``
- ``HiveInterrupt``
- ``HiveResume``
- ``HiveInterruption``

### Errors

- ``HiveRuntimeError``
- ``HiveCompilationError``
- ``HiveCheckpointQueryError``

### Advanced

- <doc:DeterminismGuarantees>
