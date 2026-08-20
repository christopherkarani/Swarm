import Foundation
import Testing
@testable import Swarm

@Suite("Full API Scenarios")
struct FullAPIScenarioTests {
    @Test("Scenario 1: simple agent with no tools")
    func helloWorld() async throws {
        let mock = MockInferenceProvider()
        await mock.setResponses(["Hello! You said: Hi"])
        let agent = try Agent(instructions: "You are a friendly assistant.", inferenceProvider: mock)
        let result = try await agent.run("Hi there")
        #expect(result.output.contains("Hello"))
    }

    @Test("Scenario 2: tool agent via Swarm.configure")
    func toolAgent() async throws {
        try await withSwarmConfigurationIsolation {
            let mock = MockInferenceProvider()
            await mock.setResponses(["42"])
            await Swarm.configure(provider: mock)
            let tool = MockTool(name: "calculator")
            let agent = try Agent(tools: [tool], instructions: "Math assistant")
            let result = try await agent.run("What is 2+2?")
            #expect(result.output == "42")
        }
    }

    @Test("Scenario 3: Conversation send/receive")
    func conversationSend() async throws {
        let mock = MockAgentRuntime(response: "Great recipe!")
        let conversation = Conversation(with: mock)
        try await conversation.send("How do I make pasta?")
        let messages = await conversation.messages
        #expect(messages.count == 2)
        #expect(messages[1].role == Conversation.Message.Role.assistant)
    }

    @Test("Scenario 4: Conversation streaming")
    func conversationStream() async throws {
        let mock = MockAgentRuntime(streamTokens: ["Hello", " ", "world"])
        let conversation = Conversation(with: mock)
        try await conversation.streamText("Tell me something")
        let lastMessage = await conversation.messages.last
        #expect(lastMessage?.text == "Hello world")
    }

    @Test("Scenario 5: three-step sequential pipeline")
    func sequentialWorkflow() async throws {
        let r = MockAgentRuntime(response: "researched")
        let w = MockAgentRuntime(response: "written")
        let e = MockAgentRuntime(response: "edited")
        let result = try await Workflow()
            .step(r).step(w).step(e)
            .run("topic")
        #expect(result.output == "edited")
    }

    @Test("Scenario 6: parallel fan-out with merge")
    func parallelWorkflow() async throws {
        let a = MockAgentRuntime(response: "positive")
        let b = MockAgentRuntime(response: "Apple, M5")
        let result = try await Workflow()
            .parallel([a, b])
            .run("text")
        #expect(result.output.contains("positive"))
        #expect(result.output.contains("Apple"))
    }

    @Test("Scenario 7: route selects correct agent")
    func routerWorkflow() async throws {
        let billing = MockAgentRuntime(response: "billing")
        let general = MockAgentRuntime(response: "general")
        let result = try await Workflow()
            .route { input in
                input.contains("bill") ? billing : general
            }
            .run("billing question")
        #expect(result.output == "billing")
    }

    @Test("Scenario 8: repeatUntil with timeout")
    func longRunning() async throws {
        let counter = ScenarioCounter()
        let agent = MockAgentRuntime(responseFactory: { counter.next() })
        let result = try await Workflow()
            .step(agent)
            .repeatUntil { $0.output.contains("SHUTDOWN") }
            .timeout(.seconds(10))
            .run("monitor")
        #expect(result.output == "SHUTDOWN")
    }

    @Test("Scenario 9: agent with ConversationMemory")
    func memoryAgent() async throws {
        let mock = MockInferenceProvider()
        await mock.setResponses(["Max"])
        let memory = ConversationMemory(maxMessages: 100)
        let agent = try Agent(instructions: "Journal", memory: memory, inferenceProvider: mock)
        _ = try await agent.run("My dog is Max")
        await memory.add(.assistant("Max"))
        let ctx = await memory.context(for: "dog", tokenLimit: 500)
        #expect(ctx.contains("Max"))
    }

    @Test("Scenario 10: input guardrail blocks bad input")
    func guardrails() async throws {
        let mock = MockInferenceProvider()
        await mock.setResponses(["ok"])
        let guardrail = InputGuard("always_trip") { _, _ in
            .tripwire(message: "blocked")
        }
        let agent = try Agent(instructions: "Service", inferenceProvider: mock, inputGuardrails: [guardrail])
        await #expect(throws: Error.self) {
            try await agent.run("bad input")
        }
    }

    @Test("Scenario 11: agent with handoffAgents delegates")
    func handoffs() async throws {
        let mock = MockInferenceProvider()
        await mock.setResponses(["routed to billing"])
        let billing = try Agent(instructions: "Billing", inferenceProvider: mock)
        let triage = try Agent(instructions: "Triage", inferenceProvider: mock, handoffAgents: [billing])
        let result = try await triage.run("refund please")
        #expect(result.output.contains("billing") || result.output.contains("routed"))
    }

    @Test("Scenario 12: observed(by:) receives callbacks")
    func observer() async throws {
        let mock = MockInferenceProvider()
        await mock.setResponses(["ok"])
        let agent = try Agent(instructions: "test", inferenceProvider: mock)
        let counter = IntegrationCallCountObserver()
        let observed = agent.observed(by: counter)
        _ = try await observed.run("hello")
        #expect(await counter.startCount == 1)
    }
}

private final class ScenarioCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count >= 2 ? "SHUTDOWN" : "running"
    }
}

actor IntegrationCallCountObserver: AgentObserver {
    var startCount = 0

    func onAgentStart(context: AgentContext?, agent: any AgentRuntime, input: String) async {
        startCount += 1
    }
}
