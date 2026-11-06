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

/// Makes a fresh temporary checkpoint directory for one test.
private func makeTemporaryCheckpointDirectory(_ label: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swarm-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// Longest file name in `directory`, in UTF-8 bytes.
private func longestFileNameBytes(in directory: URL) throws -> Int {
    try FileManager.default.contentsOfDirectory(atPath: directory.path)
        .map(\.utf8.count)
        .max() ?? 0
}

/// Releases every waiting task at once when the last participant arrives.
actor StartBarrier {
    private let participants: Int
    private var arrived = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(participants: Int) {
        self.participants = participants
    }

    func arriveAndWait() async {
        arrived += 1
        guard arrived < participants else {
            for waiter in waiters {
                waiter.resume()
            }
            waiters.removeAll()
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }
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

    @Test("a resume outliving the claim lease renews it so another store cannot take over")
    func longResumeRenewsClaim() async throws {
        let directory = try makeTemporaryCheckpointDirectory("approval-claim-renewal")
        defer { try? FileManager.default.removeItem(at: directory) }

        let counter = ApprovalToolCounter()
        let gate = ApprovalToolGate()
        let checkpointID = WorkflowCheckpointID("approval-claim-renewal")
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

        let outcomes = await WorkflowApprovalClaim.$lease.withValue(0.3) {
            let firstTask = Task { try await first.resume(decision: .approve, from: checkpointID) }
            await gate.waitUntilStarted(1)
            // Outlive several leases while the approved tool is still running.
            try? await Task.sleep(for: .milliseconds(1000))
            let secondTask = Task { try await second.resume(decision: .approve, from: checkpointID) }
            try? await Task.sleep(for: .milliseconds(300))
            await gate.release()
            return [await firstTask.result, await secondTask.result]
        }

        #expect(await counter.count == 1)
        expectOneWinnerOneConflict(outcomes)
    }

    @Test("execute refuses a run whose paused approval is being resumed")
    func executeRefusesClaimedRun() async throws {
        let store: WorkflowCheckpointing = .inMemory()
        let counter = ApprovalToolCounter()
        let gate = ApprovalToolGate()
        let checkpointID = WorkflowCheckpointID("approval-execute-while-claimed")
        let workflow = try await makeGatedWorkflow(
            checkpointID: checkpointID,
            store: store,
            counter: counter,
            gate: gate,
            scriptedCalls: 2
        )

        await #expect(throws: WorkflowApprovalRequired.self) {
            _ = try await workflow.execute("go")
        }

        let resumeTask = Task { try await workflow.resume(decision: .approve, from: checkpointID) }
        await gate.waitUntilStarted(1)

        await #expect(throws: WorkflowResumeConflict.self) {
            _ = try await workflow.execute("go")
        }

        // A different run on the same store still starts.
        let other = try await makeGatedWorkflow(
            checkpointID: WorkflowCheckpointID("approval-execute-while-claimed-other"),
            store: store,
            counter: ApprovalToolCounter(),
            gate: gate,
            scriptedCalls: 1
        )
        await #expect(throws: WorkflowApprovalRequired.self) {
            _ = try await other.execute("go")
        }

        await gate.release()
        let result = try await resumeTask.value
        #expect(result.output == "done")
        #expect(await counter.count == 1)
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

    @Test("repeated failed resumes on the file store keep checkpoint file names short")
    func repeatedFailedResumesKeepFileNamesShort() async throws {
        let directory = try makeTemporaryCheckpointDirectory("approval-claim-ids")
        defer { try? FileManager.default.removeItem(at: directory) }

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
        let checkpointID = WorkflowCheckpointID("approval-concurrent-in-process")
        let workflow = Workflow()
            .step(agent)
            .durable
            .configured(id: checkpointID, store: .fileSystem(directory: directory), policy: .everyStep)

        await #expect(throws: WorkflowApprovalRequired.self) {
            _ = try await workflow.execute("go")
        }

        await provider.setError(AgentError.generationFailed(reason: "transient"))
        for attempt in 1...6 {
            await script()
            do {
                _ = try await workflow.resume(decision: .approve, from: checkpointID)
                Issue.record("attempt \(attempt) unexpectedly succeeded")
            } catch let error as AgentError {
                #expect(error == .generationFailed(reason: "transient"), "attempt \(attempt)")
            } catch {
                Issue.record("attempt \(attempt) failed with \(error) instead of the injected error")
            }
        }

        await provider.setError(nil)
        await script()
        let result = try await workflow.resume(decision: .approve, from: checkpointID)
        #expect(result.output == "done")
        #expect(await counter.count == 1)
        #expect(try longestFileNameBytes(in: directory) <= 255)
    }

    @Test("an approval resume works with a long checkpoint ID on the file store")
    func longCheckpointIDApprovalResume() async throws {
        let directory = try makeTemporaryCheckpointDirectory("approval-long-id")
        defer { try? FileManager.default.removeItem(at: directory) }

        let counter = ApprovalToolCounter()
        let tool = makeApprovalCountingTool(name: "delete_vm", counter: counter)
        let provider = await MockInferenceProvider()
        await provider.configureToolCallingSequence(
            toolCalls: [("delete_vm", ["id": .string("vm-1")])],
            finalAnswer: "done"
        )
        let agent = try makeApprovalTestAgent(tools: [tool], provider: provider)
        let rawID = "tenant-\(UUID().uuidString)-conversation-\(UUID().uuidString)-approval-request-0001"
        #expect(rawID.count >= 115)
        let checkpointID = WorkflowCheckpointID(rawID)
        let workflow = Workflow()
            .step(agent)
            .durable
            .configured(id: checkpointID, store: .fileSystem(directory: directory), policy: .everyStep)

        await #expect(throws: WorkflowApprovalRequired.self) {
            _ = try await workflow.execute("go")
        }
        // The resumed step replays inference, so script the same call again.
        await provider.configureToolCallingSequence(
            toolCalls: [("delete_vm", ["id": .string("vm-1")])],
            finalAnswer: "done"
        )
        let result = try await workflow.resume(decision: .approve, from: checkpointID)
        #expect(result.output == "done")
        #expect(await counter.count == 1)
    }
}

@Suite("Checkpoint store compare-and-swap")
struct WorkflowCheckpointStoreCompareAndSwapTests {
    private static func checkpoint(
        _ id: String,
        step: Int,
        thread: String = "cas-thread"
    ) -> HiveCheckpoint<WorkflowDurableSchema> {
        HiveCheckpoint(
            id: HiveCheckpointID(id),
            threadID: HiveThreadID(thread),
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

    @Test("claim checkpoint IDs keep a fixed length and sort in save order")
    func claimCheckpointIDsSortInSaveOrder() {
        let base = HiveCheckpointID(String(repeating: "ab", count: 32))
        var ids = [base]
        for _ in 0..<12 {
            let claimed = WorkflowApprovalClaimCheckpointID.claim(after: ids[ids.count - 1])
            ids.append(claimed)
            ids.append(WorkflowApprovalClaimCheckpointID.release(of: claimed))
        }
        let raw = ids.map(\.rawValue)
        #expect(raw == raw.sorted())
        #expect(Set(raw).count == raw.count)
        #expect(raw.dropFirst().allSatisfy { $0.count <= base.rawValue.count + 11 })
        #expect(raw[1] == "\(base.rawValue):c00000001")
        #expect(raw[2] == "\(base.rawValue):c00000001r")
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

    @Test("file stores sharing a directory let exactly one concurrent swap win")
    func fileCompareAndSwapUnderContention() async throws {
        let directory = try makeTemporaryCheckpointDirectory("cas-contention")
        defer { try? FileManager.default.removeItem(at: directory) }
        let stores = (0..<8).map { _ in WorkflowFileCheckpointStore(directory: directory).runtimeStore }

        // Several rounds, each on a fresh thread, so a missing lock loses at least one race.
        for round in 0..<10 {
            let thread = "cas-round-\(round)"
            try await stores[0].save(Self.checkpoint("c1", step: 1, thread: thread), expectedLatestID: nil)
            let winners = await Self.raceCompareAndSwap(stores: stores, thread: thread)
            #expect(winners.count == 1, "round \(round) winners: \(winners)")
            let latest = try await stores[0].loadLatest(threadID: HiveThreadID(thread))
            #expect(latest?.id.rawValue == winners.first, "round \(round)")
        }
    }

    /// Releases every store's `save(_:expectedLatestID: "c1")` at once; returns the IDs that won.
    private static func raceCompareAndSwap(
        stores: [AnyHiveCheckpointStore<WorkflowDurableSchema>],
        thread: String
    ) async -> [String] {
        let barrier = StartBarrier(participants: stores.count)
        return await withTaskGroup(of: String?.self) { group in
            for (index, store) in stores.enumerated() {
                group.addTask {
                    let candidate = checkpoint("c2-\(index)", step: 2, thread: thread)
                    await barrier.arriveAndWait()
                    do {
                        try await store.save(candidate, expectedLatestID: HiveCheckpointID("c1"))
                        return candidate.id.rawValue
                    } catch is HiveCheckpointConflict {
                        return nil
                    } catch {
                        Issue.record("unexpected save error: \(error)")
                        return nil
                    }
                }
            }
            var winners: [String] = []
            for await winner in group {
                if let winner { winners.append(winner) }
            }
            return winners
        }
    }
}

#endif
