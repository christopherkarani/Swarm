import Foundation
import Testing
@testable import Swarm

@Suite("Workflow durable configuration types")
struct WorkflowDurableConfigurationTests {
    @Test("WorkflowCheckpointID wraps a raw string and round-trips Codable")
    func checkpointIDIsRawRepresentableAndCodable() throws {
        let id = WorkflowCheckpointID("review-run")
        #expect(id.rawValue == "review-run")
        #expect(WorkflowCheckpointID(rawValue: "review-run") == id)
        #expect(WorkflowCheckpointID("review-run") == id)

        let encoded = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(WorkflowCheckpointID.self, from: encoded)
        #expect(decoded == id)
    }
}

#if SWARM_INTEGRATIONS

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
                .configured(id: WorkflowCheckpointID("wf-parity-\(maxIterations)"), store: checkpointing, policy: .everyStep)

            let directResult = try await direct.run("start")
            let durableResult = try await durable.execute("start")

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
            .configured(id: WorkflowCheckpointID("wf-empty"), store: checkpointing, policy: .everyStep)
        await #expect(throws: WorkflowError.self) {
            _ = try await durableEmpty.execute("ignored")
        }

        let durableRepeating = Workflow()
            .step(WorkflowRecordingAgent(log: durableAgentLog))
            .repeatUntil(maxIterations: 0) { _ in false }
            .durable
            .configured(id: WorkflowCheckpointID("wf-zero-repeat"), store: checkpointing, policy: .everyStep)
        await #expect(throws: WorkflowError.self) {
            _ = try await durableRepeating.execute("ignored")
        }
        #expect(await durableAgentLog.inputs.isEmpty)
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
            .configured(id: WorkflowCheckpointID("wf-resume"), store: checkpointing, policy: .everyStep)

        let first = try await workflow.execute("start")
        #expect(first.output == "done")

        let resumed = try await workflow.resume("ignored", from: WorkflowCheckpointID("wf-resume"))
        #expect(resumed.output == "done")
    }

    @Test("durable resume throws when checkpoint is missing")
    func resumeMissingCheckpoint() async throws {
        let checkpointing = WorkflowCheckpointing.inMemory()
        let workflow = Workflow()
            .step(MockAgentRuntime(response: "ok"))
            .durable
            .configured(id: WorkflowCheckpointID("wf-known"), store: checkpointing, policy: .everyStep)

        await #expect(throws: WorkflowError.self) {
            _ = try await workflow.resume("start", from: WorkflowCheckpointID("wf-missing"))
        }
    }

    @Test("durable resume throws on workflow definition mismatch")
    func resumeDefinitionMismatch() async throws {
        let checkpointing = WorkflowCheckpointing.inMemory()

        let original = Workflow()
            .step(MockAgentRuntime(response: "a"))
            .durable
            .configured(id: WorkflowCheckpointID("wf-mismatch"), store: checkpointing, policy: .everyStep)

        _ = try await original.execute("start")

        let changed = Workflow()
            .step(MockAgentRuntime(response: "a"))
            .step(MockAgentRuntime(response: "b"))
            .durable
            .configured(id: WorkflowCheckpointID("wf-mismatch"), store: checkpointing, policy: .everyStep)

        await #expect(throws: WorkflowError.self) {
            _ = try await changed.resume("resume", from: WorkflowCheckpointID("wf-mismatch"))
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
            .configured(id: WorkflowCheckpointID("wf-agent-config-mismatch"), store: checkpointing, policy: .everyStep)

        _ = try await original.execute("start")

        let changed = Workflow()
            .step(MockAgentRuntime(
                response: "done",
                configuration: AgentConfiguration(name: "Worker", maxIterations: 5, temperature: 0.1)
            ))
            .durable
            .configured(id: WorkflowCheckpointID("wf-agent-config-mismatch"), store: checkpointing, policy: .everyStep)

        await #expect(throws: WorkflowError.self) {
            _ = try await changed.resume("resume", from: WorkflowCheckpointID("wf-agent-config-mismatch"))
        }
    }

    @Test("durable resume rejects changed route closure identity")
    func resumeRejectsChangedRouteClosureIdentity() async throws {
        let checkpointing = WorkflowCheckpointing.inMemory()

        let original = Workflow()
            .step(MockAgentRuntime(response: "seed"))
            .route({ _ in nil as (any AgentRuntime)? }, signature: "route-v1")
            .durable
            .configured(id: WorkflowCheckpointID("wf-route-closure-mismatch"), store: checkpointing, policy: .everyStep)

        await #expect(throws: WorkflowError.self) {
            _ = try await original.execute("start")
        }
        #expect(try await checkpointing.containsCheckpoint(for: "wf-route-closure-mismatch"))

        let changed = Workflow()
            .step(MockAgentRuntime(response: "seed"))
            .route({ _ in MockAgentRuntime(response: "changed-route") }, signature: "route-v2")
            .durable
            .configured(id: WorkflowCheckpointID("wf-route-closure-mismatch"), store: checkpointing, policy: .everyStep)

        await #expect(throws: WorkflowError.self) {
            _ = try await changed.resume("resume", from: WorkflowCheckpointID("wf-route-closure-mismatch"))
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
            .configured(id: WorkflowCheckpointID("wf-custom-merge-mismatch"), store: checkpointing, policy: .everyStep)

        _ = try await original.execute("start")

        let changed = Workflow()
            .parallel(
                [MockAgentRuntime(response: "branch")],
                merge: .custom { _ in "changed-merge" },
                customMergeSignature: "merge-v2"
            )
            .durable
            .configured(id: WorkflowCheckpointID("wf-custom-merge-mismatch"), store: checkpointing, policy: .everyStep)

        await #expect(throws: WorkflowError.self) {
            _ = try await changed.resume("resume", from: WorkflowCheckpointID("wf-custom-merge-mismatch"))
        }
    }

    @Test("durable resume rejects changed repeat closure identity")
    func resumeRejectsChangedRepeatClosureIdentity() async throws {
        let checkpointing = WorkflowCheckpointing.inMemory()

        let original = repeatClosureIdentityWorkflow(
            checkpointing: checkpointing,
            signature: "repeat-predicate:v1"
        ) { _ in false }

        _ = try await original.execute("start")

        let changed = repeatClosureIdentityWorkflow(
            checkpointing: checkpointing,
            signature: "repeat-predicate:v2"
        ) { _ in true }

        await #expect(throws: WorkflowError.self) {
            _ = try await changed.resume("resume", from: WorkflowCheckpointID("wf-repeat-closure-mismatch"))
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
            .configured(id: WorkflowCheckpointID("wf-implicit-identity"), store: checkpointing, policy: .everyStep)

        _ = try await workflow.execute("start")
        #expect(WorkflowDurableIdentityTesting.warningCount == 1)

        _ = try await workflow.execute("again")
        #expect(WorkflowDurableIdentityTesting.warningCount == 1)
    }

    @Test("Workflow.fallback is the preferred fallback builder")
    func workflowFallbackPreferredAPI() async throws {
        let result = try await Workflow()
            .fallback(primary: FailingAgent(), to: MockAgentRuntime(response: "backup"), retries: 2)
            .run("input")

        #expect(result.output == "backup")
        #expect(result.metadata["workflow.fallback.used"] == .bool(true))
    }

    @Test("configured durable workflow resume uses dedicated entry point")
    func configuredResumeFromCheckpoint() async throws {
        let checkpointing = WorkflowCheckpointing.inMemory()
        let checkpointID = WorkflowCheckpointID("wf-configured-resume")
        let durable = Workflow()
            .step(MockAgentRuntime(response: "done"))
            .durable
            .configured(id: checkpointID, store: checkpointing, policy: .everyStep)

        let first = try await durable.execute("start")
        #expect(first.output == "done")

        let resumed = try await durable.resume("ignored", from: checkpointID)
        #expect(resumed.output == "done")
    }

    @Test("configured resume throws when checkpoint is missing")
    func configuredResumeMissingCheckpoint() async throws {
        let checkpointing = WorkflowCheckpointing.inMemory()
        let durable = Workflow()
            .step(MockAgentRuntime(response: "ok"))
            .durable
            .configured(id: WorkflowCheckpointID("wf-configured-known"), store: checkpointing)

        await #expect(throws: WorkflowError.checkpointNotFound(id: "wf-configured-missing")) {
            _ = try await durable.resume("start", from: WorkflowCheckpointID("wf-configured-missing"))
        }
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
) -> DurableWorkflow {
    Workflow()
        .step(MockAgentRuntime(response: "draft"))
        .repeatUntil(maxIterations: 1, condition, signature: signature)
        .durable
        .configured(id: WorkflowCheckpointID("wf-repeat-closure-mismatch"), store: checkpointing, policy: .everyStep)
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

#if !SWARM_INTEGRATIONS
@Suite("Workflow durable lean configuration")
struct WorkflowDurableLeanTests {
    @Test("configured execute throws durableRuntimeUnavailable on lean builds")
    func configuredExecuteThrowsWhenEngineUnavailable() async {
        let durable = Workflow()
            .step(MockAgentRuntime(response: "done"))
            .durable
            .configured(
                id: WorkflowCheckpointID("lean-configured"),
                store: .inMemory()
            )

        do {
            _ = try await durable.execute("start")
            Issue.record("configured execute should throw on lean builds")
        } catch let error as WorkflowError {
            guard case .durableRuntimeUnavailable(let reason) = error else {
                Issue.record("expected durableRuntimeUnavailable, got \(error)")
                return
            }
            #expect(reason.contains("Durable workflow execution"))
            #expect(reason.contains("Integrations trait"))
        } catch {
            Issue.record("expected WorkflowError, got \(error)")
        }
    }
}
#endif
