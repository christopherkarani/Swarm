// AgentResultRuntimeEngineTests.swift
// SwarmTests
//
// Tests for AgentResult.runtimeEngine typed accessor.

import Testing
@testable import Swarm

@Suite("AgentResult.runtimeEngine")
struct AgentResultRuntimeEngineTests {
    private let _ephemeralDefaultStores = SwarmEphemeralStoreBootstrap.installOnce


    @Test("returns nil when metadata has no runtime.engine key")
    func returnsNilWhenAbsent() {
        let result = AgentResult(output: "hi")
        #expect(result.runtimeEngine == nil)
    }

    @Test("returns engine name from metadata")
    func returnsEngineFromMetadata() {
        let result = AgentResult(
            output: "hi",
            metadata: ["runtime.engine": .string("graph")]
        )
        #expect(result.runtimeEngine == "graph")
    }

    @Test("returns nil when metadata value is not a string")
    func returnsNilForNonString() {
        let result = AgentResult(
            output: "hi",
            metadata: ["runtime.engine": .int(1)]
        )
        #expect(result.runtimeEngine == nil)
    }

    @Test("native Agent.run records native runtime engine")
    func nativeAgentRunRecordsNativeRuntimeEngine() async throws {
        let provider = MockInferenceProvider(responses: ["hi"])
        let agent = try Agent(instructions: "Reply shortly.", inferenceProvider: provider)

        let result = try await agent.run("hello")

        #expect(result.output == "hi")
        #expect(result.runtimeEngine == "native")
    }
}
