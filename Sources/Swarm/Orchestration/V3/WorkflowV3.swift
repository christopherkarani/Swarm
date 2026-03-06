// WorkflowV3.swift
// Swarm Framework
//
// V3 Workflow with @WorkflowBuilderV3 result builder.

import Foundation

/// A multi-agent workflow composed with a result builder.
///
/// ```swift
/// let workflow = WorkflowV3 {
///     StepV3(researcher)
///     StepV3(writer)
///     StepV3(reviewer)
/// }
/// let result = try await workflow.run("Write a report on AI")
/// ```
public struct WorkflowV3: Sendable {
    /// The steps in this workflow.
    public let steps: [any WorkflowStepV3]

    /// Creates a workflow from a result builder.
    public init(@WorkflowBuilderV3 _ content: () -> [any WorkflowStepV3]) {
        self.steps = content()
    }

    /// Runs the workflow sequentially, passing output of each step as input to the next.
    public func run(_ input: String, options: RunOptions = .default) async throws -> AgentResult {
        var currentInput = input
        var lastResult: AgentResult?

        for step in steps {
            let result = try await step.execute(currentInput, options: options)
            currentInput = result.output
            lastResult = result
        }

        guard let finalResult = lastResult else {
            throw AgentError.maxIterationsExceeded(iterations: 0)
        }
        return finalResult
    }

    /// Streams events from the workflow.
    public func stream(
        _ input: String,
        options: RunOptions = .default
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var currentInput = input
                    for step in steps {
                        let result = try await step.execute(currentInput, options: options)
                        continuation.yield(.completed(result: result))
                        currentInput = result.output
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - WorkflowStepV3

/// Protocol for workflow steps.
public protocol WorkflowStepV3: Sendable {
    var id: String { get }
    func execute(_ input: String, options: RunOptions) async throws -> AgentResult
}

// MARK: - StepV3

/// A single agent step in a workflow.
///
/// ```swift
/// StepV3(myAgent)
/// StepV3(myAgent, transform: { "Summarize: \($0)" })
/// ```
public struct StepV3: WorkflowStepV3 {
    public let id: String
    public let agent: AgentV3
    private let inputTransform: (@Sendable (String) -> String)?

    /// Creates a step wrapping an agent.
    public init(_ agent: AgentV3) {
        self.id = agent.name
        self.agent = agent
        self.inputTransform = nil
    }

    /// Creates a step with an input transformation.
    public init(_ agent: AgentV3, transform: @escaping @Sendable (String) -> String) {
        self.id = agent.name
        self.agent = agent
        self.inputTransform = transform
    }

    public func execute(_ input: String, options: RunOptions) async throws -> AgentResult {
        let transformedInput = inputTransform?(input) ?? input
        return try await agent.run(transformedInput, options: options)
    }
}

// MARK: - WorkflowBuilderV3

/// Result builder for workflow composition.
@resultBuilder
public struct WorkflowBuilderV3 {
    public static func buildBlock(_ steps: [any WorkflowStepV3]...) -> [any WorkflowStepV3] {
        steps.flatMap { $0 }
    }

    public static func buildExpression(_ step: any WorkflowStepV3) -> [any WorkflowStepV3] {
        [step]
    }

    public static func buildExpression(_ step: some WorkflowStepV3) -> [any WorkflowStepV3] {
        [step]
    }

    public static func buildOptional(_ steps: [any WorkflowStepV3]?) -> [any WorkflowStepV3] {
        steps ?? []
    }

    public static func buildEither(first steps: [any WorkflowStepV3]) -> [any WorkflowStepV3] {
        steps
    }

    public static func buildEither(second steps: [any WorkflowStepV3]) -> [any WorkflowStepV3] {
        steps
    }

    public static func buildArray(_ groups: [[any WorkflowStepV3]]) -> [any WorkflowStepV3] {
        groups.flatMap { $0 }
    }
}
