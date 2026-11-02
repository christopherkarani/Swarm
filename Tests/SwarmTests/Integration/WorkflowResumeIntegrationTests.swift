#if SWARM_INTEGRATIONS
import Foundation
import Testing
@testable import Swarm

@Suite("Workflow Resume Integration")
struct WorkflowResumeIntegrationTests {
    @Test("repeat workflow resumes from checkpointed progress")
    func repeatWorkflowResumes() async throws {
        let counter = ResumeCounter()
        let checkpointing = WorkflowCheckpointing.inMemory()

        let workflow = Workflow()
            .step(MockAgentRuntime(responseFactory: { counter.next() }))
            .repeatUntil(maxIterations: 10) { $0.output == "done" }
            .durable
            .configured(id: WorkflowCheckpointID("repeat-resume"), store: checkpointing, policy: .everyStep)

        _ = try await workflow.execute("start")
        let resumed = try await workflow.resume("ignored", from: WorkflowCheckpointID("repeat-resume"))
        #expect(resumed.output == "done")
    }

    @Test("resume requires same workflow definition")
    func resumeRequiresSameDefinition() async throws {
        let checkpointing = WorkflowCheckpointing.inMemory()

        let first = Workflow()
            .step(MockAgentRuntime(response: "first"))
            .durable
            .configured(id: WorkflowCheckpointID("definition-check"), store: checkpointing, policy: .everyStep)

        _ = try await first.execute("input")

        let second = Workflow()
            .step(MockAgentRuntime(response: "first"))
            .step(MockAgentRuntime(response: "second"))
            .durable
            .configured(id: WorkflowCheckpointID("definition-check"), store: checkpointing, policy: .everyStep)

        await #expect(throws: WorkflowError.self) {
            _ = try await second.resume("input", from: WorkflowCheckpointID("definition-check"))
        }
    }
}

private final class ResumeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value >= 2 ? "done" : "running"
    }
}
#endif
