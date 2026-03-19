@testable import Swarm
import Testing

@Suite("AgentError — toolCallingRequiresCloudProvider")
struct ToolCallingErrorTests {
    @Test("toolCallingRequiresCloudProvider has correct error description")
    func errorDescription() {
        let error = AgentError.toolCallingRequiresCloudProvider
        #expect(error.errorDescription?.contains("selected provider") == true)
        #expect(error.errorDescription?.contains("tool calling") == true)
    }

    @Test("toolCallingRequiresCloudProvider has recovery suggestion mentioning Swarm.configure")
    func recoverySuggestion() {
        let error = AgentError.toolCallingRequiresCloudProvider
        #expect(error.recoverySuggestion != nil)
        #expect(error.recoverySuggestion?.contains("Swarm.configure") == true)
        #expect(error.recoverySuggestion?.contains("prompt-based tool emulation") == true)
    }

    @Test("toolCallingRequiresCloudProvider has debug description")
    func debugDescription() {
        let error = AgentError.toolCallingRequiresCloudProvider
        #expect(error.debugDescription.contains("toolCallingRequiresCloudProvider"))
    }

    @Test("existing error cases still have nil recoverySuggestion")
    func existingErrorsNoRecovery() {
        let error = AgentError.cancelled
        #expect(error.recoverySuggestion == nil)
    }
}
