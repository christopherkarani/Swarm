import Testing
@testable import Swarm

@Suite("AgentError Cause Preservation")
struct AgentErrorCauseTests {
    private struct Boom: Error, Equatable {}

    @Test("toolFailure preserves the original cause instance")
    func preservesCause() throws {
        let cause = Boom()
        let error = AgentError.toolFailure(toolName: "calculator", message: nil, cause: cause)

        guard case let .toolFailure(name, message, wrapped) = error else {
            Issue.record("expected toolFailure")
            return
        }
        #expect(name == "calculator")
        #expect(message == nil)
        #expect(wrapped as? Boom == cause)
    }

    @Test("message-only failures are valid without a cause")
    func messageOnly() {
        let error = AgentError.toolFailure(
            toolName: "websearch",
            message: "Integrations trait required",
            cause: nil
        )
        #expect(error.localizedDescription.contains("Integrations trait required"))
        guard case let .toolFailure(_, message, cause) = error else {
            Issue.record("expected toolFailure")
            return
        }
        #expect(message == "Integrations trait required")
        #expect(cause == nil)
    }

    @Test("deprecated string case still constructs and matches")
    func deprecatedCaseStillWorks() {
        let error = AgentError.toolExecutionFailed(toolName: "legacy", underlyingError: "boom")
        #expect(error.isRetryable == false)
        if case let .toolExecutionFailed(name, underlying) = error {
            #expect(name == "legacy")
            #expect(underlying == "boom")
        } else {
            Issue.record("expected toolExecutionFailed")
        }
    }

    @Test("toolFailure is classified non-retryable like its predecessor")
    func retryabilityClassification() {
        let error = AgentError.toolFailure(toolName: "t", message: nil, cause: Boom())
        #expect(error.isRetryable == false)
    }
}
