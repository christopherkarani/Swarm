#if SWARM_INTEGRATIONS
@testable import Swarm
import Testing

@Suite("Swarm Runtime Environment")
struct SwarmRuntimeEnvironmentTests {
    @Test("SwiftPM test runner is detected for isolated durable stores")
    func swiftPMTestRunnerIsDetected() {
        #expect(SwarmRuntimeEnvironment.isRunningTests)
        #expect(WaxMemory.defaultStoreURL.path.contains("AgentMemoryTests"))
        #expect(WaxMembraneStorage.defaultStoreURL.path.contains("MembraneTests"))
    }
}
#endif
