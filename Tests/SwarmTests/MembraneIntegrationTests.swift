#if SWARM_INTEGRATIONS
import Foundation
import MembraneCore
@testable import Swarm
import Testing
import Wax

@Suite("Membrane Integration")
struct MembraneIntegrationTests {
    #if canImport(Membrane)
    @Test("strict4k_jitAvoidsPromptEnvelopeTruncation")
    func strict4k_jitAvoidsPromptEnvelopeTruncation() async throws {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(content: "ok", toolCalls: [], finishReason: .completed),
        ])

        let session = try await makeLargeSession()
        let tools = makeTestTools(count: 30)
        let agent = try Agent(
            tools: tools,
            instructions: longBlock("instructions", lines: 220),
            configuration: AgentConfiguration(
                name: "strict4k-membrane",
                contextMode: .strict4k,
                defaultTracingEnabled: false
            ),
            inferenceProvider: provider,
            runEnvironment: AgentRunEnvironment(defaultMemoryStoreURL: temporaryWaxStoreURL())
        ).environment(
            \.membrane,
            MembraneEnvironment(
                isEnabled: true,
                configuration: MembraneFeatureConfiguration(
                    jitMinToolCount: 10,
                    defaultJITLoadCount: 6,
                    pointerThresholdBytes: 1024,
                    pointerSummaryMaxChars: 200
                )
            )
        )

        _ = try await agent.run("needle-user-input", session: session, observer: nil)

        let prompt = try #require(await lastToolPrompt(from: provider))
        let plannedTools = try #require(await lastToolSchemas(from: provider))

        #expect(!prompt.contains("[... context truncated for strict4k budget ...]"))

        #expect(plannedTools.count < tools.count)
        #expect((await provider.tokenCountCalls).isEmpty == false)

        let schemaNames = plannedTools.map(\.name)
        #expect(schemaNames == schemaNames.sorted {
            $0.utf8.lexicographicallyPrecedes($1.utf8)
        })
        #expect(schemaNames.contains("membrane_load_tool_schema"))
        #expect(schemaNames.contains("Add_Tools"))
        #expect(schemaNames.contains("Remove_Tools"))
        #expect(schemaNames.contains("resolve_pointer"))
    }
    #endif

    @Test("membraneRuntimeFeatureFlagsPropagateToProviderSettings")
    func membraneRuntimeFeatureFlagsPropagateToProviderSettings() async throws {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(content: "ok", toolCalls: [], finishReason: .completed),
        ])

        let tools = [MembraneTestTool(name: "runtime_test_tool")]
        let agent = try Agent(
            tools: tools,
            instructions: "Runtime flags test",
            configuration: AgentConfiguration(
                name: "membrane-runtime-flags",
                contextMode: .strict4k,
                defaultTracingEnabled: false
            ),
            inferenceProvider: provider,
            runEnvironment: AgentRunEnvironment(defaultMemoryStoreURL: temporaryWaxStoreURL())
        ).environment(
            \.membrane,
            MembraneEnvironment(
                isEnabled: true,
                configuration: MembraneFeatureConfiguration(
                    runtimeFeatureFlags: [
                        "conduit.runtime.kv_quantization": true,
                        "conduit.runtime.attention_sinks": false,
                        "conduit.runtime.kv_swap": true,
                        "conduit.runtime.incremental_prefill": true,
                        "conduit.runtime.speculative": true,
                    ],
                    runtimeModelAllowlist: ["mlx-community/model-b", "mlx-community/model-a"]
                )
            )
        )

        _ = try await agent.run("hello")

        let providerSettings = try #require(await lastToolProviderSettings(from: provider))

        #expect(providerSettings["conduit.runtime.policy.kv_quantization.enabled"] == .bool(true))
        #expect(providerSettings["conduit.runtime.policy.attention_sinks.enabled"] == .bool(false))
        #expect(providerSettings["conduit.runtime.policy.kv_swap.enabled"] == .bool(true))
        #expect(providerSettings["conduit.runtime.policy.incremental_prefill.enabled"] == .bool(true))
        #expect(providerSettings["conduit.runtime.policy.speculative.enabled"] == .bool(true))
        #expect(providerSettings["conduit.runtime.policy.model_allowlist"] == .array([.string("mlx-community/model-a"), .string("mlx-community/model-b")]))
    }

    @Test("membraneThrowFallsBackWithoutCrash")
    func membraneThrowFallsBackWithoutCrash() async throws {
        let provider = MockInferenceProvider(responses: ["fallback-ok"])
        let throwingAdapter = ThrowingMembraneAdapter()
        let agent = try Agent(
            tools: [],
            instructions: "Fallback test",
            configuration: AgentConfiguration(
                name: "membrane-fallback",
                contextMode: .strict4k,
                defaultTracingEnabled: false
            ),
            inferenceProvider: provider,
            runEnvironment: AgentRunEnvironment(defaultMemoryStoreURL: temporaryWaxStoreURL())
        ).environment(
            \.membrane,
            MembraneEnvironment(isEnabled: true, adapter: throwingAdapter)
        )

        let result = try await agent.run("hello")

        #expect(result.output == "fallback-ok")
        #expect(result.metadata["membrane.fallback.used"] == .bool(true))
        #expect(result.metadata["membrane.fallback.error"]?.stringValue?.contains("forced membrane failure") == true)
    }

    #if canImport(Membrane)
    @Test("Pointerized structured tool output resolves as JSON")
    func pointerizedStructuredToolOutputResolvesAsJSON() async throws {
        let provider = PointerResolvingInferenceProvider()
        let agent = try Agent(
            tools: [StructuredPayloadTool()],
            instructions: "Call the structured payload tool, resolve the pointer, then finish.",
            configuration: AgentConfiguration(
                name: "membrane-structured-tool-output",
                maxIterations: 4,
                defaultTracingEnabled: false
            ),
            inferenceProvider: provider,
            runEnvironment: AgentRunEnvironment(defaultMemoryStoreURL: temporaryWaxStoreURL())
        ).environment(
            \.membrane,
            MembraneEnvironment(
                isEnabled: true,
                configuration: MembraneFeatureConfiguration(
                    jitMinToolCount: 12,
                    defaultJITLoadCount: 2,
                    pointerThresholdBytes: 32,
                    pointerSummaryMaxChars: 80
                )
            )
        )

        let result = try await agent.run("exercise pointerized structured output")

        let resolvedPointerOutput = try #require(result.toolResults.last?.output.stringValue)
        let data = Data(resolvedPointerOutput.utf8)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dictionary = try #require(object)
        #expect(dictionary["message"] as? String == "quoted \"value\" with newline\nsecond line")
        #expect(dictionary["count"] as? Int == 42)
    }
    #endif

    // MARK: - one-8h1.10 characterization (OneWorkspace investigation)
    //
    // Manual gate transcript 2026-05-08T05:13Z saw `Tool 'Add_Tools' failed:
    // ... (Swarm.MembraneAgentAdapterError error 1.)`. These tests prove
    // what `error 1` actually means and how it's triggered, so callers
    // (and forks consuming this adapter) can map the error correctly
    // without a magic-number lookup.

    #if canImport(Membrane)
    @Test("Add_Tools called with missing tool_names argument throws invalidInternalToolArguments (`error 1`)")
    func addToolsMissingArgsThrowsErrorCase1() async throws {
        let adapter = DefaultMembraneAgentAdapter(
            configuration: MembraneFeatureConfiguration(jitMinToolCount: 2, defaultJITLoadCount: 1)
        )
        await #expect(throws: MembraneAgentAdapterError.self) {
            _ = try await adapter.handleInternalToolCall(
                name: MembraneInternalToolName.addTools,
                arguments: [:]  // No tool_names key at all.
            )
        }
        // Empty array: same outcome (parseToolNames returns []).
        await #expect(throws: MembraneAgentAdapterError.self) {
            _ = try await adapter.handleInternalToolCall(
                name: MembraneInternalToolName.addTools,
                arguments: ["tool_names": .array([])]
            )
        }
    }

    @Test("membrane_load_tool_schema with missing or empty tool_name throws invalidInternalToolArguments")
    func loadToolSchemaMissingArgThrowsErrorCase1() async throws {
        let adapter = DefaultMembraneAgentAdapter(
            configuration: MembraneFeatureConfiguration(jitMinToolCount: 2, defaultJITLoadCount: 1)
        )
        await #expect(throws: MembraneAgentAdapterError.self) {
            _ = try await adapter.handleInternalToolCall(
                name: MembraneInternalToolName.loadToolSchema,
                arguments: [:]
            )
        }
        await #expect(throws: MembraneAgentAdapterError.self) {
            _ = try await adapter.handleInternalToolCall(
                name: MembraneInternalToolName.loadToolSchema,
                arguments: ["tool_name": .string("")]
            )
        }
    }
    #endif

    @Test("MembraneAgentAdapterError.invalidInternalToolArguments is the second case (NSError code 1)")
    func errorCaseOrdinalIsOne() {
        // Swift bridges enum-with-payload to NSError using the case
        // declaration order. unsupportedInternalTool is case 0,
        // invalidInternalToolArguments is case 1. The 'error 1' string
        // in production transcripts maps to invalidInternalToolArguments.
        let error = MembraneAgentAdapterError.invalidInternalToolArguments(
            name: "Add_Tools",
            reason: "Missing required array argument: tool_names"
        )
        let nsError = error as NSError
        #expect(nsError.code == 1)
        // unsupportedInternalTool is the other case at code 0.
        let other = MembraneAgentAdapterError.unsupportedInternalTool(name: "x")
        let otherNS = other as NSError
        #expect(otherNS.code == 0)
    }

    #if canImport(Membrane)
    @Test("Add_Tools with valid tool_names succeeds and returns confirmation message")
    func addToolsValidArgsSucceeds() async throws {
        let adapter = DefaultMembraneAgentAdapter(
            configuration: MembraneFeatureConfiguration(jitMinToolCount: 2, defaultJITLoadCount: 1)
        )
        let result = try await adapter.handleInternalToolCall(
            name: MembraneInternalToolName.addTools,
            arguments: ["tool_names": .array([.string("listDatabases"), .string("getSchemaModel")])]
        )
        #expect(result?.contains("listDatabases") == true)
        #expect(result?.contains("getSchemaModel") == true)
    }

    @Test("Default adapter checkpoint state roundtrips loaded tools")
    func defaultAdapterCheckpointRoundtrip() async throws {
        let adapter = DefaultMembraneAgentAdapter(
            configuration: MembraneFeatureConfiguration(jitMinToolCount: 2, defaultJITLoadCount: 1)
        )
        _ = try await adapter.handleInternalToolCall(
            name: MembraneInternalToolName.addTools,
            arguments: ["tool_names": .array([.string("zzz_tool")])]
        )
        let snapshot = try await adapter.snapshotCheckpointData()
        #expect(snapshot != nil)

        let restored = DefaultMembraneAgentAdapter(
            configuration: MembraneFeatureConfiguration(jitMinToolCount: 2, defaultJITLoadCount: 1)
        )
        try await restored.restore(checkpointData: snapshot)

        let planned = try await restored.plan(
            prompt: "hello",
            toolSchemas: defaultAdapterToolSchemas(),
            profile: .strict4k
        )

        #expect(planned.toolSchemas.contains(where: { $0.name == "zzz_tool" }))
    }

    @Test("Default adapter restore(nil) clears checkpointed state")
    func defaultAdapterRestoreNilClearsState() async throws {
        let adapter = DefaultMembraneAgentAdapter(
            configuration: MembraneFeatureConfiguration(jitMinToolCount: 2, defaultJITLoadCount: 1)
        )
        _ = try await adapter.handleInternalToolCall(
            name: MembraneInternalToolName.addTools,
            arguments: ["tool_names": .array([.string("zzz_tool")])]
        )

        try await adapter.restore(checkpointData: nil)

        let planned = try await adapter.plan(
            prompt: "hello",
            toolSchemas: defaultAdapterToolSchemas(),
            profile: .strict4k
        )
        #expect(planned.toolSchemas.contains(where: { $0.name == "zzz_tool" }) == false)
    }
    #endif

    @Test("strict4k planning does not drop tools when below jit threshold")
    func strict4kPlanningKeepsSmallToolSetsVisible() async throws {
        let adapter = DefaultMembraneAgentAdapter(
            configuration: MembraneFeatureConfiguration(jitMinToolCount: 12, defaultJITLoadCount: 2)
        )
        let toolSchemas = [
            ToolSchema(name: "alpha", description: "alpha", parameters: []),
            ToolSchema(name: "beta", description: "beta", parameters: []),
            ToolSchema(name: "gamma", description: "gamma", parameters: []),
        ]

        let planned = try await adapter.plan(
            prompt: "hello",
            toolSchemas: toolSchemas,
            profile: .strict4k
        )

        let names = Set(planned.toolSchemas.map(\.name))
        #expect(names.contains("alpha"))
        #expect(names.contains("beta"))
        #expect(names.contains("gamma"))
    }

    #if canImport(Membrane)
    @Test("strict4k planning enters JIT at the lowered four-tool threshold")
    func strict4kPlanningUsesLoweredJITThreshold() async throws {
        let adapter = DefaultMembraneAgentAdapter(
            configuration: MembraneFeatureConfiguration(jitMinToolCount: 12, defaultJITLoadCount: 2)
        )
        let toolSchemas = [
            ToolSchema(name: "alpha", description: "alpha", parameters: []),
            ToolSchema(name: "beta", description: "beta", parameters: []),
            ToolSchema(name: "gamma", description: "gamma", parameters: []),
            ToolSchema(name: "delta", description: "delta", parameters: []),
        ]

        let planned = try await adapter.plan(
            prompt: "hello",
            toolSchemas: toolSchemas,
            profile: .strict4k
        )

        let names = Set(planned.toolSchemas.map(\.name))
        #expect(planned.mode == "jit")
        #expect(names.contains("alpha"))
        #expect(names.contains("beta"))
        #expect(names.contains("gamma") == false)
        #expect(names.contains("delta") == false)
        #expect(names.contains(MembraneInternalToolName.loadToolSchema))
        #expect(names.contains(MembraneInternalToolName.addTools))
        #expect(names.contains(MembraneInternalToolName.removeTools))
        #expect(names.contains(MembraneInternalToolName.resolvePointer))
    }
    #endif

    #if canImport(SQLite3)
    @Test("Wax membrane pointer recall does not index private payload bytes")
    func waxMembranePointerRecallDoesNotIndexPrivatePayloadBytes() async throws {
        let storage = WaxMembraneStorage(url: temporaryWaxStoreURL())
        let secret = "SWARM-AUDIT-040-private-payload-\(UUID().uuidString)"
        _ = try await storage.store(
            payload: Data(secret.utf8),
            dataType: .document,
            summary: "Public pointer summary only"
        )

        let secretMatches = try await storage.recall(query: secret, limit: 5)
        #expect(secretMatches.allSatisfy { !$0.content.contains(secret) })

        let summaryMatches = try await storage.recall(query: "Public pointer summary", limit: 5)
        #expect(summaryMatches.contains { $0.content.contains("Public pointer summary") })
        #expect(summaryMatches.allSatisfy { !$0.content.contains(secret) })
        #expect(summaryMatches.allSatisfy { !$0.content.contains("__payload_base64__") })
        #expect(summaryMatches.allSatisfy { !$0.content.contains(Data(secret.utf8).base64EncodedString()) })
    }

    @Test("Wax membrane pointer delete removes persisted payload")
    func waxMembranePointerDeleteRemovesPersistedPayload() async throws {
        let url = temporaryWaxStoreURL()
        let storage = WaxMembraneStorage(url: url)
        let payload = Data("SWARM-AUDIT-041-persisted-delete".utf8)
        let pointer = try await storage.store(
            payload: payload,
            dataType: .document,
            summary: "Delete me"
        )
        #expect(try await storage.resolve(pointerID: pointer.id) == payload)

        await storage.delete(pointerID: pointer.id)

        await #expect(throws: MembraneError.self) {
            _ = try await storage.resolve(pointerID: pointer.id)
        }

        let matches = try await storage.recall(query: "Delete me", limit: 5)
        #expect(matches.allSatisfy { $0.provenance.metadata["membrane.pointer.id"] != pointer.id })
    }
    #endif

    @Test("Wax membrane pointer store rolls back payload frame when indexing fails")
    func waxMembranePointerStoreRollsBackPayloadFrameWhenIndexingFails() async throws {
        let url = temporaryWaxStoreURL()
        let failingIndex = FailingWaxPointerIndex()
        let storage = WaxMembraneStorage(url: url) { _ in failingIndex }

        await #expect(throws: FailingWaxPointerIndex.Failure.self) {
            _ = try await storage.store(
                payload: Data("SWARM-AUDIT-042-rollback-payload".utf8),
                dataType: .document,
                summary: "Must roll back"
            )
        }

        let frameStore = try await Wax.FrameStore.open(at: url)
        let activePayloadFrames = await frameStore.frames().filter {
            $0.status == .active &&
                $0.metadata["membrane.kind"] == "membrane.pointer.payloadFrame"
        }
        await frameStore.close()

        #expect(activePayloadFrames.isEmpty)
    }
}

private func defaultAdapterToolSchemas() -> [ToolSchema] {
    let names = (0 ..< 6).map { String(format: "tool_%02d", $0) } + ["zzz_tool"]
    return names.map { name in
        ToolSchema(name: name, description: "test \(name)", parameters: [])
    }
}

private func lastToolPrompt(from provider: MockInferenceProvider) async -> String? {
    if let lastCall = await provider.toolCallCalls.last {
        return lastCall.prompt
    }
    if let lastCall = await provider.toolCallMessageCalls.last {
        return InferenceMessage.flattenPrompt(lastCall.messages)
    }
    return nil
}

private func lastToolSchemas(from provider: MockInferenceProvider) async -> [ToolSchema]? {
    if let lastCall = await provider.toolCallCalls.last {
        return lastCall.tools
    }
    if let lastCall = await provider.toolCallMessageCalls.last {
        return lastCall.tools
    }
    return nil
}

private func lastToolProviderSettings(from provider: MockInferenceProvider) async -> [String: SendableValue]? {
    if let lastCall = await provider.toolCallCalls.last {
        return lastCall.options.providerSettings
    }
    if let lastCall = await provider.toolCallMessageCalls.last {
        return lastCall.options.providerSettings
    }
    return nil
}

private func makeLargeSession() async throws -> InMemorySession {
    let session = InMemorySession()
    for index in 0 ..< 120 {
        try await session.addItems([
            .user("history-user-\(index): \(longBlock("u", lines: 1))"),
            .assistant("history-assistant-\(index): \(longBlock("a", lines: 1))"),
        ])
    }
    return session
}

private func longBlock(_ label: String, lines: Int) -> String {
    (0 ..< lines)
        .map { index in
            "\(label)-\(index): this is intentionally verbose content to stress prompt budget enforcement."
        }
        .joined(separator: "\n")
}

private func makeTestTools(count: Int) -> [any AnyJSONTool] {
    (0 ..< count).map { index in
        MembraneTestTool(name: String(format: "tool_%02d", count - index))
    }
}

private func temporaryWaxStoreURL() -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SwarmMembraneIntegrationTests", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appendingPathComponent("\(UUID().uuidString).mv2s")
}

private struct MembraneTestTool: AnyJSONTool, Sendable {
    let name: String
    let description: String
    let parameters: [ToolParameter]

    init(name: String) {
        self.name = name
        description = "Synthetic tool \(name) with verbose schema payload for JIT planning."
        parameters = [
            ToolParameter(name: "input", description: "Input", type: .string),
        ]
    }

    func execute(arguments _: [String: SendableValue]) async throws -> SendableValue {
        .string("ok")
    }
}

private struct StructuredPayloadTool: AnyJSONTool, Sendable {
    let name = "structured_payload"
    let description = "Returns structured JSON-compatible data large enough to pointerize."
    let parameters: [ToolParameter] = []

    func execute(arguments _: [String: SendableValue]) async throws -> SendableValue {
        .dictionary([
            "message": .string("quoted \"value\" with newline\nsecond line"),
            "count": .int(42),
            "items": .array((0 ..< 20).map { .string("item-\($0)") })
        ])
    }
}

private actor FailingWaxPointerIndex: WaxPointerIndex {
    struct Failure: Error {}

    func save(_: String, metadata _: [String: String]) async throws {
        throw Failure()
    }

    func flush() async throws {}

    func search(_ query: String, options _: Wax.Memory.SearchOptions) async throws -> Wax.Memory.Results {
        Wax.Memory.Results(query: query, items: [], totalTokens: 0)
    }

    func close() async throws {}
}

private actor PointerResolvingInferenceProvider: InferenceProvider, MessagesFromPromptInference {
    private var turn = 0

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        "done"
    }

    nonisolated func stream(prompt _: String, options _: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("done")
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt _: String,
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        try nextResponse(from: "")
    }

    func generate(messages: [InferenceMessage], options _: InferenceOptions) async throws -> String {
        InferenceMessage.flattenPrompt(messages)
    }

    nonisolated func stream(
        messages: [InferenceMessage],
        options _: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        let text = InferenceMessage.flattenPrompt(messages)
        return AsyncThrowingStream { continuation in
            continuation.yield(text)
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        try nextResponse(from: InferenceMessage.flattenPrompt(messages))
    }

    private func nextResponse(from prompt: String) throws -> InferenceResponse {
        defer { turn += 1 }
        switch turn {
        case 0:
            return InferenceResponse(
                toolCalls: [
                    .init(id: "call-structured", name: "structured_payload", arguments: [:])
                ],
                finishReason: .toolCall
            )
        case 1:
            let pointerID = try Self.pointerID(from: prompt)
            return InferenceResponse(
                toolCalls: [
                    .init(
                        id: "call-resolve",
                        name: MembraneInternalToolName.resolvePointer,
                        arguments: ["pointer_id": .string(pointerID)]
                    )
                ],
                finishReason: .toolCall
            )
        default:
            return InferenceResponse(content: "done", finishReason: .completed)
        }
    }

    private static func pointerID(from prompt: String) throws -> String {
        guard let range = prompt.range(of: #"ptr_[0-9a-f]{12}"#, options: .regularExpression) else {
            struct MissingPointer: Error {}
            throw MissingPointer()
        }
        return String(prompt[range])
    }
}

private actor ThrowingMembraneAdapter: MembraneAgentAdapter {
    func plan(
        prompt _: String,
        toolSchemas _: [ToolSchema],
        profile _: ContextProfile
    ) async throws -> MembranePlannedBoundary {
        struct ForcedFailure: Error, CustomStringConvertible {
            let description = "forced membrane failure"
        }
        throw ForcedFailure()
    }

    func transformToolResult(
        toolName _: String,
        output: String,
        profile _: ContextProfile
    ) async throws -> MembraneToolResultBoundary {
        MembraneToolResultBoundary(textForConversation: output)
    }

    func handleInternalToolCall(
        name _: String,
        arguments _: [String: SendableValue]
    ) async throws -> String? {
        nil
    }

    func restore(checkpointData _: Data?) async throws {}
    func snapshotCheckpointData() async throws -> Data? { nil }
}
#endif
