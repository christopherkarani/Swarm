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
3. Compute relevance and recency scores via the scoring engine (Metal
   ``ScoringEngine`` on Apple, portable ``CPUScoringEngine`` elsewhere).
4. Apply attention-based reranking (``AttentionEngine`` on Apple,
   ``CPUAttentionEngine`` elsewhere).
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
│  Metal kernels (5 shaders, Apple)   │
├─────────────────────────────────────┤
│  MetalANNS / BruteForceVectorIndex  │  ← vector index (MetalANNS on Apple,
│  Fixed out-degree graph · NN-Descent│     portable brute-force elsewhere)
├─────────────────────────────────────┤
│  Apple Frameworks (accelerated)     │
│  Metal · CoreML · Accelerate · ANE  │
└─────────────────────────────────────┘
```

## Portability

``AgentContext`` prefers Metal-backed engines when Metal is available and
falls back to the portable CPU engines (``CPUScoringEngine``,
``CPUAttentionEngine``, ``CPUCompressionEngine``,
``CPUConsolidationEngine``) otherwise, so the same API builds and runs on
Linux. The vector stores use MetalANNS where it can be imported and the
portable ``BruteForceVectorIndex`` elsewhere; the default embedding provider
is CoreML MiniLM on Apple and deterministic ``HashEmbeddingProvider``
pseudo-vectors elsewhere. MiniLM download and ZIP deflate extraction need
CoreML and the Compression framework, so `ensureModelAvailable()` only
delivers real embeddings on Apple platforms.
