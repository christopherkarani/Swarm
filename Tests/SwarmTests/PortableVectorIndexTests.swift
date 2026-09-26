#if SWARM_INTEGRATIONS && canImport(ContextCoreTypes)
import ContextCoreTypes
import Foundation
import Testing

@Suite("Portable brute-force vector index")
struct PortableVectorIndexTests {
    @Test("backend identity is the portable brute-force ID")
    func backendIdentity() {
        let index = BruteForceVectorIndex()
        #expect(index.backendID == .bruteForce)
        #expect(index.backendID.rawValue == "brute-force")
        #expect(index.metric == .cosine)
    }

    @Test("search ranks by descending cosine similarity")
    func searchRanksBySimilarity() async throws {
        let index = BruteForceVectorIndex()
        try await index.insert(id: "a", vector: [1, 0])
        try await index.insert(id: "b", vector: [0, 1])
        #expect(await index.count == 2)

        let hits = try await index.search(query: [1, 0], k: 2)
        #expect(hits.count == 2)
        #expect(hits[0].id == "a")
        #expect(abs(hits[0].score - 1.0) < 1e-6)
        #expect(hits[1].id == "b")
        #expect(abs(hits[1].score) < 1e-6)
    }

    @Test("search caps at k and breaks ties by ID")
    func searchCapsAndTieBreaks() async throws {
        let index = BruteForceVectorIndex()
        try await index.insert(id: "b", vector: [1, 0])
        try await index.insert(id: "a", vector: [1, 0])
        try await index.insert(id: "c", vector: [1, 0])

        let hits = try await index.search(query: [1, 0], k: 2)
        #expect(hits.map(\.id) == ["a", "b"])
    }

    @Test("empty index and non-positive k return no hits")
    func emptySearchReturnsNone() async throws {
        let index = BruteForceVectorIndex()
        #expect(try await index.search(query: [1, 0], k: 5) == [])
        try await index.insert(id: "a", vector: [1, 0])
        #expect(try await index.search(query: [1, 0], k: 0) == [])
    }

    @Test("duplicate insert and missing delete throw typed errors")
    func duplicateAndMissingErrors() async throws {
        let index = BruteForceVectorIndex()
        try await index.insert(id: "a", vector: [1, 0])
        await #expect(throws: VectorIndexError.duplicateRecord(id: "a")) {
            try await index.insert(id: "a", vector: [1, 0])
        }
        await #expect(throws: VectorIndexError.recordNotFound(id: "missing")) {
            try await index.delete(id: "missing")
        }
    }

    @Test("dimension mismatches throw typed errors")
    func dimensionMismatchErrors() async throws {
        let index = BruteForceVectorIndex()
        try await index.insert(id: "a", vector: [1, 0])
        await #expect(throws: VectorIndexError.dimensionMismatch(expected: 2, got: 3)) {
            try await index.insert(id: "b", vector: [1, 0, 0])
        }
        await #expect(throws: VectorIndexError.dimensionMismatch(expected: 2, got: 3)) {
            try await index.search(query: [1, 0, 0], k: 1)
        }
    }

    @Test("upsert replaces the existing record")
    func upsertReplaces() async throws {
        let index = BruteForceVectorIndex()
        try await index.insert(id: "a", vector: [1, 0])
        try await index.upsert(id: "a", vector: [0, 1])
        #expect(await index.count == 1)
        let hits = try await index.search(query: [0, 1], k: 1)
        #expect(hits.count == 1)
        #expect(abs(hits[0].score - 1.0) < 1e-6)
    }

    @Test("snapshot restores onto a fresh index")
    func snapshotRestoreRoundTrip() async throws {
        let index = BruteForceVectorIndex()
        try await index.insert(id: "b", vector: [0, 1])
        try await index.insert(id: "a", vector: [1, 0])

        let snapshot = await index.snapshot()
        #expect(snapshot.backendID == .bruteForce)
        #expect(snapshot.metric == .cosine)
        #expect(snapshot.dimension == 2)
        #expect(snapshot.records.map(\.id) == ["a", "b"])

        let revived = BruteForceVectorIndex()
        try await revived.restore(snapshot)
        #expect(await revived.count == 2)
        let hits = try await revived.search(query: [1, 0], k: 2)
        #expect(hits.map(\.id) == ["a", "b"])

        let resnapshot = await revived.snapshot()
        #expect(resnapshot == snapshot)
    }

    @Test("snapshot is Codable and rejects mixed widths")
    func snapshotCodableAndValidated() async throws {
        let index = BruteForceVectorIndex()
        try await index.insert(id: "a", vector: [1, 0])
        let snapshot = await index.snapshot()
        let decoded = try JSONDecoder().decode(VectorIndexSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)

        let bad = VectorIndexSnapshot(
            backendID: .bruteForce,
            metric: .cosine,
            dimension: nil,
            records: [
                .init(id: "a", vector: [1, 0]),
                .init(id: "b", vector: [1, 0, 0]),
            ]
        )
        await #expect(throws: VectorIndexError.self) {
            try await index.restore(bad)
        }
    }

    @Test("restore rejects duplicate record IDs instead of trapping")
    func restoreRejectsDuplicateIDs() async throws {
        let index = BruteForceVectorIndex()
        try await index.insert(id: "a", vector: [1, 0])
        let bad = VectorIndexSnapshot(
            backendID: .bruteForce,
            metric: .cosine,
            dimension: 2,
            records: [
                .init(id: "x", vector: [1, 0]),
                .init(id: "x", vector: [0, 1]),
            ]
        )
        await #expect(throws: VectorIndexError.self) {
            try await index.restore(bad)
        }
        #expect(await index.count == 1)
    }

    @Test("record IDs wrap chunk UUIDs")
    func recordIDWrapsUUID() {
        let uuid = UUID()
        #expect(VectorRecordID(uuid: uuid).rawValue == uuid.uuidString)
        #expect(VectorRecordID("x").description == "x")
    }
}
#endif
