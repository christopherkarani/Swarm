@testable import Swarm
import Testing

@Suite("Agent.run guardrail behavior")
struct AgentRunGuardrailBehaviorTests {
    private let _ephemeralDefaultStores = SwarmEphemeralStoreBootstrap.installOnce

    @Test("Input guardrail tripwire blocks provider execution")
    func inputGuardrailTripwireBlocksProvider() async throws {
        let provider = MockInferenceProvider(responses: ["should not be used"])
        let memory = MockAgentMemory()
        let session = InMemorySession(sessionId: "input-tripwire")
        let guardrail = InputGuard("block_input") { _ in
            GuardrailResult.tripwire(message: "blocked before provider")
        }
        let agent = try Agent(
            instructions: "Respond briefly.",
            configuration: AgentConfiguration(defaultTracingEnabled: false),
            memory: memory,
            inferenceProvider: provider,
            inputGuardrails: [guardrail]
        )

        do {
            _ = try await agent.run("blocked request", session: session)
            Issue.record("Expected input guardrail tripwire")
        } catch let error as GuardrailError {
            guard case let .inputTripwireTriggered(guardrailName, message, _) = error else {
                Issue.record("Expected inputTripwireTriggered, got \(error)")
                return
            }
            #expect(guardrailName == "block_input")
            #expect(message == "blocked before provider")
        }

        #expect(await provider.generateCallCount == 0)
        #expect(await provider.generateMessageCalls.isEmpty)
        #expect(await provider.toolCallCalls.isEmpty)
        #expect(await provider.toolCallMessageCalls.isEmpty)
        #expect(try await session.getAllItems().isEmpty)
        #expect(await memory.addCalls.isEmpty)
    }

    @Test("Output guardrail tripwire blocks session persistence")
    func outputGuardrailTripwireBlocksPersistence() async throws {
        let provider = MockInferenceProvider(responses: ["unsafe output"])
        let memory = MockAgentMemory()
        let session = InMemorySession(sessionId: "output-tripwire")
        let guardrail = OutputGuard("block_output") { output in
            output == "unsafe output"
                ? GuardrailResult.tripwire(message: "blocked before persistence")
                : GuardrailResult.passed()
        }
        let agent = try Agent(
            instructions: "Respond briefly.",
            configuration: AgentConfiguration(defaultTracingEnabled: false),
            memory: memory,
            inferenceProvider: provider,
            outputGuardrails: [guardrail]
        )

        do {
            _ = try await agent.run("produce unsafe output", session: session)
            Issue.record("Expected output guardrail tripwire")
        } catch let error as GuardrailError {
            guard case let .outputTripwireTriggered(guardrailName, _, message, _) = error else {
                Issue.record("Expected outputTripwireTriggered, got \(error)")
                return
            }
            #expect(guardrailName == "block_output")
            #expect(message == "blocked before persistence")
        }

        #expect(await provider.generateCallCount == 0)
        #expect(await provider.generateMessageCalls.count == 1)
        #expect(try await session.getAllItems().isEmpty)
        #expect(await memory.addCalls.isEmpty)
    }

    @Test("Deprecated nil tripwire message is forwarded on GuardrailError")
    func deprecatedNilTripwireMessageReachesError() async throws {
        let provider = MockInferenceProvider(responses: ["should not be used"])
        let session = InMemorySession(sessionId: "legacy-tripwire")
        let guardrail = InputGuard("legacy") { _ in
            GuardrailResult(tripwireTriggered: true)
        }
        let agent = try Agent(
            instructions: "Respond briefly.",
            configuration: AgentConfiguration(defaultTracingEnabled: false),
            inferenceProvider: provider,
            inputGuardrails: [guardrail]
        )

        do {
            _ = try await agent.run("blocked request", session: session)
            Issue.record("Expected input guardrail tripwire")
        } catch let error as GuardrailError {
            guard case let .inputTripwireTriggered(guardrailName, message, _) = error else {
                Issue.record("Expected inputTripwireTriggered, got \(error)")
                return
            }
            #expect(guardrailName == "legacy")
            #expect(message == "Tripwire triggered")
        }

        #expect(await provider.generateCallCount == 0)
    }
}
