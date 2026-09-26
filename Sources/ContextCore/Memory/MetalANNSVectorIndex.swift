#if canImport(MetalANNS)
import ContextCoreTypes
import Foundation
import MetalANNS

/// GPU-backed ``VectorIndex`` adapter over MetalANNS streaming search.
///
/// Keeps an in-memory vector mirror alongside the MetalANNS shard so
/// `snapshot()`/`restore()` work without filesystem round-trips. MetalANNS
/// reports cosine *distance* (`1 - similarity`, ascending); hits are converted
/// to similarity so scores rank higher-first like every other index.
public actor MetalANNSVectorIndex: VectorIndex {
    /// Always ``VectorIndexBackendID/metalANNS``.
    public nonisolated let backendID = VectorIndexBackendID.metalANNS
    /// Cosine ranking, matching the stores' historical configuration.
    public nonisolated let metric = VectorDistanceMetric.cosine

    private var index: Advanced.StreamingIndex
    private var mirror: [VectorRecordID: [Float]] = [:]
    private var dimension: Int?

    /// Creates an empty MetalANNS-backed index.
    ///
    /// - Parameter deltaCapacity: Streaming delta capacity before merge.
    public init(deltaCapacity: Int = 1_024) {
        let config = StreamingConfiguration(
            deltaCapacity: deltaCapacity,
            mergeStrategy: .blocking,
            indexConfiguration: IndexConfiguration(metric: .cosine)
        )
        self.index = Advanced.StreamingIndex(config: config)
    }

    /// Number of live records.
    public var count: Int {
        mirror.count
    }

    /// Inserts a vector under `id`.
    public func insert(id: VectorRecordID, vector: [Float]) async throws {
        if mirror[id] != nil {
            throw VectorIndexError.duplicateRecord(id: id)
        }
        try validateDimension(vector.count)
        do {
            try await index.insert(vector, id: id.rawValue)
        } catch {
            throw Self.map(error, id: id)
        }
        mirror[id] = vector
    }

    /// Deletes the record for `id`.
    public func delete(id: VectorRecordID) async throws {
        guard mirror[id] != nil else {
            throw VectorIndexError.recordNotFound(id: id)
        }
        do {
            try await index.delete(id: id.rawValue)
        } catch {
            throw Self.map(error, id: id)
        }
        mirror.removeValue(forKey: id)
    }

    /// Returns up to `k` hits ranked by descending similarity.
    public func search(query: [Float], k: Int) async throws -> [VectorSearchHit] {
        guard k > 0, !mirror.isEmpty else {
            return []
        }
        try validateDimension(query.count)
        let results: [SearchResult]
        do {
            results = try await index.search(query: query, k: k)
        } catch {
            throw Self.map(error, id: nil)
        }
        return results.map { VectorSearchHit(id: VectorRecordID($0.id), score: 1.0 - $0.score) }
    }

    /// Captures a deterministic snapshot of live records.
    public func snapshot() -> VectorIndexSnapshot {
        VectorIndexSnapshot(
            backendID: backendID,
            metric: metric,
            dimension: dimension,
            records: mirror.map { VectorIndexSnapshot.Record(id: $0.key, vector: $0.value) }
        )
    }

    /// Replaces index state with `snapshot`, rebuilding the MetalANNS shard.
    public func restore(_ snapshot: VectorIndexSnapshot) async throws {
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
        let deltaCapacity = max(snapshot.records.count, 1)
        let rebuilt = Advanced.StreamingIndex(
            config: StreamingConfiguration(
                deltaCapacity: deltaCapacity,
                mergeStrategy: .blocking,
                indexConfiguration: IndexConfiguration(metric: .cosine)
            )
        )
        for record in snapshot.records {
            do {
                try await rebuilt.insert(record.vector, id: record.id.rawValue)
            } catch {
                throw Self.map(error, id: record.id)
            }
        }
        index = rebuilt
        mirror = Dictionary(uniqueKeysWithValues: snapshot.records.map { ($0.id, $0.vector) })
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

    private static func map(_ error: Error, id: VectorRecordID?) -> Error {
        if let indexError = error as? VectorIndexError {
            return indexError
        }
        if let annsError = error as? ANNSError {
            switch annsError {
            case let .dimensionMismatch(expected, got):
                return VectorIndexError.dimensionMismatch(expected: expected, got: got)
            case let .idAlreadyExists(rawID):
                return VectorIndexError.duplicateRecord(id: id ?? VectorRecordID(rawID))
            case let .idNotFound(rawID):
                return VectorIndexError.recordNotFound(id: id ?? VectorRecordID(rawID))
            default:
                return VectorIndexError.backendFailure(reason: String(describing: annsError))
            }
        }
        return VectorIndexError.backendFailure(reason: String(describing: error))
    }
}
#endif
