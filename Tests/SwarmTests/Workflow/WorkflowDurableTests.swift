import Foundation
import Testing
@testable import Swarm

@Suite("Workflow Advanced")
struct WorkflowDurableTests {
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
            .route { _ in nil as (any AgentRuntime)? }
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
            .route { _ in MockAgentRuntime(response: "changed-route") }
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
            .parallel([MockAgentRuntime(response: "branch")], merge: .custom { _ in "original-merge" })
            .durable
            .checkpoint(id: "wf-custom-merge-mismatch", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)

        _ = try await original.durable.execute("start")

        let changed = Workflow()
            .parallel([MockAgentRuntime(response: "branch")], merge: .custom { _ in "changed-merge" })
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
