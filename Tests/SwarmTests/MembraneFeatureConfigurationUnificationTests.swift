#if SWARM_INTEGRATIONS && canImport(Membrane)
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
}
#endif
