import Foundation

/// Optional lifecycle observer for memory implementations that need session scoping.
///
/// ``Memory`` now includes ``Memory/beginMemorySession()`` and
/// ``Memory/endMemorySession()`` with no-op defaults. This marker remains for
/// source compatibility.
@available(*, deprecated, message: "beginMemorySession/endMemorySession are defaulted Memory requirements")
public protocol MemorySessionLifecycle: Memory {}

/// Optional hook for memories that want custom handling when session history is replayed
/// into a fresh memory instance.
@available(*, deprecated, message: "importSessionHistory is a defaulted Memory requirement")
public protocol MemorySessionReplayAware: Memory {}

public extension Memory {
    /// Seeds prior session messages into memory when the memory is eligible and still needs replay.
    func seedSessionHistoryIfNeeded(_ messages: [MemoryMessage]) async {
        guard !messages.isEmpty else {
            return
        }

        guard allowsAutomaticSessionSeeding else {
            return
        }

        guard await shouldImportSessionHistory() else {
            return
        }

        await importSessionHistory(messages)
    }
}
