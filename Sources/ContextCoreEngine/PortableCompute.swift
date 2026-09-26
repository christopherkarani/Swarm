import ContextCoreTypes
import Foundation

/// Pure, dependency-free compute kernels shared by the CPU and Metal engine paths.
///
/// This is the functional core: synchronous value-type logic with no actors,
/// I/O, or Metal. The math mirrors the `.metal` shaders in `ContextCoreShaders`
/// (`relevance_score`, `compute_recency_weights`, `token_centrality`,
/// `cross_attention_score`, `sentence_importance`, `pairwise_similarity`, and
/// `antipodal_test`) so CPU results match GPU results up to float rounding.
public enum PortableCompute: Sendable {
    /// L2 norm of a vector, or `0` when empty.
    public static func l2Norm(_ vector: [Float]) -> Float {
        guard !vector.isEmpty else {
            return 0
        }
        var sum: Float = 0
        for value in vector {
            sum += value * value
        }
        return sum.squareRoot()
    }

    /// Cosine similarity of two vectors.
    ///
    /// Returns `0` when the vectors differ in length or either norm is zero,
    /// matching the Metal kernels' `denom > 0` guard.
    public static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else {
            return 0
        }
        var dot: Float = 0
        var lhsNorm: Float = 0
        var rhsNorm: Float = 0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lhsNorm += lhs[index] * lhs[index]
            rhsNorm += rhs[index] * rhs[index]
        }
        let denominator = lhsNorm.squareRoot() * rhsNorm.squareRoot()
        guard denominator > 0 else {
            return 0
        }
        return dot / denominator
    }

    /// Blended relevance/recency scores, mirroring `relevance_score`.
    public static func relevanceScores(
        query: [Float],
        flattenedEmbeddings: [Float],
        count: Int,
        dimension: Int,
        recencyWeights: [Float],
        relevanceWeight: Float,
        recencyWeight: Float
    ) throws -> [Float] {
        guard count > 0 else {
            return []
        }
        guard query.count == dimension else {
            throw ContextCoreError.dimensionMismatch(expected: dimension, got: query.count)
        }
        guard flattenedEmbeddings.count == count * dimension else {
            throw ContextCoreError.dimensionMismatch(expected: count * dimension, got: flattenedEmbeddings.count)
        }
        guard recencyWeights.count == count else {
            throw ContextCoreError.dimensionMismatch(expected: count, got: recencyWeights.count)
        }

        let queryNorm = l2Norm(query)
        var scores = [Float](repeating: 0, count: count)
        for row in 0..<count {
            let base = row * dimension
            var dot: Float = 0
            var chunkNormSq: Float = 0
            for d in 0..<dimension {
                let q = query[d]
                let c = flattenedEmbeddings[base + d]
                dot += q * c
                chunkNormSq += c * c
            }
            let denominator = queryNorm * chunkNormSq.squareRoot()
            let cosine: Float = denominator > 0 ? dot / denominator : 0
            scores[row] = cosine * relevanceWeight + recencyWeights[row] * recencyWeight
        }
        return scores
    }

    /// Exponential recency weights with half-life decay, mirroring `compute_recency_weights`.
    ///
    /// `weight = clamp(exp(-ln(2) * age / halfLife), 0, 1)`.
    public static func recencyWeights(
        timestamps: [Date],
        halfLife: TimeInterval,
        currentTime: Date
    ) throws -> [Float] {
        guard !timestamps.isEmpty else {
            return []
        }
        guard halfLife > 0 else {
            throw ContextCoreError.compressionFailed("halfLife must be positive")
        }
        let now = currentTime.timeIntervalSince1970
        return timestamps.map { timestamp in
            let age = now - timestamp.timeIntervalSince1970
            let value = exp(-0.6931471805599453 * age / halfLife)
            return Float(min(1, max(0, value)))
        }
    }

    /// Indices of the top-k scores; lower indices win ties.
    ///
    /// Mirrors `ScoringEngine.topKIndices` selection order.
    public static func topKIndices(scores: [Float], k: Int) -> [Int] {
        guard !scores.isEmpty, k > 0 else {
            return []
        }
        let cappedK = min(k, scores.count)
        return scores.enumerated()
            .sorted { lhs, rhs in
                if lhs.element == rhs.element {
                    return lhs.offset < rhs.offset
                }
                return lhs.element > rhs.element
            }
            .prefix(cappedK)
            .map(\.offset)
    }

    /// Mean cosine centrality per embedding, mirroring `token_centrality`.
    public static func centrality(embeddings: [[Float]]) throws -> [Float] {
        guard !embeddings.isEmpty else {
            return []
        }
        if embeddings.count == 1 {
            return [0]
        }
        let dimension = try validatedDimension(embeddings)
        let norms = embeddings.map { l2Norm($0) }
        let n = embeddings.count
        var output = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var sum: Float = 0
            for j in 0..<n where j != i {
                var dot: Float = 0
                for d in 0..<dimension {
                    dot += embeddings[i][d] * embeddings[j][d]
                }
                let denominator = norms[i] * norms[j]
                if denominator > 0 {
                    sum += dot / denominator
                }
            }
            output[i] = sum / Float(n - 1)
        }
        return output
    }

    /// Blended relevance/centrality eviction scores, mirroring `cross_attention_score`.
    public static func crossAttentionScores(
        query: [Float],
        embeddings: [[Float]],
        centrality: [Float],
        relevanceWeight: Float,
        centralityWeight: Float
    ) throws -> [Float] {
        let dimension = query.count
        guard embeddings.allSatisfy({ $0.count == dimension }) else {
            throw ContextCoreError.dimensionMismatch(
                expected: dimension,
                got: embeddings.first(where: { $0.count != dimension })?.count ?? 0
            )
        }
        guard centrality.count == embeddings.count else {
            throw ContextCoreError.dimensionMismatch(expected: embeddings.count, got: centrality.count)
        }
        return embeddings.enumerated().map { index, embedding in
            cosineSimilarity(query, embedding) * relevanceWeight
                + centrality[index] * centralityWeight
        }
    }

    /// Cosine importance of each sentence embedding to the chunk embedding.
    ///
    /// Mirrors `sentence_importance`.
    public static func sentenceImportance(
        sentenceEmbeddings: [[Float]],
        chunkEmbedding: [Float]
    ) throws -> [Float] {
        let dimension = chunkEmbedding.count
        guard sentenceEmbeddings.allSatisfy({ $0.count == dimension }) else {
            throw ContextCoreError.dimensionMismatch(
                expected: dimension,
                got: sentenceEmbeddings.first(where: { $0.count != dimension })?.count ?? 0
            )
        }
        return sentenceEmbeddings.map { cosineSimilarity($0, chunkEmbedding) }
    }

    /// Dense symmetric pairwise cosine similarity matrix with unit diagonal.
    public static func pairwiseSimilarityMatrix(embeddings: [[Float]]) throws -> [[Float]] {
        guard !embeddings.isEmpty else {
            return []
        }
        if embeddings.count == 1 {
            return [[1.0]]
        }
        let dimension = try validatedDimension(embeddings)
        let norms = embeddings.map { l2Norm($0) }
        let n = embeddings.count
        var matrix = Array(repeating: Array(repeating: Float.zero, count: n), count: n)
        for index in 0..<n {
            matrix[index][index] = 1.0
        }
        for i in 0..<n {
            for j in (i + 1)..<n {
                var dot: Float = 0
                for d in 0..<dimension {
                    dot += embeddings[i][d] * embeddings[j][d]
                }
                let denominator = norms[i] * norms[j]
                let value: Float = denominator > 0 ? dot / denominator : 0
                matrix[i][j] = value
                matrix[j][i] = value
            }
        }
        return matrix
    }

    /// Strict-upper-triangle index pairs with similarity above `threshold`.
    ///
    /// Unlike the GPU path (which caps candidates at `10 * n` for bounded
    /// buffers), the CPU scan returns every qualifying pair in `(i, j)` order.
    public static func duplicateIndexPairs(
        embeddings: [[Float]],
        threshold: Float
    ) throws -> [(Int, Int)] {
        guard embeddings.count > 1 else {
            return []
        }
        _ = try validatedDimension(embeddings)
        let matrix = try pairwiseSimilarityMatrix(embeddings: embeddings)
        var pairs: [(Int, Int)] = []
        for i in 0..<embeddings.count {
            for j in (i + 1)..<embeddings.count where matrix[i][j] > threshold {
                pairs.append((i, j))
            }
        }
        return pairs
    }

    /// Fraction of dimensions with differing signs per pair, mirroring `antipodal_test`.
    ///
    /// Zero counts as non-negative on both sides, matching the shader's `>= 0` test.
    public static func antipodalFractions(
        embeddingsA: [[Float]],
        embeddingsB: [[Float]]
    ) throws -> [Float] {
        guard embeddingsA.count == embeddingsB.count else {
            throw ContextCoreError.dimensionMismatch(expected: embeddingsA.count, got: embeddingsB.count)
        }
        guard !embeddingsA.isEmpty else {
            return []
        }
        let dimension = embeddingsA[0].count
        guard dimension > 0,
              embeddingsA.allSatisfy({ $0.count == dimension }),
              embeddingsB.allSatisfy({ $0.count == dimension })
        else {
            throw ContextCoreError.dimensionMismatch(
                expected: dimension,
                got: embeddingsA.first(where: { $0.count != dimension })?.count
                    ?? embeddingsB.first(where: { $0.count != dimension })?.count
                    ?? 0
            )
        }
        return zip(embeddingsA, embeddingsB).map { lhs, rhs in
            var signDiffCount = 0
            for d in 0..<dimension where (lhs[d] >= 0) != (rhs[d] >= 0) {
                signDiffCount += 1
            }
            return Float(signDiffCount) / Float(dimension)
        }
    }

    private static func validatedDimension(_ embeddings: [[Float]]) throws -> Int {
        guard let dimension = embeddings.first?.count, dimension > 0 else {
            throw ContextCoreError.dimensionMismatch(expected: 1, got: 0)
        }
        guard embeddings.allSatisfy({ $0.count == dimension }) else {
            throw ContextCoreError.dimensionMismatch(
                expected: dimension,
                got: embeddings.first(where: { $0.count != dimension })?.count ?? 0
            )
        }
        return dimension
    }
}
