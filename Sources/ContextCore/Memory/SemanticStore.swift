import Foundation
import MetalANNS

/// Vector-backed semantic memory store for durable facts.
public actor SemanticStore: ConsolidationSemanticStore {
    private let index: Advanced.StreamingIndex
    private var chunksByID: [String: MemoryChunk] = [:]
    private let sourceSessionID: UUID
    private var embeddingDimension: Int?

    /// Creates a semantic store for a source session.
    ///
    /// - Parameter sourceSessionID: Session identifier attached to inserted chunks.
    public init(sourceSessionID: UUID = UUID()) {
        self.sourceSessionID = sourceSessionID
        let config = StreamingConfiguration(
            deltaCapacity: 1_024,
            mergeStrategy: .blocking,
            indexConfiguration: IndexConfiguration(metric: .cosine)
        )
        self.index = Advanced.StreamingIndex(config: config)
    }

    /// Number of semantic chunks currently stored.
    public var count: Int {
        chunksByID.count
    }

    /// Inserts a semantic chunk from raw content and embedding.
    ///
    /// - Parameters:
    ///   - content: Fact content.
    ///   - embedding: Fact embedding.
    ///   - metadata: Optional metadata.
    /// - Throws: `ContextCoreError.dimensionMismatch` for inconsistent dimensions.
    public func insert(
        content: String,
        embedding: [Float],
        metadata: [String: String] = [:]
    ) async throws {
        try validateDimension(embedding)

        let chunk = MemoryChunk(
            content: content,
            embedding: embedding,
            type: .semantic,
            createdAt: .now,
            lastAccessedAt: .now,
            accessCount: 1,
            retentionScore: 1.0,
            sourceSessionID: sourceSessionID,
            metadata: metadata
        )

        let chunkID = chunk.id.uuidString
        try await index.insert(embedding, id: chunkID)
        chunksByID[chunkID] = chunk
    }

    /// Inserts a pre-built semantic chunk.
    ///
    /// - Parameter chunk: Chunk to insert.
    /// - Throws: `ContextCoreError.dimensionMismatch` for inconsistent dimensions.
    public func insert(chunk: MemoryChunk) async throws {
        try validateDimension(chunk.embedding)
        let chunkID = chunk.id.uuidString
        try await index.insert(chunk.embedding, id: chunkID)
        chunksByID[chunkID] = chunk
    }

    /// Retrieves nearest semantic chunks for a query vector.
    ///
    /// - Parameters:
    ///   - query: Query embedding.
    ///   - k: Maximum number of chunks to return.
    /// - Returns: Retrieved chunks ordered by ANN distance.
    /// - Throws: `ContextCoreError.dimensionMismatch` for inconsistent dimensions.
    public func retrieve(query: [Float], k: Int) async throws -> [MemoryChunk] {
        guard !chunksByID.isEmpty else {
            return []
        }
        guard k > 0 else {
            return []
        }

        try validateDimension(query)
        let results = try await index.search(query: query, k: k)

        var retrieved: [MemoryChunk] = []
        for result in results {
            guard let chunk = chunksByID[result.id] else {
                continue
            }
            retrieved.append(chunk)
        }

        return retrieved
    }

    /// Upserts a semantic fact using cosine similarity deduplication.
    ///
    /// - Parameters:
    ///   - fact: Fact string to retain.
    ///   - embedding: Fact embedding.
    /// - Throws: `ContextCoreError.dimensionMismatch` for inconsistent dimensions.
    public func upsert(fact: String, embedding: [Float]) async throws {
        try validateDimension(embedding)

        if let existingID = bestMatchingChunkID(for: embedding, threshold: 0.9),
           var existing = chunksByID[existingID]
        {
            existing.lastAccessedAt = .now
            existing.accessCount += 1
            chunksByID[existingID] = existing
            return
        }

        try await insert(
            content: fact,
            embedding: embedding,
            metadata: ["kind": "fact"]
        )
    }

    /// Returns all semantic chunks sorted by creation time.
    public func allChunks() async -> [MemoryChunk] {
        chunksByID.values.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Applies a retention score delta to a semantic chunk.
    ///
    /// - Parameters:
    ///   - id: Chunk identifier.
    ///   - delta: Signed score delta.
    /// - Throws: `ContextCoreError.chunkNotFound` if no chunk exists.
    public func updateRetentionScore(id: UUID, delta: Float) async throws {
        let key = id.uuidString
        guard var chunk = chunksByID[key] else {
            throw ContextCoreError.chunkNotFound(id: id)
        }
        let updated = max(0, min(1, chunk.retentionScore + delta))
        chunk.retentionScore = updated
        chunksByID[key] = chunk
    }

    private func validateDimension(_ embedding: [Float]) throws {
        if let expected = embeddingDimension, expected != embedding.count {
            throw ContextCoreError.dimensionMismatch(expected: expected, got: embedding.count)
        }
        if embeddingDimension == nil {
            embeddingDimension = embedding.count
        }
    }

    private func bestMatchingChunkID(for embedding: [Float], threshold: Float) -> String? {
        var bestID: String?
        var bestSimilarity: Float = -1

        for (id, chunk) in chunksByID {
            let similarity = cosineSimilarity(embedding, chunk.embedding)
            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestID = id
            }
        }

        guard let bestID, bestSimilarity > threshold else {
            return nil
        }
        return bestID
    }

    private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count else {
            return -1
        }

        var dot: Float = 0
        var lhsNorm: Float = 0
        var rhsNorm: Float = 0

        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lhsNorm += lhs[index] * lhs[index]
            rhsNorm += rhs[index] * rhs[index]
        }

        let denominator = (lhsNorm.squareRoot() * rhsNorm.squareRoot())
        guard denominator > 0 else {
            return -1
        }
        return dot / denominator
    }
}
