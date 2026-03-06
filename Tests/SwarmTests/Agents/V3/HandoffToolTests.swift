// HandoffToolTests.swift
// Tests for HandoffV3 (handoff as tool).

@testable import Swarm
import Testing

@Suite("HandoffV3")
struct HandoffToolTests {
    @Test("Handoff conforms to ToolV3")
    func conformsToTool() {
        let target = AgentV3("Target agent").named("specialist")
        let handoff = HandoffV3(target)

        #expect(handoff.name == "handoff_to_specialist")
        #expect(handoff.description.contains("Transfer"))
    }

    @Test("Handoff default name from Agent")
    func defaultAgentName() {
        let target = AgentV3("Some instructions")
        let handoff = HandoffV3(target)
        #expect(handoff.name == "handoff_to_agent")
    }

    @Test("Handoff in ToolBuilderV3")
    func inToolBuilder() {
        let expert = AgentV3("Expert").named("expert")

        let agent = AgentV3("Router") {
            HandoffV3(expert)
        }

        #expect(agent.tools.count == 1)
        #expect(agent.tools[0].name == "handoff_to_expert")
    }

    @Test("Handoff with history mode")
    func historyMode() {
        let target = AgentV3("Target").named("target")
        let handoff = HandoffV3(target, history: .summarized(maxTokens: 500))

        if case .summarized(let maxTokens) = handoff.history {
            #expect(maxTokens == 500)
        } else {
            Issue.record("Expected .summarized")
        }
    }

    @Test("Handoff default history is .none")
    func defaultHistory() {
        let target = AgentV3("Target")
        let handoff = HandoffV3(target)

        if case .none = handoff.history { /* pass */ }
        else { Issue.record("Expected .none") }
    }

    @Test("Multiple handoffs in ToolBuilder")
    func multipleHandoffs() {
        let expert = AgentV3("Expert").named("expert")
        let summarizer = AgentV3("Summarizer").named("summarizer")

        let router = AgentV3("Router") {
            HandoffV3(expert)
            HandoffV3(summarizer)
        }

        #expect(router.tools.count == 2)
        #expect(router.tools[0].name == "handoff_to_expert")
        #expect(router.tools[1].name == "handoff_to_summarizer")
    }
}
