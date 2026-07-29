import ContextCoreEngine

/// Public alias for the engine embedding cache.
public typealias EmbeddingCache = ContextCoreEngine.EmbeddingCache
/// Public alias for CPU reference implementations.
public typealias CPUReference = ContextCoreEngine.CPUReference
/// Public alias for GPU relevance scoring engine.
public typealias ScoringEngine = ContextCoreEngine.ScoringEngine
/// Public alias for GPU attention scoring engine.
public typealias AttentionEngine = ContextCoreEngine.AttentionEngine
/// Public alias for compression engine.
public typealias CompressionEngine = ContextCoreEngine.CompressionEngine
/// Public alias for extractive compression delegate.
public typealias ExtractiveFallbackDelegate = ContextCoreEngine.ExtractiveFallbackDelegate
/// Public alias for consolidation engine.
public typealias ConsolidationEngine = ContextCoreEngine.ConsolidationEngine
/// Public alias for consolidation summary result.
public typealias ConsolidationResult = ContextCoreEngine.ConsolidationResult
/// Public alias for background consolidation scheduler.
public typealias ConsolidationScheduler = ContextCoreEngine.ConsolidationScheduler

/// Namespace marker for the `ContextCore` module.
public enum ContextCoreModule {}
