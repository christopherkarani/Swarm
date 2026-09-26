import ContextCoreEngine

/// Public alias for the engine embedding cache.
public typealias EmbeddingCache = ContextCoreEngine.EmbeddingCache
#if canImport(Metal)
/// Public alias for GPU relevance scoring engine.
public typealias ScoringEngine = ContextCoreEngine.ScoringEngine
/// Public alias for GPU attention scoring engine.
public typealias AttentionEngine = ContextCoreEngine.AttentionEngine
/// Public alias for compression engine.
public typealias CompressionEngine = ContextCoreEngine.CompressionEngine
/// Public alias for consolidation engine.
public typealias ConsolidationEngine = ContextCoreEngine.ConsolidationEngine
#endif
/// Public alias for portable CPU relevance scoring engine.
public typealias CPUScoringEngine = ContextCoreEngine.CPUScoringEngine
/// Public alias for portable CPU attention scoring engine.
public typealias CPUAttentionEngine = ContextCoreEngine.CPUAttentionEngine
/// Public alias for portable CPU compression engine.
public typealias CPUCompressionEngine = ContextCoreEngine.CPUCompressionEngine
/// Public alias for portable CPU consolidation engine.
public typealias CPUConsolidationEngine = ContextCoreEngine.CPUConsolidationEngine
/// Public alias for the portable relevance-scoring contract.
public typealias RelevanceScoringEngine = ContextCoreEngine.RelevanceScoringEngine
/// Public alias for the portable attention-scoring contract.
public typealias AttentionScoringEngine = ContextCoreEngine.AttentionScoringEngine
/// Public alias for the portable compression contract.
public typealias CompressionEngineProtocol = ContextCoreEngine.CompressionEngineProtocol
/// Public alias for the portable consolidation contract.
public typealias ConsolidationEngineProtocol = ContextCoreEngine.ConsolidationEngineProtocol
/// Public alias for pure portable compute kernels.
public typealias PortableCompute = ContextCoreEngine.PortableCompute
/// Public alias for portable sentence splitting.
public typealias PortableSentences = ContextCoreEngine.PortableSentences
/// Public alias for extractive compression delegate.
public typealias ExtractiveFallbackDelegate = ContextCoreEngine.ExtractiveFallbackDelegate
/// Public alias for consolidation summary result.
public typealias ConsolidationResult = ContextCoreEngine.ConsolidationResult
/// Public alias for background consolidation scheduler.
public typealias ConsolidationScheduler = ContextCoreEngine.ConsolidationScheduler
