// WorkflowV3Tests.swift
// Tests for V3 Workflow and @WorkflowBuilderV3.

@testable import Swarm
import Testing

@Suite("WorkflowV3")
struct WorkflowV3Tests {
    @Test("Workflow created with steps")
    func workflowCreation() {
        let a = AgentV3("Agent A").named("a")
        let b = AgentV3("Agent B").named("b")

        let workflow = WorkflowV3 {
            StepV3(a)
            StepV3(b)
        }

        #expect(workflow.steps.count == 2)
        #expect(workflow.steps[0].id == "a")
        #expect(workflow.steps[1].id == "b")
    }

    @Test("Step with input transform")
    func stepTransform() {
        let agent = AgentV3("Summarizer").named("summarizer")
        let step = StepV3(agent, transform: { "Summarize: \($0)" })
        #expect(step.id == "summarizer")
    }

    @Test("Empty workflow")
    func emptyWorkflow() {
        let workflow = WorkflowV3 {}
        #expect(workflow.steps.isEmpty)
    }

    @Test("Conditional steps in builder")
    func conditionalSteps() {
        let a = AgentV3("A").named("a")
        let b = AgentV3("B").named("b")
        let includeB = false

        let workflow = WorkflowV3 {
            StepV3(a)
            if includeB {
                StepV3(b)
            }
        }

        #expect(workflow.steps.count == 1)
    }
}
