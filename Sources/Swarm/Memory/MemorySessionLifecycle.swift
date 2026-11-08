import Foundation

// MARK: - Defaulted capability implementations

public extension Memory {
    /// Default no-op: memories without session state do nothing at session start.
    func beginMemorySession() async {}

    /// Default no-op: memories without session state do nothing at session end.
    func endMemorySession() async {}

    /// Default replay: appends each replayed message through ``add(_:)``.
    func importSessionHistory(_ messages: [MemoryMessage]) async {
        for message in messages {
            await add(message)
        }
    }

    /// Default seed gate: only fresh (empty) memories accept automatic seeding,
    /// which prevents duplicate imports into stores that already hold content.
    func shouldImportSessionHistory() async -> Bool {
        await isEmpty
    }

    /// Default tracking: single-layer memories own no separate tracked layer.
    nonisolated var trackedSessionMemory: (any Memory)? { nil }

    /// Default policy: automatic session seeding is allowed.
    nonisolated var allowsAutomaticSessionSeeding: Bool { true }
}

public extension Memory {
    /// Seeds prior session messages into memory when the memory is eligible and still needs replay.
    func seedSessionHistoryIfNeeded(_ messages: [MemoryMessage]) async {
        guard !messages.isEmpty else {
            return
        }

        guard allowsAutomaticSessionSeeding else {
            return
        }

        let shouldSeed = await shouldImportSessionHistory()
        guard shouldSeed else {
            return
        }

        await importSessionHistory(messages)
    }
}
