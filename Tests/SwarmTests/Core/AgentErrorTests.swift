@testable import Swarm
import Testing

@Suite("AgentError — toolCallingUnsupported")
struct ToolCallingErrorTests {
    @Test("toolCallingUnsupported has correct error description")
    func errorDescription() {
        let error = AgentError.toolCallingUnsupported
        #expect(error.errorDescription?.contains("selected provider") == true)
        #expect(error.errorDescription?.contains("tool calling") == true)
    }

    @Test("toolCallingUnsupported has recovery suggestion mentioning Swarm.configure")
    func recoverySuggestion() {
        let error = AgentError.toolCallingUnsupported
        #expect(error.recoverySuggestion != nil)
        #expect(error.recoverySuggestion?.contains("Swarm.configure(provider:") == true)
        #expect(error.recoverySuggestion?.localizedCaseInsensitiveContains("Foundation Models") == true)
        #expect(error.recoverySuggestion?.localizedCaseInsensitiveContains("cloudProvider") != true)
        #expect(error.recoverySuggestion?.localizedCaseInsensitiveContains("prompt-based") != true)
    }

    @Test("toolCallingUnsupported has debug description")
    func debugDescription() {
        let error = AgentError.toolCallingUnsupported
        #expect(error.debugDescription.contains("toolCallingUnsupported"))
    }

    @Test("existing error cases still have nil recoverySuggestion")
    func existingErrorsNoRecovery() {
        let error = AgentError.cancelled
        #expect(error.recoverySuggestion == nil)
    }
}

@Suite("AgentError — authenticationFailed")
struct AuthenticationFailedErrorTests {
    @Test("authenticationFailed has correct error description")
    func errorDescription() {
        let error = AgentError.authenticationFailed(reason: "bad key")
        #expect(error.errorDescription?.contains("Authentication failed") == true)
        #expect(error.errorDescription?.contains("bad key") == true)
    }

    @Test("authenticationFailed has API-key recovery suggestion")
    func recoverySuggestion() {
        let error = AgentError.authenticationFailed(reason: "bad key")
        #expect(error.recoverySuggestion?.localizedCaseInsensitiveContains("API key") == true)
    }

    @Test("authenticationFailed has debug description")
    func debugDescription() {
        let error = AgentError.authenticationFailed(reason: "bad key")
        #expect(error.debugDescription.contains("authenticationFailed"))
    }

    @Test("authenticationFailed is not retryable")
    func notRetryable() {
        let error = AgentError.authenticationFailed(reason: "bad key")
        #expect(error.isRetryable == false)
        #expect(InferenceRetryability.isRetryable(error) == false)
    }
}
