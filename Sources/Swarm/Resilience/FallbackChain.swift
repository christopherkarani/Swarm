// FallbackChain.swift
// Swarm Framework
//
// Fallback chain for graceful degradation with fluent builder pattern.

import Foundation

// MARK: - StepError

/// Represents an error that occurred during a specific fallback step.
public struct StepError: Sendable, Equatable {
    /// The name of the step that failed.
    public let stepName: String

    /// The index of the step in the chain (0-based).
    public let stepIndex: Int

    /// The error that occurred during step execution.
    public let error: Error

    /// Creates a new step error.
    /// - Parameters:
    ///   - stepName: The name of the step.
    ///   - stepIndex: The index of the step.
    ///   - error: The error that occurred.
    public init(stepName: String, stepIndex: Int, error: Error) {
        self.stepName = stepName
        self.stepIndex = stepIndex
        self.error = error
    }

    public static func == (lhs: StepError, rhs: StepError) -> Bool {
        lhs.stepName == rhs.stepName &&
            lhs.stepIndex == rhs.stepIndex &&
            String(describing: type(of: lhs.error)) == String(describing: type(of: rhs.error)) &&
            String(describing: lhs.error) == String(describing: rhs.error)
    }
}

// MARK: CustomDebugStringConvertible

extension StepError: CustomDebugStringConvertible {
    public var debugDescription: String {
        "StepError(step: \(stepName), index: \(stepIndex), error: \(error.localizedDescription))"
    }
}

// MARK: - ExecutionResult

/// The result of executing a fallback chain.
public struct ExecutionResult<Output: Sendable>: Sendable {
    /// The successful output value.
    public let output: Output

    /// The name of the step that succeeded.
    public let stepName: String

    /// The index of the successful step (0-based).
    public let stepIndex: Int

    /// Total number of attempts made before success.
    public let totalAttempts: Int

    /// Errors that occurred in previous failed steps.
    public let errors: [StepError]

    /// Creates a new execution result.
    /// - Parameters:
    ///   - output: The successful output value.
    ///   - stepName: The name of the successful step.
    ///   - stepIndex: The index of the successful step.
    ///   - totalAttempts: Total number of attempts made.
    ///   - errors: Errors from previous failed steps.
    public init(
        output: Output,
        stepName: String,
        stepIndex: Int,
        totalAttempts: Int,
        errors: [StepError]
    ) {
        self.output = output
        self.stepName = stepName
        self.stepIndex = stepIndex
        self.totalAttempts = totalAttempts
        self.errors = errors
    }
}

// MARK: CustomDebugStringConvertible

extension ExecutionResult: CustomDebugStringConvertible {
    public var debugDescription: String {
        "ExecutionResult(step: \(stepName), index: \(stepIndex), attempts: \(totalAttempts), errors: \(errors.count))"
    }
}

// MARK: - FallbackChain

/// A fluent builder for creating fallback chains with graceful degradation.
///
/// Example:
/// ```swift
/// let result = try await FallbackChain<String>()
///     .attempt(name: "Primary") {
///         try await primaryService.fetch()
///     }
///     .attempt(name: "Secondary") {
///         try await secondaryService.fetch()
///     }
///     .fallback(name: "Cache") { cachedValue }
///     .onFailure { stepName, error in
///         logger.warning("Step \(stepName) failed: \(error)")
///     }
///     .execute()
/// ```
public struct FallbackChain<Output: Sendable>: Sendable {
    // MARK: Public

    // MARK: - Initialization

    /// Creates an empty fallback chain.
    public init() {
        steps = []
        failureCallback = nil
    }

    // MARK: - Static Conveniences

    /// Creates a fallback chain from a list of operations.
    /// - Parameter operations: Named operations to execute in order.
    /// - Returns: A configured fallback chain.
    public static func from(_ operations: (name: String, operation: @Sendable () async throws -> Output)...) -> FallbackChain<Output> {
        var chain = FallbackChain<Output>()
        for (name, operation) in operations {
            chain = chain.attempt(name: name, operation)
        }
        return chain
    }

    // MARK: - Builder Methods

    /// Adds an operation step to the chain.
    /// - Parameters:
    ///   - name: The name of the step for debugging/logging.
    ///   - operation: The async operation to execute.
    /// - Returns: A new chain with the added step.
    public func attempt(
        name: String,
        _ operation: @escaping @Sendable () async throws -> Output
    ) -> FallbackChain<Output> {
        let step = Step(name: name, operation: operation)
        return FallbackChain(
            steps: steps + [step],
            failureCallback: failureCallback
        )
    }

    /// Adds a conditional operation step to the chain.
    /// - Parameters:
    ///   - name: The name of the step for debugging/logging.
    ///   - condition: Async condition that must be true for this step to execute.
    ///   - operation: The async operation to execute.
    /// - Returns: A new chain with the added conditional step.
    public func attemptIf(
        name: String,
        condition: @escaping @Sendable () async -> Bool,
        _ operation: @escaping @Sendable () async throws -> Output
    ) -> FallbackChain<Output> {
        let step = Step(name: name, operation: operation, condition: condition)
        return FallbackChain(
            steps: steps + [step],
            failureCallback: failureCallback
        )
    }

    /// Adds a final fallback that always succeeds.
    /// - Parameters:
    ///   - name: The name of the fallback step.
    ///   - value: The fallback value to return.
    /// - Returns: A new chain with the guaranteed fallback.
    public func fallback(name: String, _ value: Output) -> FallbackChain<Output> {
        let step = Step(
            name: name,
            operation: { value },
            isGuaranteedFallback: true
        )
        return FallbackChain(
            steps: steps + [step],
            failureCallback: failureCallback
        )
    }

    /// Adds a final fallback operation that always succeeds.
    /// - Parameters:
    ///   - name: The name of the fallback step.
    ///   - operation: The async operation that provides the fallback value.
    /// - Returns: A new chain with the guaranteed fallback.
    public func fallback(
        name: String,
        _ operation: @escaping @Sendable () async -> Output
    ) -> FallbackChain<Output> {
        let step = Step(
            name: name,
            operation: { await operation() },
            isGuaranteedFallback: true
        )
        return FallbackChain(
            steps: steps + [step],
            failureCallback: failureCallback
        )
    }

    /// Adds a callback that will be invoked when any step fails.
    /// - Parameter callback: Async callback receiving the step name and error.
    /// - Returns: A new chain with the failure callback.
    public func onFailure(
        _ callback: @escaping @Sendable (String, Error) async -> Void
    ) -> FallbackChain<Output> {
        FallbackChain(steps: steps, failureCallback: callback)
    }

    // MARK: - Execution

    /// Executes the fallback chain, trying each step until one succeeds.
    /// - Returns: The successful output value.
    /// - Throws: `ResilienceError.allFallbacksFailed` if all steps fail.
    public func execute() async throws -> Output {
        let result = try await executeWithResult()
        return result.output
    }

    /// Executes the fallback chain and returns detailed execution result.
    /// - Returns: An `ExecutionResult` containing the output and execution details.
    /// - Throws: `ResilienceError.allFallbacksFailed` if all steps fail.
    public func executeWithResult() async throws -> ExecutionResult<Output> {
        guard !steps.isEmpty else {
            throw ResilienceError.allFallbacksFailed(
                errors: ["No steps configured in fallback chain"]
            )
        }

        var errors: [StepError] = []

        for (index, step) in steps.enumerated() {
            // Check condition if present
            if let condition = step.condition {
                let shouldExecute = await condition()
                if !shouldExecute {
                    continue
                }
            }

            do {
                let output = try await step.operation()

                // Success - return result
                return ExecutionResult(
                    output: output,
                    stepName: step.name,
                    stepIndex: index,
                    totalAttempts: index + 1,
                    errors: errors
                )
            } catch {
                // Step failed - record error and try next step
                let stepError = StepError(
                    stepName: step.name,
                    stepIndex: index,
                    error: error
                )
                errors.append(stepError)

                // Invoke failure callback
                await failureCallback?(step.name, error)

                // If this was a guaranteed fallback, it shouldn't fail
                if step.isGuaranteedFallback {
                    throw ResilienceError.allFallbacksFailed(
                        errors: errors.map { "\($0.stepName): \($0.error.localizedDescription)" }
                    )
                }
            }
        }

        // All steps failed
        throw ResilienceError.allFallbacksFailed(
            errors: errors.map { "\($0.stepName): \($0.error.localizedDescription)" }
        )
    }

    // MARK: Internal

    // MARK: - Step

    /// Represents a single step in the fallback chain.
    struct Step: Sendable {
        /// The name of the step for debugging/logging.
        let name: String

        /// The operation to execute.
        let operation: @Sendable () async throws -> Output

        /// Optional condition that must be true for this step to execute.
        let condition: (@Sendable () async -> Bool)?

        /// Whether this step is a guaranteed-success fallback.
        let isGuaranteedFallback: Bool

        /// Creates a new step.
        /// - Parameters:
        ///   - name: The name of the step.
        ///   - operation: The operation to execute.
        ///   - condition: Optional condition for execution.
        ///   - isGuaranteedFallback: Whether this step always succeeds.
        init(
            name: String,
            operation: @escaping @Sendable () async throws -> Output,
            condition: (@Sendable () async -> Bool)? = nil,
            isGuaranteedFallback: Bool = false
        ) {
            self.name = name
            self.operation = operation
            self.condition = condition
            self.isGuaranteedFallback = isGuaranteedFallback
        }
    }

    // MARK: Private

    /// The immutable array of steps to execute.
    private let steps: [Step]

    /// Optional callback invoked when a step fails.
    private let failureCallback: (@Sendable (String, Error) async -> Void)?

    /// Internal initializer for chaining.
    private init(steps: [Step], failureCallback: (@Sendable (String, Error) async -> Void)?) {
        self.steps = steps
        self.failureCallback = failureCallback
    }
}

// MARK: CustomDebugStringConvertible

extension FallbackChain: CustomDebugStringConvertible {
    public var debugDescription: String {
        "FallbackChain(steps: \(steps.count))"
    }
}
