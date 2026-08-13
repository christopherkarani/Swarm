#if SWARM_INTEGRATIONS && canImport(ContextCore)
import ContextCore
import Foundation
@testable import Swarm
import Testing
import XCTest

@Suite("ContextCore Swarm embedding adapter")
struct ContextCoreSwarmEmbeddingAdapterTests {
    @Test("ContextCore recall is driven by a Swarm-protocol mock embedder")
    func contextCoreRecallUsesSwarmProtocolMock() async throws {
        var configuration = ContextConfiguration.default
        configuration.embeddingProvider = ContextCoreEmbeddingAdapter(ResidenceSwarmEmbedder())

        let context = try AgentContext(configuration: configuration)
        try await context.beginSession()
        try await context.remember("I live in Kyoto")
        try await context.remember("Sourdough bread needs a starter.")
        try await context.remember("Swift actors isolate mutable state.")

        let recalled = try await context.recall(query: "where do I live?", k: 3)
        #expect(recalled.first?.content == "I live in Kyoto")
    }
}

/// Characterization probe for real MiniLM embeddings.
///
/// Uses XCTest so `XCTSkip` is a skip (Swift Testing treats thrown `XCTSkip`
/// as a failure). Without a cached/bundled model this must skip loudly — never
/// pass on hash-seeded pseudo-vectors.
final class SemanticParaphraseRecallTests: XCTestCase {
    func testKyotoFactRanksFirstWhenRealEmbeddingsAreAvailable() async throws {
        SemanticEmbeddingAvailability.resetForTesting()
        guard SemanticEmbeddingAvailability.isAvailable else {
            throw XCTSkip(
                "Real embeddings are unavailable. Call SemanticEmbeddingAvailability.ensureModelAvailable() to download the MiniLM model before this probe can run."
            )
        }

        let context = try AgentContext()
        try await context.beginSession()
        try await context.remember("I live in Kyoto")
        try await context.remember("Sourdough bread needs a starter.")
        try await context.remember("Swift actors isolate mutable state.")

        let recalled = try await context.recall(query: "where do I live?", k: 3)
        XCTAssertEqual(recalled.first?.content, "I live in Kyoto")
    }
}
#endif
