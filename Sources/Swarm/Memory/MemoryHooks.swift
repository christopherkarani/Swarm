import Foundation

/// Package-internal optional memory behavior, resolved from ``Memory``.
///
/// Agent and ``CompositeMemory`` can read this value instead of probing `as?` /
/// `as AnyObject`. ``resolved(from:)`` wraps defaulted ``Memory`` requirements so
/// missing overrides are no-ops rather than skipped layers.
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

    /// Fills hooks from defaulted ``Memory`` requirements.
    ///
    /// Marker protocols remain for source compatibility. Behavior is no longer
    /// recovered with `as?`; missing overrides use the protocol defaults.
    static func resolved(from memory: any Memory) -> MemoryHooks {
        MemoryHooks(
            beginMemorySession: {
                await memory.beginMemorySession()
            },
            endMemorySession: {
                await memory.endMemorySession()
            },
            contextForQuery: { query in
                await memory.context(for: query)
            },
            memoryPromptTitle: memory.memoryPromptTitle,
            memoryPromptGuidance: memory.memoryPromptGuidance,
            memoryPriority: memory.memoryPriority,
            trackedSessionMemory: memory.trackedSessionMemory,
            allowsAutomaticSessionSeeding: memory.allowsAutomaticSessionSeeding,
            shouldImportSessionHistory: {
                await memory.shouldImportSessionHistory()
            },
            importSessionHistory: { messages in
                await memory.importSessionHistory(messages)
            }
        )
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
    return MemoryHooks.resolved(from: activeMemory).trackedSessionMemory
}
