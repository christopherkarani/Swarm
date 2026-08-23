import Foundation
@testable import Swarm
import Testing

@Suite("MetricsCollector auto-attach")
struct MetricsCollectorAutoAttachTests {
    private let _ephemeralDefaultStores = SwarmEphemeralStoreBootstrap.installOnce

    @Test("Default configuration does not auto-attach a collector")
    func defaultIsOff() throws {
        #expect(AgentConfiguration.default.autoAttachMetricsCollector == false)

        let agent = try Agent(
            "Be brief.",
            configuration: .default.defaultTracingEnabled(false),
            inferenceProvider: MockInferenceProvider(responses: ["ok"])
        )
        #expect(agent.metricsCollector == nil)
    }

    @Test("Configuration flag attaches a collector that records a successful run")
    func autoAttachRecordsRun() async throws {
        let config = AgentConfiguration.default
            .autoAttachMetricsCollector(true)
            .defaultTracingEnabled(false)
        let provider = MockInferenceProvider(responses: ["hello"])
        let agent = try Agent(
            "Be brief.",
            configuration: config,
            inferenceProvider: provider
        )

        let collector = try #require(agent.metricsCollector)
        let result = try await agent.run("Hi")
        #expect(result.output == "hello")

        let snapshot = await collector.snapshot()
        #expect(snapshot.totalExecutions == 1)
        #expect(snapshot.successfulExecutions == 1)
        #expect(snapshot.failedExecutions == 0)
    }

    @Test("Builder method is additive and does not mutate the original")
    func builderIsAdditive() {
        let original = AgentConfiguration.default
        let enabled = original.autoAttachMetricsCollector(true)

        #expect(original.autoAttachMetricsCollector == false)
        #expect(enabled.autoAttachMetricsCollector == true)
        #expect(enabled.maxIterations == original.maxIterations)
    }
}
