import Foundation

/// Owner-only file writes for ContextCore checkpoints.
///
/// Mirrors Swarm's `SecureFileIO` (ContextCore cannot import Swarm): files are
/// written atomically and restricted to `0600`, directories to `0700`, with the
/// Data Protection class `completeUntilFirstUserAuthentication` applied on a
/// best-effort basis on Apple platforms.
enum ContextCoreSecureFileIO {
    /// POSIX permissions applied to written files (`0600`).
    static let filePermissions = 0o600
    /// POSIX permissions applied to created directories (`0700`).
    static let directoryPermissions = 0o700

    /// Atomically writes `data` to `url`, then restricts it to `0600`.
    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try hardenFile(at: url)
    }

    /// Creates `url` (including intermediates).
    ///
    /// When the leaf directory is created by this call it is restricted to
    /// `0700`. Pre-existing directories keep their permissions: the store
    /// must not chmod directories it does not own.
    static func createDirectory(at url: URL) throws {
        let existed = FileManager.default.fileExists(atPath: url.path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if !existed {
            try hardenDirectory(at: url)
        }
    }

    /// Restricts an existing file to `0600`.
    static func hardenFile(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: filePermissions],
            ofItemAtPath: url.path
        )
        applyDataProtection(at: url)
    }

    /// Restricts an existing directory to `0700`.
    static func hardenDirectory(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: directoryPermissions],
            ofItemAtPath: url.path
        )
        applyDataProtection(at: url)
    }

    private static func applyDataProtection(at url: URL) {
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS) || os(visionOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}
