#if SWARM_INTEGRATIONS
import Foundation
import Testing
@testable import Swarm

@Suite("Workflow Advanced")
struct WorkflowDurableTests {
    @Test("direct and durable repeat execution share limits and result fidelity")
    func directAndDurableRepeatParity() async throws {
        for maxIterations in [1, 2] {
            let directLog = WorkflowInvocationLog()
            let direct = Workflow()
                .step(WorkflowRecordingAgent(log: directLog))
                .repeatUntil(maxIterations: maxIterations) { _ in false }

            let checkpointing = WorkflowCheckpointing.inMemory()
            let durableLog = WorkflowInvocationLog()
            let durable = Workflow()
                .step(WorkflowRecordingAgent(log: durableLog))
                .repeatUntil(maxIterations: maxIterations) { _ in false }
                .durable
                .checkpoint(id: "wf-parity-\(maxIterations)", policy: .everyStep)
                .durable
                .checkpointing(checkpointing)

            let directResult = try await direct.run("start")
            let durableResult = try await durable.durable.execute("start")

            #expect(directResult == durableResult)
            #expect(await directLog.inputs == ["start"] + Array(repeating: "result", count: maxIterations - 1))
            #expect(await durableLog.inputs == ["start"] + Array(repeating: "result", count: maxIterations - 1))
        }
    }

    @Test("direct and durable execution reject invalid workflows before agent invocation")
    func invalidWorkflowParity() async throws {
        let directEmpty = Workflow()
        await #expect(throws: WorkflowError.self) {
            _ = try await directEmpty.run("ignored")
        }

        let directAgentLog = WorkflowInvocationLog()
        let directRepeating = Workflow()
            .step(WorkflowRecordingAgent(log: directAgentLog))
            .repeatUntil(maxIterations: 0) { _ in false }
        await #expect(throws: WorkflowError.self) {
            _ = try await directRepeating.run("ignored")
        }
        #expect(await directAgentLog.inputs.isEmpty)

        let checkpointing = WorkflowCheckpointing.inMemory()
        let durableAgentLog = WorkflowInvocationLog()
        let durableEmpty = Workflow()
            .durable
            .checkpoint(id: "wf-empty", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)
        await #expect(throws: WorkflowError.self) {
            _ = try await durableEmpty.durable.execute("ignored")
        }

        let durableRepeating = Workflow()
            .step(WorkflowRecordingAgent(log: durableAgentLog))
            .repeatUntil(maxIterations: 0) { _ in false }
            .durable
            .checkpoint(id: "wf-zero-repeat", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)
        await #expect(throws: WorkflowError.self) {
            _ = try await durableRepeating.durable.execute("ignored")
        }
        #expect(await durableAgentLog.inputs.isEmpty)
    }

    @Test("durable checkpoint requires explicit checkpoint store")
    func checkpointRequiresStore() async throws {
        let workflow = Workflow()
            .step(MockAgentRuntime(response: "ok"))
            .durable
            .checkpoint(id: "wf-1")

        await #expect(throws: WorkflowError.self) {
            _ = try await workflow.durable.execute("hello")
        }
    }

    @Test("durable runtime unavailable uses Swarm-owned error naming")
    func durableRuntimeUnavailableNameIsPublic() {
        let error = WorkflowError.durableRuntimeUnavailable(reason: "missing engine")
        #expect(error.localizedDescription.contains("durable runtime unavailable"))
        #expect(error.debugDescription.contains("durableRuntimeUnavailable"))
    }

    @Test("durable execute can resume from latest checkpoint")
    func resumeFromCheckpoint() async throws {
        let checkpointing = WorkflowCheckpointing.inMemory()
        let workflow = Workflow()
            .step(MockAgentRuntime(response: "done"))
            .durable
            .checkpoint(id: "wf-resume", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)

        let first = try await workflow.durable.execute("start")
        #expect(first.output == "done")

        let resumed = try await workflow.durable.execute("ignored", resumeFrom: "wf-resume")
        #expect(resumed.output == "done")
    }

    @Test("durable resume throws when checkpoint is missing")
    func resumeMissingCheckpoint() async throws {
        let checkpointing = WorkflowCheckpointing.inMemory()
        let workflow = Workflow()
            .step(MockAgentRuntime(response: "ok"))
            .durable
            .checkpoint(id: "wf-known", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)

        await #expect(throws: WorkflowError.self) {
            _ = try await workflow.durable.execute("start", resumeFrom: "wf-missing")
        }
    }

    @Test("durable resume throws on workflow definition mismatch")
    func resumeDefinitionMismatch() async throws {
        let checkpointing = WorkflowCheckpointing.inMemory()

        let original = Workflow()
            .step(MockAgentRuntime(response: "a"))
            .durable
            .checkpoint(id: "wf-mismatch", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)

        _ = try await original.durable.execute("start")

        let changed = Workflow()
            .step(MockAgentRuntime(response: "a"))
            .step(MockAgentRuntime(response: "b"))
            .durable
            .checkpoint(id: "wf-mismatch", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)

        await #expect(throws: WorkflowError.self) {
            _ = try await changed.durable.execute("resume", resumeFrom: "wf-mismatch")
        }
    }

    @Test("durable resume rejects same-name agent configuration mismatch")
    func resumeRejectsSameNameAgentConfigurationMismatch() async throws {
        let checkpointing = WorkflowCheckpointing.inMemory()

        let original = Workflow()
            .step(MockAgentRuntime(
                response: "done",
                configuration: AgentConfiguration(name: "Worker", maxIterations: 1, temperature: 0.1)
            ))
            .durable
            .checkpoint(id: "wf-agent-config-mismatch", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)

        _ = try await original.durable.execute("start")

        let changed = Workflow()
            .step(MockAgentRuntime(
                response: "done",
                configuration: AgentConfiguration(name: "Worker", maxIterations: 5, temperature: 0.1)
            ))
            .durable
            .checkpoint(id: "wf-agent-config-mismatch", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)

        await #expect(throws: WorkflowError.self) {
            _ = try await changed.durable.execute("resume", resumeFrom: "wf-agent-config-mismatch")
        }
    }

    @Test("durable resume rejects changed route closure identity")
    func resumeRejectsChangedRouteClosureIdentity() async throws {
        let checkpointing = WorkflowCheckpointing.inMemory()

        let original = Workflow()
            .step(MockAgentRuntime(response: "seed"))
            .route({ _ in nil as (any AgentRuntime)? }, signature: "route-v1")
            .durable
            .checkpoint(id: "wf-route-closure-mismatch", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)

        await #expect(throws: WorkflowError.self) {
            _ = try await original.durable.execute("start")
        }
        #expect(try await checkpointing.containsCheckpoint(for: "wf-route-closure-mismatch"))

        let changed = Workflow()
            .step(MockAgentRuntime(response: "seed"))
            .route({ _ in MockAgentRuntime(response: "changed-route") }, signature: "route-v2")
            .durable
            .checkpoint(id: "wf-route-closure-mismatch", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)

        await #expect(throws: WorkflowError.self) {
            _ = try await changed.durable.execute("resume", resumeFrom: "wf-route-closure-mismatch")
        }
    }

    @Test("durable resume rejects changed custom merge closure identity")
    func resumeRejectsChangedCustomMergeClosureIdentity() async throws {
        let checkpointing = WorkflowCheckpointing.inMemory()

        let original = Workflow()
            .parallel(
                [MockAgentRuntime(response: "branch")],
                merge: .custom { _ in "original-merge" },
                customMergeSignature: "merge-v1"
            )
            .durable
            .checkpoint(id: "wf-custom-merge-mismatch", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)

        _ = try await original.durable.execute("start")

        let changed = Workflow()
            .parallel(
                [MockAgentRuntime(response: "branch")],
                merge: .custom { _ in "changed-merge" },
                customMergeSignature: "merge-v2"
            )
            .durable
            .checkpoint(id: "wf-custom-merge-mismatch", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)

        await #expect(throws: WorkflowError.self) {
            _ = try await changed.durable.execute("resume", resumeFrom: "wf-custom-merge-mismatch")
        }
    }

    @Test("durable resume rejects changed repeat closure identity")
    func resumeRejectsChangedRepeatClosureIdentity() async throws {
        let checkpointing = WorkflowCheckpointing.inMemory()

        let original = repeatClosureIdentityWorkflow(
            checkpointing: checkpointing,
            signature: "repeat-predicate:v1"
        ) { _ in false }

        _ = try await original.durable.execute("start")

        let changed = repeatClosureIdentityWorkflow(
            checkpointing: checkpointing,
            signature: "repeat-predicate:v2"
        ) { _ in true }

        await #expect(throws: WorkflowError.self) {
            _ = try await changed.durable.execute("resume", resumeFrom: "wf-repeat-closure-mismatch")
        }
    }

    @Test("durable execute warns once when implicit fileID:line identity would have been used")
    func durableExecuteWarnsOnceForImplicitIdentity() async throws {
        WorkflowDurableIdentityTesting.reset()
        let checkpointing = WorkflowCheckpointing.inMemory()
        let workflow = Workflow()
            .step(MockAgentRuntime(response: "seed"))
            .route { _ in MockAgentRuntime(response: "routed") }
            .durable
            .checkpoint(id: "wf-implicit-identity", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)

        _ = try await workflow.durable.execute("start")
        #expect(WorkflowDurableIdentityTesting.warningCount == 1)

        _ = try await workflow.durable.execute("again")
        #expect(WorkflowDurableIdentityTesting.warningCount == 1)
    }

    @Test("durable fallback executes backup after retries exhausted")
    func fallbackUsesBackup() async throws {
        let result = try await Workflow()
            .durable
            .fallback(primary: FailingAgent(), to: MockAgentRuntime(response: "backup"), retries: 2)
            .run("input")

        #expect(result.output == "backup")
        #expect(result.metadata["workflow.fallback.used"] == .bool(true))
    }
}

private actor WorkflowInvocationLog {
    private(set) var inputs: [String] = []

    func record(_ input: String) {
        inputs.append(input)
    }
}

private actor WorkflowRecordingAgent: AgentRuntime {
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions = "WorkflowRecordingAgent"
    nonisolated let configuration = AgentConfiguration(name: "WorkflowRecordingAgent")
    nonisolated let handoffs: [AnyHandoffConfiguration] = []

    private let log: WorkflowInvocationLog

    init(log: WorkflowInvocationLog) {
        self.log = log
    }

    func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult {
        await log.record(input)
        return AgentResult(
            output: "result",
            iterationCount: 2,
            metadata: ["marker": .string("preserved")]
        )
    }

    nonisolated func stream(
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

private func repeatClosureIdentityWorkflow(
    checkpointing: WorkflowCheckpointing,
    signature: String,
    condition: @escaping @Sendable (AgentResult) -> Bool
) -> Workflow {
    Workflow()
        .step(MockAgentRuntime(response: "draft"))
        .repeatUntil(maxIterations: 1, condition, signature: signature)
        .durable
        .checkpoint(id: "wf-repeat-closure-mismatch", policy: .everyStep)
        .durable
        .checkpointing(checkpointing)
}

private actor FailingAgent: AgentRuntime {
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions: String = "FailingAgent"
    nonisolated let configuration = AgentConfiguration(name: "FailingAgent")
    nonisolated let handoffs: [AnyHandoffConfiguration] = []

    func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult {
        throw AgentError.internalError(reason: "forced failure")
    }

    nonisolated func stream(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.finish(throwing: AgentError.internalError(reason: "forced failure"))
        }
    }

    func cancel() async {}
}
#endif
