// SecureFileIO.swift
// Swarm Framework
//
// Owner-only file writes for checkpoints, memory, and cached artifacts.

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Owner-only file writes for checkpoints, memory, and cached artifacts.
///
/// Files are written atomically and then restricted to `0600`, directories to
/// `0700`. On Apple platforms the Data Protection class
/// `completeUntilFirstUserAuthentication` is additionally applied on a
/// best-effort basis (it is advisory on macOS and enforced on iOS).
///
/// Use ``hardenTree(at:)`` to migrate directories written before this
/// hardening existed; see `WorkflowCheckpointing.hardenFilePermissions(in:)`.
enum SecureFileIO {
    /// POSIX permissions applied to written files (`0600`).
    static let filePermissions = 0o600
    /// POSIX permissions applied to created directories (`0700`).
    static let directoryPermissions = 0o700

    /// Atomically writes `data` to `url` as an owner-only (`0600`) file.
    ///
    /// The bytes land in a same-directory temporary file created with
    /// `O_CREAT`/`0600`, so they are never readable by group/other — not
    /// even between creation and the atomic rename over `url`.
    ///
    /// - Parameters:
    ///   - data: Bytes to write.
    ///   - url: Destination file URL.
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
    /// must not chmod directories it does not own (shared or system roots
    /// would fail or surprise the owner). Files written inside are always
    /// `0600` via ``write(_:to:)``; use ``hardenTree(at:)`` to migrate a
    /// pre-existing directory on request.
    ///
    /// - Parameter url: Directory URL to create.
    static func createDirectory(at url: URL) throws {
        let existed = FileManager.default.fileExists(atPath: url.path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if !existed {
            try hardenDirectory(at: url)
        }
    }

    /// Restricts an existing file to `0600`.
    ///
    /// - Parameter url: File URL to harden.
    static func hardenFile(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: filePermissions],
            ofItemAtPath: url.path
        )
        applyDataProtection(at: url)
    }

    /// Restricts an existing directory to `0700`.
    ///
    /// - Parameter url: Directory URL to harden.
    static func hardenDirectory(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: directoryPermissions],
            ofItemAtPath: url.path
        )
        applyDataProtection(at: url)
    }

    /// Hardens `url` as a file or directory based on its on-disk type.
    ///
    /// - Parameter url: File or directory URL to harden.
    static func harden(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw CocoaError(.fileNoSuchFile)
        }
        if isDirectory.boolValue {
            try hardenDirectory(at: url)
        } else {
            try hardenFile(at: url)
        }
    }

    /// Recursively hardens `url` and its contents to owner-only permissions.
    ///
    /// Items that cannot be hardened are skipped; the returned count reflects
    /// hardened items only. Throws when `url` itself does not exist.
    /// Symbolic links — the root or items inside — are skipped, never
    /// followed, so out-of-tree link targets keep their permissions.
    ///
    /// - Parameter url: Root file or directory URL.
    /// - Returns: Number of items hardened, including the root.
    @discardableResult
    static func hardenTree(at url: URL) throws -> Int {
        var hardened = 0
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard isSymbolicLink(url) == false else {
            return hardened
        }
        if (try? harden(url)) != nil {
            hardened += 1
        }
        guard let enumerator = FileManager.default.enumerator(atPath: url.path) else {
            return hardened
        }
        for case let relativePath as String in enumerator {
            let itemURL = url.appendingPathComponent(relativePath)
            if isSymbolicLink(itemURL) != false {
                // Never chmod through a link: the target may live outside
                // the tree. Skip its descendants as well.
                enumerator.skipDescendants()
                continue
            }
            if (try? harden(itemURL)) != nil {
                hardened += 1
            }
        }
        return hardened
    }

    /// Whether `url` is a symbolic link (`nil` when it cannot be told).
    private static func isSymbolicLink(_ url: URL) -> Bool? {
        try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink
    }

    /// POSIX `write(2)`. Kept behind a helper because the enum's own
    /// ``write(_:to:)`` shadows the global `write` symbol.
    private static func posixWrite(_ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int {
        #if canImport(Darwin)
        Darwin.write(fd, buffer, count)
        #elseif canImport(Glibc)
        Glibc.write(fd, buffer, count)
        #else
        #error("SecureFileIO.write requires Darwin or Glibc")
        #endif
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
