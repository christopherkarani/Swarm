import Foundation
@testable import Swarm
import Testing

@Suite("Membrane Integration")
struct MembraneIntegrationTests {
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
            inferenceProvider: provider
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

        #if SWARM_MEMBRANE
        #expect(plannedTools.count < tools.count)

        let schemaNames = plannedTools.map(\.name)
        #expect(schemaNames == schemaNames.sorted {
            $0.utf8.lexicographicallyPrecedes($1.utf8)
        })
        #expect(schemaNames.contains("membrane_load_tool_schema"))
        #expect(schemaNames.contains("Add_Tools"))
        #expect(schemaNames.contains("Remove_Tools"))
        #expect(schemaNames.contains("resolve_pointer"))
        #endif
    }

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
            inferenceProvider: provider
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
            inferenceProvider: provider
        ).environment(
            \.membrane,
            MembraneEnvironment(isEnabled: true, adapter: throwingAdapter)
        )

        let result = try await agent.run("hello")

        #expect(result.output == "fallback-ok")
        #expect(result.metadata["membrane.fallback.used"] == .bool(true))
        #expect(result.metadata["membrane.fallback.error"]?.stringValue?.contains("forced membrane failure") == true)
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
        // Without SWARM_MEMBRANE, plan() always uses allowAll mode (no JIT filtering).
        // The exclusion assertion only applies when JIT is active.
        #if SWARM_MEMBRANE
        #expect(planned.toolSchemas.contains(where: { $0.name == "zzz_tool" }) == false)
        #else
        _ = planned
        #endif
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
        output: String
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
