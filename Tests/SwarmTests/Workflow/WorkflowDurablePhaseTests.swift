#if SWARM_INTEGRATIONS
import Foundation
import HiveCore
@testable import Swarm
import Testing

/// AC-005 coverage for the durable workflow phase enum.
///
/// Invariant note: an invalid combination such as "completed with pending
/// cursors" cannot be expressed in the current encoding by construction — the
/// cursors exist only as associated values of `.running`, while `.completed`
/// carries exclusively its result snapshot. The legacy-fixture tests below pin
/// that migration folds the old parallel channels into exactly one phase case,
/// never both.
@Suite("Workflow durable phase")
struct WorkflowDurablePhaseTests {
    // MARK: - Round trip

    @Test("phase survives encode-decode round trip and resumes to the same result")
    func phaseRoundTripsAndResumesToSameResult() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let log = ExecutionLog()
        let checkpointing = WorkflowCheckpointing.fileSystem(directory: directory)
        let workflow = makeLinearWorkflow(log: log, checkpointing: checkpointing, checkpointID: "wf-roundtrip")

        let first = try await workflow.durable.execute("start")
        #expect(first.output == "C")

        let store = WorkflowFileCheckpointStore(directory: directory)
        let checkpoint = try await requireLatestCheckpoint(from: store, threadID: HiveThreadID("wf-roundtrip"))

        // The persisted phase payload decodes back to the terminal state and,
        // under the deterministic sorted-keys codec, re-encodes byte-identically.
        let phaseData = try requireChannelData(
            checkpoint.globalDataByChannelID[WorkflowDurableSchema.phaseKey.id.rawValue],
            channel: "workflow.phase"
        )
        let phase = try JSONDecoder().decode(WorkflowDurablePhase.self, from: phaseData)
        guard case .completed(let snapshot) = phase else {
            Issue.record("expected terminal phase, got \(phase)")
            return
        }
        #expect(snapshot.output == "C")
        #expect(try WorkflowCheckpointCodec<WorkflowDurablePhase>().encode(phase) == phaseData)

        let resumed = try await workflow.durable.execute("ignored", resumeFrom: "wf-roundtrip")
        #expect(resumed.output == "C")

        // Resuming a completed run must end at the router without re-running steps.
        let counts = await log.counts
        #expect(counts["A"] == 1)
        #expect(counts["B"] == 1)
        #expect(counts["C"] == 1)
    }

    @Test("mid-run checkpoint encodes a running phase and resumes with step granularity")
    func midRunCheckpointEncodesRunningPhase() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let log = ExecutionLog()
        let checkpointing = WorkflowCheckpointing.fileSystem(directory: directory)
        let controller = WorkflowDurableFaultController(queue: [.afterCheckpointWrite])

        try await WorkflowDurableFaultInjection.$controller.withValue(controller) {
            do {
                _ = try await makeLinearWorkflow(log: log, checkpointing: checkpointing, checkpointID: "wf-midrun")
                    .durable.execute("start")
                Issue.record("expected injected fault")
            } catch let fault as WorkflowDurableInjectedFault {
                #expect(fault.point == .afterCheckpointWrite)
            }
        }

        // Inspect the raw persisted bytes before resuming.
        let store = WorkflowFileCheckpointStore(directory: directory)
        let checkpoint = try await requireLatestCheckpoint(from: store, threadID: HiveThreadID("wf-midrun"))
        let phaseData = try requireChannelData(
            checkpoint.globalDataByChannelID[WorkflowDurableSchema.phaseKey.id.rawValue],
            channel: "workflow.phase"
        )
        let phase = try JSONDecoder().decode(WorkflowDurablePhase.self, from: phaseData)
        guard case .running(let stepCursor, let iterationCursor, let lastResult) = phase else {
            Issue.record("expected running phase, got \(phase)")
            return
        }
        #expect(stepCursor == 1)
        #expect(iterationCursor == 0)
        #expect(lastResult?.output == "A")

        let resumed = try await makeLinearWorkflow(log: log, checkpointing: checkpointing, checkpointID: "wf-midrun")
            .durable.execute("ignored", resumeFrom: "wf-midrun")
        #expect(resumed.output == "C")

        let counts = await log.counts
        #expect(counts["A"] == 1)
        #expect(counts["B"] == 1)
        #expect(counts["C"] == 1)
    }

    // MARK: - Legacy migration

    @Test("legacy completed checkpoint migrates and never re-runs steps")
    func legacyCompletedCheckpointMigrates() async throws {
        let backend = WorkflowInMemoryCheckpointStore()
        let checkpointing = WorkflowCheckpointing(backend: backend)
        let log = ExecutionLog()
        let workflow = makeTwoStepWorkflow(log: log, checkpointing: checkpointing, checkpointID: "wf-legacy-done")

        let fixture = legacyCheckpoint(threadID: "wf-legacy-done", signature: workflow.workflowSignature) {
            $0["workflow.completed"] = encodedJSON(true)
            $0["workflow.stepCursor"] = encodedJSON(0)
            $0["workflow.iterationCursor"] = encodedJSON(0)
            $0["workflow.lastResult"] = encodedJSON(Optional<WorkflowResultSnapshot>.none)
            $0["workflow.currentInput"] = encodedJSON("seed")
        }
        try await backend.save(fixture)

        let result = try await workflow.durable.execute("ignored", resumeFrom: "wf-legacy-done")
        // Spec section 9 edge case: {"completed": true, "stepCursor": 0} decodes
        // to .completed — never .running — so no step executes again and the
        // synthesized snapshot falls back to the persisted current input.
        #expect(result.output == "seed")

        let counts = await log.counts
        #expect(counts["A"] == nil)
        #expect(counts["B"] == nil)

        // The flushed post-migration state persists the phase channel only; no
        // legacy cursor/completed channels survive migration.
        let checkpoint = try await requireLatestCheckpoint(
            from: checkpointing.runtimeStore,
            threadID: HiveThreadID("wf-legacy-done")
        )
        #expect(checkpoint.globalDataByChannelID["workflow.completed"] == nil)
        #expect(checkpoint.globalDataByChannelID["workflow.stepCursor"] == nil)
        let phaseData = try requireChannelData(
            checkpoint.globalDataByChannelID[WorkflowDurableSchema.phaseKey.id.rawValue],
            channel: "workflow.phase"
        )
        guard case .completed(let migratedSnapshot)? = try? JSONDecoder()
            .decode(WorkflowDurablePhase?.self, from: phaseData) else {
            Issue.record("expected migrated phase to be completed")
            return
        }
        #expect(migratedSnapshot.output == "seed")
    }

    @Test("legacy completed checkpoint with residual cursors folds to completed with its snapshot")
    func legacyCompletedWithResidualCursorsFoldsToCompleted() async throws {
        let backend = WorkflowInMemoryCheckpointStore()
        let checkpointing = WorkflowCheckpointing(backend: backend)
        let log = ExecutionLog()
        let workflow = makeTwoStepWorkflow(log: log, checkpointing: checkpointing, checkpointID: "wf-legacy-done-cursors")

        let fixture = legacyCheckpoint(threadID: "wf-legacy-done-cursors", signature: workflow.workflowSignature) {
            $0["workflow.completed"] = encodedJSON(true)
            $0["workflow.stepCursor"] = encodedJSON(1)
            $0["workflow.iterationCursor"] = encodedJSON(1)
            $0["workflow.lastResult"] = encodedJSON(Optional(WorkflowResultSnapshot(AgentResult(output: "B-out"))))
            $0["workflow.currentInput"] = encodedJSON("residual-input")
        }
        try await backend.save(fixture)

        let result = try await workflow.durable.execute("ignored", resumeFrom: "wf-legacy-done-cursors")
        // Completion wins over residual cursors: the fold must never produce
        // .running, and the persisted snapshot — not the input-text fallback —
        // becomes the result.
        #expect(result.output == "B-out")

        let counts = await log.counts
        #expect(counts["A"] == nil)
        #expect(counts["B"] == nil)
    }

    @Test("legacy running checkpoint migrates cursors and finishes remaining steps")
    func legacyRunningCheckpointMigratesAndContinues() async throws {
        let backend = WorkflowInMemoryCheckpointStore()
        let checkpointing = WorkflowCheckpointing(backend: backend)
        let log = ExecutionLog()
        let workflow = makeTwoStepWorkflow(log: log, checkpointing: checkpointing, checkpointID: "wf-legacy-running")

        let fixture = legacyCheckpoint(threadID: "wf-legacy-running", signature: workflow.workflowSignature) {
            $0["workflow.completed"] = encodedJSON(false)
            $0["workflow.stepCursor"] = encodedJSON(1)
            $0["workflow.iterationCursor"] = encodedJSON(0)
            $0["workflow.lastResult"] = encodedJSON(Optional(WorkflowResultSnapshot(AgentResult(output: "A-out"))))
            $0["workflow.currentInput"] = encodedJSON("A-out")
        }
        try await backend.save(fixture)

        let result = try await workflow.durable.execute("ignored", resumeFrom: "wf-legacy-running")
        #expect(result.output == "B-out")

        let counts = await log.counts
        #expect(counts["A"] == nil)
        #expect(counts["B"] == 1)
    }

    @Test("legacy file-backed checkpoint fixture decodes and migrates")
    func legacyFileBackedFixtureMigrates() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let checkpointing = WorkflowCheckpointing.fileSystem(directory: directory)
        let workflow = makeTwoStepWorkflow(checkpointing: checkpointing, checkpointID: "wf-legacy-file")

        let fixture = legacyCheckpoint(threadID: "wf-legacy-file", signature: workflow.workflowSignature) {
            $0["workflow.completed"] = encodedJSON(false)
            $0["workflow.stepCursor"] = encodedJSON(0)
            $0["workflow.iterationCursor"] = encodedJSON(0)
            $0["workflow.lastResult"] = encodedJSON(Optional<WorkflowResultSnapshot>.none)
            $0["workflow.currentInput"] = encodedJSON("start")
        }
        let fileName = "workflow-wf-legacy-file-legacy-cp.json"
        try JSONEncoder().encode(fixture).write(to: directory.appendingPathComponent(fileName))
        let manifest = WorkflowCheckpointManifest(
            version: 1,
            runs: [
                "wf-legacy-file": [
                    WorkflowCheckpointManifestEntry(
                        checkpointID: "legacy-cp",
                        stepIndex: 0,
                        fileName: fileName
                    )
                ]
            ]
        )
        try JSONEncoder().encode(manifest)
            .write(to: directory.appendingPathComponent(WorkflowFileCheckpointStore.manifestFileName))

        let result = try await workflow.durable.execute("ignored", resumeFrom: "wf-legacy-file")
        #expect(result.output == "B-out")
    }

    @Test("checkpoints without the legacy discriminator pass through and fail version matching")
    func unknownFormatPassesThroughToVersionMismatch() async throws {
        let backend = WorkflowInMemoryCheckpointStore()
        let checkpointing = WorkflowCheckpointing(backend: backend)
        let workflow = makeTwoStepWorkflow(checkpointing: checkpointing, checkpointID: "wf-unknown-format")

        // Mismatched schema versions but no legacy discriminator channel: the
        // migrator must not guess at an unknown layout.
        let fixture = legacyCheckpoint(threadID: "wf-unknown-format", signature: workflow.workflowSignature) { _ in }
        try await backend.save(fixture)

        do {
            _ = try await workflow.durable.execute("ignored", resumeFrom: "wf-unknown-format")
            Issue.record("expected version mismatch")
        } catch let error as HiveRuntimeError {
            guard case .checkpointVersionMismatch(let expectedSchema, _, let foundSchema, _) = error else {
                Issue.record("unexpected HiveRuntimeError \(error)")
                return
            }
            #expect(foundSchema == "legacy-pre-phase-enum-schema")
            #expect(expectedSchema != foundSchema)
        }
    }

    @Test("corrupt legacy payload fails resume instead of fabricating state")
    func corruptLegacyPayloadFailsLoudly() async throws {
        let backend = WorkflowInMemoryCheckpointStore()
        let checkpointing = WorkflowCheckpointing(backend: backend)
        let log = ExecutionLog()
        let workflow = makeTwoStepWorkflow(log: log, checkpointing: checkpointing, checkpointID: "wf-legacy-corrupt")

        let fixture = legacyCheckpoint(threadID: "wf-legacy-corrupt", signature: workflow.workflowSignature) {
            $0["workflow.completed"] = encodedJSON(false)
            $0["workflow.lastResult"] = Data("not-json".utf8)
            $0["workflow.currentInput"] = encodedJSON("seed")
        }
        try await backend.save(fixture)

        do {
            _ = try await workflow.durable.execute("ignored", resumeFrom: "wf-legacy-corrupt")
            Issue.record("expected decode failure")
        } catch is DecodingError {
            // Expected: present-but-undecodable legacy entries fail loudly.
        }

        let counts = await log.counts
        #expect(counts.isEmpty)
    }

    @Test("tampered negative stepCursor fails resume with a typed error instead of trapping")
    func negativeStepCursorFailsResumeWithTypedError() async throws {
        let backend = WorkflowInMemoryCheckpointStore()
        let checkpointing = WorkflowCheckpointing(backend: backend)
        let log = ExecutionLog()
        let workflow = makeTwoStepWorkflow(log: log, checkpointing: checkpointing, checkpointID: "wf-legacy-negative-step")

        let fixture = legacyCheckpoint(threadID: "wf-legacy-negative-step", signature: workflow.workflowSignature) {
            $0["workflow.completed"] = encodedJSON(false)
            $0["workflow.stepCursor"] = encodedJSON(-1)
            $0["workflow.iterationCursor"] = encodedJSON(0)
            $0["workflow.lastResult"] = encodedJSON(Optional<WorkflowResultSnapshot>.none)
            $0["workflow.currentInput"] = encodedJSON("seed")
        }
        try await backend.save(fixture)

        do {
            _ = try await workflow.durable.execute("ignored", resumeFrom: "wf-legacy-negative-step")
            Issue.record("expected invalid-workflow error")
        } catch let error as WorkflowError {
            guard case .invalidWorkflow(let reason) = error else {
                Issue.record("unexpected WorkflowError \(error)")
                return
            }
            #expect(reason.contains("negative cursors"))
            #expect(reason.contains("stepCursor: -1"))
        }

        // The tampered cursor must never reach the step table as a subscript.
        let counts = await log.counts
        #expect(counts.isEmpty)
    }

    @Test("tampered negative iterationCursor fails resume with a typed error")
    func negativeIterationCursorFailsResumeWithTypedError() async throws {
        let backend = WorkflowInMemoryCheckpointStore()
        let checkpointing = WorkflowCheckpointing(backend: backend)
        let log = ExecutionLog()
        let workflow = makeTwoStepWorkflow(log: log, checkpointing: checkpointing, checkpointID: "wf-legacy-negative-iteration")

        let fixture = legacyCheckpoint(threadID: "wf-legacy-negative-iteration", signature: workflow.workflowSignature) {
            $0["workflow.completed"] = encodedJSON(false)
            $0["workflow.stepCursor"] = encodedJSON(0)
            $0["workflow.iterationCursor"] = encodedJSON(-3)
            $0["workflow.lastResult"] = encodedJSON(Optional<WorkflowResultSnapshot>.none)
            $0["workflow.currentInput"] = encodedJSON("seed")
        }
        try await backend.save(fixture)

        do {
            _ = try await workflow.durable.execute("ignored", resumeFrom: "wf-legacy-negative-iteration")
            Issue.record("expected invalid-workflow error")
        } catch let error as WorkflowError {
            guard case .invalidWorkflow(let reason) = error else {
                Issue.record("unexpected WorkflowError \(error)")
                return
            }
            #expect(reason.contains("iterationCursor: -3"))
        }

        let counts = await log.counts
        #expect(counts.isEmpty)
    }

    // MARK: - Result fidelity

    @Test("repeat conditions receive full agent results in durable runs")
    func repeatConditionSeesFullAgentResults() async throws {
        let observations = MetadataRecorder()
        let checkpointing = makeInMemoryCheckpointing()

        let workflow = Workflow()
            .step(MetadataEchoAgent())
            .repeatUntil(maxIterations: 4) { result in
                observations.record(result.metadata["pass"])
                return result.metadata["pass"] == .string("done")
            }
            .durable
            .checkpoint(id: "wf-repeat-fidelity", policy: .onCompletion)
            .durable
            .checkpointing(checkpointing)

        let result = try await workflow.durable.execute("start")

        // Pass 1 observes "no" and iterates; pass 2 observes "done" and stops.
        // If the mid-run result were reconstructed from the input text alone,
        // the metadata would be lost and neither observation would match.
        #expect(await observations.values == [.string("no"), .string("done")])
        #expect(result.output == "again")
        #expect(result.metadata["pass"] == .string("done"))
    }

    @Test("resumed repeat boundary evaluates metadata from the persisted snapshot")
    func resumedRepeatBoundaryUsesPersistedMetadata() async throws {
        let observations = MetadataRecorder()
        let log = ExecutionLog()
        let checkpointing = makeInMemoryCheckpointing()
        let controller = WorkflowDurableFaultController(queue: [.afterCheckpointWrite])

        try await WorkflowDurableFaultInjection.$controller.withValue(controller) {
            do {
                _ = try await Workflow()
                    .step(MetadataEchoAgent(log: log))
                    .repeatUntil(maxIterations: 4) { result in
                        observations.record(result.metadata["pass"])
                        return result.metadata["pass"] == .string("done")
                    }
                    .durable
                    .checkpoint(id: "wf-repeat-resume", policy: .everyStep)
                    .durable
                    .checkpointing(checkpointing)
                    .durable
                    .execute("start")
                Issue.record("expected injected fault")
            } catch let fault as WorkflowDurableInjectedFault {
                #expect(fault.point == .afterCheckpointWrite)
            }
        }

        // No boundary ran before the fault, so nothing was observed yet; the
        // committed step's snapshot only exists in the persisted checkpoint.
        #expect(await observations.values.isEmpty)

        let result = try await Workflow()
            .step(MetadataEchoAgent(log: log))
            .repeatUntil(maxIterations: 4) { result in
                observations.record(result.metadata["pass"])
                return result.metadata["pass"] == .string("done")
            }
            .durable
            .checkpoint(id: "wf-repeat-resume", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)
            .durable
            .execute("ignored", resumeFrom: "wf-repeat-resume")

        // The first boundary observation must come from the decoded snapshot's
        // metadata ("no"). A fallback AgentResult(currentInput) carries no
        // metadata and would record "<nil>" instead. The agent then runs exactly
        // one more time (pass 2), proving the committed step was not re-executed.
        #expect(await observations.values == [.string("no"), .string("done")])
        let counts = await log.counts
        #expect(counts["MetadataEchoAgent"] == 2)
        #expect(result.output == "again")
        #expect(result.metadata["pass"] == .string("done"))
    }

    // MARK: - Helpers

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-phase-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeInMemoryCheckpointing() -> WorkflowCheckpointing {
        WorkflowCheckpointing(backend: WorkflowInMemoryCheckpointStore())
    }

    private func makeLinearWorkflow(
        log: ExecutionLog? = nil,
        checkpointing: WorkflowCheckpointing,
        checkpointID: String
    ) -> Workflow {
        Workflow()
            .step(CountingAgent(label: "A", log: log))
            .step(CountingAgent(label: "B", log: log))
            .step(CountingAgent(label: "C", log: log))
            .durable
            .checkpoint(id: checkpointID, policy: .everyStep)
            .durable
            .checkpointing(checkpointing)
    }

    private func makeTwoStepWorkflow(
        log: ExecutionLog? = nil,
        checkpointing: WorkflowCheckpointing,
        checkpointID: String
    ) -> Workflow {
        Workflow()
            .step(CountingAgent(label: "A", log: log, response: "A-out"))
            .step(CountingAgent(label: "B", log: log, response: "B-out"))
            .durable
            .checkpoint(id: checkpointID, policy: .everyStep)
            .durable
            .checkpointing(checkpointing)
    }

    /// Builds a checkpoint pinned to the pre-phase-enum six-channel layout.
    ///
    /// The fixture is constructed inline (spec section 6: no binary fixtures);
    /// `HiveCheckpoint`'s Codable shape is unchanged by this ticket, so these
    /// bytes are exactly what earlier releases persisted.
    private func legacyCheckpoint(
        threadID: String,
        signature: String,
        populate: (inout [String: Data]) -> Void
    ) -> HiveCheckpoint<WorkflowDurableSchema> {
        var channels: [String: Data] = [:]
        channels["workflow.signature"] = encodedJSON(signature)
        populate(&channels)

        // Realistic pre-change bookkeeping: the old engine version-bumped every
        // committed channel, stamped updatedChannelsLastCommit, and recorded
        // per-node seen versions, so surviving checkpoints carry the removed
        // channel IDs inside these maps. Migration must prune them or the
        // runtime rejects the checkpoint as corrupt.
        return HiveCheckpoint(
            id: HiveCheckpointID("legacy-cp"),
            threadID: HiveThreadID(threadID),
            runID: HiveRunID(UUID()),
            stepIndex: 0,
            schemaVersion: "legacy-pre-phase-enum-schema",
            graphVersion: "legacy-pre-phase-enum-graph",
            checkpointFormatVersion: "HCP1",
            channelVersionsByChannelID: [
                "workflow.currentInput": 2,
                "workflow.signature": 1,
                "workflow.stepCursor": 2,
                "workflow.iterationCursor": 1,
                "workflow.completed": 1,
                "workflow.lastResult": 2,
            ],
            versionsSeenByNodeID: [
                "workflow.execute": [
                    "workflow.currentInput": 2,
                    "workflow.lastResult": 2,
                    "workflow.stepCursor": 2,
                ],
            ],
            updatedChannelsLastCommit: [
                "workflow.currentInput",
                "workflow.lastResult",
                "workflow.stepCursor",
            ],
            globalDataByChannelID: channels,
            frontier: [],
            deferredFrontier: [],
            joinBarrierSeenByJoinID: [:],
            interruption: nil,
            lineage: nil
        )
    }

    private func encodedJSON<T: Encodable & Sendable>(_ value: T) -> Data {
        try! JSONEncoder().encode(value)
    }

    private func requireChannelData(_ data: Data?, channel: String) throws -> Data {
        guard let data else {
            throw LegacyFixtureError.missingChannel(channel)
        }
        return data
    }

    private func requireLatestCheckpoint(
        from store: WorkflowFileCheckpointStore,
        threadID: HiveThreadID
    ) async throws -> HiveCheckpoint<WorkflowDurableSchema> {
        guard let checkpoint = try await store.loadLatest(threadID: threadID) else {
            throw LegacyFixtureError.missingCheckpoint(threadID.rawValue)
        }
        return checkpoint
    }

    private func requireLatestCheckpoint(
        from store: AnyHiveCheckpointStore<WorkflowDurableSchema>,
        threadID: HiveThreadID
    ) async throws -> HiveCheckpoint<WorkflowDurableSchema> {
        guard let checkpoint = try await store.loadLatest(threadID: threadID) else {
            throw LegacyFixtureError.missingCheckpoint(threadID.rawValue)
        }
        return checkpoint
    }
}

private enum LegacyFixtureError: Error {
    case missingChannel(String)
    case missingCheckpoint(String)
}

private actor ExecutionLog {
    private var values: [String] = []

    func record(_ label: String) {
        values.append(label)
    }

    var counts: [String: Int] {
        values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }
}

private actor CountingAgent: AgentRuntime {
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions: String
    nonisolated let configuration = AgentConfiguration(name: "CountingAgent")
    nonisolated let handoffs: [AnyHandoffConfiguration] = []

    private let response: String
    private let log: ExecutionLog?

    init(label: String, log: ExecutionLog?, response: String? = nil) {
        self.log = log
        self.response = response ?? label
        instructions = label
    }

    func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult {
        await log?.record(instructions)
        return AgentResult(output: response)
    }

    nonisolated func stream(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.finish(throwing: AgentError.internalError(reason: "counting agent does not stream"))
        }
    }

    func cancel() async {}
}

/// Agent whose result metadata flips once its input marks a completed pass.
private actor MetadataEchoAgent: AgentRuntime {
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions: String
    nonisolated let configuration = AgentConfiguration(name: "MetadataEchoAgent")
    nonisolated let handoffs: [AnyHandoffConfiguration] = []

    private let log: ExecutionLog?

    init(log: ExecutionLog? = nil) {
        self.log = log
        instructions = "MetadataEchoAgent"
    }

    func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult {
        await log?.record(instructions)
        return AgentResult(
            output: "again",
            metadata: ["pass": .string(input == "again" ? "done" : "no")]
        )
    }

    nonisolated func stream(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.finish(throwing: AgentError.internalError(reason: "metadata echo agent does not stream"))
        }
    }

    func cancel() async {}
}

/// Thread-safe recorder for values observed inside repeat conditions.
private final class MetadataRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [SendableValue] = []

    var values: [SendableValue] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ value: SendableValue?) {
        lock.lock()
        defer { lock.unlock() }
        if let value {
            recorded.append(value)
        } else {
            recorded.append(.string("<nil>"))
        }
    }
}
#endif
