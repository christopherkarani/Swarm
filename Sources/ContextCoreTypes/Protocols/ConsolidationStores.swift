import Foundation

/// Episodic-store capabilities required by the consolidation pipeline.
public protocol ConsolidationEpisodicStore: Sendable {
    /// Current chunk count.
    var count: Int { get async }
    /// Returns all episodic chunks.
    func allChunks() async -> [MemoryChunk]
    /// Applies a retention-score delta to a chunk.
    func updateRetentionScore(id: UUID, delta: Float) async throws
    /// Removes a chunk by identifier.
    func evict(id: UUID) async throws
    /// Marks a chunk as consolidated.
    func markConsolidated(id: UUID) async throws
    /// Returns `true` when the chunk has already been consolidated.
    func isConsolidated(id: UUID) async -> Bool
}

/// Semantic-store capabilities required by the consolidation pipeline.
public protocol ConsolidationSemanticStore: Sendable {
    /// Current chunk count.
    var count: Int { get async }
    /// Returns all semantic chunks.
    func allChunks() async -> [MemoryChunk]
    /// Upserts a fact and embedding into semantic memory.
    func upsert(fact: String, embedding: [Float]) async throws
}
