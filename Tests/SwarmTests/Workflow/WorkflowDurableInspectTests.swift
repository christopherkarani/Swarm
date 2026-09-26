#if SWARM_INTEGRATIONS
import Foundation
import HiveCore
@testable import Swarm
import Testing

@Suite("Durable workflow inspection")
struct WorkflowDurableInspectTests {
    @Test("inspect returns newest-last history after file-store durable execute")
    func inspectReturnsHistoryNewestLast() async throws {
        let directory = try makeInspectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WorkflowCheckpointing.fileSystem(directory: directory)
        let run = WorkflowCheckpointID("inspect-history")
        let durable = Workflow()
            .step(MockAgentRuntime(response: "one"))
            .step(MockAgentRuntime(response: "two"))
            .durable
            .configured(id: run, store: store, policy: .everyStep)

        let result = try await durable.execute("start")
        #expect(result.output == "two")

        let inspection = try await durable.inspect()
        #expect(inspection.run == run)
        #expect(inspection.checkpoints.count >= 2)

        let stepIndexes = inspection.checkpoints.map(\.stepIndex)
        #expect(stepIndexes == stepIndexes.sorted())

        #expect(inspection.isCompleted)
        #expect(inspection.latest?.isCompleted == true)
        #expect(inspection.latest?.lastResult?.output == "two")
        #expect(inspection.signatureMatches)
        #expect(inspection.checkpoints.allSatisfy(\.signatureMatches))

        let running = inspection.checkpoints.filter { !$0.isCompleted }
        #expect(!running.isEmpty)
        #expect(running.allSatisfy { $0.stepCursor != nil && $0.iterationCursor != nil })
    }

    @Test("inspect(run:) reads another run from the same store")
    func inspectRunReadsAnotherRun() async throws {
        let directory = try makeInspectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WorkflowCheckpointing.fileSystem(directory: directory)
        let first = WorkflowCheckpointID("inspect-first")
        let second = WorkflowCheckpointID("inspect-second")

        let firstDurable = Workflow()
            .step(MockAgentRuntime(response: "first-done"))
            .durable
            .configured(id: first, store: store, policy: .everyStep)
        _ = try await firstDurable.execute("start")

        let secondDurable = Workflow()
            .step(MockAgentRuntime(response: "second-done"))
            .durable
            .configured(id: second, store: store, policy: .everyStep)
        _ = try await secondDurable.execute("start")

        let inspection = try await firstDurable.inspect(run: second)
        #expect(inspection.run == second)
        #expect(!inspection.checkpoints.isEmpty)
        #expect(inspection.latest?.lastResult?.output == "second-done")
    }

    @Test("inspect skips corrupt checkpoint files")
    func inspectSkipsCorruptFiles() async throws {
        let directory = try makeInspectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WorkflowCheckpointing.fileSystem(directory: directory)
        let run = WorkflowCheckpointID("inspect-corrupt")
        let durable = Workflow()
            .step(MockAgentRuntime(response: "one"))
            .step(MockAgentRuntime(response: "two"))
            .durable
            .configured(id: run, store: store, policy: .everyStep)
        _ = try await durable.execute("start")

        let full = try await durable.inspect()
        #expect(full.checkpoints.count >= 2)

        let newestFileName = try newestManifestFileName(in: directory, run: run)
        try Data("{not-json".utf8).write(
            to: directory.appendingPathComponent(newestFileName),
            options: .atomic
        )

        let inspection = try await durable.inspect()
        #expect(inspection.checkpoints.count == full.checkpoints.count - 1)
        #expect(inspection.checkpoints.map(\.checkpointID) == full.checkpoints.dropLast().map(\.checkpointID))
    }

    @Test("inspect tolerates a missing manifest")
    func inspectToleratesMissingManifest() async throws {
        let directory = try makeInspectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WorkflowCheckpointing.fileSystem(directory: directory)
        let run = WorkflowCheckpointID("inspect-no-manifest")
        let durable = Workflow()
            .step(MockAgentRuntime(response: "done"))
            .durable
            .configured(id: run, store: store, policy: .everyStep)
        _ = try await durable.execute("start")
        let full = try await durable.inspect()

        try FileManager.default.removeItem(
            at: directory.appendingPathComponent(WorkflowFileCheckpointStore.manifestFileName)
        )

        let inspection = try await durable.inspect()
        #expect(inspection.checkpoints.map(\.checkpointID) == full.checkpoints.map(\.checkpointID))
    }

    @Test("inspect flags workflow signature mismatch")
    func inspectFlagsSignatureMismatch() async throws {
        let directory = try makeInspectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WorkflowCheckpointing.fileSystem(directory: directory)
        let run = WorkflowCheckpointID("inspect-mismatch")

        let original = Workflow()
            .step(MockAgentRuntime(response: "done"))
            .durable
            .configured(id: run, store: store, policy: .everyStep)
        _ = try await original.execute("start")
        #expect(try await original.inspect().signatureMatches)

        let changed = Workflow()
            .step(MockAgentRuntime(response: "done"))
            .step(MockAgentRuntime(response: "changed"))
            .durable
            .configured(id: WorkflowCheckpointID("inspect-mismatch-other"), store: store, policy: .everyStep)

        let inspection = try await changed.inspect(run: run)
        #expect(!inspection.checkpoints.isEmpty)
        #expect(!inspection.signatureMatches)
        #expect(inspection.checkpoints.allSatisfy { !$0.signatureMatches })
    }

    @Test("inspect throws checkpointNotFound for an unknown run")
    func inspectMissingRunThrows() async throws {
        let directory = try makeInspectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let durable = Workflow()
            .step(MockAgentRuntime(response: "done"))
            .durable
            .configured(
                id: WorkflowCheckpointID("inspect-known"),
                store: .fileSystem(directory: directory),
                policy: .everyStep
            )

        await #expect(throws: WorkflowError.checkpointNotFound(id: "inspect-missing")) {
            _ = try await durable.inspect(run: WorkflowCheckpointID("inspect-missing"))
        }
    }

    @Test("in-memory history is newest-last")
    func inMemoryHistoryIsNewestLast() async throws {
        let store = WorkflowCheckpointing.inMemory()
        let run = WorkflowCheckpointID("inspect-memory")
        let durable = Workflow()
            .step(MockAgentRuntime(response: "one"))
            .step(MockAgentRuntime(response: "two"))
            .durable
            .configured(id: run, store: store, policy: .everyStep)
        _ = try await durable.execute("start")

        let inspection = try await durable.inspect()
        #expect(inspection.checkpoints.count >= 2)
        let stepIndexes = inspection.checkpoints.map(\.stepIndex)
        #expect(stepIndexes == stepIndexes.sorted())
        #expect(inspection.isCompleted)
    }

    @Test("fork resumes an older checkpoint under a new run")
    func forkResumesOlderCheckpointUnderNewRun() async throws {
        let directory = try makeInspectDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WorkflowCheckpointing.fileSystem(directory: directory)
        let source = WorkflowCheckpointID("inspect-fork-source")
        let durable = Workflow()
            .step(MockAgentRuntime(response: "one"))
            .step(MockAgentRuntime(response: "two"))
            .durable
            .configured(id: source, store: store, policy: .everyStep)
        _ = try await durable.execute("start")

        let sourceHistory = try await durable.inspect()
        let forkPoint = try #require(sourceHistory.checkpoints.first(where: { !$0.isCompleted }))

        let target = WorkflowCheckpointID("inspect-fork-target")
        let forked = try await durable.resume("forked", from: target, forkingFrom: forkPoint.checkpointID)
        #expect(forked.output == "two")

        let targetHistory = try await durable.inspect(run: target)
        #expect(!targetHistory.checkpoints.isEmpty)
        #expect(targetHistory.isCompleted)
        #expect(targetHistory.latest?.lastResult?.output == "two")

        let sourceAfter = try await durable.inspect()
        #expect(sourceAfter.checkpoints.count == sourceHistory.checkpoints.count)
    }

    @Test("fork rejects a missing source checkpoint")
    func forkMissingSourceCheckpointThrows() async throws {
        let store = WorkflowCheckpointing.inMemory()
        let durable = Workflow()
            .step(MockAgentRuntime(response: "done"))
            .durable
            .configured(id: WorkflowCheckpointID("inspect-fork-known"), store: store, policy: .everyStep)
        _ = try await durable.execute("start")

        await #expect(throws: WorkflowError.checkpointNotFound(id: "inspect-fork-known")) {
            _ = try await durable.resume(
                "input",
                from: WorkflowCheckpointID("inspect-fork-new"),
                forkingFrom: "no-such-checkpoint"
            )
        }
    }

    @Test("fork rejects an existing target run")
    func forkExistingTargetThrowsInvalidWorkflow() async throws {
        let store = WorkflowCheckpointing.inMemory()
        let durable = Workflow()
            .step(MockAgentRuntime(response: "done"))
            .durable
            .configured(id: WorkflowCheckpointID("inspect-fork-claimed-source"), store: store, policy: .everyStep)
        _ = try await durable.execute("start")
        let forkPoint = try #require(try await durable.inspect().checkpoints.first)

        let target = WorkflowCheckpointID("inspect-fork-claimed-target")
        let occupant = Workflow()
            .step(MockAgentRuntime(response: "done"))
            .durable
            .configured(id: target, store: store, policy: .everyStep)
        _ = try await occupant.execute("start")

        do {
            _ = try await durable.resume("input", from: target, forkingFrom: forkPoint.checkpointID)
            Issue.record("fork into an existing run should throw")
        } catch let error as WorkflowError {
            guard case .invalidWorkflow = error else {
                Issue.record("expected invalidWorkflow, got \(error)")
                return
            }
        }
    }
}

private func makeInspectDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swarm-inspect-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func newestManifestFileName(in directory: URL, run: WorkflowCheckpointID) throws -> String {
    let manifestURL = directory.appendingPathComponent(WorkflowFileCheckpointStore.manifestFileName)
    let manifest = try JSONDecoder().decode(
        WorkflowCheckpointManifest.self,
        from: Data(contentsOf: manifestURL)
    )
    let entries = try #require(manifest.runs[run.rawValue])
    let newest = try #require(entries.max(by: { lhs, rhs in
        if lhs.stepIndex != rhs.stepIndex { return lhs.stepIndex < rhs.stepIndex }
        return lhs.checkpointID < rhs.checkpointID
    }))
    return newest.fileName
}
#endif

#if !SWARM_INTEGRATIONS
import Testing
@testable import Swarm

@Suite("Durable workflow inspection lean")
struct WorkflowDurableInspectLeanTests {
    @Test("inspect throws durableRuntimeUnavailable on lean builds")
    func inspectThrowsWhenEngineUnavailable() async {
        let durable = Workflow()
            .step(MockAgentRuntime(response: "done"))
            .durable
            .configured(
                id: WorkflowCheckpointID("lean-inspect"),
                store: .inMemory()
            )

        await #expect(throws: WorkflowError.self) {
            _ = try await durable.inspect()
        }
        do {
            _ = try await durable.inspect()
            Issue.record("inspect should throw on lean builds")
        } catch let error as WorkflowError {
            guard case .durableRuntimeUnavailable(let reason) = error else {
                Issue.record("expected durableRuntimeUnavailable, got \(error)")
                return
            }
            #expect(reason.contains("Durable workflow"))
        } catch {
            Issue.record("expected WorkflowError, got \(error)")
        }
    }

    @Test("fork resume throws durableRuntimeUnavailable on lean builds")
    func forkResumeThrowsWhenEngineUnavailable() async {
        let durable = Workflow()
            .step(MockAgentRuntime(response: "done"))
            .durable
            .configured(
                id: WorkflowCheckpointID("lean-fork"),
                store: .inMemory()
            )

        do {
            _ = try await durable.resume(
                "input",
                from: WorkflowCheckpointID("lean-fork-target"),
                forkingFrom: "cp-1"
            )
            Issue.record("fork resume should throw on lean builds")
        } catch let error as WorkflowError {
            guard case .durableRuntimeUnavailable = error else {
                Issue.record("expected durableRuntimeUnavailable, got \(error)")
                return
            }
        } catch {
            Issue.record("expected WorkflowError, got \(error)")
        }
    }
}
#endif
