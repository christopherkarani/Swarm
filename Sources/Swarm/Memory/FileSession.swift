// FileSession.swift
// Swarm Framework
//
// Cross-platform file-backed session using SessionSnapshot JSON.

import Foundation

/// A file-backed session that persists across restarts on every platform.
///
/// `FileSession` stores one ``SessionSnapshot`` JSON document per session ID
/// inside `directory`, writing through on every mutation with atomic file
/// replacement. Unlike `PersistentSession` (SwiftData, Apple-only), it works
/// on Linux servers too, and the files are human-inspectable.
///
/// ```swift
/// let directory = URL(fileURLWithPath: "/var/lib/myapp/sessions")
/// let session = FileSession(sessionId: "user-123-chat", directory: directory)
/// try await session.addItem(.user("Hello!"))
/// // ... after a restart, the same ID reloads the same history ...
/// let resumed = FileSession(sessionId: "user-123-chat", directory: directory)
/// let history = try await resumed.getAllItems()
/// ```
///
/// ## Thread Safety
/// As an actor, `FileSession` provides automatic thread-safe access. Items
/// are cached in memory after the first read; concurrent processes sharing
/// one file each see their own writes plus whatever was on disk when they
/// loaded — last writer wins per mutation, not per message.
///
/// ## File Layout
/// `<directory>/<sanitized-sessionId>-<hash>.json`. The readable prefix keeps
/// alphanumerics plus `-_.` and maps every other scalar to `_` (capped at
/// 128 characters), so hostile IDs cannot escape the directory. The suffix is
/// a 64-bit FNV-1a hash of the raw session ID in hex, so IDs that sanitize to
/// the same prefix (`"user/1"` and `"user_1"`) never share a file.
///
/// Files written by earlier releases as `<sanitized-sessionId>.json` are
/// still read when they hold this session's ID; the first successful write
/// moves the history to the new name and removes the legacy file.
///
/// ## Load Failures
/// If the file exists but cannot be read or decoded, every operation throws
/// and the file is left untouched: a session never replaces history it
/// failed to load.
public actor FileSession: Session {
    // MARK: Public

    /// Unique identifier for this session.
    nonisolated public let sessionId: String

    /// Directory holding this session's file. Created on first write.
    nonisolated public let directory: URL

    /// Number of items currently stored in the session.
    ///
    /// Like `PersistentSession.itemCount`, backend errors surface as `0`
    /// with a `Log.memory` error; use ``getItemCount()`` when error
    /// propagation matters.
    public var itemCount: Int {
        get async {
            do {
                try ensureLoaded()
                return items.count
            } catch {
                Log.memory.error("Failed to get item count for file session '\(sessionId)': \(error.localizedDescription). Returning 0.")
                return 0
            }
        }
    }

    /// Whether the session contains no items.
    public var isEmpty: Bool {
        get async {
            await itemCount == 0
        }
    }

    // MARK: - Initialization

    /// Creates a file-backed session.
    ///
    /// Nothing is read or written until the first access: a missing file
    /// starts empty, and an existing file for this session ID loads lazily.
    ///
    /// - Parameters:
    ///   - sessionId: Unique identifier for the session. Default: a new UUID string.
    ///   - directory: Directory holding this session's file.
    public init(sessionId: String = UUID().uuidString, directory: URL) {
        self.sessionId = sessionId
        self.directory = directory
    }

    /// Retrieves the item count with proper error propagation.
    public func getItemCount() async throws -> Int {
        try ensureLoaded()
        return items.count
    }

    // MARK: - Session Protocol Methods

    /// Retrieves conversation history from the session.
    public func getItems(limit: Int?) async throws -> [MemoryMessage] {
        try ensureLoaded()
        guard let limit else {
            return items
        }
        guard limit > 0 else {
            return []
        }
        let startIndex = max(0, items.count - limit)
        return Array(items[startIndex...])
    }

    /// Adds items to the conversation history and persists them.
    public func addItems(_ newItems: [MemoryMessage]) async throws {
        try ensureLoaded()
        items.append(contentsOf: newItems)
        try persist()
    }

    /// Removes and returns the most recent item, persisting the result.
    public func popItem() async throws -> MemoryMessage? {
        try ensureLoaded()
        guard !items.isEmpty else {
            return nil
        }
        let removed = items.removeLast()
        try persist()
        return removed
    }

    /// Clears all items and persists the empty session.
    public func clearSession() async throws {
        try ensureLoaded()
        items.removeAll()
        try persist()
    }

    // MARK: Internal

    /// File holding this session's snapshot.
    nonisolated var fileURL: URL {
        directory.appendingPathComponent("\(sanitizedSessionId)-\(sessionIdHash).json")
    }

    /// Pre-hash file name used by earlier releases; read for migration only.
    nonisolated var legacyFileURL: URL {
        directory.appendingPathComponent("\(sanitizedSessionId).json")
    }

    // MARK: Private

    private var items: [MemoryMessage] = []
    private var loaded = false

    /// Legacy file adopted at load time; removed after the first successful write.
    private var adoptedLegacyFile: URL?

    private nonisolated var sanitizedSessionId: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let mapped = sessionId.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let base = String(mapped)
        if base.isEmpty {
            return "session"
        }
        return String(base.prefix(128))
    }

    /// 64-bit FNV-1a of the raw session ID's UTF-8 bytes, as 16 hex digits.
    ///
    /// Deterministic across processes and platforms (unlike `Hasher`), so the
    /// same ID always maps to the same file.
    private nonisolated var sessionIdHash: String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in sessionId.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    /// Loads the snapshot once. `loaded` flips only after a successful read,
    /// so a failed load keeps throwing instead of exposing an empty session
    /// whose next write would replace the unread file.
    private func ensureLoaded() throws {
        guard !loaded else { return }
        if let snapshot = try readSnapshot(at: fileURL) {
            guard snapshot.sessionId == sessionId else {
                throw SessionError.invalidState(
                    reason: "File session '\(sessionId)' holds data for session '\(snapshot.sessionId)'"
                )
            }
            items = snapshot.items
        } else if let legacy = try readSnapshot(at: legacyFileURL), legacy.sessionId == sessionId {
            // A legacy file holding another ID belongs to a colliding session; ignore it.
            items = legacy.items
            adoptedLegacyFile = legacyFileURL
        }
        loaded = true
    }

    /// Reads and decodes the snapshot at `url`; `nil` when no file exists.
    private func readSnapshot(at url: URL) throws -> SessionSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SessionError.retrievalFailed(
                reason: "Failed to read file session '\(sessionId)'",
                underlyingError: error.localizedDescription
            )
        }
        do {
            return try SessionSnapshot(encoded: data)
        } catch let sessionError as SessionError {
            throw sessionError
        } catch {
            throw SessionError.retrievalFailed(
                reason: "Failed to decode file session '\(sessionId)'",
                underlyingError: error.localizedDescription
            )
        }
    }

    private func persist() throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try SessionSnapshot(sessionId: sessionId, items: items).encoded()
            try data.write(to: fileURL, options: .atomic)
        } catch let sessionError as SessionError {
            throw sessionError
        } catch {
            throw SessionError.storageFailed(
                reason: "Failed to persist file session '\(sessionId)'",
                underlyingError: error.localizedDescription
            )
        }
        if let legacy = adoptedLegacyFile {
            // History now lives at `fileURL`; dropping the legacy copy is best effort.
            try? FileManager.default.removeItem(at: legacy)
            adoptedLegacyFile = nil
        }
    }
}

extension FileSession: ConversationBranchingSession {
    package func branchConversationSession() async throws -> any Session {
        try ensureLoaded()
        let branched = FileSession(directory: directory)
        try await branched.addItems(items)
        return branched
    }
}
