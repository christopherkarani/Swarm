import Foundation
import Testing
@testable import Swarm

#if SWARM_INTEGRATIONS

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
}

private func checkpointCount(_ durable: DurableWorkflow) async -> Int {
    (try? await durable.inspect().checkpoints.count) ?? 0
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
