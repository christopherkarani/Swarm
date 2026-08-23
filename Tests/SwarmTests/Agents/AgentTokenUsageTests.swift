import Foundation
@testable import Swarm
import Testing

@Suite("Agent Token Usage Population", .ephemeralDefaultStores)
struct AgentTokenUsageTests {

    @Test("Provider-reported usage reaches AgentResult, onLLMEnd, and MetricsCollector")
    func providerUsageReachesResultObserverAndMetrics() async throws {
        let expected = TokenUsage(inputTokens: 11, outputTokens: 7)
        let echo = MockTool(name: "echo", result: .string("ok"))
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    .init(id: "c1", name: "echo", arguments: [:])
                ],
                finishReason: .toolCall,
                usage: TokenUsage(inputTokens: 4, outputTokens: 2)
            ),
            InferenceResponse(
                content: "all done",
                finishReason: .completed,
                usage: TokenUsage(inputTokens: 7, outputTokens: 5)
            ),
        ])

        let collector = MetricsCollector()
        let observer = TokenUsageRecordingObserver()
        let agent = try Agent(
            tools: [echo],
            instructions: "Use echo.",
            configuration: .default.maxIterations(3),
            inferenceProvider: provider,
            tracer: collector
        )

        let result = try await agent.run("go", observer: observer)

        #expect(result.output == "all done")
        #expect(result.tokenUsage == expected)

        let llmUsage = await observer.llmEndUsage
        #expect(llmUsage.count == 2)
        #expect(llmUsage[0] == TokenUsage(inputTokens: 4, outputTokens: 2))
        #expect(llmUsage[1] == TokenUsage(inputTokens: 7, outputTokens: 5))

        let snapshot = await collector.snapshot()
        #expect(snapshot.inputTokens == expected.inputTokens)
        #expect(snapshot.outputTokens == expected.outputTokens)
        #expect(snapshot.totalTokens == expected.totalTokens)
    }

    @Test("Nil provider usage stays nil on AgentResult and does not crash")
    func nilProviderUsageStaysNil() async throws {
        let provider = MockInferenceProvider(responses: ["hello"])
        let collector = MetricsCollector()
        let observer = TokenUsageRecordingObserver()
        let agent = try Agent(
            tools: [],
            instructions: "Be brief.",
            inferenceProvider: provider,
            tracer: collector
        )

        let result = try await agent.run("Hi", observer: observer)
        #expect(result.output == "hello")
        #expect(result.tokenUsage == nil)

        let llmUsage = await observer.llmEndUsage
        #expect(llmUsage == [nil])

        let snapshot = await collector.snapshot()
        #expect(snapshot.inputTokens == 0)
        #expect(snapshot.outputTokens == 0)
    }

    @Test("Handoff merges child usage on AgentResult without double-counting metrics")
    func handoffMergesUsageWithoutDoubleCountingMetrics() async throws {
        let parentUsage = TokenUsage(inputTokens: 10, outputTokens: 5)
        let childUsage = TokenUsage(inputTokens: 20, outputTokens: 10)
        let combined = TokenUsage(inputTokens: 30, outputTokens: 15)

        let sourceProvider = MockInferenceProvider()
        await sourceProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    .init(id: "call_handoff", name: "handoff_to_target", arguments: [:])
                ],
                finishReason: .toolCall,
                usage: parentUsage
            )
        ])

        let targetProvider = MockInferenceProvider()
        await targetProvider.setToolCallResponses([
            InferenceResponse(
                content: "specialist done",
                finishReason: .completed,
                usage: childUsage
            )
        ])

        let collector = MetricsCollector()
        let target = try Agent(
            tools: [MockTool(name: "noop", result: .string("ok"))],
            instructions: "Finish the task.",
            configuration: AgentConfiguration(name: "target-agent", defaultTracingEnabled: false),
            inferenceProvider: targetProvider,
            tracer: collector
        )
        let source = try Agent(
            tools: [],
            instructions: "Route to the specialist.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            inferenceProvider: sourceProvider,
            tracer: collector,
            handoffs: [
                AnyHandoffConfiguration(
                    HandoffConfiguration(
                        targetAgent: target,
                        toolNameOverride: "handoff_to_target"
                    )
                )
            ]
        )

        let result = try await source.run("please route this")
        #expect(result.output == "specialist done")
        #expect(result.tokenUsage == combined)

        let snapshot = await collector.snapshot()
        #expect(snapshot.inputTokens == combined.inputTokens)
        #expect(snapshot.outputTokens == combined.outputTokens)
        #expect(snapshot.totalTokens == combined.totalTokens)
    }

    @Test("Foundation Models path leaves token usage nil without crashing")
    func foundationModelsLeavesTokenUsageNil() async throws {
        #if canImport(FoundationModels)
        guard ProcessInfo.processInfo.environment["SWARM_RUN_LIVE_FOUNDATION_MODELS_TESTS"] == "1" else {
            return
        }
        guard #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) else { return }
        guard FoundationModelsInferenceProvider.isAvailable else { return }

        let provider = FoundationModelsInferenceProvider()
        let agent = try Agent(
            tools: [],
            instructions: "Reply with the single word hi.",
            inferenceProvider: provider
        )
        let result = try await agent.run("Say hi")
        #expect(result.tokenUsage == nil)
        #expect(!result.output.isEmpty)
        #else
        // Linux / non-Apple: Foundation Models is unavailable; nil usage is the contract.
        #expect(Bool(true))
        #endif
    }
}

private actor TokenUsageRecordingObserver: AgentObserver {
    var llmEndUsage: [TokenUsage?] = []

    func onLLMEnd(
        context _: AgentContext?,
        agent _: any AgentRuntime,
        response _: String,
        usage: TokenUsage?
    ) async {
        llmEndUsage.append(usage)
    }
}
