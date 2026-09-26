#if SWARM_INTEGRATIONS && canImport(ContextCore)
import ContextCore
import Foundation
import Testing

@Suite("ContextCore portable CPU compute")
struct ContextCorePortableComputeTests {
    // MARK: - Pure kernels

    @Test("relevance scores blend cosine similarity and recency")
    func relevanceScoresBlendCosineAndRecency() throws {
        let scores = try ContextCore.PortableCompute.relevanceScores(
            query: [1, 0],
            flattenedEmbeddings: [1, 0, 0, 1],
            count: 2,
            dimension: 2,
            recencyWeights: [1, 1],
            relevanceWeight: 0.7,
            recencyWeight: 0.3
        )
        #expect(scores.count == 2)
        #expect(abs(scores[0] - 1.0) < 1e-6)
        #expect(abs(scores[1] - 0.3) < 1e-6)
    }

    @Test("relevance scores reject inconsistent dimensions")
    func relevanceScoresRejectBadDimensions() {
        #expect(throws: ContextCore.ContextCoreError.self) {
            try ContextCore.PortableCompute.relevanceScores(
                query: [1, 0, 0],
                flattenedEmbeddings: [1, 0],
                count: 1,
                dimension: 2,
                recencyWeights: [1],
                relevanceWeight: 0.7,
                recencyWeight: 0.3
            )
        }
    }

    @Test("recency weights decay with half-life and clamp to unit range")
    func recencyWeightsDecayAndClamp() throws {
        let now = Date()
        let weights = try ContextCore.PortableCompute.recencyWeights(
            timestamps: [now, now.addingTimeInterval(-10), now.addingTimeInterval(60)],
            halfLife: 10,
            currentTime: now
        )
        #expect(weights.count == 3)
        #expect(abs(weights[0] - 1.0) < 1e-6)
        #expect(abs(weights[1] - 0.5) < 1e-4)
        #expect(weights[2] == 1.0)
    }

    @Test("recency weights reject non-positive half-life")
    func recencyWeightsRejectBadHalfLife() {
        #expect(throws: ContextCore.ContextCoreError.self) {
            try ContextCore.PortableCompute.recencyWeights(
                timestamps: [.now],
                halfLife: 0,
                currentTime: .now
            )
        }
    }

    @Test("top-k indices order by score with lower-index tie-breaks")
    func topKIndicesOrderAndTieBreak() {
        #expect(ContextCore.PortableCompute.topKIndices(scores: [0.1, 0.9, 0.5], k: 2) == [1, 2])
        #expect(ContextCore.PortableCompute.topKIndices(scores: [0.5, 0.5, 0.5], k: 2) == [0, 1])
        #expect(ContextCore.PortableCompute.topKIndices(scores: [0.2], k: 5) == [0])
        #expect(ContextCore.PortableCompute.topKIndices(scores: [], k: 3) == [])
        #expect(ContextCore.PortableCompute.topKIndices(scores: [0.2], k: 0) == [])
    }

    @Test("centrality is zero for singletons and one for identical pairs")
    func centralitySingletonAndIdenticalPair() throws {
        #expect(try ContextCore.PortableCompute.centrality(embeddings: [[1, 0]]) == [0])
        let pair = try ContextCore.PortableCompute.centrality(embeddings: [[1, 0], [1, 0]])
        #expect(pair.count == 2)
        #expect(abs(pair[0] - 1.0) < 1e-6)
        #expect(abs(pair[1] - 1.0) < 1e-6)
    }

    @Test("pairwise matrix is symmetric with unit diagonal")
    func pairwiseMatrixSymmetricUnitDiagonal() throws {
        let matrix = try ContextCore.PortableCompute.pairwiseSimilarityMatrix(embeddings: [[1, 0], [0, 1]])
        #expect(matrix.count == 2)
        #expect(matrix[0][0] == 1.0)
        #expect(matrix[1][1] == 1.0)
        #expect(abs(matrix[0][1]) < 1e-6)
        #expect(abs(matrix[1][0]) < 1e-6)
    }

    @Test("antipodal fractions count sign flips")
    func antipodalFractionsCountSignFlips() throws {
        let fractions = try ContextCore.PortableCompute.antipodalFractions(
            embeddingsA: [[1, 1, 1, 1]],
            embeddingsB: [[1, -1, 1, -1]]
        )
        #expect(fractions.count == 1)
        #expect(abs(fractions[0] - 0.5) < 1e-6)
    }

    // MARK: - CPU scoring / attention ranking

    @Test("CPU scoring sorts by descending score and preserves order unsorted")
    func cpuScoringSortsDescending() async throws {
        let engine = ContextCore.CPUScoringEngine()
        let chunks = [
            makeChunk(content: "unrelated", embedding: [0, 1]),
            makeChunk(content: "match", embedding: [1, 0]),
        ]
        let sorted = try await engine.scoreChunks(
            query: [1, 0],
            chunks: chunks,
            recencyWeights: [0.5, 0.5],
            relevanceWeight: 0.7,
            recencyWeight: 0.3
        )
        #expect(sorted.map(\.chunk.content) == ["match", "unrelated"])
        #expect(sorted[0].score > sorted[1].score)

        let unsorted = try await engine.scoreChunksUnsorted(
            query: [1, 0],
            chunks: chunks,
            recencyWeights: [0.5, 0.5],
            relevanceWeight: 0.7,
            recencyWeight: 0.3
        )
        #expect(unsorted.map(\.chunk.content) == ["unrelated", "match"])
    }

    @Test("CPU scoring rejects dimension mismatches")
    func cpuScoringRejectsMismatch() async {
        let engine = ContextCore.CPUScoringEngine()
        await #expect(throws: ContextCore.ContextCoreError.self) {
            try await engine.scoreChunks(
                query: [1, 0],
                chunks: [makeChunk(content: "bad", embedding: [1, 0, 0])],
                recencyWeights: [1],
                relevanceWeight: 0.7,
                recencyWeight: 0.3
            )
        }
    }

    @Test("CPU attention ranks eviction ascending")
    func cpuAttentionEvictionAscending() async throws {
        let engine = ContextCore.CPUAttentionEngine()
        let chunks = [
            makeChunk(content: "match", embedding: [1, 0]),
            makeChunk(content: "unrelated", embedding: [0, 1]),
        ]
        let ranked = try await engine.scoreWindowForEviction(
            taskQuery: [1, 0],
            windowChunks: chunks,
            relevanceWeight: 0.6,
            centralityWeight: 0.4
        )
        #expect(ranked.count == 2)
        #expect(ranked[0].evictionScore <= ranked[1].evictionScore)
    }

    // MARK: - CPU compression

    @Test("CPU compression ranks the most similar sentence first")
    func cpuCompressionRanksSentences() async throws {
        let provider = FixedVectorEmbeddingProvider(vectors: [
            "Alpha beta gamma.": [1, 0],
            "Delta epsilon.": [0, 1],
            "Zeta eta theta iota.": [-1, 0],
        ])
        let engine = ContextCore.CPUCompressionEngine(
            embeddingProvider: provider,
            tokenCounter: WordTokenCounter()
        )
        let ranked = try await engine.rankSentences(
            in: "Alpha beta gamma. Delta epsilon. Zeta eta theta iota.",
            chunkEmbedding: [0, 1]
        )
        #expect(ranked.count == 3)
        #expect(ranked[0].sentence == "Delta epsilon.")
        #expect(ranked[0].importance > ranked[1].importance)
    }

    @Test("CPU compression leaves under-budget chunks untouched")
    func cpuCompressionLeavesUnderBudgetUntouched() async throws {
        let engine = ContextCore.CPUCompressionEngine(
            embeddingProvider: FixedVectorEmbeddingProvider(vectors: [:]),
            tokenCounter: WordTokenCounter()
        )
        let chunk = makeChunk(content: "Short content here.", embedding: [1, 0])
        let result = try await engine.compress(chunk: chunk, targetTokens: 100)
        #expect(result.content == chunk.content)
        #expect(result.metadata["compressionRatio"] == nil)
    }

    @Test("CPU compression reduces over-budget chunks within target")
    func cpuCompressionReducesOverBudget() async throws {
        let engine = ContextCore.CPUCompressionEngine(
            embeddingProvider: FixedVectorEmbeddingProvider(vectors: [:]),
            tokenCounter: WordTokenCounter()
        )
        let chunk = makeChunk(
            content: "First sentence has several words in it. Second sentence also has several words. Third sentence keeps going with more words.",
            embedding: [0, 1]
        )
        let target = 8
        let result = try await engine.compress(chunk: chunk, targetTokens: target)
        #expect(WordTokenCounter().count(result.content) <= target)
        #expect(result.metadata["compressionRatio"] != nil)
        #expect(result.metadata["originalTokenCount"] != nil)
    }

    // MARK: - CPU packing

    @Test("window packer fits system prompt, guaranteed turns, and memory in budget")
    func windowPackerFitsBudget() async throws {
        let counter = WordTokenCounter()
        let engine = ContextCore.CPUCompressionEngine(
            embeddingProvider: FixedVectorEmbeddingProvider(vectors: [:]),
            tokenCounter: counter
        )
        let packer = ContextCore.WindowPacker(
            compressionEngine: engine,
            tokenCounter: counter,
            minimumChunkSize: 1,
            recentTurnsGuaranteed: 1
        )
        let turn = ContextCore.Turn(role: .user, content: "hello world", tokenCount: 2)
        let memory = makeChunk(content: "relevant memory content here", embedding: [1, 0])
        let window = try await packer.pack(
            systemPrompt: "sys prompt",
            recentTurns: [turn],
            scoredMemory: [(chunk: memory, score: 0.9)],
            budget: 100
        )
        #expect(window.totalTokens <= 100)
        #expect(window.chunks.contains(where: { $0.isSystemPrompt }))
        #expect(window.chunks.contains(where: { $0.isGuaranteedRecent }))
        #expect(window.chunks.count == 3)
    }

    @Test("window packer never exceeds a tight budget")
    func windowPackerRespectsTightBudget() async throws {
        let counter = WordTokenCounter()
        let engine = ContextCore.CPUCompressionEngine(
            embeddingProvider: FixedVectorEmbeddingProvider(vectors: [:]),
            tokenCounter: counter
        )
        let packer = ContextCore.WindowPacker(
            compressionEngine: engine,
            tokenCounter: counter,
            minimumChunkSize: 1,
            recentTurnsGuaranteed: 1
        )
        let turn = ContextCore.Turn(role: .user, content: "hello world", tokenCount: 2)
        let memory = (0..<5).map { index in
            (chunk: makeChunk(content: "memory candidate number \(index) with filler words", embedding: [1, 0]), score: Float(5 - index))
        }
        let window = try await packer.pack(
            systemPrompt: "sys",
            recentTurns: [turn],
            scoredMemory: memory,
            budget: 12
        )
        #expect(window.totalTokens <= 12)
        #expect(window.chunks.contains(where: { $0.isSystemPrompt }))
    }

    @Test("progressive compressor drops lowest-priority candidates under deficit")
    func progressiveCompressorHandlesDeficit() async throws {
        let counter = WordTokenCounter()
        let engine = ContextCore.CPUCompressionEngine(
            embeddingProvider: FixedVectorEmbeddingProvider(vectors: [:]),
            tokenCounter: counter
        )
        let compressor = ContextCore.ProgressiveCompressor(
            compressionEngine: engine,
            tokenCounter: counter
        )
        let chunk = makeChunk(content: "lorem ipsum dolor sit amet consectetur", embedding: [1, 0])
        let unchanged = try await compressor.compress(
            candidates: [(chunk: chunk, evictionScore: 0.1)],
            tokenDeficit: 0
        )
        #expect(unchanged.count == 1)
        #expect(unchanged[0].compressionLevel == .none)

        let dropped = try await compressor.compress(
            candidates: [(chunk: chunk, evictionScore: 0.9)],
            tokenDeficit: 1_000
        )
        #expect(dropped.count == 1)
        #expect(dropped[0].compressionLevel == .dropped)
        #expect(dropped[0].tokensSaved == counter.count(chunk.content))
    }

    // MARK: - CPU consolidation

    @Test("CPU consolidation finds duplicates above threshold")
    func cpuConsolidationFindsDuplicates() async throws {
        let engine = ContextCore.CPUConsolidationEngine(
            embeddingProvider: FixedVectorEmbeddingProvider(vectors: [:])
        )
        let episodic = TestEpisodicStore()
        let vector = [Float](repeating: 0.5, count: 4)
        let first = makeChunk(content: "same fact stated once", embedding: vector)
        let second = makeChunk(content: "same fact stated once again here", embedding: vector)
        let odd = makeChunk(content: "different", embedding: [1, -1, 1, -1])
        await episodic.seed([first, second, odd])

        let pairs = try await engine.findDuplicates(in: episodic, threshold: 0.92)
        #expect(pairs.count == 1)
        #expect(Set([pairs[0].0, pairs[0].1]) == Set([first.id, second.id]))
    }

    @Test("CPU consolidation promotes facts and evicts low-retention chunks")
    func cpuConsolidationPromotesAndEvicts() async throws {
        let engine = ContextCore.CPUConsolidationEngine(
            embeddingProvider: FixedVectorEmbeddingProvider(vectors: [:])
        )
        let episodic = TestEpisodicStore()
        let semantic = TestSemanticStore()
        let vector = [Float](repeating: 0.5, count: 4)
        let first = makeChunk(content: "shared fact", embedding: vector)
        let second = makeChunk(content: "shared fact repeated", embedding: vector)
        var stale = makeChunk(content: "stale", embedding: [1, 0, 0, 0])
        stale.retentionScore = 0.05
        await episodic.seed([first, second, stale])

        let result = try await engine.consolidate(
            session: UUID(),
            episodicStore: episodic,
            semanticStore: semantic,
            threshold: 0.92
        )
        #expect(result.duplicatePairsFound == 1)
        #expect(result.factsPromoted == 1)
        #expect(result.chunksEvicted == 1)
        #expect(await episodic.isConsolidated(id: first.id))
        #expect(await semantic.count == 1)
    }

    // MARK: - Portable hashing and fallback embeddings

    @Test("embedding cache round-trips through portable hashing")
    func embeddingCacheRoundTrips() async {
        let cache = ContextCore.EmbeddingCache(capacity: 4)
        #expect(await cache.get("missing") == nil)
        await cache.set("key", value: [1, 2, 3])
        #expect(await cache.get("key") == [1, 2, 3])
        #expect(await cache.count == 1)
    }

    @Test("hash embedding provider is deterministic and normalized")
    func hashEmbeddingProviderDeterministic() async throws {
        let provider = ContextCore.HashEmbeddingProvider(dimensions: 8)
        let first = try await provider.embed("hello")
        let second = try await provider.embed("hello")
        #expect(first == second)
        #expect(first.count == 8)
        let norm = first.reduce(Float.zero) { $0 + $1 * $1 }.squareRoot()
        #expect(abs(norm - 1.0) < 1e-5)
    }

    #if canImport(Metal)
    @Test("CPU scoring matches Metal within tolerance")
    func cpuScoringMatchesMetal() async throws {
        guard let metal = try? ContextCore.ScoringEngine() else {
            return
        }
        let cpu = ContextCore.CPUScoringEngine()
        let chunks = [
            makeChunk(content: "a", embedding: [0.2, 0.8, -0.1]),
            makeChunk(content: "b", embedding: [-0.4, 0.3, 0.9]),
            makeChunk(content: "c", embedding: [0.7, -0.2, 0.5]),
        ]
        let query: [Float] = [0.5, 0.5, 0.5]
        let recency: [Float] = [0.9, 0.4, 0.7]
        let expected = try await metal.scoreChunksUnsorted(
            query: query, chunks: chunks, recencyWeights: recency,
            relevanceWeight: 0.7, recencyWeight: 0.3
        )
        let actual = try await cpu.scoreChunksUnsorted(
            query: query, chunks: chunks, recencyWeights: recency,
            relevanceWeight: 0.7, recencyWeight: 0.3
        )
        #expect(actual.count == expected.count)
        for (lhs, rhs) in zip(actual, expected) {
            #expect(abs(lhs.score - rhs.score) < 1e-4)
        }

        let now = Date()
        let timestamps = [now, now.addingTimeInterval(-3_600), now.addingTimeInterval(-86_400)]
        let expectedWeights = try await metal.computeRecencyWeights(
            timestamps: timestamps, halfLife: 86_400, currentTime: now
        )
        let actualWeights = try await cpu.computeRecencyWeights(
            timestamps: timestamps, halfLife: 86_400, currentTime: now
        )
        // Looser than scoring: the Metal path rounds timestamps to Float seconds.
        for (lhs, rhs) in zip(actualWeights, expectedWeights) {
            #expect(abs(lhs - rhs) < 0.02)
        }
    }
    #endif
}

private func makeChunk(content: String, embedding: [Float]) -> ContextCore.MemoryChunk {
    ContextCore.MemoryChunk(
        content: content,
        embedding: embedding,
        type: .episodic,
        retentionScore: 0.5,
        sourceSessionID: UUID()
    )
}

private struct FixedVectorEmbeddingProvider: ContextCore.EmbeddingProvider, Sendable {
    let dimensions = 2
    let modelIdentifier = "test-fixed"
    var vectors: [String: [Float]]

    func embed(_ text: String) async throws -> [Float] {
        vectors[text] ?? [0, 1]
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        texts.map { vectors[$0] ?? [0, 1] }
    }
}

private struct WordTokenCounter: ContextCore.TokenCounter, Sendable {
    func count(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

private actor TestEpisodicStore: ContextCore.ConsolidationEpisodicStore {
    private var chunks: [UUID: ContextCore.MemoryChunk] = [:]
    private var consolidated: Set<UUID> = []

    var count: Int { chunks.count }

    func seed(_ chunks: [ContextCore.MemoryChunk]) {
        for chunk in chunks {
            self.chunks[chunk.id] = chunk
        }
    }

    func allChunks() -> [ContextCore.MemoryChunk] {
        chunks.values.sorted { $0.createdAt < $1.createdAt }
    }

    func updateRetentionScore(id: UUID, delta: Float) throws {
        guard var chunk = chunks[id] else {
            throw ContextCore.ContextCoreError.chunkNotFound(id: id)
        }
        chunk.retentionScore = max(0, min(1, chunk.retentionScore + delta))
        chunks[id] = chunk
    }

    func evict(id: UUID) throws {
        guard chunks[id] != nil else {
            throw ContextCore.ContextCoreError.chunkNotFound(id: id)
        }
        chunks.removeValue(forKey: id)
    }

    func markConsolidated(id: UUID) throws {
        guard chunks[id] != nil else {
            throw ContextCore.ContextCoreError.chunkNotFound(id: id)
        }
        consolidated.insert(id)
    }

    func isConsolidated(id: UUID) -> Bool {
        consolidated.contains(id)
    }
}

private actor TestSemanticStore: ContextCore.ConsolidationSemanticStore {
    private var chunks: [ContextCore.MemoryChunk] = []

    var count: Int { chunks.count }

    func allChunks() -> [ContextCore.MemoryChunk] {
        chunks
    }

    func upsert(fact: String, embedding: [Float]) {
        chunks.append(
            ContextCore.MemoryChunk(
                content: fact,
                embedding: embedding,
                type: .semantic,
                retentionScore: 1.0,
                sourceSessionID: UUID()
            )
        )
    }
}
#endif
