import Foundation
import HiveCore
@testable import Swarm
@testable import SwarmHive
import Testing

@Suite("Membrane Hive Checkpoint Integration")
struct MembraneHiveCheckpointTests {
    @Test("Schema includes checkpointed membrane state channel")
    func schemaIncludesCheckpointedMembraneChannel() {
        let spec = ChatGraph.Schema.channelSpecs.first { $0.id.rawValue == "membraneCheckpointData" }
        #expect(spec != nil)
        #expect(spec?.persistence == .checkpointed)
    }

    @Test("Pre-model restores membrane checkpoint state before model invocation")
    func preModelRestoresBeforeModelInvocation() async throws {
        let graph = try ChatGraph.makeToolUsingChatAgent()
        let adapter = RecordingMembraneAdapter(snapshot: makeSnapshot(payload: "membrane-v1"))

        let context = RuntimeContext(
            modelName: "test-model",
            toolApprovalPolicy: .never,
            membraneCheckpointAdapter: adapter
        )

        let environment = HiveEnvironment<ChatGraph.Schema>(
            context: context,
            clock: NoopClock(),
            logger: NoopLogger(),
            model: AnyHiveModelClient(StubModelClient(chunks: [
                .final(HiveChatResponse(message: HiveChatMessage(
                    id: "m1",
                    role: .assistant,
                    content: "ok",
                    toolCalls: []
                )))
            ])),
            modelRouter: nil,
            tools: AnyHiveToolRegistry(StubToolRegistry(resultContent: "ok")),
            checkpointStore: nil
        )

        let runtime = try HiveRuntime(graph: graph, environment: environment)
        let outcome = try await waitOutcome(
            await runtime.run(
                threadID: HiveThreadID("membrane-restore-order"),
                input: "hello",
                options: HiveRunOptions(maxSteps: 5, checkpointPolicy: .disabled)
            )
        )
        _ = try requireFullStore(outcome: outcome)

        let restoreCount = await adapter.restoreCount()
        #expect(restoreCount > 0)
    }

    @Test("Checkpoint payload restores across runtime resume path")
    func checkpointPayloadRestoresAcrossResumePath() async throws {
        let graph = try ChatGraph.makeToolUsingChatAgent()
        let checkpointStore = InMemoryCheckpointStore<ChatGraph.Schema>()

        let writerAdapter = RecordingMembraneAdapter(snapshot: makeSnapshot(payload: "state-v1"))
        let writerContext = RuntimeContext(
            modelName: "test-model",
            toolApprovalPolicy: .never,
            membraneCheckpointAdapter: writerAdapter
        )
        let writerEnvironment = HiveEnvironment<ChatGraph.Schema>(
            context: writerContext,
            clock: NoopClock(),
            logger: NoopLogger(),
            model: AnyHiveModelClient(StubModelClient(chunks: [
                .final(HiveChatResponse(message: HiveChatMessage(
                    id: "writer-final",
                    role: .assistant,
                    content: "writer done",
                    toolCalls: []
                )))
            ])),
            modelRouter: nil,
            tools: AnyHiveToolRegistry(StubToolRegistry(resultContent: "ok")),
            checkpointStore: AnyHiveCheckpointStore(checkpointStore)
        )

        let writerRuntime = try HiveRuntime(graph: graph, environment: writerEnvironment)
        _ = try await waitOutcome(
            await writerRuntime.run(
                threadID: HiveThreadID("membrane-checkpoint-thread"),
                input: "seed",
                options: HiveRunOptions(maxSteps: 5, checkpointPolicy: .everyStep)
            )
        )

        let restoredAdapter = RecordingMembraneAdapter(snapshot: nil)
        let restoredContext = RuntimeContext(
            modelName: "test-model",
            toolApprovalPolicy: .never,
            membraneCheckpointAdapter: restoredAdapter
        )
        let restoredEnvironment = HiveEnvironment<ChatGraph.Schema>(
            context: restoredContext,
            clock: NoopClock(),
            logger: NoopLogger(),
            model: AnyHiveModelClient(StubModelClient(chunks: [
                .final(HiveChatResponse(message: HiveChatMessage(
                    id: "reader-final",
                    role: .assistant,
                    content: "reader done",
                    toolCalls: []
                )))
            ])),
            modelRouter: nil,
            tools: AnyHiveToolRegistry(StubToolRegistry(resultContent: "ok")),
            checkpointStore: AnyHiveCheckpointStore(checkpointStore)
        )

        let restoredRuntime = try HiveRuntime(graph: graph, environment: restoredEnvironment)
        _ = try await waitOutcome(
            await restoredRuntime.run(
                threadID: HiveThreadID("membrane-checkpoint-thread"),
                input: "resume",
                options: HiveRunOptions(maxSteps: 5, checkpointPolicy: .disabled)
            )
        )

        let restored = await restoredAdapter.lastRestoredSnapshot()
        #expect(restored?.backendState == Data("state-v1".utf8))
    }
}

private actor RecordingMembraneAdapter: MembraneCheckpointAdapter {
    private var restored: MembraneContextSnapshot?
    private var restoreCalls: Int = 0
    private let storedSnapshot: MembraneContextSnapshot?

    init(snapshot: MembraneContextSnapshot?) {
        storedSnapshot = snapshot
    }

    func restore(snapshot: MembraneContextSnapshot?) async throws {
        restoreCalls += 1
        restored = snapshot
    }

    func snapshot() async throws -> MembraneContextSnapshot? {
        storedSnapshot ?? restored
    }

    func lastRestoredSnapshot() -> MembraneContextSnapshot? {
        restored
    }

    func restoreCount() -> Int {
        restoreCalls
    }
}

private func makeSnapshot(payload: String) -> MembraneContextSnapshot {
    MembraneContextSnapshot(
        budget: .init(totalTokens: 2048),
        csoSummaries: [],
        pagingCursor: nil,
        toolState: .init(mode: .allowAll, loadedToolNames: [], allowListToolNames: [], usageCounts: []),
        pointerIDs: [],
        backendID: "test",
        backendState: Data(payload.utf8)
    )
}

private struct StubModelClient: HiveModelClient {
    let chunks: [HiveChatStreamChunk]

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        for chunk in chunks {
            if case let .final(response) = chunk {
                return response
            }
        }
        return HiveChatResponse(message: HiveChatMessage(id: "fallback", role: .assistant, content: ""))
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

private struct StubToolRegistry: HiveToolRegistry, Sendable {
    let resultContent: String

    func listTools() -> [HiveToolDefinition] { [] }

    func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        HiveToolResult(toolCallID: call.id, content: resultContent)
    }
}

private struct NoopClock: HiveClock {
    func nowNanoseconds() -> UInt64 { 0 }
    func sleep(nanoseconds: UInt64) async throws { try await Task.sleep(nanoseconds: nanoseconds) }
}

private struct NoopLogger: HiveLogger {
    func debug(_ message: String, metadata: [String: String]) {}
    func info(_ message: String, metadata: [String: String]) {}
    func error(_ message: String, metadata: [String: String]) {}
}

private actor InMemoryCheckpointStore<Schema: HiveSchema>: HiveCheckpointStore {
    private var checkpoints: [HiveCheckpoint<Schema>] = []

    func save(_ checkpoint: HiveCheckpoint<Schema>) async throws {
        checkpoints.append(checkpoint)
    }

    func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<Schema>? {
        checkpoints
            .filter { $0.threadID == threadID }
            .max { lhs, rhs in
                if lhs.stepIndex == rhs.stepIndex {
                    return lhs.id.rawValue < rhs.id.rawValue
                }
                return lhs.stepIndex < rhs.stepIndex
            }
    }
}

private func waitOutcome<Schema: HiveSchema>(
    _ handle: HiveRunHandle<Schema>
) async throws -> HiveRunOutcome<Schema> {
    try await handle.outcome.value
}

private func requireFullStore<Schema: HiveSchema>(outcome: HiveRunOutcome<Schema>) throws -> HiveGlobalStore<Schema> {
    switch outcome {
    case let .finished(output, _),
         let .cancelled(output, _),
         let .outOfSteps(_, output, _):
        switch output {
        case let .fullStore(store):
            return store
        case .channels:
            throw TestFailure("Expected full store output.")
        }
    case .interrupted:
        throw TestFailure("Expected non-interrupted outcome.")
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
