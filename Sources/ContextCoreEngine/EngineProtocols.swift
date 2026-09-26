import ContextCoreTypes
import Foundation

/// Portable scoring-engine contract over relevance, recency, and ranking.
///
/// Both the Metal-backed ``ScoringEngine`` (when Metal is available) and the
/// portable ``CPUScoringEngine`` conform to this protocol, so callers can depend
/// on the abstraction instead of a concrete compute backend.
public protocol RelevanceScoringEngine: Sendable {
    /// Scores candidate chunks against a query vector, sorted by descending score.
    func scoreChunks(
        query: [Float],
        chunks: [MemoryChunk],
        recencyWeights: [Float],
        relevanceWeight: Float,
        recencyWeight: Float
    ) async throws -> [(chunk: MemoryChunk, score: Float)]

    /// Scores candidate chunks without sorting, preserving input order.
    func scoreChunksUnsorted(
        query: [Float],
        chunks: [MemoryChunk],
        recencyWeights: [Float],
        relevanceWeight: Float,
        recencyWeight: Float
    ) async throws -> [(chunk: MemoryChunk, score: Float)]

    /// Returns indices of the top-k scores, with lower indices winning ties.
    func topKIndices(scores: [Float], k: Int) async throws -> [Int]

    /// Computes exponential recency weights with half-life decay.
    func computeRecencyWeights(
        timestamps: [Date],
        halfLife: TimeInterval,
        currentTime: Date
    ) async throws -> [Float]
}

public extension RelevanceScoringEngine {
    /// Computes exponential recency weights relative to the current time.
    func computeRecencyWeights(
        timestamps: [Date],
        halfLife: TimeInterval
    ) async throws -> [Float] {
        try await computeRecencyWeights(timestamps: timestamps, halfLife: halfLife, currentTime: .now)
    }
}

/// Portable attention-engine contract over centrality and eviction scoring.
public protocol AttentionScoringEngine: Sendable {
    /// Computes centrality for each embedding within a candidate set.
    func computeCentrality(embeddings: [[Float]]) async throws -> [Float]

    /// Produces eviction scores sorted ascending (lowest — keep — first).
    func scoreWindowForEviction(
        taskQuery: [Float],
        windowChunks: [MemoryChunk],
        relevanceWeight: Float,
        centralityWeight: Float
    ) async throws -> [(chunk: MemoryChunk, evictionScore: Float)]
}

/// Portable compression-engine contract over sentence ranking and budgeted compression.
public protocol CompressionEngineProtocol: Sendable {
    /// Ranks sentences in a chunk by similarity to the chunk embedding, descending.
    func rankSentences(
        in chunk: String,
        chunkEmbedding: [Float]
    ) async throws -> [(sentence: String, importance: Float)]

    /// Compresses a memory chunk to a target token budget.
    func compress(chunk: MemoryChunk, targetTokens: Int) async throws -> MemoryChunk

    /// Compresses a turn to a target token budget, preserving identity fields.
    func compressTurn(turn: Turn, targetTokens: Int) async throws -> Turn

    /// Replaces the active compression delegate.
    func setCompressionDelegate(_ delegate: any CompressionDelegate) async

    /// Embeds text with this engine's embedding provider.
    func embedForCompression(_ text: String) async throws -> [Float]
}

/// Portable consolidation-engine contract over deduplication and promotion.
public protocol ConsolidationEngineProtocol: Sendable {
    /// Finds duplicate episodic chunk pairs above a similarity threshold.
    func findDuplicates(
        in store: any ConsolidationEpisodicStore,
        threshold: Float
    ) async throws -> [(UUID, UUID)]

    /// Computes pairwise cosine similarity for embedding vectors.
    func pairwiseSimilarity(embeddings: [[Float]]) async throws -> [[Float]]

    /// Runs a full consolidation pass for the active session.
    func consolidate(
        session: UUID,
        episodicStore: any ConsolidationEpisodicStore,
        semanticStore: any ConsolidationSemanticStore,
        threshold: Float
    ) async throws -> ConsolidationResult

    /// Finds contradiction candidates from semantic memory.
    func contradictionCandidates(
        in store: any ConsolidationSemanticStore,
        similarityThreshold: Float,
        antipodalThreshold: Float
    ) async throws -> [(MemoryChunk, MemoryChunk)]

    /// Computes antipodal (sign-flip) fractions for embedding pairs.
    func antipodalFractions(
        embeddingsA: [[Float]],
        embeddingsB: [[Float]]
    ) async throws -> [Float]
}

/// Summary metrics from a consolidation pass.
public struct ConsolidationResult: Sendable, Equatable {
    /// Number of duplicate pairs found.
    public let duplicatePairsFound: Int
    /// Number of facts promoted to semantic memory.
    public let factsPromoted: Int
    /// Number of episodic chunks evicted.
    public let chunksEvicted: Int
    /// Consolidation duration in milliseconds.
    public let durationMs: Double

    /// Creates a consolidation result.
    public init(
        duplicatePairsFound: Int,
        factsPromoted: Int,
        chunksEvicted: Int,
        durationMs: Double
    ) {
        self.duplicatePairsFound = duplicatePairsFound
        self.factsPromoted = factsPromoted
        self.chunksEvicted = chunksEvicted
        self.durationMs = durationMs
    }
}
