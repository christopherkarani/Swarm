import Foundation
import Testing
@testable import Swarm

@Suite("Secure file IO")
struct SecureFileIOTests {
    @Test("Secure writes restrict files to owner-only and round-trip content")
    func secureWriteRestrictsPermissions() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-secure-io-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }

        try SecureFileIO.write(Data("secret-content".utf8), to: url)
        #expect(try Data(contentsOf: url) == Data("secret-content".utf8))
        #expect(try permissions(of: url) == 0o600)
    }

    @Test("Secure writes replace existing files, stay owner-only, and leak no temps")
    func secureWriteReplacesExistingFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-secure-overwrite-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }

        try SecureFileIO.write(Data("first".utf8), to: url)
        try SecureFileIO.write(Data("second".utf8), to: url)
        #expect(try Data(contentsOf: url) == Data("second".utf8))
        #expect(try permissions(of: url) == 0o600)

        let siblings = try FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        // Compare names only: directory listings resolve the /var -> /private/var symlink.
        let matches = siblings.filter { $0.lastPathComponent.contains(url.lastPathComponent) }
        #expect(matches.map(\.lastPathComponent) == [url.lastPathComponent])
    }

    @Test("Secure writes handle empty data")
    func secureWriteHandlesEmptyData() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-secure-empty-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }

        try SecureFileIO.write(Data(), to: url)
        #expect(try Data(contentsOf: url) == Data())
        #expect(try permissions(of: url) == 0o600)
    }

    @Test("Secure directory creation restricts the leaf to owner-only")
    func secureCreateDirectoryRestrictsPermissions() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-secure-dir-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url) }

        try SecureFileIO.createDirectory(at: url)
        #expect(try permissions(of: url) == 0o700)
    }

    @Test("Secure directory creation leaves pre-existing directories untouched")
    func secureCreateDirectoryLeavesPreexistingUntouched() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-shared-dir-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)

        try SecureFileIO.createDirectory(at: url)
        #expect(try permissions(of: url) == 0o755)
    }

    @Test("hardenTree migrates loose permissions and counts hardened items")
    func hardenTreeMigratesLoosePermissions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-harden-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = nested.appendingPathComponent("plain.txt")
        try Data("plain".utf8).write(to: file, options: .atomic)

        // Simulate pre-hardening files with group/other-readable permissions.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nested.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)

        let hardened = try SecureFileIO.hardenTree(at: root)
        #expect(hardened == 3)
        #expect(try permissions(of: file) == 0o600)
        #expect(try permissions(of: nested) == 0o700)
        #expect(try permissions(of: root) == 0o700)
    }

    @Test("hardenTree skips symlinks instead of following them")
    func hardenTreeSkipsSymlinks() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-harden-link-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = base.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: outside.path)
        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let hardened = try SecureFileIO.hardenTree(at: root)
        #expect(hardened == 1)
        #expect(try permissions(of: root) == 0o700)
        #expect(try permissions(of: outside) == 0o644)

        // A symlinked root hardens nothing.
        #expect(try SecureFileIO.hardenTree(at: link) == 0)
        #expect(try permissions(of: outside) == 0o644)
    }

    @Test("hardenTree throws for a missing path")
    func hardenTreeThrowsForMissingPath() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-missing-\(UUID().uuidString)")
        #expect(throws: CocoaError.self) {
            try SecureFileIO.hardenTree(at: missing)
        }
    }

    @Test("WorkflowCheckpointing migrates a pre-existing directory")
    func checkpointingMigrationHardensDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-checkpoint-migrate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("workflow-old.json")
        try Data("{}".utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

        let hardened = try WorkflowCheckpointing.hardenFilePermissions(in: root)
        #expect(hardened == 2)
        #expect(try permissions(of: file) == 0o600)
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let raw = attributes[.posixPermissions] as? Int ?? 0
        return raw & 0o777
    }
}
