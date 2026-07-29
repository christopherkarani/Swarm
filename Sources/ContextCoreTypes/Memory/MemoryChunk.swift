import Foundation

/// Logical memory tier used by ContextCore.
public enum MemoryType: String, Codable, Sendable, Hashable {
    /// Turn-level conversational memory.
    case episodic
    /// Consolidated long-lived factual memory.
    case semantic
    /// Tool-usage and procedural memory.
    case procedural
}

/// A retrievable memory item stored in ContextCore.
public struct MemoryChunk: Identifiable, Codable, Sendable, Hashable {
    /// Stable chunk identifier.
    public let id: UUID
    /// Raw chunk text.
    public var content: String
    /// Embedding vector used for semantic operations.
    public var embedding: [Float]
    /// Memory tier classification.
    public let type: MemoryType
    /// Original creation timestamp.
    public let createdAt: Date
    /// Last access timestamp.
    public var lastAccessedAt: Date
    /// Access count used for retention heuristics.
    public var accessCount: Int
    /// Retention score in `[0, 1]`.
    public var retentionScore: Float
    /// Session identifier where this chunk originated.
    public let sourceSessionID: UUID
    /// Arbitrary metadata associated with the chunk.
    public var metadata: [String: String]

    /// Creates a memory chunk.
    ///
    /// - Parameters:
    ///   - id: Stable chunk identifier.
    ///   - content: Text content.
    ///   - embedding: Embedding vector.
    ///   - type: Memory tier.
    ///   - createdAt: Creation timestamp.
    ///   - lastAccessedAt: Last access timestamp.
    ///   - accessCount: Access counter.
    ///   - retentionScore: Retention score in `[0, 1]`.
    ///   - sourceSessionID: Source session identifier.
    ///   - metadata: Optional metadata.
    public init(
        id: UUID = UUID(),
        content: String,
        embedding: [Float],
        type: MemoryType,
        createdAt: Date = .now,
        lastAccessedAt: Date = .now,
        accessCount: Int = 1,
        retentionScore: Float,
        sourceSessionID: UUID,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.content = content
        self.embedding = embedding
        self.type = type
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.accessCount = accessCount
        self.retentionScore = retentionScore
        self.sourceSessionID = sourceSessionID
        self.metadata = metadata
    }
}
