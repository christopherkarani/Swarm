# Tuning Guide

Tune ``ContextConfiguration`` to balance latency, retrieval quality, and memory behavior for your workload.

## Parameter Reference

| Parameter | Default | Effect | Tune when... |
|---|---:|---|---|
| `maxTokens` | `4096` | Hard token budget | Your model has larger/smaller context |
| `tokenBudgetSafetyMargin` | `0.10` | Headroom fraction | You have exact tokenizer (set to 0) |
| `episodicMemoryK` | `8` | Chunks from episodic per call | Sessions are short (decrease) or long (increase) |
| `semanticMemoryK` | `4` | Chunks from semantic per call | Few facts (decrease) or knowledge-heavy (increase) |
| `recentTurnsGuaranteed` | `3` | Recent turns always included | Fast back-and-forth (increase) or long turns (decrease) |
| `episodicHalfLifeDays` | `7` | Episodic recency decay | Short-lived tasks (decrease) or long projects (increase) |
| `semanticHalfLifeDays` | `90` | Semantic recency decay | Facts change often (decrease) or are stable (increase) |
| `consolidationThreshold` | `200` | Auto-consolidation trigger | Memory-constrained (decrease) or large sessions (increase) |
| `similarityMergeThreshold` | `0.92` | Duplicate detection bar | False merges (increase) or missed duplicates (decrease) |
| `relevanceWeight` | `0.7` | Similarity vs recency blend | Task-focused (increase) or time-sensitive (decrease) |
| `centralityWeight` | `0.4` | Centrality vs relevance for eviction | Prefer topically connected (increase) or task-relevant (decrease) |
| `efSearch` | `64` | ANN search breadth | Recall is low (increase) or latency is high (decrease) |
| `embeddingProvider` | `CoreMLEmbeddingProvider + cache` | Query/chunk embedding source | Swap for custom model/provider |
| `tokenCounter` | `ApproximateTokenCounter` | Token estimation for packing | Inject exact model tokenizer |
| `compressionDelegate` | `nil` | Optional abstractive compression | You want higher-quality summaries |

## Practical Profiles

- Low latency: decrease `episodicMemoryK`/`semanticMemoryK`, increase `tokenBudgetSafetyMargin`, keep `efSearch` moderate.
- High recall: increase `episodicMemoryK`, `semanticMemoryK`, and `efSearch`; expect higher p95/p99 latency.
- Long-running projects: increase half-life values and consolidation threshold to preserve durable context.

## Starting Point

```swift
var config = ContextConfiguration.default
config.maxTokens = 4096
config.episodicMemoryK = 8
config.semanticMemoryK = 4
config.relevanceWeight = 0.7
let context = try AgentContext(configuration: config)
```
