import Foundation

/// Optional lifecycle observer for memory implementations that need session scoping.
///
/// Session begin/end are now defaulted requirements on ``Memory``; implement
/// ``Memory/beginMemorySession()`` and ``Memory/endMemorySession()`` directly
/// instead of conforming to this protocol.
@available(*, deprecated, message: "Implement beginMemorySession() and endMemorySession() on your Memory conformance instead.")
public protocol MemorySessionLifecycle: Memory {
    /// Called at the beginning of an agent `run` / `stream`.
    func beginMemorySession() async

    /// Called at the end of an agent `run` / `stream` (success or failure).
    func endMemorySession() async
}

/// Optional hook for memories that want custom handling when session history is replayed
/// into a fresh memory instance.
///
/// History import is now a defaulted requirement on ``Memory``; implement
/// ``Memory/importSessionHistory(_:)`` directly instead of conforming to this
/// protocol.
@available(*, deprecated, message: "Implement importSessionHistory(_:) on your Memory conformance instead.")
public protocol MemorySessionReplayAware: Memory {
    /// Imports a batch of session history messages using memory-specific logic.
    func importSessionHistory(_ messages: [MemoryMessage]) async
}

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
