/// Abstraction over embedding backends used by ContextCore.
///
/// Shape matches Swarm's public `EmbeddingProvider` (`dimensions`, `embed`,
/// `embedQuery`, batch `embed(_ texts:)`). The two protocols cannot be the
/// same Swift type: Swarm cannot depend on this Integrations-only module, and
/// this module cannot import Swarm without a cycle. Callers that already have
/// a Swarm provider should wrap it with `ContextCoreEmbeddingAdapter`.
public protocol EmbeddingProvider: Sendable {
    /// Dimensionality produced by this provider.
    var dimensions: Int { get }

    /// Human-readable model identifier used for diagnostics and cache keys.
    ///
    /// Default implementation returns `"unknown"`.
    var modelIdentifier: String { get }

    /// Produces an embedding for a single text input.
    ///
    /// - Parameter text: Input text to embed.
    /// - Returns: A vector with fixed length ``dimensions``.
    /// - Throws: Any provider-specific embedding failure.
    func embed(_ text: String) async throws -> [Float]

    /// Produces a query embedding, which some models specialize separately.
    ///
    /// Default implementation calls ``embed(_:)``.
    func embedQuery(_ query: String) async throws -> [Float]

    /// Produces embeddings for multiple inputs.
    ///
    /// Default implementation calls ``embed(_:)`` sequentially.
    func embed(_ texts: [String]) async throws -> [[Float]]
}

public extension EmbeddingProvider {
    var modelIdentifier: String { "unknown" }

    /// Historical alias for ``dimensions``.
    var dimension: Int { dimensions }

    func embedQuery(_ query: String) async throws -> [Float] {
        try await embed(query)
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        for text in texts {
            try Task.checkCancellation()
            results.append(try await embed(text))
        }
        return results
    }

    /// Historical alias for ``embed(_:)`` batch.
    func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        try await embed(texts)
    }
}
