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

    @Test("toolFailure is classified non-retryable like its predecessor")
    func retryabilityClassification() {
        let error = AgentError.toolFailure(toolName: "t", message: nil, cause: Boom())
        #expect(error.isRetryable == false)
    }

    @Test("stopOnToolError keeps the underlying error reachable through the engine seam")
    func engineStopOnToolErrorPreservesCause() async throws {
        struct Marker: Error, Equatable {}
        let marker = Marker()
        let registry = ToolRegistry()
        try await registry.register(MockErrorTool(name: "boom", error: marker))
        let agent = ParallelTestMockAgent()

        do {
            _ = try await ToolExecutionEngine().execute(
                toolName: "boom",
                arguments: [:],
                registry: registry,
                agent: agent,
                context: nil,
                resultBuilder: AgentResult.Builder(),
                observer: nil,
                tracing: nil,
                stopOnToolError: true
            )
            Issue.record("expected toolFailure")
        } catch let error as AgentError {
            guard case let .toolFailure(toolName, _, cause) = error else {
                Issue.record("expected toolFailure, got \(error)")
                return
            }
            #expect(toolName == "boom")
            let registryWrapper = try #require(cause as? AgentError)
            guard case .toolFailure(_, _, let innerCause) = registryWrapper else {
                Issue.record("expected nested toolFailure, got \(registryWrapper)")
                return
            }
            #expect(innerCause as? Marker == marker)
        }
    }
}
