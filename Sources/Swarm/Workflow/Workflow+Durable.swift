import Foundation

public extension Workflow {
    /// Namespaced access to durable workflow APIs.
    var durable: Durable { Durable(workflow: self) }

    struct Durable: Sendable {
        fileprivate let workflow: Workflow

        /// Whether the durable Hive engine is linked in this build.
        ///
        /// Configuration APIs (``configured(id:store:policy:)``, ``checkpoint(id:policy:)``,
        /// ``checkpointing(_:)``) still type-check on lean builds.
        /// ``DurableWorkflow/execute(_:)`` and ``execute(_:resumeFrom:)`` throw when
        /// checkpointing is configured until you rebuild with `--traits Integrations`.
        public static var isAvailable: Bool {
            IntegrationsTrait.isEnabled
        }

        public enum CheckpointPolicy: Sendable {
            case onCompletion
            case everyStep
        }

        /// Enables workflow checkpointing for this workflow.
        @available(*, deprecated, message: "Use configured(id:store:policy:) to build a DurableWorkflow.")
        public func checkpoint(id: String, policy: CheckpointPolicy = .onCompletion) -> Workflow {
            IntegrationsTrait.warnIfUnavailable(
                feature: "Durable workflow checkpointing",
                logger: Log.orchestration
            )
            var copy = workflow
            copy.advancedConfiguration.checkpoint = Workflow.CheckpointConfiguration(
                id: id,
                policy: policy
            )
            return copy
        }

        /// Configures checkpoint persistence for durable workflow execution.
        @available(*, deprecated, message: "Use configured(id:store:policy:) to build a DurableWorkflow.")
        public func checkpointing(_ checkpointing: WorkflowCheckpointing) -> Workflow {
            IntegrationsTrait.warnIfUnavailable(
                feature: "Durable workflow checkpointing",
                logger: Log.orchestration
            )
            var copy = workflow
            copy.advancedConfiguration.checkpointing = checkpointing
            return copy
        }

        /// Builds a fully configured durable workflow with checkpoint identity and persistence.
        public func configured(
            id: WorkflowCheckpointID,
            store: WorkflowCheckpointing,
            policy: CheckpointPolicy = .onCompletion
        ) -> DurableWorkflow {
            IntegrationsTrait.warnIfUnavailable(
                feature: "Durable workflow checkpointing",
                logger: Log.orchestration
            )
            return DurableWorkflow(
                workflow: workflow,
                checkpointID: id,
                checkpointing: store,
                policy: policy
            )
        }

        /// Adds a workflow-level fallback step.
        @available(*, deprecated, message: "Use Workflow.fallback(primary:to:retries:) instead.")
        public func fallback(
            primary: some AgentRuntime,
            to backup: some AgentRuntime,
            retries: Int = 0
        ) -> Workflow {
            workflow.fallback(primary: primary, to: backup, retries: retries)
        }

        /// Executes a durable workflow, optionally resuming from a checkpoint ID.
        @available(*, deprecated, message: "Use DurableWorkflow.execute(_:) or DurableWorkflow.resume(_:from:).")
        public func execute(_ input: String, resumeFrom checkpointID: String? = nil) async throws -> AgentResult {
            try await workflow.executeDurable(input, resumeFrom: checkpointID)
        }

        /// Backward-compatible alias for `execute(_:resumeFrom:)`.
        @available(*, deprecated, renamed: "execute(_:resumeFrom:)")
        public func run(_ input: String, resumeFrom checkpointID: String? = nil) async throws -> AgentResult {
            try await execute(input, resumeFrom: checkpointID)
        }

    }
}

extension Workflow {
    func executeDurableConfigured(
        input: String,
        checkpointID: WorkflowCheckpointID,
        checkpointing: WorkflowCheckpointing,
        policy: Workflow.Durable.CheckpointPolicy,
        resume: Bool
    ) async throws -> AgentResult {
        #if SWARM_INTEGRATIONS
        if resume {
            guard try await checkpointing.containsCheckpoint(for: checkpointID.rawValue) else {
                throw WorkflowError.checkpointNotFound(id: checkpointID.rawValue)
            }
        }

        WorkflowDurableIdentity.warnIfUsingImplicitIdentity(self)

        let engine = WorkflowDurableEngine(
            workflow: self,
            checkpointing: checkpointing,
            checkpointID: checkpointID.rawValue,
            policy: policy,
            resume: resume
        )

        return try await executeWithTimeout {
            try await engine.run(startInput: input)
        }
        #else
        throw WorkflowError.durableRuntimeUnavailable(
            reason: IntegrationsTrait.requirementMessage(for: "Durable workflow execution")
        )
        #endif
    }

    func executeDurable(_ input: String, resumeFrom checkpointID: String?) async throws -> AgentResult {
        #if SWARM_INTEGRATIONS
        guard let checkpoint = advancedConfiguration.checkpoint else {
            if checkpointID != nil {
                throw WorkflowError.invalidWorkflow(
                    reason: "Cannot resume a workflow without durable checkpoint configuration"
                )
            }
            return try await executeWithTimeout {
                try await executeDirect(input: input)
            }
        }

        guard let checkpointing = advancedConfiguration.checkpointing else {
            throw WorkflowError.checkpointStoreRequired
        }

        let resolvedCheckpointID = checkpointID ?? checkpoint.id
        if checkpointID != nil {
            guard try await checkpointing.containsCheckpoint(for: resolvedCheckpointID) else {
                throw WorkflowError.checkpointNotFound(id: resolvedCheckpointID)
            }
        }

        WorkflowDurableIdentity.warnIfUsingImplicitIdentity(self)

        let engine = WorkflowDurableEngine(
            workflow: self,
            checkpointing: checkpointing,
            checkpointID: resolvedCheckpointID,
            policy: checkpoint.policy,
            resume: checkpointID != nil
        )

        return try await executeWithTimeout {
            try await engine.run(startInput: input)
        }
        #else
        if checkpointID != nil || advancedConfiguration.checkpoint != nil || advancedConfiguration.checkpointing != nil {
            throw WorkflowError.durableRuntimeUnavailable(
                reason: IntegrationsTrait.requirementMessage(for: "Durable workflow execution")
            )
        }
        return try await executeWithTimeout {
            try await executeDirect(input: input)
        }
        #endif
    }
}

enum WorkflowDurableIdentity {
    static let implicitIdentityWarning = """
        Durable workflow uses implicit step identity (kind + position). \
        Source fileID:line is no longer part of resume matching. Pass signature: \
        on route, repeatUntil, and custom merge when those closures change.
        """

    static func warnIfUsingImplicitIdentity(_ workflow: Workflow) {
        guard workflow.usesImplicitOpaqueIdentity else { return }
        if WorkflowDurableIdentityRecorder.shared.record() {
            Log.orchestration.warning("\(implicitIdentityWarning)")
        }
    }
}

enum WorkflowDurableIdentityTesting {
    static var warningCount: Int {
        WorkflowDurableIdentityRecorder.shared.count
    }

    static func reset() {
        WorkflowDurableIdentityRecorder.shared.reset()
    }
}

private final class WorkflowDurableIdentityRecorder: @unchecked Sendable {
    static let shared = WorkflowDurableIdentityRecorder()
    private let lock = NSLock()
    private var didWarn = false
    private var recordedCount = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedCount
    }

    func record() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didWarn else { return false }
        didWarn = true
        recordedCount += 1
        return true
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        didWarn = false
        recordedCount = 0
    }
}
