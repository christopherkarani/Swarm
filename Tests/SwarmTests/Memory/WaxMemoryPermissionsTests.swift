#if SWARM_INTEGRATIONS
import Foundation
@testable import Swarm
import Testing

@Suite("WaxMemory file permissions")
struct WaxMemoryPermissionsTests {
    #if canImport(SQLite3)
    @Test("Memory store files are owner-only")
    func memoryStoreFilesAreOwnerOnly() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wax-memory-perms-\(UUID().uuidString).mv2s")
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await WaxMemory(url: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try permissions(of: url) == 0o600)
    }
    #endif

    @Test("Ephemeral store directories are owner-only")
    func ephemeralStoreDirectoriesAreOwnerOnly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-wax-root-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let url = WaxMemory.makeEphemeralStoreURL(under: root)
        let directory = url.deletingLastPathComponent()
        #expect(try permissions(of: directory) == 0o700)
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let raw = attributes[.posixPermissions] as? Int ?? 0
        return raw & 0o777
    }
}
#endif
