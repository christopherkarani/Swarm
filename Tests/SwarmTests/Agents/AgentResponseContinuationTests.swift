import Testing
@testable import Swarm

@Suite("Agent Response Continuation")
struct AgentResponseContinuationTests {
    @Test("runWithResponse auto-tracks previous response id per session")
    func runWithResponseAutoTracksPreviousResponseID() async throws {
        let provider = MockInferenceProvider(
            responses: ["first reply", "second reply"],
            capabilities: [.responseContinuation]
        )
        let session = InMemorySession(sessionId: "response-tracking-runwithresponse")
        let config = AgentConfiguration.default.autoPreviousResponseId(true)
        let agent = try Agent(configuration: config, inferenceProvider: provider)

        let first = try await agent.runWithResponse("first prompt", session: session, observer: nil)
        _ = try await agent.runWithResponse("second prompt", session: session, observer: nil)

        let calls = await provider.generateMessageCalls
        #expect(calls.count == 2)
        if calls.count == 2 {
            #expect(calls[0].options.previousResponseId == nil)
            #expect(calls[1].options.previousResponseId == first.responseId)
        }
    }

    @Test("run auto-tracks synthetic response id for subsequent runs")
    func runAutoTracksSyntheticResponseID() async throws {
        let provider = MockInferenceProvider(
            responses: ["first run", "second run"],
            capabilities: [.responseContinuation]
        )
        let session = InMemorySession(sessionId: "response-tracking-run")
        let config = AgentConfiguration.default.autoPreviousResponseId(true)
        let agent = try Agent(configuration: config, inferenceProvider: provider)

        let firstResult = try await agent.run("first prompt", session: session, observer: nil)
        _ = try await agent.run("second prompt", session: session, observer: nil)

        let calls = await provider.generateMessageCalls
        #expect(calls.count == 2)
        if calls.count == 2 {
            #expect(calls[0].options.previousResponseId == nil)
        }

        guard case let .string(firstResponseID)? = firstResult.metadata["response.id"] else {
            Issue.record("Expected first run metadata to include response.id")
            return
        }
        if calls.count == 2 {
            #expect(calls[1].options.previousResponseId == firstResponseID)
        }
    }

    @Test("explicit previous response id overrides auto tracking")
    func explicitPreviousResponseIDWins() async throws {
        let provider = MockInferenceProvider(
            responses: ["reply"],
            capabilities: [.responseContinuation]
        )
        let session = InMemorySession(sessionId: "response-tracking-explicit")
        let config = AgentConfiguration.default
            .autoPreviousResponseId(true)
            .previousResponseId("explicit-response-id")
        let agent = try Agent(configuration: config, inferenceProvider: provider)

        _ = try await agent.run("prompt", session: session, observer: nil)

        let call = await provider.generateMessageCalls.last
        #expect(call?.options.previousResponseId == "explicit-response-id")
    }

    @Test("previous response id is stripped when provider does not advertise continuation support")
    func stripsPreviousResponseIDWithoutContinuationCapability() async throws {
        let provider = MockInferenceProvider(responses: ["reply"])
        let session = InMemorySession(sessionId: "response-tracking-no-capability")
        let config = AgentConfiguration.default
            .autoPreviousResponseId(true)
            .previousResponseId("explicit-response-id")
        let agent = try Agent(configuration: config, inferenceProvider: provider)

        _ = try await agent.run("prompt", session: session, observer: nil)

        let call = await provider.generateMessageCalls.last
        #expect(call?.options.previousResponseId == nil)
    }
}
