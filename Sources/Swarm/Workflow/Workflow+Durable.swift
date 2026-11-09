import Foundation

public extension Workflow {
    /// Namespaced access to durable workflow APIs.
    var durable: Durable { Durable(workflow: self) }

    struct Durable: Sendable {
        fileprivate let workflow: Workflow

        /// Whether the durable Hive engine is linked in this build.
        ///
        /// ``configured(id:store:policy:)`` still type-checks on lean builds.
        /// ``DurableWorkflow/execute(_:)`` and ``DurableWorkflow/resume(_:from:)``
        /// throw until you rebuild with `--traits Integrations`.
        public static var isAvailable: Bool {
            IntegrationsTrait.isEnabled
        }

        public enum CheckpointPolicy: Sendable {
            case onCompletion
            case everyStep
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
    }
}

extension Workflow {
    /// Runs one durable entry under this workflow's timeout.
    ///
    /// The engine classifies the latest checkpoint once and decides from it;
    /// this wrapper only builds the engine.
    func executeDurable(
        _ entry: WorkflowDurableEntry,
        checkpointID: WorkflowCheckpointID,
        checkpointing: WorkflowCheckpointing,
        policy: Workflow.Durable.CheckpointPolicy
    ) async throws -> AgentResult {
        #if SWARM_INTEGRATIONS
        WorkflowDurableIdentity.warnIfUsingImplicitIdentity(self)

        let engine = WorkflowDurableEngine(
            workflow: self,
            checkpointing: checkpointing,
            checkpointID: checkpointID.rawValue,
            policy: policy
        )

        return try await executeWithTimeout {
            try await engine.run(entry)
        }
        #else
        let feature = switch entry {
        case .decide: "Durable workflow approval resume"
        case .start, .resume: "Durable workflow execution"
        }
        throw WorkflowError.durableRuntimeUnavailable(
            reason: IntegrationsTrait.requirementMessage(for: feature)
        )
        #endif
    }

    func executeDurableFork(
        input: String,
        sourceRun: WorkflowCheckpointID,
        sourceCheckpointID: String,
        targetRun: WorkflowCheckpointID,
        checkpointing: WorkflowCheckpointing,
        policy: Workflow.Durable.CheckpointPolicy
    ) async throws -> AgentResult {
        #if SWARM_INTEGRATIONS
        let history = try await checkpointing.history(for: sourceRun.rawValue)
        guard history.contains(where: { $0.id.rawValue == sourceCheckpointID }) else {
            throw WorkflowError.checkpointNotFound(id: sourceRun.rawValue)
        }
        if try await checkpointing.containsCheckpoint(for: targetRun.rawValue) {
            throw WorkflowError.invalidWorkflow(
                reason: "Cannot fork into run '\(targetRun.rawValue)' because it already has checkpoints"
            )
        }

        WorkflowDurableIdentity.warnIfUsingImplicitIdentity(self)

        let fork = WorkflowDurableFork(
            workflow: self,
            checkpointing: checkpointing,
            sourceRun: sourceRun,
            sourceCheckpointID: sourceCheckpointID,
            targetRun: targetRun,
            policy: policy
        )
        return try await executeWithTimeout {
            try await fork.run(startInput: input)
        }
        #else
        throw WorkflowError.durableRuntimeUnavailable(
            reason: IntegrationsTrait.requirementMessage(for: "Durable workflow fork")
        )
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
