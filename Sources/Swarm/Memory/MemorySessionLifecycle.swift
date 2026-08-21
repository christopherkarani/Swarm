import Foundation

/// Optional lifecycle observer for memory implementations that need session scoping.
///
/// This is primarily used by persistent, single-file memories (e.g. Wax) to tag
/// ingested content per agent run without exposing storage-specific APIs to agents.
public protocol MemorySessionLifecycle: Memory {
    /// Called at the beginning of an agent `run` / `stream`.
    func beginMemorySession() async

    /// Called at the end of an agent `run` / `stream` (success or failure).
    func endMemorySession() async
}

/// Optional hook for memories that want custom handling when session history is replayed
/// into a fresh memory instance.
public protocol MemorySessionReplayAware: Memory {
    /// Imports a batch of session history messages using memory-specific logic.
    func importSessionHistory(_ messages: [MemoryMessage]) async
}

public extension Memory {
    /// Seeds prior session messages into memory when the memory is eligible and still needs replay.
    func seedSessionHistoryIfNeeded(_ messages: [MemoryMessage]) async {
        guard !messages.isEmpty else {
            return
        }

        let hooks = MemoryHooks.resolved(from: self)
        guard hooks.allowsAutomaticSessionSeeding else {
            return
        }

        let shouldSeed = if let shouldImport = hooks.shouldImportSessionHistory {
            await shouldImport()
        } else {
            await isEmpty
        }
        guard shouldSeed else {
            return
        }

        if let importHistory = hooks.importSessionHistory {
            await importHistory(messages)
        } else {
            for message in messages {
                await add(message)
            }
        }
    }
}

/// Internal hook for composite memories that contain the agent's default memory
/// as one layer. The agent runtime uses this to preserve the default memory's
/// per-session clearing and serialization behavior without clearing static
/// memory layers such as workspace context.
protocol MemorySessionTrackingProvider: Sendable {
    var trackedSessionMemory: (any Memory)? { get }
}

/// Internal hook for memories that need per-layer control over when session
/// replay should be imported.
protocol MemorySessionSeedControlling: Memory {
    func shouldImportSessionHistory() async -> Bool
}
