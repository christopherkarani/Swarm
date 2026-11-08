import Foundation
import Testing
@testable import Swarm

#if SWARM_INTEGRATIONS
import HiveCore

@Suite("Workflow durable cancellation")
struct WorkflowDurableCancellationTests {
    @Test("cancelling the caller stops the durable run and throws")
    func callerCancellationStopsRun() async throws {
        let probe = CancellationProbe()
        let run = WorkflowCheckpointID("wf-cancel-caller")
        let durable = Workflow()
            .step(BlockingStepAgent(probe: probe, blockFor: .milliseconds(500)))
            .step(RecordingStepAgent(probe: probe))
            .durable
            .configured(id: run, store: .inMemory(), policy: .everyStep)

        let task = Task { try await durable.execute("start") }
        try await probe.waitUntilBlockingStepStarted()
        task.cancel()

        let outcome = await task.result
        #expect(throws: AgentError.cancelled) { _ = try outcome.get() }

        let checkpointsAtCancel = await checkpointCount(durable)
        try await Task.sleep(for: .seconds(1))

        #expect(await probe.blockingStepCompleted == false)
        #expect(await probe.laterStepInputs.isEmpty)
        #expect(await checkpointCount(durable) == checkpointsAtCancel)
    }

    @Test("workflow timeout stops the durable run")
    func timeoutStopsRun() async throws {
        let probe = CancellationProbe()
        let durable = Workflow()
            .step(BlockingStepAgent(probe: probe, blockFor: .milliseconds(500)))
            .step(RecordingStepAgent(probe: probe))
            .timeout(.milliseconds(100))
            .durable
            .configured(id: WorkflowCheckpointID("wf-cancel-timeout"), store: .inMemory(), policy: .everyStep)

        await #expect(throws: AgentError.timeout(duration: .milliseconds(100))) {
            _ = try await durable.execute("start")
        }

        let checkpointsAtTimeout = await checkpointCount(durable)
        try await Task.sleep(for: .seconds(1))

        #expect(await probe.blockingStepCompleted == false)
        #expect(await probe.laterStepInputs.isEmpty)
        #expect(await checkpointCount(durable) == checkpointsAtTimeout)
    }

    @Test("cancelling during the onCompletion flush still persists the completion checkpoint")
    func cancellationDuringCompletionFlushPersistsCheckpoint() async throws {
        let backend = GatedCheckpointStore()
        let probe = CancellationProbe()
        let durable = Workflow()
            .step(RecordingStepAgent(probe: probe))
            .durable
            .configured(
                id: WorkflowCheckpointID("wf-cancel-flush"),
                store: WorkflowCheckpointing(backend: backend),
                policy: .onCompletion
            )

        let task = Task { try await durable.execute("start") }
        try await backend.waitUntilSaveStarted()
        task.cancel()
        await backend.releaseSaves()

        let result = try await task.value
        #expect(result.output == "later-output")
        #expect(await probe.laterStepInputs == ["start"])
        #expect(try await backend.containsCheckpoint(for: "wf-cancel-flush"))
    }
}

private func checkpointCount(_ durable: DurableWorkflow) async -> Int {
    (try? await durable.inspect().checkpoints.count) ?? 0
}

/// In-memory store whose saves wait for ``releaseSaves()``, honoring
/// cooperative cancellation while they wait (like real I/O-backed stores).
private actor GatedCheckpointStore: WorkflowDurableCheckpointStore, HiveCheckpointStore {
    typealias Schema = WorkflowDurableSchema

    private let inner = WorkflowInMemoryCheckpointStore()
    private var saveStarted = false
    private var released = false

    nonisolated var runtimeStore: AnyHiveCheckpointStore<WorkflowDurableSchema> {
        AnyHiveCheckpointStore(self)
    }

    func releaseSaves() {
        released = true
    }

    func waitUntilSaveStarted() async throws {
        for _ in 0 ..< 400 where !saveStarted {
            try await Task.sleep(for: .milliseconds(5))
        }
        guard saveStarted else {
            throw AgentError.internalError(reason: "checkpoint save never started")
        }
    }

    func save(_ checkpoint: HiveCheckpoint<WorkflowDurableSchema>) async throws {
        saveStarted = true
        while !released {
            try await Task.sleep(for: .milliseconds(5))
        }
        try await inner.save(checkpoint)
    }

    func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<WorkflowDurableSchema>? {
        try await inner.loadLatest(threadID: threadID)
    }

    func containsCheckpoint(for checkpointID: String) async throws -> Bool {
        try await inner.containsCheckpoint(for: checkpointID)
    }

    func history(for checkpointID: String) async throws -> [HiveCheckpoint<WorkflowDurableSchema>] {
        try await inner.history(for: checkpointID)
    }
}

private actor CancellationProbe {
    private(set) var blockingStepStarted = false
    private(set) var blockingStepCompleted = false
    private(set) var laterStepInputs: [String] = []

    func markBlockingStepStarted() {
        blockingStepStarted = true
    }

    func markBlockingStepCompleted() {
        blockingStepCompleted = true
    }

    func recordLaterStep(_ input: String) {
        laterStepInputs.append(input)
    }

    func waitUntilBlockingStepStarted() async throws {
        for _ in 0 ..< 200 where !blockingStepStarted {
            try await Task.sleep(for: .milliseconds(5))
        }
        guard blockingStepStarted else {
            throw AgentError.internalError(reason: "blocking step never started")
        }
    }
}

/// Step that blocks for `blockFor`, honoring cooperative cancellation.
private struct BlockingStepAgent: AgentRuntime {
    let tools: [any AnyJSONTool] = []
    let instructions = "BlockingStepAgent"
    let configuration = AgentConfiguration(name: "BlockingStepAgent")
    let handoffs: [AnyHandoffConfiguration] = []
    let probe: CancellationProbe
    let blockFor: Duration

    func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult {
        await probe.markBlockingStepStarted()
        try await Task.sleep(for: blockFor)
        await probe.markBlockingStepCompleted()
        return AgentResult(output: "blocked-output")
    }

    func stream(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.finish(throwing: AgentError.internalError(reason: "blocking agent does not stream"))
        }
    }

    func cancel() async {}
}

/// Step that records every invocation so tests can prove it never ran.
private struct RecordingStepAgent: AgentRuntime {
    let tools: [any AnyJSONTool] = []
    let instructions = "RecordingStepAgent"
    let configuration = AgentConfiguration(name: "RecordingStepAgent")
    let handoffs: [AnyHandoffConfiguration] = []
    let probe: CancellationProbe

    func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult {
        await probe.recordLaterStep(input)
        return AgentResult(output: "later-output")
    }

    func stream(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.finish(throwing: AgentError.internalError(reason: "recording agent does not stream"))
        }
    }

    func cancel() async {}
}

#endif
