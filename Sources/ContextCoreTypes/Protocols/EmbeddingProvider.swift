/// Abstraction over embedding backends used by ContextCore.
public protocol EmbeddingProvider: Sendable {
    /// Produces an embedding for a single text input.
    ///
    /// - Parameter text: Input text to embed.
    /// - Returns: A vector with fixed length ``dimension``.
    /// - Throws: Any provider-specific embedding failure.
    func embed(_ text: String) async throws -> [Float]
    /// Produces embeddings for multiple inputs.
    ///
    /// - Parameter texts: Input texts.
    /// - Returns: Embeddings in the same order as `texts`.
    /// - Throws: Any provider-specific embedding failure.
    func embedBatch(_ texts: [String]) async throws -> [[Float]]
    /// Dimensionality produced by this provider.
    var dimension: Int { get }
}
