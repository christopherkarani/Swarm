import Foundation

/// Package-internal snapshot of a memory's optional capabilities.
///
/// Agent and ``CompositeMemory`` read this value instead of probing memory
/// types at runtime. Every capability is a defaulted ``Memory`` requirement,
/// so ``resolved(from:)`` is pure witness dispatch: memories that do not
/// implement a capability resolve to hooks wrapping the protocol defaults
/// (session begin/end is a no-op, retrieval falls back to
/// ``Memory/context(for:tokenLimit:)``).
///
/// - Note: `MemoryHooks` is not part of the public API. Generated `@AgentActor` `run()`
///   still uses ``MemorySessionLifecycle`` directly so consumer modules can compile.
package struct MemoryHooks: Sendable {
    var beginMemorySession: (@Sendable () async -> Void)?
    var endMemorySession: (@Sendable () async -> Void)?
    var contextForQuery: (@Sendable (MemoryQuery) async -> String)?
    var memoryPromptTitle: String?
    var memoryPromptGuidance: String?
    var memoryPriority: MemoryPriorityHint?
    var trackedSessionMemory: (any Memory)?
    var allowsAutomaticSessionSeeding: Bool
    var shouldImportSessionHistory: (@Sendable () async -> Bool)?
    var importSessionHistory: (@Sendable ([MemoryMessage]) async -> Void)?

    init(
        beginMemorySession: (@Sendable () async -> Void)? = nil,
        endMemorySession: (@Sendable () async -> Void)? = nil,
        contextForQuery: (@Sendable (MemoryQuery) async -> String)? = nil,
        memoryPromptTitle: String? = nil,
        memoryPromptGuidance: String? = nil,
        memoryPriority: MemoryPriorityHint? = nil,
        trackedSessionMemory: (any Memory)? = nil,
        allowsAutomaticSessionSeeding: Bool = true,
        shouldImportSessionHistory: (@Sendable () async -> Bool)? = nil,
        importSessionHistory: (@Sendable ([MemoryMessage]) async -> Void)? = nil
    ) {
        self.beginMemorySession = beginMemorySession
        self.endMemorySession = endMemorySession
        self.contextForQuery = contextForQuery
        self.memoryPromptTitle = memoryPromptTitle
        self.memoryPromptGuidance = memoryPromptGuidance
        self.memoryPriority = memoryPriority
        self.trackedSessionMemory = trackedSessionMemory
        self.allowsAutomaticSessionSeeding = allowsAutomaticSessionSeeding
        self.shouldImportSessionHistory = shouldImportSessionHistory
        self.importSessionHistory = importSessionHistory
    }
}

package extension MemoryHooks {
    static let empty = MemoryHooks()

    /// Snapshots a memory's capabilities through defaulted `Memory` witnesses.
    ///
    /// Synchronously readable requirements (prompt metadata, tracking, seeding
    /// policy) are captured eagerly; asynchronous ones are wrapped into
    /// `@Sendable` closures that forward to the witness.
    static func resolved(from memory: any Memory) -> MemoryHooks {
        var hooks = MemoryHooks.empty

        let metadata = memory.memoryPromptMetadata
        hooks.memoryPromptTitle = metadata?.title
        hooks.memoryPromptGuidance = metadata?.guidance
        hooks.memoryPriority = metadata?.priority
        hooks.trackedSessionMemory = memory.trackedSessionMemory
        hooks.allowsAutomaticSessionSeeding = memory.allowsAutomaticSessionSeeding

        hooks.beginMemorySession = { await memory.beginMemorySession() }
        hooks.endMemorySession = { await memory.endMemorySession() }
        hooks.contextForQuery = { query in
            await memory.context(for: query)
        }
        hooks.shouldImportSessionHistory = {
            await memory.shouldImportSessionHistory()
        }
        hooks.importSessionHistory = { messages in
            await memory.importSessionHistory(messages)
        }

        return hooks
    }
}

/// Stable identity for actor-backed ``Memory`` existentials.
///
/// Prefer this over `as AnyObject` / `===` when comparing memory instances.
package func memoryObjectIdentifier(_ memory: any Memory) -> ObjectIdentifier {
    ObjectIdentifier(memory)
}

package func memoriesAreSameInstance(_ lhs: any Memory, _ rhs: any Memory) -> Bool {
    memoryObjectIdentifier(lhs) == memoryObjectIdentifier(rhs)
}

/// Session-isolation handle used by Agent: the default memory itself, or a composite's tracked layer.
package func resolvedTrackedSessionMemory(
    from activeMemory: any Memory,
    defaultMemory: (any Memory)?
) -> (any Memory)? {
    if let defaultMemory, memoriesAreSameInstance(activeMemory, defaultMemory) {
        return defaultMemory
    }
    return activeMemory.trackedSessionMemory
}
