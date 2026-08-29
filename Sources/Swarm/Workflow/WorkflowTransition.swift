import Foundation

/// Pure state machine for the control flow shared by direct and durable workflows.
///
/// Agent execution, repeat predicates, and persistence remain in their respective
/// shells. This type only validates progress and selects the next value-level
/// action.
enum WorkflowTransition {
    enum Repetition: Sendable, Equatable {
        case singlePass
        case until(maxIterations: Int)
    }

    struct Policy: Sendable, Equatable {
        let stepCount: Int
        let repetition: Repetition

        init(stepCount: Int, repetition: Repetition) {
            self.stepCount = stepCount
            self.repetition = repetition
        }
    }

    struct Progress: Sendable, Equatable {
        let stepCursor: Int
        let iterationCursor: Int
        let currentInput: String
        let lastResult: AgentResult?

        init(
            stepCursor: Int,
            iterationCursor: Int,
            currentInput: String,
            lastResult: AgentResult?
        ) {
            self.stepCursor = stepCursor
            self.iterationCursor = iterationCursor
            self.currentInput = currentInput
            self.lastResult = lastResult
        }
    }

    enum RepeatBoundaryOutcome: Sendable, Equatable {
        case satisfied
        case notSatisfied
    }

    enum Decision: Sendable, Equatable {
        case runStep(Progress)
        case evaluateRepeat(progress: Progress, result: AgentResult)
        case complete(progress: Progress, result: AgentResult)
        case fail(WorkflowError)
    }

    static func start(input: String, policy: Policy) -> Decision {
        if let error = validationError(for: policy) {
            return .fail(error)
        }
        return decide(
            progress: Progress(
                stepCursor: 0,
                iterationCursor: 0,
                currentInput: input,
                lastResult: nil
            ),
            policy: policy
        )
    }

    static func validationError(for policy: Policy) -> WorkflowError? {
        guard policy.stepCount > 0 else {
            return .invalidWorkflow(reason: "Workflow has no steps")
        }
        if case .until(let maxIterations) = policy.repetition, maxIterations <= 0 {
            return .invalidWorkflow(reason: "Workflow repeatUntil requires maxIterations to be greater than zero")
        }
        return nil
    }

    static func decide(progress: Progress, policy: Policy) -> Decision {
        if let error = validationError(for: policy) {
            return .fail(error)
        }
        guard progress.stepCursor >= 0, progress.iterationCursor >= 0 else {
            return .fail(.invalidWorkflow(
                reason: "workflow transition received negative cursors "
                    + "(stepCursor: \(progress.stepCursor), iterationCursor: \(progress.iterationCursor))"
            ))
        }

        guard progress.stepCursor < policy.stepCount else {
            let result = progress.lastResult ?? AgentResult(output: progress.currentInput)
            switch policy.repetition {
            case .singlePass:
                return .complete(progress: progress, result: result)
            case .until:
                return .evaluateRepeat(progress: progress, result: result)
            }
        }

        return .runStep(progress)
    }

    static func afterStep(
        progress: Progress,
        result: AgentResult,
        policy: Policy
    ) -> Decision {
        guard progress.stepCursor >= 0, progress.stepCursor < policy.stepCount else {
            return .fail(.invalidWorkflow(reason: "workflow transition completed an invalid step cursor"))
        }
        let (nextStepCursor, overflow) = progress.stepCursor.addingReportingOverflow(1)
        guard !overflow else {
            return .fail(.invalidWorkflow(reason: "workflow transition step cursor overflowed"))
        }
        return decide(
            progress: Progress(
                stepCursor: nextStepCursor,
                iterationCursor: progress.iterationCursor,
                currentInput: result.output,
                lastResult: result
            ),
            policy: policy
        )
    }

    static func afterRepeatBoundary(
        progress: Progress,
        result: AgentResult,
        outcome: RepeatBoundaryOutcome,
        policy: Policy
    ) -> Decision {
        guard case .until(let maxIterations) = policy.repetition else {
            return .fail(.invalidWorkflow(reason: "workflow transition evaluated a non-repeating workflow"))
        }
        guard progress.stepCursor >= policy.stepCount else {
            return .fail(.invalidWorkflow(reason: "workflow transition evaluated repeat before the final step"))
        }

        if outcome == .satisfied {
            return .complete(progress: progress, result: result)
        }

        let (nextIteration, overflow) = progress.iterationCursor.addingReportingOverflow(1)
        guard !overflow else {
            return .fail(.invalidWorkflow(reason: "workflow transition iteration cursor overflowed"))
        }
        guard nextIteration < maxIterations else {
            return .complete(progress: progress, result: result)
        }

        return decide(
            progress: Progress(
                stepCursor: 0,
                iterationCursor: nextIteration,
                currentInput: result.output,
                lastResult: result
            ),
            policy: policy
        )
    }
}
