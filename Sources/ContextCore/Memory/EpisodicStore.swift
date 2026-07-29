import Foundation
import MetalANNS

/// Vector-backed episodic memory store for turn-level history.
public actor EpisodicStore: ConsolidationEpisodicStore {
    private let index: Advanced.StreamingIndex
    private var chunksByID: [String: MemoryChunk] = [:]
    private let sourceSessionID: UUID
    private var embeddingDimension: Int?
    private let consolidatedMarkerKey = "consolidated.phase4"

    /// Creates an episodic store for a source session.
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

    /// Number of chunks currently stored.
    public var count: Int {
        chunksByID.count
    }

    /// Inserts a turn into episodic memory.
    ///
    /// - Parameter turn: Turn to index and store.
    /// - Throws: `ContextCoreError.embeddingFailed` when turn embedding is missing.
    public func insert(turn: Turn) async throws {
        guard let embedding = turn.embedding else {
            throw ContextCoreError.embeddingFailed("Turn embedding is nil")
        }

        try validateDimension(embedding)

        var metadata = turn.metadata
        metadata["turnRole"] = turn.role.rawValue
        metadata["turnID"] = turn.id.uuidString

        let chunk = MemoryChunk(
            id: turn.id,
            content: turn.content,
            embedding: embedding,
            type: .episodic,
            createdAt: turn.timestamp,
            lastAccessedAt: .now,
            accessCount: 1,
            retentionScore: 0.5,
            sourceSessionID: sourceSessionID,
            metadata: metadata
        )

        try await insert(chunk: chunk)
    }

    /// Inserts an already constructed memory chunk.
    ///
    /// - Parameter chunk: Chunk to index.
    /// - Throws: `ContextCoreError.dimensionMismatch` for inconsistent dimensions.
    public func insert(chunk: MemoryChunk) async throws {
        try validateDimension(chunk.embedding)

        let chunkID = chunk.id.uuidString
        try await index.insert(chunk.embedding, id: chunkID)
        chunksByID[chunkID] = chunk
    }

    /// Retrieves nearest episodic chunks for a query vector.
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

    /// Returns all chunks sorted by creation time.
    public func allChunks() async -> [MemoryChunk] {
        chunksByID.values.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Applies a retention score delta to a chunk.
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

    /// Evicts a chunk from episodic storage and ANN index.
    ///
    /// - Parameter id: Chunk identifier.
    /// - Throws: `ContextCoreError.chunkNotFound` if no chunk exists.
    public func evict(id: UUID) async throws {
        let key = id.uuidString
        guard chunksByID[key] != nil else {
            throw ContextCoreError.chunkNotFound(id: id)
        }
        try await index.delete(id: key)
        chunksByID.removeValue(forKey: key)
    }

    /// Marks a chunk as consolidated.
    ///
    /// - Parameter id: Chunk identifier.
    /// - Throws: `ContextCoreError.chunkNotFound` if no chunk exists.
    public func markConsolidated(id: UUID) async throws {
        let key = id.uuidString
        guard var chunk = chunksByID[key] else {
            throw ContextCoreError.chunkNotFound(id: id)
        }
        chunk.metadata[consolidatedMarkerKey] = "true"
        chunksByID[key] = chunk
    }

    /// Returns whether a chunk has been marked as consolidated.
    ///
    /// - Parameter id: Chunk identifier.
    /// - Returns: `true` when consolidated marker is present.
    public func isConsolidated(id: UUID) async -> Bool {
        let key = id.uuidString
        guard let chunk = chunksByID[key] else {
            return false
        }
        return chunk.metadata[consolidatedMarkerKey] == "true"
    }

    private func validateDimension(_ embedding: [Float]) throws {
        if let expected = embeddingDimension, expected != embedding.count {
            throw ContextCoreError.dimensionMismatch(expected: expected, got: embedding.count)
        }
        if embeddingDimension == nil {
            embeddingDimension = embedding.count
        }
    }
}
