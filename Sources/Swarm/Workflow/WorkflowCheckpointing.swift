import Foundation

/// Checkpoint persistence configuration for advanced workflows.
public struct WorkflowCheckpointing: Sendable {
    /// Whether durable checkpoint stores are linked in this build.
    ///
    /// Lean builds still type-check these factories so workflow graphs compile, but
    /// ``Workflow/Durable/execute(_:resumeFrom:)`` throws until you rebuild with
    /// `--traits Integrations` (or add `traits: ["Integrations"]` to the Swarm
    /// package dependency).
    public static var isAvailable: Bool {
        IntegrationsTrait.isEnabled
    }

    #if SWARM_INTEGRATIONS
    let backend: any WorkflowDurableCheckpointStore

    init(backend: some WorkflowDurableCheckpointStore) {
        self.backend = backend
    }
    #else
    init() {}
    #endif

    /// In-memory checkpoint persistence.
    public static func inMemory() -> WorkflowCheckpointing {
        IntegrationsTrait.warnIfUnavailable(
            feature: "Durable workflow checkpointing",
            logger: Log.orchestration
        )
        #if SWARM_INTEGRATIONS
        return WorkflowCheckpointing(backend: WorkflowInMemoryCheckpointStore())
        #else
        return WorkflowCheckpointing()
        #endif
    }

    /// File-system checkpoint persistence rooted at `directory`.
    public static func fileSystem(directory: URL) -> WorkflowCheckpointing {
        IntegrationsTrait.warnIfUnavailable(
            feature: "Durable workflow checkpointing",
            logger: Log.orchestration
        )
        #if SWARM_INTEGRATIONS
        return WorkflowCheckpointing(backend: WorkflowFileCheckpointStore(directory: directory))
        #else
        return WorkflowCheckpointing()
        #endif
    }
}
