import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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

    /// Atomically writes `data` to `url` as an owner-only (`0600`) file.
    ///
    /// The bytes land in a same-directory temporary file created with
    /// `O_CREAT`/`0600`, so they are never readable by group/other — not
    /// even between creation and the atomic rename over `url`.
    static func write(_ data: Data, to url: URL) throws {
        let tempURL = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
        )
        let tempPath = tempURL.path
        let fd = tempPath.withCString { cPath in
            open(cPath, O_WRONLY | O_CREAT | O_EXCL, mode_t(filePermissions))
        }
        guard fd >= 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: tempPath])
        }
        do {
            try data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    guard let baseAddress = buffer.baseAddress else { break }
                    let written = posixWrite(fd, baseAddress.advanced(by: offset), buffer.count - offset)
                    guard written > 0 else {
                        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: tempPath])
                    }
                    offset += written
                }
            }
        } catch {
            close(fd)
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
        guard close(fd) == 0 else {
            try? FileManager.default.removeItem(at: tempURL)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: tempPath])
        }
        let renamed = tempPath.withCString { tempCPath in
            url.path.withCString { destinationCPath in
                rename(tempCPath, destinationCPath)
            }
        }
        guard renamed == 0 else {
            try? FileManager.default.removeItem(at: tempURL)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        // The renamed file already carries the temp file's `0600` mode;
        // re-apply defensively (and for Data Protection) like before.
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

    /// POSIX `write(2)`. Kept behind a helper because the enum's own
    /// `write(_:to:)` shadows the global `write` symbol.
    private static func posixWrite(_ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int {
        #if canImport(Darwin)
        Darwin.write(fd, buffer, count)
        #elseif canImport(Glibc)
        Glibc.write(fd, buffer, count)
        #else
        #error("ContextCoreSecureFileIO.write requires Darwin or Glibc")
        #endif
    }
}
