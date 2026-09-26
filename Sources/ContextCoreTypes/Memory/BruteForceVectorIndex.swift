import Foundation

/// Pure-Swift brute-force vector index.
///
/// Portable (no Metal, Accelerate, or third-party deps) and the default
/// ``VectorIndex`` where MetalANNS is unavailable. Exact search: linear scan
/// with deterministic tie-breaks (lower ID first).
public actor BruteForceVectorIndex: VectorIndex {
    /// Always ``VectorIndexBackendID/bruteForce``.
    public nonisolated let backendID = VectorIndexBackendID.bruteForce
    /// Metric selected at creation.
    public nonisolated let metric: VectorDistanceMetric

    private var vectors: [VectorRecordID: [Float]] = [:]
    private var dimension: Int?

    /// Creates an empty index.
    ///
    /// - Parameter metric: Ranking metric. Defaults to cosine.
    public init(metric: VectorDistanceMetric = .cosine) {
        self.metric = metric
    }

    /// Number of live records.
    public var count: Int {
        vectors.count
    }

    /// Inserts a vector under `id`.
    public func insert(id: VectorRecordID, vector: [Float]) throws {
        if vectors[id] != nil {
            throw VectorIndexError.duplicateRecord(id: id)
        }
        try validateDimension(vector.count)
        vectors[id] = vector
    }

    /// Deletes the record for `id`.
    public func delete(id: VectorRecordID) throws {
        guard vectors[id] != nil else {
            throw VectorIndexError.recordNotFound(id: id)
        }
        vectors.removeValue(forKey: id)
    }

    /// Returns up to `k` hits ranked by descending similarity.
    public func search(query: [Float], k: Int) throws -> [VectorSearchHit] {
        guard k > 0, !vectors.isEmpty else {
            return []
        }
        try validateDimension(query.count)
        let scored = vectors.map { (id: $0.key, score: Self.similarity(query, $0.value, metric: metric)) }
        return scored
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.id.rawValue < rhs.id.rawValue
                }
                return lhs.score > rhs.score
            }
            .prefix(k)
            .map { VectorSearchHit(id: $0.id, score: $0.score) }
    }

    /// Captures a deterministic snapshot of live records.
    public func snapshot() -> VectorIndexSnapshot {
        VectorIndexSnapshot(
            backendID: backendID,
            metric: metric,
            dimension: dimension,
            records: vectors.map { VectorIndexSnapshot.Record(id: $0.key, vector: $0.value) }
        )
    }

    /// Replaces index state with `snapshot`.
    public func restore(_ snapshot: VectorIndexSnapshot) throws {
        var widths = Set<Int>()
        var seenIDs = Set<VectorRecordID>()
        for record in snapshot.records {
            widths.insert(record.vector.count)
            guard seenIDs.insert(record.id).inserted else {
                throw VectorIndexError.snapshotIncompatible(
                    reason: "snapshot contains duplicate record id \(record.id.rawValue)"
                )
            }
        }
        if widths.count > 1 {
            throw VectorIndexError.snapshotIncompatible(reason: "snapshot records have mixed widths")
        }
        if let expected = snapshot.dimension, let width = widths.first, expected != width {
            throw VectorIndexError.snapshotIncompatible(
                reason: "snapshot dimension \(expected) does not match record width \(width)"
            )
        }
        vectors = Dictionary(uniqueKeysWithValues: snapshot.records.map { ($0.id, $0.vector) })
        dimension = snapshot.dimension ?? widths.first
    }

    private func validateDimension(_ width: Int) throws {
        if let expected = dimension, expected != width {
            throw VectorIndexError.dimensionMismatch(expected: expected, got: width)
        }
        if dimension == nil {
            dimension = width
        }
    }

    private static func similarity(_ lhs: [Float], _ rhs: [Float], metric: VectorDistanceMetric) -> Float {
        switch metric {
        case .cosine:
            cosineSimilarity(lhs, rhs)
        case .euclidean:
            1.0 / (1.0 + euclideanDistance(lhs, rhs))
        case .dot:
            dot(lhs, rhs)
        }
    }

    private static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else {
            return 0
        }
        let dot = dot(lhs, rhs)
        let denominator = l2Norm(lhs) * l2Norm(rhs)
        guard denominator > 0 else {
            return 0
        }
        return dot / denominator
    }

    private static func euclideanDistance(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count else {
            return .greatestFiniteMagnitude
        }
        var sum: Float = 0
        for index in lhs.indices {
            let delta = lhs[index] - rhs[index]
            sum += delta * delta
        }
        return sum.squareRoot()
    }

    private static func dot(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count else {
            return 0
        }
        var sum: Float = 0
        for index in lhs.indices {
            sum += lhs[index] * rhs[index]
        }
        return sum
    }

    private static func l2Norm(_ vector: [Float]) -> Float {
        var sum: Float = 0
        for value in vector {
            sum += value * value
        }
        return sum.squareRoot()
    }
}
