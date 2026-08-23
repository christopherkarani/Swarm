import Testing
@testable import Swarm

@Suite("AgentObserver")
struct AgentObserverTests {
    private let _ephemeralDefaultStores = SwarmEphemeralStoreBootstrap.installOnce

    @Test("AgentObserver conformance works")
    func observerConformance() async throws {
        struct TestObserver: AgentObserver {
            func onAgentStart(context: AgentContext?, agent: any AgentRuntime, input: String) async {}
        }
        let observer = TestObserver()
        await observer.onAgentStart(context: nil, agent: MockAgentRuntime(response: ""), input: "test")
    }

    @Test("observed(by:) wraps agent and calls observer")
    func observedByFluent() async throws {
        let mock = MockInferenceProvider()
        await mock.setResponses(["ok"])
        let agent = try Agent(instructions: "test", inferenceProvider: mock)
        let observer = CallCountObserver()
        let observed = agent.observed(by: observer)
        _ = try await observed.run("hello")
        #expect(await observer.startCount == 1)
    }

    @Test("observed(by:) combines stored and per-call observers")
    func observedByCombinesStoredAndAdditionalObservers() async throws {
        let agent = MockAgentRuntime(response: "ok")
        let storedObserver = CallCountObserver()
        let additionalObserver = CallCountObserver()
        let observed = agent.observed(by: storedObserver)

        _ = try await observed.run("hello", observer: additionalObserver)

        #expect(await storedObserver.startCount == 1)
        #expect(await storedObserver.endCount == 1)
        #expect(await additionalObserver.startCount == 1)
        #expect(await additionalObserver.endCount == 1)
    }

    @Test("observed(by:) propagates stored observer through stream")
    func observedByStreamPropagatesStoredObserver() async throws {
        let mock = MockInferenceProvider()
        await mock.setResponses(["ok"])
        let agent = try Agent(instructions: "test", inferenceProvider: mock)
        let observer = CallCountObserver()
        let observed = agent.observed(by: observer)

        for try await _ in observed.stream("hello") {}

        #expect(await observer.startCount == 1)
        #expect(await observer.endCount == 1)
    }

    @Test("observed(by:) propagates stored observer through runWithResponse")
    func observedByRunWithResponsePropagatesStoredObserver() async throws {
        let agent = MockAgentRuntime(response: "ok")
        let observer = CallCountObserver()
        let observed = agent.observed(by: observer)

        let response = try await observed.runWithResponse("hello")

        #expect(response.output == "ok")
        #expect(await observer.startCount == 1)
        #expect(await observer.endCount == 1)
    }

    @Test("Workflow parallel passes observer to all branches")
    func workflowParallelPassesObserverToAllBranches() async throws {
        let observer = CallCountObserver()

        _ = try await Workflow()
            .parallel([
                MockAgentRuntime(response: "one"),
                MockAgentRuntime(response: "two")
            ])
            .observed(by: observer)
            .run("hello")

        #expect(await observer.startCount == 2)
        #expect(await observer.endCount == 2)
    }

    @Test("LoggingObserver conforms to AgentObserver")
    func loggingObserverConformance() {
        let _: any AgentObserver = LoggingObserver()
    }

    @Test("run with observer: parameter compiles")
    func runWithObserverParam() async throws {
        let mock = MockInferenceProvider()
        await mock.setResponses(["ok"])
        let agent = try Agent(instructions: "test", inferenceProvider: mock)
        let observer = LoggingObserver()
        _ = try await agent.run("hello", observer: observer)
    }
}

actor CallCountObserver: AgentObserver {
    var startCount = 0
    var endCount = 0

    func onAgentStart(context: AgentContext?, agent: any AgentRuntime, input: String) async {
        startCount += 1
    }

    func onAgentEnd(context: AgentContext?, agent: any AgentRuntime, result: AgentResult) async {
        endCount += 1
    }
}
