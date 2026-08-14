import Swarm
import Testing

enum MembraneFeatureConfigurationFixtures {
    static var swarmDefault: MembraneFeatureConfiguration { .default }
}

@Suite("MembraneFeatureConfiguration")
struct MembraneFeatureConfigurationTests {
    @Test("public defaults are the canonical unified values")
    func publicDefaultsAreCanonical() {
        let configuration = MembraneFeatureConfigurationFixtures.swarmDefault
        #expect(configuration.jitMinToolCount == 12)
        #expect(configuration.defaultJITLoadCount == 6)
        #expect(configuration.pointerThresholdBytes == 400)
        #expect(configuration.pointerSummaryMaxChars == 240)
        #expect(configuration.runtimeFeatureFlags.isEmpty)
        #expect(configuration.runtimeModelAllowlist.isEmpty)
    }
}
