#if SWARM_INTEGRATIONS && canImport(ContextCore)
import ContextCore
import Foundation
@testable import Swarm
import Testing

@Suite("Semantic memory availability")
struct SemanticMemoryAvailabilityTests {
    @Test("fallback path logs once and reports semantic memory unavailable")
    func fallbackPathLogsAndReportsUnavailable() async throws {
        SemanticMemoryDiagnostics.reset()
        let url = try makeTemporaryWaxURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let memory = try DefaultAgentMemory(configuration: .init(waxStoreURL: url))
        _ = await memory.context(for: "semantic recall probe", tokenLimit: 64)

        #expect(memory.isSemanticMemoryAvailable == false)
        let warning = try #require(SemanticMemoryDiagnostics.lastWarning)
        #expect(warning.contains("Real embeddings are unavailable"))
        #expect(warning.contains("Semantic recall quality is degraded"))
        #expect(warning.contains("vector rankings are not meaningful"))
    }

    @Test("custom embedding provider reports semantic memory available")
    func customProviderReportsAvailable() throws {
        SemanticMemoryDiagnostics.reset()
        let url = try makeTemporaryWaxURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var contextConfiguration = ContextConfiguration.default
        contextConfiguration.embeddingProvider = FixedSemanticEmbeddingProvider()

        let memory = try DefaultAgentMemory(
            configuration: .init(
                contextCoreConfiguration: ContextCoreMemoryConfiguration(
                    contextConfiguration: contextConfiguration
                ),
                waxStoreURL: url
            )
        )

        #expect(memory.isSemanticMemoryAvailable == true)
    }
}

private struct FixedSemanticEmbeddingProvider: ContextCore.EmbeddingProvider, Sendable {
    let dimension = 384

    func embed(_ text: String) async throws -> [Float] {
        var vector = [Float](repeating: 0, count: dimension)
        vector[0] = Float(text.hashValue % 100) / 100
        return vector
    }

    func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        for text in texts {
            results.append(try await embed(text))
        }
        return results
    }
}

private func makeTemporaryWaxURL() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "swarm-semantic-memory-tests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appendingPathComponent("wax-memory-\(UUID().uuidString).mv2s")
}
#endif
