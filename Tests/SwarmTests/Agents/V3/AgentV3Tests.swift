// AgentV3Tests.swift
// Tests for the V3 Agent struct.

@testable import Swarm
import Testing

// MARK: - Fixtures

private struct MockToolV3: ToolV3 {
    let name = "mock"
    let description = "A mock tool"
    func call() async throws -> String { "mocked" }
}

private struct AnotherMockTool: ToolV3 {
    let name = "another"
    let description = "Another mock"
    func call() async throws -> String { "another" }
}

// MARK: - Suite

@Suite("AgentV3 struct")
struct AgentV3Tests {
    @Test("Minimal agent with instructions only")
    func minimalAgent() {
        let agent = AgentV3("You are a helpful assistant.")
        #expect(agent.instructions == "You are a helpful assistant.")
        #expect(agent.name == "Agent")
        #expect(agent.tools.isEmpty)
        #expect(agent.guardrails.isEmpty)
        #expect(agent.provider == nil)
        #expect(agent.hooks == nil)
    }

    @Test("Agent with tools via trailing closure")
    func agentWithTools() {
        let agent = AgentV3("Helper") {
            MockToolV3()
            AnotherMockTool()
        }
        #expect(agent.tools.count == 2)
        #expect(agent.tools[0].name == "mock")
        #expect(agent.tools[1].name == "another")
    }

    @Test("Agent with guardrails")
    func agentWithGuardrails() {
        let agent = AgentV3("Helper", guardrails: [.maxInput(500), .inputNotEmpty])
        #expect(agent.guardrails.count == 2)
    }

    @Test(".named() modifier")
    func namedModifier() {
        let agent = AgentV3("Helper").named("MyAgent")
        #expect(agent.name == "MyAgent")
        #expect(agent.instructions == "Helper") // unchanged
    }

    @Test(".memory() modifier")
    func memoryModifier() {
        let agent = AgentV3("Helper").memory(.conversation(limit: 30))
        if case .conversation(let limit) = agent.memoryOption {
            #expect(limit == 30)
        } else {
            Issue.record("Expected .conversation")
        }
    }

    @Test("Modifier chain preserves all properties")
    func modifierChain() {
        let agent = AgentV3("Instructions", guardrails: [.inputNotEmpty]) {
            MockToolV3()
        }
        .named("ChainedAgent")
        .memory(.slidingWindow(count: 10))

        #expect(agent.name == "ChainedAgent")
        #expect(agent.instructions == "Instructions")
        #expect(agent.tools.count == 1)
        #expect(agent.guardrails.count == 1)
        if case .slidingWindow(let count) = agent.memoryOption {
            #expect(count == 10)
        } else {
            Issue.record("Expected .slidingWindow")
        }
    }

    @Test("Agent is a value type (struct)")
    func valueType() {
        let agent1 = AgentV3("Original")
        let agent2 = agent1.named("Copy")
        #expect(agent1.name == "Agent") // original unchanged
        #expect(agent2.name == "Copy")
    }
}
