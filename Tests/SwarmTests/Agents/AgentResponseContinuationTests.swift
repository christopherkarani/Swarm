import Testing
@testable import Swarm

@Suite("Agent Response Continuation", .ephemeralDefaultStores)
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
        let agent = try Agent(configuration: config, inferenceProvider: provider)

        _ = try await agent.runWithResponse("prompt", continuing: "explicit-response-id", session: session)

        let call = await provider.generateMessageCalls.last
        #expect(call?.options.previousResponseId == "explicit-response-id")
    }

    @Test("explicit previous response id applies to one run only")
    func explicitPreviousResponseIDIsPerRun() async throws {
        let provider = MockInferenceProvider(
            responses: ["first", "second"],
            capabilities: [.responseContinuation]
        )
        let agent = try Agent(configuration: .default, inferenceProvider: provider)

        _ = try await agent.runWithResponse("prompt", continuing: "explicit-response-id")
        _ = try await agent.runWithResponse("again")

        let calls = await provider.generateMessageCalls
        #expect(calls.count == 2)
        #expect(calls[0].options.previousResponseId == "explicit-response-id")
        #expect(calls[1].options.previousResponseId == nil)
        #expect(agent.configuration == .default)
    }

    @Test("blank continuing ids are not sent to the provider", arguments: ["", "  "])
    func blankContinuingIDIsIgnored(previousResponseID: String) async throws {
        let provider = MockInferenceProvider(
            responses: ["reply"],
            capabilities: [.responseContinuation]
        )
        let agent = try Agent(configuration: .default, inferenceProvider: provider)

        _ = try await agent.runWithResponse("hi", continuing: previousResponseID)

        let call = await provider.generateMessageCalls.last
        #expect(call != nil)
        #expect(call?.options.previousResponseId == nil)
    }

    @Test("previous response id is stripped when provider does not advertise continuation support")
    func stripsPreviousResponseIDWithoutContinuationCapability() async throws {
        let provider = MockInferenceProvider(responses: ["reply"])
        let session = InMemorySession(sessionId: "response-tracking-no-capability")
        let config = AgentConfiguration.default
            .autoPreviousResponseId(true)
        let agent = try Agent(configuration: config, inferenceProvider: provider)

        _ = try await agent.runWithResponse("prompt", continuing: "explicit-response-id", session: session)

        let call = await provider.generateMessageCalls.last
        #expect(call?.options.previousResponseId == nil)
    }
}
