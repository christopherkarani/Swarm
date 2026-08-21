import Foundation

/// Package-internal optional memory behavior, resolved from public marker protocols.
///
/// Agent and ``CompositeMemory`` read this value instead of probing `as?` / `as AnyObject`.
/// ``resolved(from:)`` is the compatibility shim: it is the only site that may cast the
/// public marker protocols (and the package-internal tracking / seed controllers).
///
/// Memories that do not conform to a marker produce ``empty`` hooks for that capability
/// (session begin/end is a no-op, retrieval falls back to ``Memory/context(for:tokenLimit:)``).
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

    /// Fills hooks from public marker protocols and package-internal controllers.
    ///
    /// This is the only remaining `as?` pyramid for optional memory behavior.
    static func resolved(from memory: any Memory) -> MemoryHooks {
        var hooks = MemoryHooks.empty

        if let lifecycle = memory as? any MemorySessionLifecycle {
            hooks.beginMemorySession = {
                await lifecycle.beginMemorySession()
            }
            hooks.endMemorySession = {
                await lifecycle.endMemorySession()
            }
        }

        if let policyAware = memory as? any MemoryRetrievalPolicyAware {
            hooks.contextForQuery = { query in
                await policyAware.context(for: query)
            }
        }

        if let descriptor = memory as? any MemoryPromptDescriptor {
            hooks.memoryPromptTitle = descriptor.memoryPromptTitle
            hooks.memoryPromptGuidance = descriptor.memoryPromptGuidance
            hooks.memoryPriority = descriptor.memoryPriority
        }

        if let trackingProvider = memory as? any MemorySessionTrackingProvider {
            hooks.trackedSessionMemory = trackingProvider.trackedSessionMemory
        }

        if let importPolicy = memory as? any MemorySessionImportPolicy {
            hooks.allowsAutomaticSessionSeeding = importPolicy.allowsAutomaticSessionSeeding
        }

        if let seedController = memory as? any MemorySessionSeedControlling {
            hooks.shouldImportSessionHistory = {
                await seedController.shouldImportSessionHistory()
            }
        }

        if let replayAware = memory as? any MemorySessionReplayAware {
            hooks.importSessionHistory = { messages in
                await replayAware.importSessionHistory(messages)
            }
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
    return MemoryHooks.resolved(from: activeMemory).trackedSessionMemory
}
