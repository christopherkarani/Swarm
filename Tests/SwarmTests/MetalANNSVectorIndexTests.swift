#if SWARM_INTEGRATIONS && canImport(ContextCore) && canImport(MetalANNS)
import ContextCore
import Foundation
import Testing

@Suite("MetalANNS vector index adapter")
struct MetalANNSVectorIndexTests {
    @Test("backend identity is the MetalANNS ID")
    func backendIdentity() {
        let index = MetalANNSVectorIndex()
        #expect(index.backendID == .metalANNS)
        #expect(index.backendID.rawValue == "metal-anns")
        #expect(index.metric == .cosine)
    }

    @Test("search ranks identical vectors first with similarity scores")
    func searchRanksBySimilarity() async throws {
        let index = MetalANNSVectorIndex()
        try await index.insert(id: "a", vector: [1, 0, 0, 0])
        try await index.insert(id: "b", vector: [0, 1, 0, 0])

        let hits = try await index.search(query: [1, 0, 0, 0], k: 2)
        #expect(hits.count == 2)
        #expect(hits[0].id.rawValue == "a")
        #expect(abs(hits[0].score - 1.0) < 1e-4)
        #expect(hits[0].score >= hits[1].score)
    }

    @Test("snapshot restores onto a fresh adapter")
    func snapshotRestoreRoundTrip() async throws {
        let index = MetalANNSVectorIndex()
        try await index.insert(id: "a", vector: [1, 0, 0, 0])
        try await index.insert(id: "b", vector: [0, 1, 0, 0])

        let snapshot = await index.snapshot()
        #expect(snapshot.backendID == .metalANNS)
        #expect(snapshot.records.count == 2)

        let revived = MetalANNSVectorIndex()
        try await revived.restore(snapshot)
        #expect(await revived.count == 2)
        let hits = try await revived.search(query: [1, 0, 0, 0], k: 1)
        #expect(hits.count == 1)
        #expect(hits[0].id.rawValue == "a")
    }

    @Test("duplicate insert and missing delete throw typed errors")
    func duplicateAndMissingErrors() async throws {
        let index = MetalANNSVectorIndex()
        try await index.insert(id: "a", vector: [1, 0, 0, 0])
        await #expect(throws: VectorIndexError.self) {
            try await index.insert(id: "a", vector: [1, 0, 0, 0])
        }
        await #expect(throws: VectorIndexError.recordNotFound(id: "missing")) {
            try await index.delete(id: "missing")
        }
    }

    @Test("semantic store retrieves through an injected portable index")
    func semanticStoreWithPortableIndex() async throws {
        let store = SemanticStore(index: BruteForceVectorIndex())
        try await store.insert(content: "fact one", embedding: [1, 0])
        try await store.insert(content: "fact two", embedding: [0, 1])

        let hits = try await store.retrieve(query: [1, 0], k: 2)
        #expect(hits.count == 2)
        #expect(hits[0].content == "fact one")
    }

    @Test("episodic store inserts, retrieves, and evicts through a portable index")
    func episodicStoreWithPortableIndex() async throws {
        let store = EpisodicStore(index: BruteForceVectorIndex())
        let turn = Turn(role: .user, content: "hello", embedding: [1, 0])
        try await store.insert(turn: turn)

        let hits = try await store.retrieve(query: [1, 0], k: 1)
        #expect(hits.count == 1)
        #expect(hits[0].content == "hello")

        try await store.evict(id: turn.id)
        #expect(await store.count == 0)
        #expect(try await store.retrieve(query: [1, 0], k: 1) == [])
    }

    @Test("restore rejects duplicate record IDs")
    func restoreRejectsDuplicateIDs() async throws {
        let index = MetalANNSVectorIndex()
        try await index.insert(id: "a", vector: [1, 0, 0, 0])
        let bad = VectorIndexSnapshot(
            backendID: .metalANNS,
            metric: .cosine,
            dimension: 4,
            records: [
                .init(id: "x", vector: [1, 0, 0, 0]),
                .init(id: "x", vector: [0, 1, 0, 0]),
            ]
        )
        await #expect(throws: VectorIndexError.self) {
            try await index.restore(bad)
        }
        #expect(await index.count == 1)
    }

    @Test("default stores keep the MetalANNS backend")
    func defaultStoresUseMetalANNS() async throws {
        let semantic = SemanticStore()
        try await semantic.insert(content: "fact one", embedding: [1, 0, 0, 0])
        let semanticHits = try await semantic.retrieve(query: [1, 0, 0, 0], k: 1)
        #expect(semanticHits.count == 1)

        let episodic = EpisodicStore()
        try await episodic.insert(turn: Turn(role: .user, content: "hello", embedding: [1, 0, 0, 0]))
        let episodicHits = try await episodic.retrieve(query: [1, 0, 0, 0], k: 1)
        #expect(episodicHits.count == 1)
    }
}
#endif
