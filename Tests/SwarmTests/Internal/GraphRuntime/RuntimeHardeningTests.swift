#if SWARM_INTEGRATIONS
import Foundation
import HiveCore
@_spi(ColonyInternal) @testable import Swarm
import Testing

@Suite("RuntimeHardening — state determinism")
struct RuntimeHardeningStateDiffTests {
    @Test("identical snapshots have no diff and the same final-state hash")
    func identicalSnapshotsMatch() throws {
        let lhs = makeSnapshot()
        let rhs = makeSnapshot()

        #expect(HiveDeterminism.firstStateDiff(expected: lhs, actual: rhs) == nil)
        #expect(try HiveDeterminism.finalStateHash(lhs) == HiveDeterminism.finalStateHash(rhs))
    }

    @Test("thread ID mismatch is reported first")
    func threadIDMismatch() {
        let diff = HiveDeterminism.firstStateDiff(
            expected: makeSnapshot(threadID: "a", stepIndex: 1),
            actual: makeSnapshot(threadID: "b", stepIndex: 2)
        )
        #expect(diff == HiveDeterminismDiff(path: "threadID", expected: "a", actual: "b"))
    }

    @Test("run identity is ignored by default and compared when requested")
    func runIdentityIsOptIn() throws {
        let lhs = makeSnapshot(runID: HiveRunID(UUID()), checkpointID: "cp-1")
        let rhs = makeSnapshot(runID: HiveRunID(UUID()), checkpointID: "cp-2")

        #expect(HiveDeterminism.firstStateDiff(expected: lhs, actual: rhs) == nil)
        #expect(try HiveDeterminism.finalStateHash(lhs) == HiveDeterminism.finalStateHash(rhs))

        let diff = HiveDeterminism.firstStateDiff(expected: lhs, actual: rhs, includeRuntimeIdentity: true)
        #expect(diff?.path == "runID")
        #expect(try HiveDeterminism.finalStateHash(lhs, includeRuntimeIdentity: true)
            != HiveDeterminism.finalStateHash(rhs, includeRuntimeIdentity: true))
    }

    @Test("checkpoint ID is compared only with runtime identity")
    func checkpointIDIsRuntimeIdentity() {
        let runID = HiveRunID(UUID())
        let diff = HiveDeterminism.firstStateDiff(
            expected: makeSnapshot(runID: runID, checkpointID: "cp-1"),
            actual: makeSnapshot(runID: runID, checkpointID: "cp-2"),
            includeRuntimeIdentity: true
        )
        #expect(diff == HiveDeterminismDiff(path: "checkpointID", expected: "Optional(\"cp-1\")", actual: "Optional(\"cp-2\")"))
    }

    @Test("step index mismatch is reported")
    func stepIndexMismatch() {
        let diff = HiveDeterminism.firstStateDiff(
            expected: makeSnapshot(stepIndex: 1),
            actual: makeSnapshot(stepIndex: 2)
        )
        #expect(diff?.path == "stepIndex")
    }

    @Test("interruption payload hash mismatch is reported without runtime identity")
    func interruptionPayloadMismatch() {
        let diff = HiveDeterminism.firstStateDiff(
            expected: makeSnapshot(interruption: .init(interruptID: HiveInterruptID("i-1"), payloadHash: "p1")),
            actual: makeSnapshot(interruption: .init(interruptID: HiveInterruptID("i-2"), payloadHash: "p2"))
        )
        #expect(diff == HiveDeterminismDiff(
            path: "interruption.payloadHash",
            expected: "Optional(\"p1\")",
            actual: "Optional(\"p2\")"
        ))
    }

    @Test("frontier hash mismatch is reported before entry details")
    func frontierHashMismatch() {
        let diff = HiveDeterminism.firstStateDiff(
            expected: makeSnapshot(frontier: frontier(hash: "h1", [entry("a")])),
            actual: makeSnapshot(frontier: frontier(hash: "h2", [entry("b")]))
        )
        #expect(diff == HiveDeterminismDiff(path: "frontier.hash", expected: "h1", actual: "h2"))
    }

    @Test("frontier entry fields are compared by index")
    func frontierEntryMismatch() {
        let provenance = HiveDeterminism.firstStateDiff(
            expected: makeSnapshot(frontier: frontier(hash: "h", [entry("a", provenance: .graph)])),
            actual: makeSnapshot(frontier: frontier(hash: "h", [entry("a", provenance: .spawn)]))
        )
        #expect(provenance == HiveDeterminismDiff(
            path: "frontier.entries[0].provenance",
            expected: "graph",
            actual: "spawn"
        ))

        let fingerprint = HiveDeterminism.firstStateDiff(
            expected: makeSnapshot(frontier: frontier(hash: "h", [entry("a"), entry("b", fingerprint: "f1")])),
            actual: makeSnapshot(frontier: frontier(hash: "h", [entry("a"), entry("b", fingerprint: "f2")]))
        )
        #expect(fingerprint?.path == "frontier.entries[1].localFingerprintHash")
    }

    @Test("channel entry payload hash mismatch is reported")
    func channelEntryMismatch() {
        let diff = HiveDeterminism.firstStateDiff(
            expected: makeSnapshot(channelState: channels(hash: "c", [("messages", "m1")])),
            actual: makeSnapshot(channelState: channels(hash: "c", [("messages", "m2")]))
        )
        #expect(diff == HiveDeterminismDiff(
            path: "channelState.entries[0].payloadHash",
            expected: "m1",
            actual: "m2"
        ))
    }

    @Test("missing channel state counts as zero entries")
    func missingChannelState() {
        let diff = HiveDeterminism.firstStateDiff(
            expected: makeSnapshot(channelState: channels(hash: "c", [("messages", "m1")])),
            actual: makeSnapshot(channelState: nil)
        )
        #expect(diff?.path == "channelState.hash")
    }

    @Test("snapshot source mismatch is reported last")
    func sourceMismatch() {
        let diff = HiveDeterminism.firstStateDiff(
            expected: makeSnapshot(source: .memory),
            actual: makeSnapshot(source: .checkpoint)
        )
        #expect(diff == HiveDeterminismDiff(path: "source", expected: "memory", actual: "checkpoint"))
    }
}

@Suite("RuntimeHardening — transcript determinism")
struct RuntimeHardeningTranscriptTests {
    @Test("projection orders events by index and rejects missing or foreign schema versions")
    func projectionOrdersAndValidatesSchema() throws {
        let runID = HiveRunID(UUID())
        let events = [
            event(runID: runID, index: 2, kind: .runFinished),
            event(runID: runID, index: 0, kind: .runStarted(threadID: HiveThreadID("t"))),
            event(runID: runID, index: 1, kind: .stepStarted(stepIndex: 0, frontierCount: 1), stepIndex: 0)
        ]

        let transcript = try HiveDeterminism.projectTranscript(events)
        #expect(transcript.events.map(\.eventIndex) == [0, 1, 2])

        let missing = event(runID: runID, index: 0, kind: .runFinished, metadata: [:])
        #expect(throws: HiveTranscriptCompatibilityError.missingSchemaVersion(eventIndex: 0)) {
            _ = try HiveDeterminism.projectTranscript([missing])
        }

        let foreign = event(
            runID: runID,
            index: 0,
            kind: .runFinished,
            metadata: [EventSchemaVersion.metadataKey: "other"]
        )
        #expect(throws: HiveTranscriptCompatibilityError.incompatibleSchemaVersion(
            expected: EventSchemaVersion.current,
            found: "other",
            eventIndex: 0
        )) {
            _ = try HiveDeterminism.transcriptHash([foreign])
        }
    }

    @Test("transcript diff reports schema, count, and per-event dictionary paths")
    func transcriptDiffPaths() {
        let base = transcript(events: [record(metadata: ["k": "v"], attributes: ["a": "1"])])

        #expect(HiveDeterminism.firstTranscriptDiff(expected: base, actual: base) == nil)

        let otherSchema = HiveCanonicalTranscript(schemaVersion: "other", events: base.events)
        #expect(HiveDeterminism.firstTranscriptDiff(expected: base, actual: otherSchema)?.path == "schemaVersion")

        let empty = transcript(events: [])
        #expect(HiveDeterminism.firstTranscriptDiff(expected: base, actual: empty)
            == HiveDeterminismDiff(path: "events.count", expected: "1", actual: "0"))

        let extraMetadata = transcript(events: [record(metadata: ["k": "v", "z": "new"], attributes: ["a": "1"])])
        #expect(HiveDeterminism.firstTranscriptDiff(expected: base, actual: extraMetadata)
            == HiveDeterminismDiff(path: "events[0].metadata.z", expected: "nil", actual: "Optional(\"new\")"))

        let changedAttribute = transcript(events: [record(metadata: ["k": "v"], attributes: ["a": "2"])])
        #expect(HiveDeterminism.firstTranscriptDiff(expected: base, actual: changedAttribute)?.path
            == "events[0].attributes.a")
    }
}

@Suite("RuntimeHardening — run option validation")
struct RuntimeHardeningRunOptionTests {
    @Test("missing model client is rejected before option bounds")
    func missingModelClient() throws {
        let controller = try makeController(model: nil)
        #expect(throws: SwarmRuntimeError.modelClientMissing) {
            try controller.validateRunOptions(HiveRunOptions(maxSteps: -1))
        }
    }

    @Test("missing tool registry is rejected")
    func missingToolRegistry() throws {
        let controller = try makeController(tools: nil)
        #expect(throws: SwarmRuntimeError.toolRegistryMissing) {
            try controller.validateRunOptions(HiveRunOptions())
        }
    }

    @Test("checkpointing policies require a checkpoint store")
    func checkpointPolicyRequiresStore() throws {
        let controller = try makeController()
        for policy: HiveCheckpointPolicy in [.everyStep, .every(steps: 2), .onInterrupt] {
            let error = runtimeError { try controller.validateRunOptions(HiveRunOptions(checkpointPolicy: policy)) }
            #expect(isCheckpointStoreMissing(error))
        }
        try controller.validateRunOptions(HiveRunOptions(checkpointPolicy: .disabled))
    }

    @Test("tool approval requires a checkpoint store")
    func toolApprovalRequiresStore() throws {
        let controller = try makeController(toolApprovalPolicy: .always)
        let error = runtimeError { try controller.validateRunOptions(HiveRunOptions()) }
        #expect(isCheckpointStoreMissing(error))
    }

    @Test("checkpoint every-N requires at least one step")
    func everyStepsLowerBound() throws {
        let controller = try makeController()
        let error = runtimeError {
            try controller.validateRunOptions(HiveRunOptions(checkpointPolicy: .every(steps: 0)))
        }
        #expect(invalidRunOptionsReason(error) == "checkpointPolicy.every requires steps >= 1")
    }

    @Test("compaction policy requires a tokenizer")
    func compactionRequiresTokenizer() throws {
        let controller = try makeController(
            compactionPolicy: HiveCompactionPolicy(maxTokens: 100, preserveLastMessages: 2)
        )
        let error = runtimeError { try controller.validateRunOptions(HiveRunOptions()) }
        #expect(invalidRunOptionsReason(error) == "Compaction policy requires a tokenizer.")
    }

    @Test("output projection rejects unknown channels and accepts known ones")
    func outputProjectionChannels() throws {
        let controller = try makeController()
        let error = runtimeError {
            try controller.validateRunOptions(
                HiveRunOptions(outputProjectionOverride: .channels([HiveChannelID("nope")]))
            )
        }
        #expect(invalidRunOptionsReason(error) == "output projection includes unknown channel nope")
        try controller.validateRunOptions(
            HiveRunOptions(outputProjectionOverride: .channels([ChatGraph.Schema.finalAnswerKey.id]))
        )
    }
}

// MARK: - Helpers

/// Runs `body` and returns the `HiveRuntimeError` it threw (`HiveRuntimeError` is not `Equatable`).
private func runtimeError(_ body: () throws -> Void) -> HiveRuntimeError? {
    do {
        try body()
    } catch let error as HiveRuntimeError {
        return error
    } catch {
        Issue.record("Expected HiveRuntimeError, got \(error)")
        return nil
    }
    Issue.record("Expected HiveRuntimeError, but nothing was thrown")
    return nil
}

private func isCheckpointStoreMissing(_ error: HiveRuntimeError?) -> Bool {
    if case .checkpointStoreMissing = error { return true }
    return false
}

private func invalidRunOptionsReason(_ error: HiveRuntimeError?) -> String? {
    if case let .invalidRunOptions(reason) = error { return reason }
    return nil
}

private func makeSnapshot(
    threadID: String = "thread",
    runID: HiveRunID? = nil,
    stepIndex: Int? = 3,
    interruption: HiveRuntimeInterruptionSummary<ChatGraph.Schema>? = nil,
    checkpointID: String? = nil,
    frontier: GraphRuntimeFrontierSummary = frontier(hash: "fh", [entry("a")]),
    channelState: HiveRuntimeChannelStateSummary? = channels(hash: "ch", [("messages", "m")]),
    source: HiveStateSnapshotSource = .memory
) -> GraphRuntimeStateSnapshot<ChatGraph.Schema> {
    GraphRuntimeStateSnapshot(
        threadID: HiveThreadID(threadID),
        runID: runID,
        stepIndex: stepIndex,
        interruption: interruption,
        checkpointID: checkpointID.map { HiveCheckpointID($0) },
        frontier: frontier,
        channelState: channelState,
        eventSchemaVersion: EventSchemaVersion.current,
        source: source
    )
}

private func frontier(hash: String, _ entries: [GraphRuntimeFrontierSummary.Entry]) -> GraphRuntimeFrontierSummary {
    GraphRuntimeFrontierSummary(count: entries.count, hash: hash, entries: entries)
}

private func entry(
    _ node: String,
    provenance: HiveTaskProvenance = .graph,
    fingerprint: String = "fp"
) -> GraphRuntimeFrontierSummary.Entry {
    GraphRuntimeFrontierSummary.Entry(
        nodeID: HiveNodeID(node),
        provenance: provenance,
        localFingerprintHash: fingerprint
    )
}

private func channels(hash: String, _ entries: [(String, String)]) -> HiveRuntimeChannelStateSummary {
    HiveRuntimeChannelStateSummary(
        hash: hash,
        entries: entries.map { .init(channelID: HiveChannelID($0.0), payloadHash: $0.1) }
    )
}

private func event(
    runID: HiveRunID,
    index: UInt64,
    kind: HiveEventKind,
    stepIndex: Int? = nil,
    metadata: [String: String] = [EventSchemaVersion.metadataKey: EventSchemaVersion.current]
) -> HiveEvent {
    HiveEvent(
        id: HiveEventID(
            runID: runID,
            attemptID: HiveRunAttemptID(UUID()),
            eventIndex: index,
            stepIndex: stepIndex,
            taskOrdinal: nil
        ),
        kind: kind,
        metadata: metadata
    )
}

private func transcript(events: [HiveCanonicalEventRecord]) -> HiveCanonicalTranscript {
    HiveCanonicalTranscript(schemaVersion: EventSchemaVersion.current, events: events)
}

private func record(metadata: [String: String], attributes: [String: String]) -> HiveCanonicalEventRecord {
    HiveCanonicalEventRecord(
        eventIndex: 0,
        stepIndex: nil,
        taskOrdinal: nil,
        kind: "runFinished",
        attributes: attributes,
        metadata: metadata
    )
}

private func makeController(
    model: AnyHiveModelClient? = AnyHiveModelClient(HardeningStubModelClient()),
    tools: AnyHiveToolRegistry? = AnyHiveToolRegistry(HardeningStubToolRegistry()),
    toolApprovalPolicy: ToolApprovalPolicy = .never,
    compactionPolicy: HiveCompactionPolicy? = nil
) throws -> GraphRunController {
    let context = RuntimeContext(
        modelName: "test-model",
        model: model,
        tools: tools,
        toolApprovalPolicy: toolApprovalPolicy,
        compactionPolicy: compactionPolicy
    )
    let environment = HiveEnvironment<ChatGraph.Schema>(
        context: context,
        clock: HardeningNoopClock(),
        logger: HardeningNoopLogger(),
        checkpointStore: nil
    )
    let runtime = try HiveRuntime(graph: ChatGraph.makeToolUsingChatAgent(), environment: environment)
    return GraphRunController(runtime: runtime)
}

private struct HardeningStubModelClient: HiveModelClient {
    func complete(_: HiveChatRequest) async throws -> HiveChatResponse {
        HiveChatResponse(message: HiveChatMessage(id: "m", role: .assistant, content: "ok"))
    }

    func stream(_: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.final(HiveChatResponse(message: HiveChatMessage(id: "m", role: .assistant, content: "ok"))))
            continuation.finish()
        }
    }
}

private struct HardeningStubToolRegistry: HiveToolRegistry {
    func listTools() -> [HiveToolDefinition] { [] }

    func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        HiveToolResult(toolCallID: call.id, content: "ok")
    }
}

private struct HardeningNoopClock: HiveClock {
    func nowNanoseconds() -> UInt64 { 0 }
    func sleep(nanoseconds _: UInt64) async throws {}
}

private struct HardeningNoopLogger: HiveLogger {
    func debug(_: String, metadata _: [String: String]) {}
    func info(_: String, metadata _: [String: String]) {}
    func error(_: String, metadata _: [String: String]) {}
}
#endif
