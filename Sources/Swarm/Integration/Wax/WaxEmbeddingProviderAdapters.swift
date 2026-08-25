#if SWARM_INTEGRATIONS
import Foundation
import WaxVectorSearch

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
