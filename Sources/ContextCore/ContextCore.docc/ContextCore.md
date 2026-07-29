# ``ContextCore``

GPU-accelerated context management for on-device AI agents.

## Overview

ContextCore sits between an agent reasoning loop and the model context window.
It scores, ranks, compresses, and curates candidate memory in real time before each model call.

## Topics

### Essentials

- <doc:GettingStarted>
- ``AgentContext``
- ``ContextWindow``

### Memory Types

- <doc:ArchitectureOverview>
- ``MemoryChunk``
- ``MemoryType``

### Configuration

- <doc:TuningGuide>
- ``ContextConfiguration``

### Integration

- <doc:IntegratingWithAppleFoundationModels>
- <doc:IntegratingWithWax>

### Data Model

- ``Turn``
- ``TurnRole``
- ``ToolCall``

### Protocols

- ``EmbeddingProvider``
- ``TokenCounter``
- ``CompressionDelegate``

### Errors

- ``ContextCoreError``
