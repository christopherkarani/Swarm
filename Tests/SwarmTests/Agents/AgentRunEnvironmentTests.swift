// AgentRunEnvironmentTests.swift
// SwarmTests
//
// Proves AgentRunEnvironment isolation semantics. Ranking and inference-options
// assembly live on AgentTurnDependencyResolver in AgentTurnDependenciesTests.

import Foundation
import Testing
@testable import Swarm

// MARK: - Test Doubles

private func makeAgent(
    configuration: AgentConfiguration,
    provider: MockInferenceProvider,
    environment: AgentRunEnvironment
) throws -> Agent {
    try Agent(
        configuration: configuration,
        inferenceProvider: provider,
        runEnvironment: environment
    )
}

// MARK: - Environment Isolation & Default Sharing

@Suite("AgentRunEnvironment", .ephemeralDefaultStores)
struct AgentRunEnvironmentTests {

    private let config = AgentConfiguration.default.autoPreviousResponseId(true)

    @Test("two constructed environments carry fully isolated tracker state")
    func constructedEnvironmentsAreIsolated() async throws {
        let first = AgentRunEnvironment()
        let second = AgentRunEnvironment()

        #expect(first.responseTracker !== second.responseTracker)
        #expect(first.defaultMemorySessionTracker !== second.defaultMemorySessionTracker)

        let response = AgentResponse(responseId: "first-env-response", output: "hi", agentName: "A")
        await first.responseTracker.recordResponse(response, sessionId: "isolation-session")

        let leaked = await second.responseTracker.getLatestResponseId(for: "isolation-session")
        #expect(leaked == nil)

        let own = await first.responseTracker.getLatestResponseId(for: "isolation-session")
        #expect(own == "first-env-response")
    }

    @Test("default-configured agents share one environment exactly as the former globals")
    func defaultAgentsShareLiveEnvironment() throws {
        let first = try Agent(configuration: .default)
        let second = try Agent(configuration: .default)

        #expect(first.runEnvironment.responseTracker === second.runEnvironment.responseTracker)
        #expect(
            first.runEnvironment.defaultMemorySessionTracker
                === second.runEnvironment.defaultMemorySessionTracker
        )
        #expect(first.runEnvironment.responseTracker === AgentRunEnvironment.live.responseTracker)
        #expect(
            first.runEnvironment.defaultMemorySessionTracker
                === AgentRunEnvironment.live.defaultMemorySessionTracker
        )

        // Former process-global statics delegate to the shared default instance.
        #expect(Agent.autoResponseTracker === first.runEnvironment.responseTracker)
        #expect(Agent.defaultMemorySessionTracker === first.runEnvironment.defaultMemorySessionTracker)
    }

    @Test("explicit default memory store URL threads through to default memory creation")
    func explicitDefaultMemoryStoreURLThreadsThrough() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentRunEnvironmentTests", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).mv2s")

        let agent = try makeAgent(
            configuration: config,
            provider: MockInferenceProvider(responses: ["ok"]),
            environment: AgentRunEnvironment(defaultMemoryStoreURL: storeURL)
        )

        #expect(agent.runEnvironment.defaultMemoryStoreURL == storeURL)
        #expect(AgentRunEnvironment.live.defaultMemoryStoreURL == nil)

        #if SWARM_INTEGRATIONS && canImport(ContextCore)
        let memory = try Agent.makeDefaultMemory(waxStoreURL: storeURL)
        #expect(memory is DefaultAgentMemory)
        #endif
    }

    @Test("agents using defaults share response tracking across copies")
    func defaultAgentsShareTrackerStateAcrossRuns() async throws {
        let sessionID = "shared-default-\(UUID().uuidString)"
        let session = InMemorySession(sessionId: sessionID)
        let provider = MockInferenceProvider(
            responses: ["first reply", "second reply"],
            capabilities: [.responseContinuation]
        )

        let first = try Agent(configuration: config, inferenceProvider: provider)
        let second = try Agent(configuration: config, inferenceProvider: provider)

        let firstResult = try await first.run("first prompt", session: session)
        _ = try await second.run("second prompt", session: session)

        guard case let .string(firstResponseID)? = firstResult.metadata["response.id"] else {
            Issue.record("Expected first result metadata to include response.id")
            return
        }

        let calls = await provider.generateMessageCalls
        #expect(calls.count == 2)
        if calls.count == 2 {
            #expect(calls[0].options.previousResponseId == nil)
            #expect(calls[1].options.previousResponseId == firstResponseID)
        }
    }

    @Test("agents with distinct environments isolate response tracking across copies")
    func distinctEnvironmentsIsolateTrackingAcrossRuns() async throws {
        let sessionID = "isolated-envs-\(UUID().uuidString)"
        let session = InMemorySession(sessionId: sessionID)
        let provider = MockInferenceProvider(
            responses: ["first reply", "second reply"],
            capabilities: [.responseContinuation]
        )

        let first = try makeAgent(
            configuration: config,
            provider: provider,
            environment: AgentRunEnvironment()
        )
        let second = try makeAgent(
            configuration: config,
            provider: provider,
            environment: AgentRunEnvironment()
        )

        let firstResult = try await first.run("first prompt", session: session)
        _ = try await second.run("second prompt", session: session)

        guard case let .string(firstResponseID)? = firstResult.metadata["response.id"] else {
            Issue.record("Expected first result metadata to include response.id")
            return
        }
        #expect(!firstResponseID.isEmpty)

        let calls = await provider.generateMessageCalls
        #expect(calls.count == 2)
        if calls.count == 2 {
            #expect(calls[0].options.previousResponseId == nil)
            #expect(calls[1].options.previousResponseId == nil)
        }
    }

    @Test("session tracker clears memory only when the session changes")
    func sessionTrackerClearsOnlyOnSessionChange() async throws {
        let tracker = DefaultMemorySessionTracker()
        let key = ObjectIdentifier(NSObject())

        let firstClaim = try await tracker.beginRun(for: key, sessionID: "s1")
        #expect(firstClaim == true)

        // Same session re-claiming while active must not trigger a memory clear.
        let reentrantClaim = try await tracker.beginRun(for: key, sessionID: "s1")
        #expect(reentrantClaim == false)

        await tracker.endRun(for: key)
        await tracker.endRun(for: key)

        let changedClaim = try await tracker.beginRun(for: key, sessionID: "s2")
        #expect(changedClaim == true)

        await tracker.endRun(for: key)
    }

    @Test("session tracker state is isolated between instances")
    func sessionTrackerStateIsPerInstance() async throws {
        let first = DefaultMemorySessionTracker()
        let second = DefaultMemorySessionTracker()
        let key = ObjectIdentifier(NSObject())

        let firstResult = try await first.beginRun(for: key, sessionID: "shared-session")
        let secondResult = try await second.beginRun(for: key, sessionID: "shared-session")

        #expect(firstResult == true)
        #expect(secondResult == true)
    }
}
