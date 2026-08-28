import Foundation
import Testing
@testable import Swarm

@Suite("Workflow transition")
struct WorkflowTransitionTests {
    @Test("start rejects empty and non-positive repeating policies")
    func invalidPoliciesFailBeforeRunning() {
        let policies = [
            WorkflowTransition.Policy(stepCount: 0, repetition: .singlePass),
            WorkflowTransition.Policy(stepCount: 1, repetition: .until(maxIterations: 0)),
            WorkflowTransition.Policy(stepCount: 1, repetition: .until(maxIterations: -1)),
        ]

        for policy in policies {
            let decision = WorkflowTransition.start(input: "input", policy: policy)
            guard case .fail(let error) = decision else {
                Issue.record("expected invalid policy to fail: \(policy)")
                continue
            }
            guard case .invalidWorkflow = error else {
                Issue.record("expected WorkflowError.invalidWorkflow, got \(error)")
                continue
            }
        }
    }

    @Test("repeat boundary honors one- and two-pass limits")
    func repeatLimitsReturnTheLastFullResult() {
        for maxIterations in [1, 2] {
            let policy = WorkflowTransition.Policy(
                stepCount: 1,
                repetition: .until(maxIterations: maxIterations)
            )
            var decision = WorkflowTransition.start(input: "input", policy: policy)
            var runCount = 0
            var lastResult: AgentResult?

            repeatLoop: while true {
                switch decision {
                case .runStep(let progress):
                    runCount += 1
                    let result = AgentResult(
                        output: "pass-\(runCount)",
                        iterationCount: runCount,
                        metadata: ["marker": .string("full-result")]
                    )
                    lastResult = result
                    decision = WorkflowTransition.afterStep(
                        progress: progress,
                        result: result,
                        policy: policy
                    )

                case .evaluateRepeat(let progress, let result):
                    #expect(result == lastResult)
                    decision = WorkflowTransition.afterRepeatBoundary(
                        progress: progress,
                        result: result,
                        outcome: .notSatisfied,
                        policy: policy
                    )

                case .complete(_, let result):
                    #expect(runCount == maxIterations)
                    #expect(result == lastResult)
                    break repeatLoop

                case .fail(let error):
                    Issue.record("unexpected transition failure: \(error)")
                    break repeatLoop
                }
            }
        }
    }

    @Test("a satisfied repeat boundary completes with the supplied result")
    func satisfiedBoundaryPreservesResult() {
        let policy = WorkflowTransition.Policy(stepCount: 1, repetition: .until(maxIterations: 3))
        let result = AgentResult(
            output: "done",
            iterationCount: 7,
            metadata: ["marker": .string("preserved")]
        )
        let progress = WorkflowTransition.Progress(
            stepCursor: 1,
            iterationCursor: 0,
            currentInput: result.output,
            lastResult: result
        )

        let decision = WorkflowTransition.afterRepeatBoundary(
            progress: progress,
            result: result,
            outcome: .satisfied,
            policy: policy
        )

        guard case .complete(_, let completed) = decision else {
            Issue.record("expected satisfied repeat boundary to complete")
            return
        }
        #expect(completed == result)
    }
}
