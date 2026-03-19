// EmbeddingProvider.swift
// Swarm Framework
//
// Protocol for text-to-vector embeddings for semantic search.

import Foundation

// MARK: - EmbeddingProvider

/// Protocol for embedding text into vectors for semantic search.
///
/// Embedding providers convert text into dense vector representations
/// that capture semantic meaning. These vectors enable similarity search
/// in ``VectorMemory`` for retrieval-augmented generation (RAG) applications.
///
/// ## Overview
///
/// Text embeddings are numerical representations of text where semantically
/// similar texts have similar vector representations. This enables:
///
/// - Semantic search: Find documents about similar topics even with different words
/// - Clustering: Group related texts automatically
/// - Classification: Use embeddings as features for ML models
///
/// ## Common Embedding Dimensions
///
/// | Provider | Dimensions | Notes |
/// |----------|------------|-------|
/// | OpenAI text-embedding-3-small | 1536 | Good balance of quality and cost |
/// | OpenAI text-embedding-3-large | 3072 | Highest quality |
/// | Cohere embed | 1024 | Multilingual support |
/// | Sentence Transformers | 384-768 | On-device capable |
///
/// ## Implementing a Provider
///
/// Create a custom provider by conforming to `EmbeddingProvider`:
///
/// ```swift
/// struct OpenAIEmbeddingProvider: EmbeddingProvider {
///     let apiKey: String
///     let model: String = "text-embedding-3-small"
///
///     var dimensions: Int { 1536 }
///     var modelIdentifier: String { model }
///
///     func embed(_ text: String) async throws -> [Float] {
///         // Call OpenAI embeddings API
///         let request = EmbeddingRequest(
///             model: model,
///             input: text
///         )
///         let response = try await api.embed(request)
///         return response.embedding
///     }
/// }
/// ```
///
/// ## Usage with VectorMemory
///
/// ```swift
/// let provider = OpenAIEmbeddingProvider(apiKey: apiKey)
/// let memory = Memory.vector(
///     embeddingProvider: provider,
///     similarityThreshold: 0.75,
///     maxResults: 10
/// )
/// ```
///
/// ## Query vs Document Embeddings
///
/// Some models (like Snowflake Arctic) benefit from different processing
/// for queries versus documents. Override ``embedQuery(_:)`` if your
/// provider supports this optimization:
///
/// ```swift
/// func embedQuery(_ query: String) async throws -> [Float] {
///     // Add query-specific prefix if required by model
///     let prefixed = "Represent this sentence for searching: \(query)"
///     return try await embed(prefixed)
/// }
/// ```
///
/// - SeeAlso: ``VectorMemory``, ``EmbeddingError``, ``EmbeddingUtils``
public protocol EmbeddingProvider: Sendable {
    /// The dimensionality of embeddings produced by this provider.
    ///
    /// All embeddings from this provider will have this many dimensions.
    /// Common values include 384, 768, 1024, 1536, and 3072.
    ///
    /// This property is used by ``VectorMemory`` to validate embeddings
    /// and allocate appropriate storage.
    ///
    /// ## Example
    ///
    /// ```swift
    /// var dimensions: Int { 1536 }  // OpenAI text-embedding-3-small
    /// ```
    var dimensions: Int { get }

    /// The model identifier used for embeddings.
    ///
    /// A human-readable string identifying the embedding model.
    /// Used for logging, diagnostics, and cache key generation.
    ///
    /// ## Example
    ///
    /// ```swift
    /// var modelIdentifier: String { "text-embedding-3-small" }
    /// ```
    ///
    /// Default implementation returns `"unknown"`.
    var modelIdentifier: String { get }

    /// Embeds a single text into a vector.
    ///
    /// This is the core method that converts text into a dense vector
    /// representation. The returned vector should have length equal to
    /// ``dimensions``.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let embedding = try await provider.embed("The quick brown fox")
    /// // embedding.count == provider.dimensions
    /// ```
    ///
    /// - Parameter text: The text to embed.
    /// - Returns: A vector of floats representing the text's semantic meaning.
    ///   The vector length equals ``dimensions``.
    /// - Throws: ``EmbeddingError`` if embedding fails, or provider-specific errors.
    func embed(_ text: String) async throws -> [Float]

    /// Embeds a query text into a vector (optimized for retrieval).
    ///
    /// Some embedding models benefit from different processing for queries
    /// versus documents. For example, bi-encoder models may use special
    /// prefixes to indicate query intent.
    ///
    /// Default implementation calls ``embed(_:)``.
    ///
    /// ## When to Override
    ///
    /// Override this method if your embedding model:
    /// - Requires query-specific prefixes
    /// - Uses different models for queries vs documents
    /// - Benefits from query expansion or preprocessing
    ///
    /// ## Example
    ///
    /// ```swift
    /// func embedQuery(_ query: String) async throws -> [Float] {
    ///     // Snowflake Arctic style query prefix
    ///     return try await embed("Represent this sentence for retrieval: \(query)")
    /// }
    /// ```
    ///
    /// - Parameter query: The search query to embed.
    /// - Returns: A vector of floats representing the query's semantic meaning.
    /// - Throws: ``EmbeddingError`` if embedding fails.
    func embedQuery(_ query: String) async throws -> [Float]

    /// Embeds multiple texts in a batch.
    ///
    /// Batch embedding is more efficient than calling ``embed(_:)`` multiple
    /// times, as it reduces network round-trips and enables provider-level
    /// optimizations.
    ///
    /// Default implementation calls ``embed(_:)`` sequentially. Override
    /// this method for providers that support native batch operations.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let texts = ["First document", "Second document", "Third document"]
    /// let embeddings = try await provider.embed(texts)
    /// // embeddings.count == 3
    /// // embeddings[0].count == provider.dimensions
    /// ```
    ///
    /// - Parameter texts: Array of texts to embed.
    /// - Returns: Array of embedding vectors in the same order as input.
    /// - Throws: ``EmbeddingError`` if any embedding fails, including
    ///   ``EmbeddingError/batchTooLarge(size:limit:)`` if the batch
    ///   exceeds provider limits.
    func embed(_ texts: [String]) async throws -> [[Float]]
}

// MARK: - Default Implementations

public extension EmbeddingProvider {
    /// Default model identifier.
    ///
    /// Returns `"unknown"`. Override to provide a specific model name.
    var modelIdentifier: String { "unknown" }

    /// Default query embedding implementation.
    ///
    /// Simply calls ``embed(_:)`` with the query text.
    func embedQuery(_ query: String) async throws -> [Float] {
        try await embed(query)
    }

    /// Default batch implementation - sequential embedding.
    ///
    /// Processes texts one at a time. Override this for providers that
    /// support native batch operations for better performance.
    ///
    /// This implementation checks for task cancellation between each
    /// embedding operation.
    func embed(_ texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)

        for text in texts {
            try Task.checkCancellation()
            let embedding = try await embed(text)
            results.append(embedding)
        }

        return results
    }
}

// MARK: - EmbeddingError

/// Errors specific to embedding operations.
///
/// `EmbeddingError` provides detailed information about failures during
/// text embedding operations, enabling appropriate error handling and
/// retry strategies.
///
/// ## Error Handling Example
///
/// ```swift
/// do {
///     let embedding = try await provider.embed(text)
/// } catch let error as EmbeddingError {
///     switch error {
///     case .rateLimitExceeded(let retryAfter):
///         // Wait and retry
///         try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
///     case .networkError(let underlying):
///         // Log and retry with backoff
///         logger.error("Network error: \(underlying)")
///     case .authenticationFailed:
///         // Refresh credentials
///         await refreshAPIKey()
///     default:
///         throw error
///     }
/// }
/// ```
///
/// - SeeAlso: ``EmbeddingProvider``
public enum EmbeddingError: Error, Sendable, CustomStringConvertible {
    /// The embedding model is not available.
    ///
    /// The model may be loading, disabled, or the specified model
    /// name may not exist.
    case modelUnavailable(reason: String)

    /// Embedding dimensions don't match expected.
    ///
    /// The returned embedding has a different dimensionality than
    /// the provider's ``EmbeddingProvider/dimensions`` property.
    case dimensionMismatch(expected: Int, got: Int)

    /// Input text is empty or invalid.
    ///
    /// The embedding provider cannot process empty strings or
    /// the input contains invalid characters.
    case emptyInput

    /// Batch size exceeds provider limits.
    ///
    /// The requested batch size is larger than the provider supports.
    /// Retry with a smaller batch.
    case batchTooLarge(size: Int, limit: Int)

    /// Network or API error.
    ///
    /// A network-level error occurred while communicating with the
    /// embedding service. The underlying error provides more details.
    case networkError(underlying: any Error & Sendable)

    /// Rate limit exceeded.
    ///
    /// Too many requests have been made. Wait for the specified
    /// duration before retrying.
    case rateLimitExceeded(retryAfter: TimeInterval?)

    /// Invalid API key or authentication failure.
    ///
    /// The credentials provided are invalid or expired.
    case authenticationFailed

    /// Generic embedding failure.
    ///
    /// An unspecified error occurred during embedding. The reason
    /// string provides additional context.
    case embeddingFailed(reason: String)

    /// Human-readable description of the error.
    public var description: String {
        switch self {
        case let .modelUnavailable(reason):
            return "Embedding model unavailable: \(reason)"
        case let .dimensionMismatch(expected, got):
            return "Embedding dimension mismatch: expected \(expected), got \(got)"
        case .emptyInput:
            return "Cannot embed empty input"
        case let .batchTooLarge(size, limit):
            return "Batch size \(size) exceeds limit \(limit)"
        case let .networkError(error):
            return "Network error: \(error.localizedDescription)"
        case let .rateLimitExceeded(retryAfter):
            if let retry = retryAfter {
                return "Rate limit exceeded, retry after \(retry)s"
            }
            return "Rate limit exceeded"
        case .authenticationFailed:
            return "Authentication failed"
        case let .embeddingFailed(reason):
            return "Embedding failed: \(reason)"
        }
    }
}

// MARK: - EmbeddingUtils

/// Utility functions for working with embeddings.
///
/// `EmbeddingUtils` provides common vector operations used in semantic
/// search and similarity calculations. These functions are optimized
/// for embedding comparison tasks.
///
/// ## Example Usage
///
/// ```swift
/// let vec1 = try await provider.embed("King")
/// let vec2 = try await provider.embed("Queen")
///
/// let similarity = EmbeddingUtils.cosineSimilarity(vec1, vec2)
/// // similarity is between -1 and 1, higher means more similar
/// ```
///
/// - SeeAlso: ``VectorMemory``, ``EmbeddingProvider``
enum EmbeddingUtils {
    /// Calculates cosine similarity between two vectors.
    ///
    /// Cosine similarity measures the cosine of the angle between two vectors,
    /// indicating their directional similarity regardless of magnitude.
    ///
    /// ## Formula
    ///
    /// ```
    /// similarity = (A · B) / (||A|| × ||B||)
    /// ```
    ///
    /// ## Interpretation
    ///
    /// | Score | Meaning |
    /// |-------|---------|
    /// | 1.0 | Identical direction (most similar) |
    /// | 0.0 | Orthogonal (unrelated) |
    /// | -1.0 | Opposite direction (most dissimilar) |
    ///
    /// In practice, embeddings for similar texts typically score 0.7-0.9.
    ///
    /// - Parameters:
    ///   - vec1: First vector.
    ///   - vec2: Second vector.
    /// - Returns: Similarity score between -1 and 1 (1 = identical).
    ///   Returns 0 if vectors have different lengths or are empty.
    static func cosineSimilarity(_ vec1: [Float], _ vec2: [Float]) -> Float {
        guard vec1.count == vec2.count, !vec1.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var norm1: Float = 0
        var norm2: Float = 0

        for i in 0..<vec1.count {
            dotProduct += vec1[i] * vec2[i]
            norm1 += vec1[i] * vec1[i]
            norm2 += vec2[i] * vec2[i]
        }

        let denominator = sqrt(norm1) * sqrt(norm2)
        return denominator > 0 ? dotProduct / denominator : 0
    }

    /// Calculates Euclidean distance between two vectors.
    ///
    /// Euclidean distance measures the straight-line distance between
    /// two points in vector space. Lower values indicate more similar vectors.
    ///
    /// ## Formula
    ///
    /// ```
    /// distance = √Σ(A[i] - B[i])²
    /// ```
    ///
    /// ## Interpretation
    ///
    /// - Distance of 0 means identical vectors
    /// - Smaller distances mean more similar vectors
    /// - For normalized vectors, related to cosine similarity
    ///
    /// - Parameters:
    ///   - embedding1: First vector.
    ///   - embedding2: Second vector.
    /// - Returns: Euclidean distance (lower = more similar).
    ///   Returns `Float.infinity` if vectors have different lengths.
    static func euclideanDistance(_ embedding1: [Float], _ embedding2: [Float]) -> Float {
        guard embedding1.count == embedding2.count else { return Float.infinity }

        var sum: Float = 0
        for i in 0..<embedding1.count {
            let diff = embedding1[i] - embedding2[i]
            sum += diff * diff
        }

        return sqrt(sum)
    }

    /// Normalizes a vector to unit length.
    ///
    /// L2 normalization scales a vector so its Euclidean norm (magnitude)
    /// equals 1. This is useful for preparing vectors for cosine similarity
    /// calculations.
    ///
    /// ## Formula
    ///
    /// ```
    /// normalized[i] = vec[i] / ||vec||
    /// ```
    ///
    /// - Parameter vector: The vector to normalize.
    /// - Returns: Unit vector (magnitude = 1). Returns original vector if
    ///   it has zero magnitude.
    static func normalize(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }
}
