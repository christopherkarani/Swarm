#if SWARM_INTEGRATIONS && canImport(ContextCore)
import ContextCore
import Foundation

/// Bridges Swarm's public ``EmbeddingProvider`` into ContextCore's internal embedder protocol.
///
/// The two protocols describe one concept but cannot be the same Swift type:
/// Swarm is the public product, ContextCore is an Integrations-only internal
/// module, and neither can import the other without a cycle. Use this adapter
/// to drive ContextCore memory with a Swarm-protocol embedder.
public struct ContextCoreEmbeddingAdapter: ContextCore.EmbeddingProvider {
    /// The Swarm embedder being adapted.
    public let base: any EmbeddingProvider

    /// Creates an adapter around a Swarm ``EmbeddingProvider``.
    ///
    /// - Parameter base: Swarm-protocol embedder.
    public init(_ base: any EmbeddingProvider) {
        self.base = base
    }

    public var dimensions: Int { base.dimensions }

    public var modelIdentifier: String { base.modelIdentifier }

    public func embed(_ text: String) async throws -> [Float] {
        try await base.embed(text)
    }

    public func embedQuery(_ query: String) async throws -> [Float] {
        try await base.embedQuery(query)
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        try await base.embed(texts)
    }
}

/// Re-export so `import Swarm` can call the explicit MiniLM delivery API.
public typealias SemanticEmbeddingAvailability = ContextCore.SemanticEmbeddingAvailability
public typealias EmbeddingModelDeliveryConfiguration = ContextCore.EmbeddingModelDeliveryConfiguration
public typealias EmbeddingModelDeliveryProgress = ContextCore.EmbeddingModelDeliveryProgress
public typealias EmbeddingModelDeliveryError = ContextCore.EmbeddingModelDeliveryError
public typealias EmbeddingModelCatalog = ContextCore.EmbeddingModelCatalog
public typealias EmbeddingModelLoadSource = ContextCore.EmbeddingModelLoadSource
#endif
