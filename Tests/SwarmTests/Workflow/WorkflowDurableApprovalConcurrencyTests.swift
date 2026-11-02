import Foundation
import HiveCore
import Testing
@testable import Swarm

#if SWARM_INTEGRATIONS

/// Holds tool executions until released, so a test can overlap two resumes.
actor ApprovalToolGate {
    private(set) var started = 0
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        started += 1
        guard !released else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        released = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }

    func waitUntilStarted(_ count: Int) async {
        while started < count {
            await Task.yield()
        }
    }
}

private func makeGatedApprovalTool(counter: ApprovalToolCounter, gate: ApprovalToolGate) -> FunctionTool {
    FunctionTool(
        name: "delete_vm",
        description: "Approval-gated tool that blocks until released",
        executionSemantics: ToolExecutionSemantics(approvalRequirement: .always)
    ) { _ in
        await counter.increment()
        await gate.enter()
        return .string("ok")
    }
}

private func makeGatedWorkflow(
    checkpointID: WorkflowCheckpointID,
    store: WorkflowCheckpointing,
    counter: ApprovalToolCounter,
    gate: ApprovalToolGate,
    scriptedCalls: Int
) async throws -> DurableWorkflow {
    let provider = await MockInferenceProvider()
    let call: (name: String, args: [String: SendableValue]) = ("delete_vm", ["id": .string("vm-1")])
    await provider.configureToolCallingSequence(
        toolCalls: Array(repeating: call, count: scriptedCalls),
        finalAnswer: "done"
    )
    await provider.setResponses(["done", "done"])
    let agent = try makeApprovalTestAgent(tools: [makeGatedApprovalTool(counter: counter, gate: gate)], provider: provider)
    return Workflow()
        .step(agent)
        .durable
        .configured(id: checkpointID, store: store, policy: .everyStep)
}

/// Starts two overlapping approve-resumes and returns their outcomes.
private func overlappingApprovals(
    first: DurableWorkflow,
    second: DurableWorkflow,
    checkpointID: WorkflowCheckpointID,
    gate: ApprovalToolGate
) async -> [Result<AgentResult, any Error>] {
    let firstTask = Task { try await first.resume(decision: .approve, from: checkpointID) }
    await gate.waitUntilStarted(1)
    let secondTask = Task { try await second.resume(decision: .approve, from: checkpointID) }
    // Give the second resume time to either fail fast or reach the tool.
    try? await Task.sleep(for: .milliseconds(300))
    await gate.release()
    return [await firstTask.result, await secondTask.result]
}

/// Asserts exactly one resume won and the other lost with a resume conflict.
private func expectOneWinnerOneConflict(_ outcomes: [Result<AgentResult, any Error>]) {
    var successes = 0
    var conflicts = 0
    for outcome in outcomes {
        switch outcome {
        case .success:
            successes += 1
        case .failure(let error as WorkflowResumeConflict):
            _ = error
            conflicts += 1
        case .failure(let error):
            Issue.record("unexpected resume error: \(error)")
        }
    }
    #expect(successes == 1)
    #expect(conflicts == 1)
}

@Suite("Concurrent durable approval resumes", .ephemeralDefaultStores)
struct WorkflowDurableApprovalConcurrencyTests {
    @Test("two concurrent approves in one process execute the tool once")
    func concurrentInProcessApprovesExecuteOnce() async throws {
        let counter = ApprovalToolCounter()
        let gate = ApprovalToolGate()
        let checkpointID = WorkflowCheckpointID("approval-concurrent-in-process")
        let workflow = try await makeGatedWorkflow(
            checkpointID: checkpointID,
            store: .inMemory(),
            counter: counter,
            gate: gate,
            scriptedCalls: 2
        )

        await #expect(throws: WorkflowApprovalRequired.self) {
            _ = try await workflow.execute("go")
        }

        let outcomes = await overlappingApprovals(
            first: workflow,
            second: workflow,
            checkpointID: checkpointID,
            gate: gate
        )

        #expect(await counter.count == 1)
        expectOneWinnerOneConflict(outcomes)
    }

    @Test("two approves through separate stores on one directory execute the tool once")
    func concurrentCrossStoreApprovesExecuteOnce() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-approval-concurrent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let counter = ApprovalToolCounter()
        let gate = ApprovalToolGate()
        let checkpointID = WorkflowCheckpointID("approval-concurrent-cross-store")
        // Separate store instances emulate two processes sharing the directory.
        // The first handle pauses then resumes (two calls); the second only resumes.
        let first = try await makeGatedWorkflow(
            checkpointID: checkpointID,
            store: .fileSystem(directory: directory),
            counter: counter,
            gate: gate,
            scriptedCalls: 2
        )
        let second = try await makeGatedWorkflow(
            checkpointID: checkpointID,
            store: .fileSystem(directory: directory),
            counter: counter,
            gate: gate,
            scriptedCalls: 1
        )

        await #expect(throws: WorkflowApprovalRequired.self) {
            _ = try await first.execute("go")
        }

        let outcomes = await overlappingApprovals(
            first: first,
            second: second,
            checkpointID: checkpointID,
            gate: gate
        )

        #expect(await counter.count == 1)
        expectOneWinnerOneConflict(outcomes)
    }

    @Test("a resume that fails before committing releases its claim")
    func failedResumeReleasesClaim() async throws {
        let counter = ApprovalToolCounter()
        let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
        let provider = await MockInferenceProvider()
        let script: () async -> Void = {
            await provider.configureToolCallingSequence(
                toolCalls: [("delete_vm", ["id": .string("vm-1")])],
                finalAnswer: "done"
            )
        }
        await script()
        let agent = try makeApprovalTestAgent(tools: [tool], provider: provider)
        let checkpointID = WorkflowCheckpointID("approval-claim-release")
        let workflow = Workflow()
            .step(agent)
            .durable
            .configured(id: checkpointID, store: .inMemory(), policy: .everyStep)

        await #expect(throws: WorkflowApprovalRequired.self) {
            _ = try await workflow.execute("go")
        }

        await script()
        await provider.setError(AgentError.generationFailed(reason: "transient"))
        await #expect(throws: (any Error).self) {
            _ = try await workflow.resume(decision: .approve, from: checkpointID)
        }

        await provider.setError(nil)
        await script()
        let result = try await workflow.resume(decision: .approve, from: checkpointID)
        #expect(result.output == "done")
        #expect(await counter.count == 1)
    }
}

@Suite("Checkpoint store compare-and-swap")
struct WorkflowCheckpointStoreCompareAndSwapTests {
    private static func checkpoint(_ id: String, step: Int) -> HiveCheckpoint<WorkflowDurableSchema> {
        HiveCheckpoint(
            id: HiveCheckpointID(id),
            threadID: HiveThreadID("cas-thread"),
            runID: HiveRunID(UUID()),
            stepIndex: step,
            schemaVersion: "schema",
            graphVersion: "graph",
            globalDataByChannelID: [:],
            frontier: [],
            joinBarrierSeenByJoinID: [:],
            interruption: nil
        )
    }

    private static func expectCompareAndSwap(
        first: AnyHiveCheckpointStore<WorkflowDurableSchema>,
        second: AnyHiveCheckpointStore<WorkflowDurableSchema>
    ) async throws {
        try await first.save(checkpoint("c1", step: 1), expectedLatestID: nil)
        try await first.save(checkpoint("c2", step: 2), expectedLatestID: HiveCheckpointID("c1"))
        await #expect(throws: HiveCheckpointConflict.self) {
            try await second.save(checkpoint("c2b", step: 2), expectedLatestID: HiveCheckpointID("c1"))
        }
        let latest = try await second.loadLatest(threadID: HiveThreadID("cas-thread"))
        #expect(latest?.id == HiveCheckpointID("c2"))
    }

    @Test("in-memory store rejects a stale expected checkpoint")
    func inMemoryCompareAndSwap() async throws {
        let store = WorkflowInMemoryCheckpointStore()
        try await Self.expectCompareAndSwap(first: store.runtimeStore, second: store.runtimeStore)
    }

    @Test("file stores sharing a directory reject a stale expected checkpoint")
    func fileCompareAndSwapAcrossInstances() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-cas-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await Self.expectCompareAndSwap(
            first: WorkflowFileCheckpointStore(directory: directory).runtimeStore,
            second: WorkflowFileCheckpointStore(directory: directory).runtimeStore
        )
    }
}

#endif
