import Foundation

/// Typed identifier for a single vector record held by a ``VectorIndex``.
///
/// Wraps the raw string key so record IDs cannot be confused with chunk IDs,
/// tool names, or other stringly-typed values at call sites.
public struct VectorRecordID: Hashable, Codable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    /// Raw key persisted by the backing index.
    public let rawValue: String

    /// Creates an ID from a raw key.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates an ID from a chunk or turn UUID.
    public init(uuid: UUID) {
        self.rawValue = uuid.uuidString
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String {
        rawValue
    }
}

/// Backend identity for ``VectorIndex`` implementations.
///
/// The portable brute-force index is the default where MetalANNS is
/// unavailable (Linux); the MetalANNS adapter keeps GPU-backed ANN on Apple.
public struct VectorIndexBackendID: Hashable, Codable, Sendable, Equatable, CustomStringConvertible {
    /// Raw backend identifier recorded in snapshots.
    public let rawValue: String

    /// Creates a backend ID from a raw identifier.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Pure-Swift brute-force index. Portable; the Linux default.
    public static let bruteForce = VectorIndexBackendID("brute-force")
    /// GPU-backed MetalANNS adapter. Apple-only.
    public static let metalANNS = VectorIndexBackendID("metal-anns")

    public var description: String {
        rawValue
    }
}

/// Distance metric used for vector ranking.
public enum VectorDistanceMetric: String, Sendable, Codable, Equatable {
    /// Cosine similarity. Higher ranks first.
    case cosine
    /// Euclidean distance mapped to similarity. Higher ranks first.
    case euclidean
    /// Raw dot product. Higher ranks first.
    case dot
}

/// A single ranked search hit.
///
/// `score` is always a similarity: higher values rank first, regardless of
/// the backing index or metric.
public struct VectorSearchHit: Sendable, Equatable {
    /// Record identifier.
    public let id: VectorRecordID
    /// Similarity score. Higher ranks first.
    public let score: Float

    /// Creates a search hit.
    public init(id: VectorRecordID, score: Float) {
        self.id = id
        self.score = score
    }
}

/// Codable snapshot of a ``VectorIndex`` for persistence and round-trips.
///
/// Records are sorted by ID so snapshots are deterministic for a given state.
public struct VectorIndexSnapshot: Sendable, Codable, Equatable {
    /// A single snapshotted record.
    public struct Record: Sendable, Codable, Equatable {
        /// Record identifier.
        public let id: VectorRecordID
        /// Stored vector.
        public let vector: [Float]

        /// Creates a snapshot record.
        public init(id: VectorRecordID, vector: [Float]) {
            self.id = id
            self.vector = vector
        }
    }

    /// Backend that produced this snapshot.
    public let backendID: VectorIndexBackendID
    /// Metric the records were indexed under.
    public let metric: VectorDistanceMetric
    /// Index dimensionality, or `nil` when the snapshotted index was empty.
    public let dimension: Int?
    /// Records sorted by ID.
    public let records: [Record]

    /// Creates a snapshot.
    public init(
        backendID: VectorIndexBackendID,
        metric: VectorDistanceMetric,
        dimension: Int?,
        records: [Record]
    ) {
        self.backendID = backendID
        self.metric = metric
        self.dimension = dimension
        self.records = records.sorted { $0.id.rawValue < $1.id.rawValue }
    }
}

/// Typed failures for ``VectorIndex`` operations.
public enum VectorIndexError: Error, Sendable, Equatable {
    /// A vector did not match the index dimensionality.
    case dimensionMismatch(expected: Int, got: Int)
    /// No record exists for the ID.
    case recordNotFound(id: VectorRecordID)
    /// A record already exists for the ID.
    case duplicateRecord(id: VectorRecordID)
    /// A snapshot could not be restored.
    case snapshotIncompatible(reason: String)
    /// The backing index reported a failure.
    case backendFailure(reason: String)
}

/// Portable contract over ANN vector indexes.
///
/// `SemanticStore` and `EpisodicStore` depend on this abstraction instead of
/// MetalANNS directly, so Linux builds use ``BruteForceVectorIndex`` while
/// Apple builds keep the GPU-backed adapter.
public protocol VectorIndex: Sendable {
    /// Backend identity recorded in snapshots and diagnostics.
    var backendID: VectorIndexBackendID { get }
    /// Metric used for ranking.
    var metric: VectorDistanceMetric { get }
    /// Number of live records.
    var count: Int { get async }

    /// Inserts a vector under `id`.
    ///
    /// - Throws: ``VectorIndexError/duplicateRecord(id:)`` when `id` exists,
    ///   ``VectorIndexError/dimensionMismatch(expected:got:)`` on bad width.
    func insert(id: VectorRecordID, vector: [Float]) async throws

    /// Deletes the record for `id`.
    ///
    /// - Throws: ``VectorIndexError/recordNotFound(id:)`` when `id` is missing.
    func delete(id: VectorRecordID) async throws

    /// Returns up to `k` hits ranked by descending similarity.
    ///
    /// - Throws: ``VectorIndexError/dimensionMismatch(expected:got:)`` on bad width.
    func search(query: [Float], k: Int) async throws -> [VectorSearchHit]

    /// Captures a deterministic snapshot of live records.
    func snapshot() async throws -> VectorIndexSnapshot

    /// Replaces index state with `snapshot`.
    ///
    /// - Throws: ``VectorIndexError/snapshotIncompatible(reason:)`` when the
    ///   snapshot is internally inconsistent.
    func restore(_ snapshot: VectorIndexSnapshot) async throws
}

public extension VectorIndex {
    /// Inserts `vector` under `id`, replacing any existing record.
    func upsert(id: VectorRecordID, vector: [Float]) async throws {
        do {
            try await delete(id: id)
        } catch let error as VectorIndexError {
            guard case .recordNotFound = error else {
                throw error
            }
        }
        try await insert(id: id, vector: vector)
    }
}
