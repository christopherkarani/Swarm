import Testing
@testable import Swarm

@Suite("SwarmConfig", .serialized)
struct SwarmConfigTests {
    @Test func configureStoresGlobalProvider() async {
        await withSwarmConfigurationIsolation {
            let mock = MockInferenceProvider(responses: [])
            await Swarm.configure(provider: mock)
            let provider = await Swarm.defaultProvider
            #expect(provider != nil)
        }
    }

    @Test func resetClearsProviders() async {
        await withSwarmConfigurationIsolation {
            let mock = MockInferenceProvider(responses: [])
            await Swarm.configure(provider: mock)
            await Swarm.reset()
            let provider = await Swarm.defaultProvider
            #expect(provider == nil)
        }
    }
}
