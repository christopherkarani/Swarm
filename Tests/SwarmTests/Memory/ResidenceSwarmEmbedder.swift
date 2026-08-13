#if SWARM_INTEGRATIONS
import Foundation
@testable import Swarm

/// Swarm-protocol embedder used to drive ContextCore through `ContextCoreEmbeddingAdapter`.
///
/// Lives in a Swarm-only file so `EmbeddingProvider` is not ambiguous with ContextCore's protocol.
struct ResidenceSwarmEmbedder: EmbeddingProvider {
    let dimensions = 8
    let modelIdentifier = "residence-test-embedder"

    func embed(_ text: String) async throws -> [Float] {
        let lowered = text.lowercased()
        var vector = [Float](repeating: 0, count: dimensions)
        if lowered.contains("kyoto") || lowered.contains("where do i live") {
            vector[0] = 1
        } else if lowered.contains("sourdough") {
            vector[1] = 1
        } else {
            vector[2] = 1
        }
        return vector
    }
}
#endif
