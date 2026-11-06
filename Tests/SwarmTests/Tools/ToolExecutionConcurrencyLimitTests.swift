import Foundation
@testable import Swarm
import Testing

@Suite("Tool execution concurrency limit")
struct ToolExecutionConcurrencyLimitTests {
    @Test("executeBatch never exceeds the default fan-out cap")
    func defaultCapBoundsFanOut() async throws {
        let gauge = InFlightGauge()
        let registry = try await Self.registry(gauge: gauge, toolCount: 20)

        let outcomes = try await ToolExecutionEngine().executeBatch(
            Self.calls(count: 20),
            registry: registry,
            agent: ParallelTestMockAgent(),
            context: nil,
            resultBuilder: AgentResult.Builder(),
            observer: nil,
            tracing: nil,
            stopOnToolError: false,
            allowConcurrent: true
        )

        #expect(outcomes.count == 20)
        #expect(await gauge.peak <= AgentConfiguration.defaultMaxConcurrentToolCalls)
    }

    @Test("executeBatch honors an explicit cap and keeps input order", arguments: [1, 3])
    func explicitCapBoundsFanOut(cap: Int) async throws {
        let gauge = InFlightGauge()
        let registry = try await Self.registry(gauge: gauge, toolCount: 10)

        let outcomes = try await ToolExecutionEngine().executeBatch(
            Self.calls(count: 10),
            registry: registry,
            agent: ParallelTestMockAgent(),
            context: nil,
            resultBuilder: AgentResult.Builder(),
            observer: nil,
            tracing: nil,
            stopOnToolError: false,
            allowConcurrent: true,
            maxConcurrentCalls: cap
        )

        #expect(outcomes.map(\.call.toolName) == Self.calls(count: 10).map(\.toolName))
        #expect(await gauge.peak <= cap)
        #expect(await gauge.peak >= 1)
    }

    @Test("Agent tool batches honor AgentConfiguration.maxConcurrentToolCalls")
    func agentConfigurationCapsToolFanOut() async throws {
        let gauge = InFlightGauge()
        let tools = (0 ..< 6).map { index in
            FunctionTool(name: "tool_\(index)", description: "Measures overlap") { _ in
                await gauge.enter()
                try await Task.sleep(for: .milliseconds(20))
                await gauge.leave()
                return .string("ok")
            }
        }
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: (0 ..< 6).map {
                    InferenceResponse.ParsedToolCall(id: "call_\($0)", name: "tool_\($0)", arguments: [:])
                },
                finishReason: .toolCall,
                usage: nil
            ),
            InferenceResponse(content: "done", toolCalls: [], finishReason: .completed, usage: nil),
        ])
        let configuration = AgentConfiguration.default
            .enableStreaming(false)
            .defaultTracingEnabled(false)
            .parallelToolCalls(true)
            .maxConcurrentToolCalls(2)
        let agent = try Agent(tools: tools, configuration: configuration, inferenceProvider: provider)

        let result = try await agent.run("run all")

        #expect(result.output == "done")
        #expect(result.toolResults.count == 6)
        #expect(await gauge.peak <= 2)
    }

    @Test("maxConcurrentToolCalls defaults to 8 and coerces values below 1")
    func configurationDefaultAndCoercion() {
        #expect(AgentConfiguration.default.maxConcurrentToolCalls == 8)
        #expect(AgentConfiguration(maxConcurrentToolCalls: 0).maxConcurrentToolCalls == 1)
        var configuration = AgentConfiguration.default
        configuration.maxConcurrentToolCalls = -3
        #expect(configuration.maxConcurrentToolCalls == 1)
        #expect(AgentConfiguration.default.maxConcurrentToolCalls(4).maxConcurrentToolCalls == 4)
    }

    static func registry(gauge: InFlightGauge, toolCount: Int) async throws -> ToolRegistry {
        let registry = ToolRegistry()
        for index in 0 ..< toolCount {
            try await registry.register(
                FunctionTool(name: "tool_\(index)", description: "Measures overlap") { _ in
                    await gauge.enter()
                    try await Task.sleep(for: .milliseconds(20))
                    await gauge.leave()
                    return .string("ok")
                }
            )
        }
        return registry
    }

    static func calls(count: Int) -> [ToolCall] {
        (0 ..< count).map { ToolCall(toolName: "tool_\($0)", arguments: [:]) }
    }
}

/// Records how many tool bodies run at once.
actor InFlightGauge {
    private(set) var current = 0
    private(set) var peak = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func leave() {
        current -= 1
    }
}
