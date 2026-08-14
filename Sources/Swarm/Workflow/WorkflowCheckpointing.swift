import Foundation

/// Retention policy for file-backed durable workflow checkpoints.
///
/// The file store keeps the newest `maxCheckpointsPerRun` checkpoints per
/// durable run (checkpoint ID / Hive thread) and records them in a manifest so
/// loads do not scan or decode the entire directory.
public struct WorkflowCheckpointRetention: Sendable, Equatable {
    /// Default policy: keep the 16 newest checkpoints per run.
    public static let `default` = WorkflowCheckpointRetention(maxCheckpointsPerRun: 16)

    /// Maximum number of checkpoints retained for a single durable run.
    ///
    /// Values below 1 are clamped to 1.
    public var maxCheckpointsPerRun: Int

    /// Creates a keep-latest-N retention policy.
    ///
    /// - Parameter maxCheckpointsPerRun: Number of newest checkpoints to keep
    ///   per run. Defaults to 16.
    public init(maxCheckpointsPerRun: Int = 16) {
        self.maxCheckpointsPerRun = max(1, maxCheckpointsPerRun)
    }
}

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
    ///
    /// Checkpoints are pruned to ``WorkflowCheckpointRetention/maxCheckpointsPerRun``
    /// per durable run. Loads consult a directory manifest instead of decoding
    /// every file.
    ///
    /// - Parameters:
    ///   - directory: Directory that stores checkpoint JSON files and the manifest.
    ///   - retention: Keep-latest-N policy. Defaults to 16 checkpoints per run.
    public static func fileSystem(
        directory: URL,
        retention: WorkflowCheckpointRetention = .default
    ) -> WorkflowCheckpointing {
        IntegrationsTrait.warnIfUnavailable(
            feature: "Durable workflow checkpointing",
            logger: Log.orchestration
        )
        #if SWARM_INTEGRATIONS
        return WorkflowCheckpointing(
            backend: WorkflowFileCheckpointStore(directory: directory, retention: retention)
        )
        #else
        return WorkflowCheckpointing()
        #endif
    }

    #if SWARM_INTEGRATIONS
    /// Testing hook that injects a file operator for load/scan assertions.
    static func fileSystem(
        directory: URL,
        retention: WorkflowCheckpointRetention = .default,
        files: any WorkflowCheckpointFileOperating
    ) -> WorkflowCheckpointing {
        WorkflowCheckpointing(
            backend: WorkflowFileCheckpointStore(
                directory: directory,
                retention: retention,
                files: files
            )
        )
    }
    #endif
}
