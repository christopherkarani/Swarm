#if SWARM_INTEGRATIONS
import Foundation
import Testing
@testable import Swarm

@Suite("Workflow Hive Engine")
struct WorkflowHiveEngineTests {
    @Test("durable checkpoint everyStep supports resume")
    func checkpointEveryStepSupportsResume() async throws {
        let checkpointing = WorkflowCheckpointing.inMemory()
        let workflow = Workflow()
            .step(LocalConstantAgent(output: "ok"))
            .durable
            .checkpoint(id: "hive-engine-1", policy: .everyStep)
            .durable
            .checkpointing(checkpointing)

        let first = try await workflow.durable.execute("start")
        #expect(first.output == "ok")

        let resumed = try await workflow.durable.execute("ignored", resumeFrom: "hive-engine-1")
        #expect(resumed.output == "ok")
    }

    @Test("durable checkpoint endOnly persists final checkpoint")
    func checkpointEndOnlyPersistsFinalCheckpoint() async throws {
        let checkpointing = WorkflowCheckpointing.inMemory()
        let workflow = Workflow()
            .step(LocalConstantAgent(output: "final"))
            .durable
            .checkpoint(id: "hive-engine-2", policy: .onCompletion)
            .durable
            .checkpointing(checkpointing)

        _ = try await workflow.durable.execute("start")
        let resumed = try await workflow.durable.execute("ignored", resumeFrom: "hive-engine-2")
        #expect(resumed.output == "final")
    }
}

private struct LocalConstantAgent: AgentRuntime {
    let output: String

    init(output: String) {
        self.output = output
    }

    var tools: [any AnyJSONTool] { [] }
    var instructions: String { "LocalConstantAgent" }
    var configuration: AgentConfiguration { AgentConfiguration(name: "LocalConstantAgent") }
    var handoffs: [AnyHandoffConfiguration] { [] }

    func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult {
        AgentResult(output: output)
    }

    func stream(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.yield(.lifecycle(.started(input: input)))
            continuation.yield(.lifecycle(.completed(result: AgentResult(output: self.output))))
            continuation.finish()
        }
    }

    func cancel() async {}
}
#endif
