#if SWARM_INTEGRATIONS && canImport(Membrane)
import Foundation
import Membrane
@testable import Swarm
import Testing

@Suite("MembraneFeatureConfiguration unification")
struct MembraneFeatureConfigurationUnificationTests {
    @Test("Membrane session defaults match Swarm public defaults")
    func membraneSessionDefaultsMatchSwarm() {
        let swarm = MembraneFeatureConfigurationFixtures.swarmDefault
        let membrane = Membrane.MembraneFeatureConfiguration.default
        #expect(membrane.jitMinToolCount == swarm.jitMinToolCount)
        #expect(membrane.defaultJITLoadCount == swarm.defaultJITLoadCount)
        #expect(membrane.pointerThresholdBytes == swarm.pointerThresholdBytes)
        #expect(membrane.pointerSummaryMaxChars == swarm.pointerSummaryMaxChars)
        #expect(membrane.runtimeFeatureFlags == swarm.runtimeFeatureFlags)
        #expect(membrane.runtimeModelAllowlist == swarm.runtimeModelAllowlist)

        let environment = MembraneEnvironment.contextCoreSession()
        #expect(environment.configuration == swarm)
        #expect(environment.isEnabled)
    }

    @Test("contextCoreSession initialSnapshot seeds JIT plan")
    func contextCoreSessionInitialSnapshotAffectsPlan() async throws {
        let environment = MembraneEnvironment.contextCoreSession(
            initialSnapshot: jitSnapshot(loadedToolNames: ["gamma"])
        )
        let adapter = try #require(environment.adapter)
        let planned = try await adapter.plan(
            prompt: "hello",
            toolSchemas: sessionFactoryToolSchemas(),
            profile: .balanced
        )

        let names = Set(planned.toolSchemas.map(\.name))
        #expect(planned.mode == "jit")
        #expect(names.contains("gamma"))
        #expect(names.contains("alpha") == false)
        #expect(names.contains("beta") == false)
        #expect(names.contains(MembraneInternalToolName.loadToolSchema))
    }

    @Test("contextCoreSession pointerStore receives pointerized tool output")
    func contextCoreSessionPointerStoreIsUsed() async throws {
        let store = InMemoryPointerStore()
        let environment = MembraneEnvironment.contextCoreSession(
            configuration: MembraneFeatureConfiguration(
                pointerThresholdBytes: 8,
                pointerSummaryMaxChars: 16
            ),
            pointerStore: store
        )
        let adapter = try #require(environment.adapter)
        let payload = String(repeating: "x", count: 64)
        let result = try await adapter.transformToolResult(
            toolName: "alpha",
            output: payload,
            profile: .balanced
        )
        let pointerID = try #require(result.pointerID)
        #expect(try await store.resolve(pointerID: pointerID) == Data(payload.utf8))
    }

    @Test("contextCoreSession restore applies ContextSnapshot to plan")
    func contextCoreSessionRestoreAffectsPlan() async throws {
        let environment = MembraneEnvironment.contextCoreSession()
        let adapter = try #require(environment.adapter)
        try await adapter.restore(
            checkpointData: JSONEncoder().encode(jitSnapshot(loadedToolNames: ["gamma"]))
        )

        let planned = try await adapter.plan(
            prompt: "hello",
            toolSchemas: sessionFactoryToolSchemas(),
            profile: .balanced
        )
        let names = Set(planned.toolSchemas.map(\.name))
        #expect(planned.mode == "jit")
        #expect(names.contains("gamma"))
        #expect(names.contains("alpha") == false)
        #expect(names.contains("beta") == false)
    }
}

private func jitSnapshot(loadedToolNames: [String]) -> ContextSnapshot {
    ContextSnapshot(
        budget: .init(totalTokens: 4096),
        toolState: .init(
            mode: .jit,
            loadedToolNames: loadedToolNames,
            allowListToolNames: [],
            usageCounts: []
        )
    )
}

private func sessionFactoryToolSchemas() -> [ToolSchema] {
    ["alpha", "beta", "gamma"].map { name in
        ToolSchema(name: name, description: name, parameters: [])
    }
}
#endif
