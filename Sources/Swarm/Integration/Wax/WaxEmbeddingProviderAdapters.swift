#if SWARM_INTEGRATIONS
import Foundation
import WaxVectorSearch

/// Adapter that exposes a Wax embedding provider to Swarm.
public struct SwarmEmbeddingProviderAdapter: EmbeddingProvider {
    public let base: any WaxVectorSearch.EmbeddingProvider

    public init(_ base: any WaxVectorSearch.EmbeddingProvider) {
        self.base = base
    }

    public var dimensions: Int { base.dimensions }

    public var modelIdentifier: String {
        base.identity?.model ?? "wax"
    }

    public func embed(_ text: String) async throws -> [Float] {
        try await base.embed(text)
    }

    public func embedQuery(_ query: String) async throws -> [Float] {
        // WaxVectorSearch.EmbeddingProvider has no embedQuery — fall back to embed
        try await base.embed(query)
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        for text in texts {
            try Task.checkCancellation()
            results.append(try await base.embed(text))
        }
        return results
    }
}

/// Adapter that exposes a Swarm embedding provider to Wax.
public struct WaxEmbeddingProviderAdapter: WaxVectorSearch.EmbeddingProvider {
    public let base: any EmbeddingProvider
    public let normalize: Bool
    public let identity: WaxVectorSearch.EmbeddingIdentity?

    public init(
        _ base: any EmbeddingProvider,
        normalize: Bool = false,
        providerName: String? = "swarm"
    ) {
        self.base = base
        self.normalize = normalize
        self.identity = WaxVectorSearch.EmbeddingIdentity(
            provider: providerName,
            model: base.modelIdentifier,
            dimensions: base.dimensions,
            normalized: normalize
        )
    }

    public var dimensions: Int { base.dimensions }

    public func embed(_ text: String) async throws -> [Float] {
        let embedding = try await base.embed(text)
        return normalize ? EmbeddingUtils.normalize(embedding) : embedding
    }
}
#endif
