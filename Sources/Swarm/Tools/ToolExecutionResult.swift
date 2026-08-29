// ToolExecutionResult.swift
// Swarm Framework
//
// Types for parallel tool execution results and error handling strategies.

import Foundation

// MARK: - ParallelExecutionErrorStrategy

/// Strategy for handling errors during parallel tool execution.
///
/// When executing multiple tools concurrently, errors can occur in any of them.
/// This enum defines how the executor should respond to these errors.
///
/// Example:
/// ```swift
/// let executor = ParallelToolExecutor()
///
/// // Fail immediately on first error (cancels remaining tasks)
/// let results = try await executor.executeInParallel(
///     calls, using: registry, agent: agent, context: nil,
///     errorStrategy: .failFast
/// )
///
/// // Collect all errors and throw composite error at end
/// let results = try await executor.executeInParallel(
///     calls, using: registry, agent: agent, context: nil,
///     errorStrategy: .collectErrors
/// )
///
/// // Continue execution and include failures in results
/// let results = try await executor.executeInParallel(
///     calls, using: registry, agent: agent, context: nil,
///     errorStrategy: .continueOnError
/// )
/// ```
public enum ParallelExecutionErrorStrategy: Sendable, Equatable {
    /// Throw immediately on first error encountered.
    ///
    /// When any tool execution fails, the executor immediately throws the error
    /// and cancels any remaining tool executions. This is the fastest way to
    /// fail but may leave some tools unexecuted.
    case failFast

    /// Collect all errors and throw a composite error at the end.
    ///
    /// All tool executions complete (or fail), and if any errors occurred,
    /// a composite error containing all failures is thrown after completion.
    /// This ensures all tools are attempted before failing.
    case collectErrors

    /// Continue execution and include failures in results.
    ///
    /// All tool executions complete, and failures are captured in the
    /// ``ToolExecutionResult/result`` property as `.failure` cases.
    /// No error is thrown; callers inspect individual results for failures.
    case continueOnError
}

// MARK: - ToolExecutionResult

/// Result of a single tool execution in parallel execution context.
///
/// Captures comprehensive information about a tool execution including
/// the tool name, arguments, result (success or failure), timing, and timestamp.
///
/// This type is used by parallel executors to report individual tool outcomes
/// while preserving detailed execution metadata.
///
/// Example:
/// ```swift
/// let result = ToolExecutionResult(
///     toolName: "weather",
///     arguments: ["location": .string("San Francisco")],
///     result: .success(.string("72F and sunny")),
///     duration: .milliseconds(150),
///     timestamp: Date()
/// )
///
/// if result.isSuccess {
///     print("Tool \(result.toolName) returned: \(result.value!)")
/// } else {
///     print("Tool \(result.toolName) failed: \(result.error!)")
/// }
/// ```
public struct ToolExecutionResult: Sendable {
    /// The name of the tool that was executed.
    public let toolName: String

    /// The arguments that were passed to the tool.
    public let arguments: [String: SendableValue]

    /// The result of the tool execution.
    ///
    /// Contains `.success` with the tool's return value, or `.failure` with
    /// the error that occurred during execution.
    public let result: Result<SendableValue, Error>

    /// The duration of the tool execution.
    ///
    /// Measures the time from when execution started to when it completed
    /// (either successfully or with an error).
    public let duration: Duration

    /// The timestamp when the tool execution was initiated.
    public let timestamp: Date

    /// Returns `true` if the tool execution succeeded.
    public var isSuccess: Bool {
        switch result {
        case .success:
            true
        case .failure:
            false
        }
    }

    /// Returns the successful value if the execution succeeded, otherwise `nil`.
    public var value: SendableValue? {
        switch result {
        case let .success(value):
            value
        case .failure:
            nil
        }
    }

    /// Returns the error if the execution failed, otherwise `nil`.
    public var error: Error? {
        switch result {
        case .success:
            nil
        case let .failure(error):
            error
        }
    }

    // MARK: - Initialization

    /// Creates a new tool execution result.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool that was executed.
    ///   - arguments: The arguments passed to the tool.
    ///   - result: The result of the execution (success or failure).
    ///   - duration: The duration of the execution.
    ///   - timestamp: The timestamp when execution was initiated. Defaults to now.
    public init(
        toolName: String,
        arguments: [String: SendableValue],
        result: Result<SendableValue, Error>,
        duration: Duration,
        timestamp: Date = TurnEnvironment.live.now()
    ) {
        self.toolName = toolName
        self.arguments = arguments
        self.result = result
        self.duration = duration
        self.timestamp = timestamp
    }

    /// Creates a successful tool execution result.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool that was executed.
    ///   - arguments: The arguments passed to the tool.
    ///   - value: The successful return value.
    ///   - duration: The duration of the execution.
    ///   - timestamp: The timestamp when execution was initiated. Defaults to now.
    /// - Returns: A new `ToolExecutionResult` representing success.
    public static func success(
        toolName: String,
        arguments: [String: SendableValue],
        value: SendableValue,
        duration: Duration,
        timestamp: Date = TurnEnvironment.live.now()
    ) -> ToolExecutionResult {
        ToolExecutionResult(
            toolName: toolName,
            arguments: arguments,
            result: .success(value),
            duration: duration,
            timestamp: timestamp
        )
    }

    /// Creates a failed tool execution result.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool that was executed.
    ///   - arguments: The arguments passed to the tool.
    ///   - error: The error that occurred during execution.
    ///   - duration: The duration until the error occurred.
    ///   - timestamp: The timestamp when execution was initiated. Defaults to now.
    /// - Returns: A new `ToolExecutionResult` representing failure.
    public static func failure(
        toolName: String,
        arguments: [String: SendableValue],
        error: Error,
        duration: Duration,
        timestamp: Date = TurnEnvironment.live.now()
    ) -> ToolExecutionResult {
        ToolExecutionResult(
            toolName: toolName,
            arguments: arguments,
            result: .failure(error),
            duration: duration,
            timestamp: timestamp
        )
    }

    /// Maps an Engine ``ToolResult`` onto the public parallel-executor result.
    static func from(call: ToolCall, result: ToolResult) -> ToolExecutionResult {
        switch result.outcome {
        case let .success(value):
            return .success(
                toolName: call.toolName,
                arguments: call.arguments,
                value: value,
                duration: result.duration
            )
        case let .failure(message):
            return .failure(
                toolName: call.toolName,
                arguments: call.arguments,
                error: AgentError.toolFailure(toolName: call.toolName, message: message, cause: nil),
                duration: result.duration
            )
        }
    }
}

// MARK: CustomStringConvertible

extension ToolExecutionResult: CustomStringConvertible {
    public var description: String {
        let status = isSuccess ? "success" : "failure"
        let resultDescription: String = switch result {
        case let .success(value):
            value.description
        case let .failure(error):
            error.localizedDescription
        }
        return """
        ToolExecutionResult(\
        tool: \(toolName), \
        status: \(status), \
        duration: \(duration), \
        result: \(resultDescription))
        """
    }
}

// MARK: CustomDebugStringConvertible

extension ToolExecutionResult: CustomDebugStringConvertible {
    public var debugDescription: String {
        """
        ToolExecutionResult {
            toolName: \(toolName)
            arguments: \(arguments)
            result: \(result)
            duration: \(duration)
            timestamp: \(timestamp)
        }
        """
    }
}

// MARK: Equatable

extension ToolExecutionResult: Equatable {
    /// Compares two tool execution results for equality.
    ///
    /// Error comparison uses `localizedDescription` since `Error` doesn't conform to `Equatable`.
    public static func == (lhs: ToolExecutionResult, rhs: ToolExecutionResult) -> Bool {
        guard lhs.toolName == rhs.toolName,
              lhs.arguments == rhs.arguments,
              lhs.duration == rhs.duration,
              lhs.isSuccess == rhs.isSuccess else {
            return false
        }

        switch (lhs.result, rhs.result) {
        case let (.success(lhsValue), .success(rhsValue)):
            return lhsValue == rhsValue
        case let (.failure(lhsError), .failure(rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}
