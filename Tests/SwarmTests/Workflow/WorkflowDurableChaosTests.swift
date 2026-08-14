#if SWARM_INTEGRATIONS
import Foundation
import HiveCore
@testable import Swarm
import Testing

@Suite("Workflow durable chaos")
struct WorkflowDurableChaosTests {
    @Test("resume survives engineered kills and preserves step granularity")
    func resumeSurvivesEngineeredKills() async throws {
        for iteration in 0 ..< 3 {
            try await runChaosScenario(iteration: iteration)
        }
    }
}

private func runChaosScenario(iteration: Int) async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swarm-chaos-\(iteration)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let log = ExecutionLog()
    let checkpointing = WorkflowCheckpointing.fileSystem(
        directory: directory,
        retention: WorkflowCheckpointRetention(maxCheckpointsPerRun: 8)
    )
    let checkpointID = "chaos-\(iteration)"
    let faults: [WorkflowDurableFaultPoint] = [
        .midStep,
        .beforeCheckpointWrite,
        .afterCheckpointWrite,
        .midStep,
        .beforeCheckpointWrite,
        .afterCheckpointWrite,
    ]
    let controller = WorkflowDurableFaultController(queue: faults)

    try await WorkflowDurableFaultInjection.$controller.withValue(controller) {
        for index in faults.indices {
            let resumeFrom = try await checkpointing.containsCheckpoint(for: checkpointID)
                ? checkpointID
                : nil
            do {
                _ = try await makeChaosWorkflow(
                    log: log,
                    checkpointing: checkpointing,
                    checkpointID: checkpointID
                ).durable.execute("start", resumeFrom: resumeFrom)
                Issue.record("expected injected fault \(faults[index]) on attempt \(index)")
            } catch let fault as WorkflowDurableInjectedFault {
                #expect(fault.point == faults[index])
            }
        }
    }

    let result = try await makeChaosWorkflow(
        log: log,
        checkpointing: checkpointing,
        checkpointID: checkpointID
    ).durable.execute("ignored", resumeFrom: checkpointID)

    #expect(result.output == "C")
    let counts = await log.counts
    #expect(counts["A"] == 3)
    #expect(counts["B"] == 3)
    #expect(counts["C"] == 1)
    #expect(await controller.injected == faults)

    try assertCheckpointsAreWellFormed(in: directory)
}

private func makeChaosWorkflow(
    log: ExecutionLog,
    checkpointing: WorkflowCheckpointing,
    checkpointID: String
) -> Workflow {
    Workflow()
        .step(ChaosAgent(label: "A", log: log))
        .step(ChaosAgent(label: "B", log: log))
        .step(ChaosAgent(label: "C", log: log))
        .durable
        .checkpoint(id: checkpointID, policy: .everyStep)
        .durable
        .checkpointing(checkpointing)
}

private func assertCheckpointsAreWellFormed(in directory: URL) throws {
    let urls = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    )
    let decoder = JSONDecoder()
    var decodedCheckpoints = 0

    for url in urls {
        let name = url.lastPathComponent
        let data = try Data(contentsOf: url)
        if name == WorkflowFileCheckpointStore.manifestFileName {
            let manifest = try decoder.decode(WorkflowCheckpointManifest.self, from: data)
            #expect(manifest.version == 1)
            continue
        }
        #expect(name.hasSuffix(".json"))
        _ = try decoder.decode(HiveCheckpoint<WorkflowDurableSchema>.self, from: data)
        decodedCheckpoints += 1
    }

    #expect(decodedCheckpoints > 0)
}

private actor ExecutionLog {
    private var values: [String] = []

    func record(_ label: String) {
        values.append(label)
    }

    var counts: [String: Int] {
        values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }
}

private actor ChaosAgent: AgentRuntime {
    nonisolated let label: String
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions: String
    nonisolated let configuration: AgentConfiguration
    nonisolated let handoffs: [AnyHandoffConfiguration] = []
    private let log: ExecutionLog

    init(label: String, log: ExecutionLog) {
        self.label = label
        self.log = log
        instructions = label
        configuration = AgentConfiguration(name: label)
    }

    func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult {
        await log.record(label)
        if let controller = WorkflowDurableFaultInjection.controller {
            try await controller.consumeMidStep()
        }
        return AgentResult(output: label)
    }

    nonisolated func stream(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.finish(throwing: AgentError.internalError(reason: "chaos agent does not stream"))
        }
    }

    func cancel() async {}
}
#endif
