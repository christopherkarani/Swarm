# Architecture Overview

ContextCore manages four complementary memory layers and builds a task-specific working context window for each model call.

## Four Memory Types

- Working memory: The final ``ContextWindow`` injected into the model prompt.
- Episodic memory: Turn-level conversation history stored in vector space for fast similarity retrieval.
- Semantic memory: Consolidated high-value facts promoted from episodic memory for longer retention.
- Procedural memory: Tool usage patterns and execution traces keyed by task type.

## Scoring and Packing Pipeline

1. Embed the current task query.
2. Retrieve episodic and semantic candidates.
3. Compute relevance and recency scores on GPU via ``ScoringEngine``.
4. Apply attention-based reranking via ``AttentionEngine``.
5. Pack candidates under budget with ``WindowPacker``.
6. Optionally compress low-priority chunks via ``ProgressiveCompressor``.
7. Order chunks for model attention using ``ChunkOrderer``.

## Consolidation Flow

Consolidation periodically scans episodic memory for near-duplicate chunks, promotes durable facts into semantic memory, and evicts low-retention episodic chunks. This keeps long sessions stable without unbounded growth.

## Full Stack

```text
┌─────────────────────────────────────┐
│         Your App / Bebop            │  ← domain logic, UI, business rules
├─────────────────────────────────────┤
│           ContextCore               │  ← this framework
│  AgentContext · WindowPacker        │
│  ConsolidationEngine · Scoring      │
│  Metal kernels (5 shaders)          │
├─────────────────────────────────────┤
│            MetalANNS                │  ← vector index dependency
│  Fixed out-degree graph · NN-Descent│
│  Metal kernels (5 shaders)          │
├─────────────────────────────────────┤
│         Apple Frameworks            │
│  Metal · CoreML · Accelerate · ANE  │
└─────────────────────────────────────┘
```
