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
            .checkpoint(id: "repeat-resume", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)

        _ = try await workflow.durable.execute("start")
        let resumed = try await workflow.durable.execute("ignored", resumeFrom: "repeat-resume")
        #expect(resumed.output == "done")
    }

    @Test("resume requires same workflow definition")
    func resumeRequiresSameDefinition() async throws {
        let checkpointing = WorkflowCheckpointing.inMemory()

        let first = Workflow()
            .step(MockAgentRuntime(response: "first"))
            .durable
            .checkpoint(id: "definition-check", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)

        _ = try await first.durable.execute("input")

        let second = Workflow()
            .step(MockAgentRuntime(response: "first"))
            .step(MockAgentRuntime(response: "second"))
            .durable
            .checkpoint(id: "definition-check", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)

        await #expect(throws: WorkflowError.self) {
            _ = try await second.durable.execute("input", resumeFrom: "definition-check")
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
