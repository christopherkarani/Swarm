#if SWARM_INTEGRATIONS
// WaxIntegrationTests.swift
// SwarmTests
//
// Tests for the Wax embedding adapter and deprecated integration compatibility.

@testable import Swarm
import Testing

@Suite("Wax Integration Compatibility and Embedding Provider Adapter Tests")
struct WaxEmbeddingProviderAdapterTests {
    @Test("Deprecated Wax integration marker remains source-compatible")
    func deprecatedWaxIntegrationRemainsSourceCompatible() {
        let integration = WaxIntegration()

        #expect(integration.isEnabled == true)
        #expect(WaxIntegration.debugDescription == "Wax integration is enabled")
    }

    @Test("Wax embedding adapter normalizes vectors when requested")
    func waxEmbeddingAdapterNormalizesVectorsWhenRequested() async throws {
        let adapter = WaxEmbeddingProviderAdapter(FixedEmbeddingProvider(vector: [3, 4]), normalize: true)

        let embedding = try await adapter.embed("query")

        #expect(embedding.count == 2)
        #expect(abs(embedding[0] - 0.6) < 0.0001)
        #expect(abs(embedding[1] - 0.8) < 0.0001)
        #expect(adapter.identity?.normalized == true)
    }

    @Test("Wax embedding adapter preserves raw vectors by default")
    func waxEmbeddingAdapterPreservesRawVectorsByDefault() async throws {
        let adapter = WaxEmbeddingProviderAdapter(FixedEmbeddingProvider(vector: [3, 4]))

        let embedding = try await adapter.embed("query")

        #expect(embedding == [3, 4])
        #expect(adapter.identity?.normalized == false)
    }
}

private struct FixedEmbeddingProvider: EmbeddingProvider {
    let vector: [Float]
    let dimensions: Int
    let modelIdentifier = "fixed"

    init(vector: [Float]) {
        self.vector = vector
        self.dimensions = vector.count
    }

    func embed(_: String) async throws -> [Float] {
        vector
    }
}
#endif
