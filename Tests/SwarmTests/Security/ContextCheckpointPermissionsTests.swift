#if SWARM_INTEGRATIONS && canImport(ContextCore)
import ContextCore
import Foundation
import Testing
@testable import Swarm

@Suite("ContextCore checkpoint file permissions")
struct ContextCheckpointPermissionsTests {
    @Test("Checkpoints are owner-only and stay loadable")
    func checkpointsAreOwnerOnly() async throws {
        let context = try ContextCore.AgentContext()
        try await context.beginSession(systemPrompt: "test-prompt")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("context-checkpoint-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("checkpoint.json")

        try await context.checkpoint(to: url)
        #expect(try permissions(of: url) == 0o600)
        #expect(try permissions(of: directory) == 0o700)

        let restored = try await ContextCore.AgentContext.load(from: url)
        #expect(restored.stats.totalSessions == 1)
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let raw = attributes[.posixPermissions] as? Int ?? 0
        return raw & 0o777
    }
}
#endif
