import ContextCoreTypes
import Foundation

/// Portable CPU relevance and recency scoring engine.
///
/// Thin imperative shell over ``PortableCompute``; same API shape and validation
/// behavior as the Metal-backed `ScoringEngine`.
public actor CPUScoringEngine: RelevanceScoringEngine {
    /// Creates a CPU scoring engine.
    public init() {}

    /// Scores candidate chunks against a query vector, sorted by descending score.
    public func scoreChunks(
        query: [Float],
        chunks: [MemoryChunk],
        recencyWeights: [Float],
        relevanceWeight: Float = 0.7,
        recencyWeight: Float = 0.3
    ) async throws -> [(chunk: MemoryChunk, score: Float)] {
        let unsorted = try await scoreChunksUnsorted(
            query: query,
            chunks: chunks,
            recencyWeights: recencyWeights,
            relevanceWeight: relevanceWeight,
            recencyWeight: recencyWeight
        )
        return unsorted.sorted(by: { $0.score > $1.score })
    }

    /// Scores candidate chunks without sorting, preserving input order.
    public func scoreChunksUnsorted(
        query: [Float],
        chunks: [MemoryChunk],
        recencyWeights: [Float],
        relevanceWeight: Float = 0.7,
        recencyWeight: Float = 0.3
    ) async throws -> [(chunk: MemoryChunk, score: Float)] {
        guard !chunks.isEmpty else {
            return []
        }
        guard chunks.count == recencyWeights.count else {
            throw ContextCoreError.dimensionMismatch(expected: chunks.count, got: recencyWeights.count)
        }

        let dimension = query.count
        var flattened: [Float] = []
        flattened.reserveCapacity(chunks.count * dimension)
        for chunk in chunks {
            guard chunk.embedding.count == dimension else {
                throw ContextCoreError.dimensionMismatch(expected: dimension, got: chunk.embedding.count)
            }
            flattened.append(contentsOf: chunk.embedding)
        }

        let scores = try PortableCompute.relevanceScores(
            query: query,
            flattenedEmbeddings: flattened,
            count: chunks.count,
            dimension: dimension,
            recencyWeights: recencyWeights,
            relevanceWeight: relevanceWeight,
            recencyWeight: recencyWeight
        )
        return zip(chunks, scores).map { (chunk: $0.0, score: $0.1) }
    }

    /// Returns indices of the top-k scores, with lower indices winning ties.
    public func topKIndices(scores: [Float], k: Int) async throws -> [Int] {
        PortableCompute.topKIndices(scores: scores, k: k)
    }

    /// Computes exponential recency weights with half-life decay.
    public func computeRecencyWeights(
        timestamps: [Date],
        halfLife: TimeInterval,
        currentTime: Date = .now
    ) async throws -> [Float] {
        try PortableCompute.recencyWeights(
            timestamps: timestamps,
            halfLife: halfLife,
            currentTime: currentTime
        )
    }
}

/// Portable CPU attention centrality and eviction scoring engine.
public actor CPUAttentionEngine: AttentionScoringEngine {
    /// Creates a CPU attention engine.
    public init() {}

    /// Computes centrality for each embedding within a candidate set.
    public func computeCentrality(embeddings: [[Float]]) async throws -> [Float] {
        try PortableCompute.centrality(embeddings: embeddings)
    }

    /// Produces eviction scores sorted ascending (lowest — keep — first).
    public func scoreWindowForEviction(
        taskQuery: [Float],
        windowChunks: [MemoryChunk],
        relevanceWeight: Float = 0.6,
        centralityWeight: Float = 0.4
    ) async throws -> [(chunk: MemoryChunk, evictionScore: Float)] {
        guard !windowChunks.isEmpty else {
            return []
        }

        let embeddings = windowChunks.map(\.embedding)
        let dimension = taskQuery.count
        guard embeddings.allSatisfy({ $0.count == dimension }) else {
            throw ContextCoreError.dimensionMismatch(
                expected: dimension,
                got: embeddings.first(where: { $0.count != dimension })?.count ?? 0
            )
        }

        let centralityScores = try PortableCompute.centrality(embeddings: embeddings)
        let eviction = try PortableCompute.crossAttentionScores(
            query: taskQuery,
            embeddings: embeddings,
            centrality: centralityScores,
            relevanceWeight: relevanceWeight,
            centralityWeight: centralityWeight
        )
        return zip(windowChunks, eviction)
            .map { (chunk: $0.0, evictionScore: $0.1) }
            .sorted(by: { $0.evictionScore < $1.evictionScore })
    }
}

/// Portable CPU compression engine for ranking and reducing text chunks.
public actor CPUCompressionEngine: CompressionEngineProtocol {
    private let embeddingProvider: any EmbeddingProvider
    private let tokenCounter: any TokenCounter
    private var compressionDelegate: (any CompressionDelegate)?

    /// Creates a CPU compression engine.
    public init(
        embeddingProvider: any EmbeddingProvider,
        tokenCounter: any TokenCounter,
        compressionDelegate: (any CompressionDelegate)? = nil
    ) {
        self.embeddingProvider = embeddingProvider
        self.tokenCounter = tokenCounter
        self.compressionDelegate = compressionDelegate
    }

    /// Ranks sentences in a chunk by similarity to the chunk embedding, descending.
    public func rankSentences(
        in chunk: String,
        chunkEmbedding: [Float]
    ) async throws -> [(sentence: String, importance: Float)] {
        let sentences = PortableSentences.split(chunk)
        guard !sentences.isEmpty else {
            return []
        }

        let sentenceEmbeddings = try await embeddingProvider.embedBatch(sentences)
        guard sentenceEmbeddings.count == sentences.count else {
            throw ContextCoreError.embeddingFailed("embedBatch returned mismatched result count")
        }

        let importance = try PortableCompute.sentenceImportance(
            sentenceEmbeddings: sentenceEmbeddings,
            chunkEmbedding: chunkEmbedding
        )
        return zip(sentences, importance)
            .map { (sentence: $0.0, importance: $0.1) }
            .sorted(by: { $0.importance > $1.importance })
    }

    /// Compresses a memory chunk to a target token budget.
    public func compress(chunk: MemoryChunk, targetTokens: Int) async throws -> MemoryChunk {
        let currentTokens = tokenCounter.count(chunk.content)
        if currentTokens <= targetTokens {
            return chunk
        }

        let delegate = compressionDelegate ?? makeDefaultExtractiveDelegate()
        let compressedContent = try await delegate.compress(chunk.content, targetTokens: targetTokens)
        let compressedTokens = tokenCounter.count(compressedContent)
        let ratio = Float(currentTokens) / Float(max(compressedTokens, 1))

        var compressed = chunk
        compressed.content = compressedContent
        compressed.embedding = try await embeddingProvider.embed(compressedContent)
        compressed.metadata["compressionRatio"] = String(format: "%.2f", ratio)
        compressed.metadata["originalTokenCount"] = "\(currentTokens)"
        return compressed
    }

    /// Compresses a turn to a target token budget, preserving identity fields.
    public func compressTurn(turn: Turn, targetTokens: Int) async throws -> Turn {
        let currentTokens = tokenCounter.count(turn.content)
        if currentTokens <= targetTokens {
            return turn
        }

        let delegate = compressionDelegate ?? makeDefaultExtractiveDelegate()
        let compressedContent = try await delegate.compress(turn.content, targetTokens: targetTokens)
        let compressedTokens = tokenCounter.count(compressedContent)
        let ratio = Float(currentTokens) / Float(max(compressedTokens, 1))
        let compressedEmbedding = try await embeddingProvider.embed(compressedContent)

        var metadata = turn.metadata
        metadata["compressionRatio"] = String(format: "%.2f", ratio)
        metadata["originalTokenCount"] = "\(currentTokens)"

        return Turn(
            id: turn.id,
            role: turn.role,
            content: compressedContent,
            timestamp: turn.timestamp,
            tokenCount: compressedTokens,
            embedding: compressedEmbedding,
            metadata: metadata
        )
    }

    /// Replaces the active compression delegate.
    public func setCompressionDelegate(_ delegate: any CompressionDelegate) {
        compressionDelegate = delegate
    }

    /// Embeds text with this engine's embedding provider.
    public func embedForCompression(_ text: String) async throws -> [Float] {
        try await embeddingProvider.embed(text)
    }

    private func makeDefaultExtractiveDelegate() -> ExtractiveFallbackDelegate {
        ExtractiveFallbackDelegate(
            compressionEngine: self,
            tokenCounter: tokenCounter
        )
    }
}

/// Portable CPU consolidation engine for deduplication, promotion, and contradiction detection.
public actor CPUConsolidationEngine: ConsolidationEngineProtocol {
    private let embeddingProvider: any EmbeddingProvider

    /// Creates a CPU consolidation engine.
    ///
    /// - Parameter embeddingProvider: Retained for API parity with the Metal engine;
    ///   consolidation itself is embedding-arithmetic over stored vectors.
    public init(embeddingProvider: any EmbeddingProvider) {
        self.embeddingProvider = embeddingProvider
    }

    /// Finds duplicate episodic chunk pairs above a similarity threshold.
    public func findDuplicates(
        in store: any ConsolidationEpisodicStore,
        threshold: Float = 0.92
    ) async throws -> [(UUID, UUID)] {
        let allChunks = await store.allChunks()
        let chunks = await unconsolidatedChunks(from: allChunks, store: store)
        guard chunks.count > 1 else {
            return []
        }
        let pairs = try PortableCompute.duplicateIndexPairs(
            embeddings: chunks.map(\.embedding),
            threshold: threshold
        )
        return pairs.map { (chunks[$0.0].id, chunks[$0.1].id) }
    }

    /// Computes pairwise cosine similarity for embedding vectors.
    public func pairwiseSimilarity(embeddings: [[Float]]) async throws -> [[Float]] {
        try PortableCompute.pairwiseSimilarityMatrix(embeddings: embeddings)
    }

    /// Runs a full consolidation pass for the active session.
    public func consolidate(
        session _: UUID,
        episodicStore: any ConsolidationEpisodicStore,
        semanticStore: any ConsolidationSemanticStore,
        threshold: Float = 0.92
    ) async throws -> ConsolidationResult {
        let start = Date()
        let allChunks = await episodicStore.allChunks()
        let unconsolidated = await unconsolidatedChunks(from: allChunks, store: episodicStore)
        let pairs: [(Int, Int)]
        if unconsolidated.count > 1 {
            pairs = try PortableCompute.duplicateIndexPairs(
                embeddings: unconsolidated.map(\.embedding),
                threshold: threshold
            )
        } else {
            pairs = []
        }

        var chunkMap = Dictionary(uniqueKeysWithValues: allChunks.map { ($0.id, $0) })

        var promotedIDs = Set<UUID>()
        var processedChunkIDs = Set<UUID>()

        for (indexA, indexB) in pairs {
            let chunkA = unconsolidated[indexA]
            let chunkB = unconsolidated[indexB]
            guard !processedChunkIDs.contains(chunkA.id), !processedChunkIDs.contains(chunkB.id) else {
                continue
            }
            guard await !episodicStore.isConsolidated(id: chunkA.id),
                  await !episodicStore.isConsolidated(id: chunkB.id)
            else {
                continue
            }

            processedChunkIDs.insert(chunkA.id)
            processedChunkIDs.insert(chunkB.id)

            let factChunk = chunkA.content.count <= chunkB.content.count ? chunkA : chunkB
            if !promotedIDs.contains(factChunk.id) {
                try await semanticStore.upsert(fact: factChunk.content, embedding: factChunk.embedding)
                promotedIDs.insert(factChunk.id)
            }

            try await episodicStore.updateRetentionScore(id: chunkA.id, delta: -0.2)
            try await episodicStore.updateRetentionScore(id: chunkB.id, delta: -0.2)
            if var updatedA = chunkMap[chunkA.id] {
                updatedA.retentionScore = max(0, min(1, updatedA.retentionScore - 0.2))
                chunkMap[chunkA.id] = updatedA
            }
            if var updatedB = chunkMap[chunkB.id] {
                updatedB.retentionScore = max(0, min(1, updatedB.retentionScore - 0.2))
                chunkMap[chunkB.id] = updatedB
            }
            try await episodicStore.markConsolidated(id: chunkA.id)
            try await episodicStore.markConsolidated(id: chunkB.id)
        }

        var evicted = 0
        for chunk in chunkMap.values where chunk.retentionScore < 0.1 {
            try await episodicStore.evict(id: chunk.id)
            evicted += 1
        }

        let durationMs = Date().timeIntervalSince(start) * 1000
        return ConsolidationResult(
            duplicatePairsFound: pairs.count,
            factsPromoted: promotedIDs.count,
            chunksEvicted: evicted,
            durationMs: durationMs
        )
    }

    /// Finds contradiction candidates from semantic memory.
    public func contradictionCandidates(
        in store: any ConsolidationSemanticStore,
        similarityThreshold: Float = 0.75,
        antipodalThreshold: Float = 0.30
    ) async throws -> [(MemoryChunk, MemoryChunk)] {
        let facts = await store.allChunks()
        guard facts.count > 1 else {
            return []
        }

        let embeddings = facts.map(\.embedding)
        let similarities = try PortableCompute.pairwiseSimilarityMatrix(embeddings: embeddings)

        var candidatePairs: [(embeddingsA: [Float], embeddingsB: [Float], i: Int, j: Int)] = []
        for i in 0..<facts.count {
            for j in (i + 1)..<facts.count where similarities[i][j] > similarityThreshold {
                candidatePairs.append((embeddings[i], embeddings[j], i, j))
            }
        }
        guard !candidatePairs.isEmpty else {
            return []
        }

        let fractions = try PortableCompute.antipodalFractions(
            embeddingsA: candidatePairs.map(\.embeddingsA),
            embeddingsB: candidatePairs.map(\.embeddingsB)
        )
        var matches: [(MemoryChunk, MemoryChunk)] = []
        for (offset, pair) in candidatePairs.enumerated() where fractions[offset] > antipodalThreshold {
            matches.append((facts[pair.i], facts[pair.j]))
        }
        return matches
    }

    /// Computes antipodal (sign-flip) fractions for embedding pairs.
    public func antipodalFractions(
        embeddingsA: [[Float]],
        embeddingsB: [[Float]]
    ) async throws -> [Float] {
        try PortableCompute.antipodalFractions(embeddingsA: embeddingsA, embeddingsB: embeddingsB)
    }

    private func unconsolidatedChunks(
        from allChunks: [MemoryChunk],
        store: any ConsolidationEpisodicStore
    ) async -> [MemoryChunk] {
        var chunks: [MemoryChunk] = []
        chunks.reserveCapacity(allChunks.count)
        for chunk in allChunks {
            if await store.isConsolidated(id: chunk.id) {
                continue
            }
            chunks.append(chunk)
        }
        return chunks
    }
}

/// Background trigger that schedules consolidation after insertion thresholds.
public actor ConsolidationScheduler {
    private let engine: any ConsolidationEngineProtocol
    private let countThreshold: Int
    private let insertionThreshold: Int
    private let similarityThreshold: Float

    private var insertionsSinceLastConsolidation = 0
    private var isConsolidating = false
    private var triggerCountValue = 0
    private var lastResultValue: ConsolidationResult?

    /// Creates a consolidation scheduler.
    ///
    /// - Parameters:
    ///   - engine: Consolidation engine to run (Metal or CPU).
    ///   - countThreshold: Episodic count trigger threshold.
    ///   - insertionThreshold: Insertion count trigger threshold.
    ///   - similarityThreshold: Duplicate similarity threshold for scheduled runs.
    public init(
        engine: any ConsolidationEngineProtocol,
        countThreshold: Int = 200,
        insertionThreshold: Int = 50,
        similarityThreshold: Float = 0.92
    ) {
        self.engine = engine
        self.countThreshold = countThreshold
        self.insertionThreshold = insertionThreshold
        self.similarityThreshold = similarityThreshold
    }

    /// Notifies scheduler that an insertion occurred and may trigger consolidation.
    public func notifyInsertion(
        episodicCount: Int,
        session: UUID,
        episodicStore: any ConsolidationEpisodicStore,
        semanticStore: any ConsolidationSemanticStore
    ) async {
        insertionsSinceLastConsolidation += 1

        let shouldConsolidate = episodicCount > countThreshold || insertionsSinceLastConsolidation > insertionThreshold
        guard shouldConsolidate, !isConsolidating else {
            return
        }

        isConsolidating = true
        triggerCountValue += 1

        let engine = self.engine
        let threshold = self.similarityThreshold

        Task.detached(priority: .background) {
            do {
                let result = try await engine.consolidate(
                    session: session,
                    episodicStore: episodicStore,
                    semanticStore: semanticStore,
                    threshold: threshold
                )
                await self.finish(result: result)
            } catch {
                await self.finish(result: nil)
            }
        }
    }

    /// Number of consolidation triggers issued.
    public func triggerCount() -> Int {
        triggerCountValue
    }

    /// Indicates whether a background consolidation task is running.
    public func isRunning() -> Bool {
        isConsolidating
    }

    /// Latest successful consolidation result.
    public func lastResult() -> ConsolidationResult? {
        lastResultValue
    }

    private func finish(result: ConsolidationResult?) {
        if let result {
            lastResultValue = result
            resetCounter()
        }
        isConsolidating = false
    }

    private func resetCounter() {
        insertionsSinceLastConsolidation = 0
    }
}
