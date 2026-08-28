// AgentEvent.swift
// Swarm Framework
//
// Events emitted during agent execution for streaming and observation.

import Foundation

// MARK: - AgentEvent

/// Events emitted during agent execution, used for streaming responses.
///
/// `AgentEvent` is organized into five nested namespaces so consumers can
/// pattern-match at whatever level of detail they need:
///
/// ```swift
/// for try await event in agent.stream("What's 2+2?") {
///     switch event {
///     case .lifecycle(.started(let input)):
///         print("Started with: \(input)")
///     case .output(.thinking(thought: let thought)):
///         print("Thinking: \(thought)")
///     case .tool(.started(call: let call)):
///         print("Calling tool: \(call.toolName)")
///     case .lifecycle(.completed(let result)):
///         print("Result: \(result.output)")
///     default:
///         break
///     }
/// }
/// ```
public enum AgentEvent: Sendable {

    // MARK: - New V3 Nested Cases

    /// Agent lifecycle events (start, complete, fail, cancel, guardrail, iteration).
    case lifecycle(Lifecycle)

    /// Tool call events (started, partial streaming, completed, failed).
    case tool(Tool)

    /// Output events (token, chunk, thinking, partial thinking).
    case output(Output)

    /// Agent handoff events (requested, started, completed, skipped).
    case handoff(Handoff)

    /// Observability events (decision, plan, guardrail state, memory, LLM telemetry).
    case observation(Observation)

    // MARK: - Nested Enums

    /// Lifecycle events covering the overall agent execution arc.
    public enum Lifecycle: Sendable {
        /// Agent execution has started.
        case started(input: String)

        /// Agent execution completed successfully.
        case completed(result: AgentResult)

        /// Agent execution failed.
        case failed(error: AgentError)

        /// Agent execution was cancelled.
        case cancelled

        /// A guardrail rejected input or output.
        case guardrailFailed(error: GuardrailError)

        /// A new iteration of the reasoning loop began.
        case iterationStarted(number: Int)

        /// An iteration of the reasoning loop completed.
        case iterationCompleted(number: Int)
    }

    /// Tool invocation events.
    public enum Tool: Sendable {
        /// A tool call was initiated.
        case started(call: ToolCall)

        /// Partial (streaming) argument data arrived for an in-progress tool call.
        case partial(update: PartialToolCallUpdate)

        /// A tool call completed successfully.
        case completed(call: ToolCall, result: ToolResult)

        /// A tool call failed.
        case failed(call: ToolCall, error: AgentError)
    }

    /// Token and thought output events.
    public enum Output: Sendable {
        /// A single token streamed from the model.
        case token(String)

        /// A larger text chunk streamed from the model.
        case chunk(String)

        /// The agent produced a reasoning thought (ReAct "Thought" step).
        case thinking(thought: String)

        /// A partial thought during streaming.
        case thinkingPartial(String)
    }

    /// Handoff events when control transfers between agents.
    public enum Handoff: Sendable {
        /// A handoff was requested but not yet started.
        case requested(from: String, to: String, reason: String?)

        /// A handoff completed.
        case completed(from: String, to: String)

        /// A handoff has started with specific input forwarded to the target agent.
        case started(from: String, to: String, input: String)

        /// A handoff completed and produced a result.
        case completedWithResult(from: String, to: String, result: AgentResult)

        /// A handoff was skipped (e.g. handoffs disabled).
        case skipped(from: String, to: String, reason: String)
    }

    /// Observability and telemetry events.
    public enum Observation: Sendable {
        /// The agent made a named decision, optionally from a set of options.
        case decision(String, options: [String]?)

        /// The agent's execution plan was created or updated.
        case planUpdated(String, stepCount: Int)

        /// A guardrail check started.
        case guardrailStarted(name: String, type: GuardrailType)

        /// A guardrail check passed.
        case guardrailPassed(name: String, type: GuardrailType)

        /// A guardrail tripwire was triggered.
        case guardrailTriggered(name: String, type: GuardrailType, message: String?)

        /// Memory was accessed.
        case memoryAccessed(operation: MemoryOperation, count: Int)

        /// An LLM call started.
        case llmStarted(model: String?, promptTokens: Int?)

        /// An LLM call completed with usage telemetry.
        case llmCompleted(model: String?, promptTokens: Int?, completionTokens: Int?, duration: TimeInterval)

        /// Provider inference will be retried after a transient failure.
        ///
        /// `attempt` is 1-indexed (the first retry is `1`).
        case inferenceRetry(attempt: Int, message: String)
    }

}

// MARK: - GuardrailType

/// Type of guardrail check.
public enum GuardrailType: String, Sendable, Codable {
    case input
    case output
    case toolInput
    case toolOutput
}

// MARK: - MemoryOperation

/// Type of memory operation.
public enum MemoryOperation: String, Sendable, Codable {
    case read
    case write
    case search
    case clear
}

// MARK: - ToolCall

/// Represents a tool call made by the agent.
///
/// A ToolCall captures all the information about an agent's decision
/// to invoke a particular tool with specific arguments.
public struct ToolCall: Sendable, Equatable, Identifiable, Codable {
    /// Unique identifier for this tool call.
    public let id: UUID

    /// Provider-assigned tool call identifier, if available (e.g. OpenAI/Anthropic tool call IDs).
    ///
    /// This enables correlation across provider-native tool calling flows and multi-turn tool interactions.
    public let providerCallId: String?

    /// Name of the tool being called.
    public let toolName: String

    /// Arguments passed to the tool.
    public let arguments: [String: SendableValue]

    /// Timestamp when the call was initiated.
    public let timestamp: Date

    /// Creates a new tool call.
    /// - Parameters:
    ///   - id: Unique identifier. Default: new UUID
    ///   - providerCallId: Provider-assigned tool call identifier. Default: nil
    ///   - toolName: The name of the tool.
    ///   - arguments: Arguments for the tool.
    ///   - timestamp: When the call was made. Default: now
    public init(
        id: UUID = TurnEnvironment.live.newUUID(),
        providerCallId: String? = nil,
        toolName: String,
        arguments: [String: SendableValue] = [:],
        timestamp: Date = TurnEnvironment.live.now()
    ) {
        self.id = id
        self.providerCallId = providerCallId
        self.toolName = toolName
        self.arguments = arguments
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case providerCallId
        case toolName
        case arguments
        case timestamp
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        providerCallId = try container.decodeIfPresent(String.self, forKey: .providerCallId)
        toolName = try container.decode(String.self, forKey: .toolName)
        arguments = try container.decode([String: SendableValue].self, forKey: .arguments)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(providerCallId, forKey: .providerCallId)
        try container.encode(toolName, forKey: .toolName)
        try container.encode(arguments, forKey: .arguments)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

// MARK: - ToolResult

/// Represents the result of a tool execution.
///
/// `ToolResult` is a closed outcome: execution either succeeded with a value or
/// failed with a message. `callId` and `duration` sit outside the outcome so
/// timing and correlation stay available on both paths.
///
/// Construct values with ``success(callId:output:duration:)`` or
/// ``failure(callId:error:duration:)``. Compatibility accessors
/// (``isSuccess``, ``output``, ``errorMessage``) preserve the previous
/// stored-property surface for observers, event streams, and tests.
///
/// | Outcome | ``isSuccess`` | ``output`` | ``errorMessage`` |
/// |---------|---------------|------------|------------------|
/// | ``Outcome/success(_:)`` | `true` | associated value | `nil` |
/// | ``Outcome/failure(message:)`` | `false` | `.null` | associated message |
public struct ToolResult: Sendable, Equatable, Codable {
    /// Closed success-or-failure payload for a tool invocation.
    public enum Outcome: Sendable, Equatable {
        /// The tool returned a value.
        case success(SendableValue)
        /// The tool failed. `message` matches historical ``errorMessage`` semantics.
        case failure(message: String)
    }

    /// The tool call that produced this result.
    public let callId: UUID

    /// Duration of the tool execution.
    public let duration: Duration

    /// Success value or failure message. Invalid combinations cannot be stored.
    public let outcome: Outcome

    /// Whether the tool execution was successful.
    public var isSuccess: Bool {
        switch outcome {
        case .success:
            true
        case .failure:
            false
        }
    }

    /// The output value from the tool.
    ///
    /// On failure this is always ``SendableValue/null``.
    public var output: SendableValue {
        switch outcome {
        case let .success(value):
            value
        case .failure:
            .null
        }
    }

    /// Error message if the tool failed.
    public var errorMessage: String? {
        switch outcome {
        case .success:
            nil
        case let .failure(message):
            message
        }
    }

    /// Creates a result from a closed outcome.
    ///
    /// Prefer ``success(callId:output:duration:)`` or ``failure(callId:error:duration:)``.
    public init(callId: UUID, duration: Duration, outcome: Outcome) {
        self.callId = callId
        self.duration = duration
        self.outcome = outcome
    }

    /// Creates a new tool result from independently specified success flags.
    ///
    /// Prefer ``success(callId:output:duration:)`` or ``failure(callId:error:duration:)``.
    /// A failure with a nil message is stored as `"Tool execution failed"`.
    /// Success ignores `errorMessage`; failure ignores `output`.
    @available(*, deprecated, message: "Use ToolResult.success(...) or .failure(callId:error:duration:)")
    public init(
        callId: UUID,
        isSuccess: Bool,
        output: SendableValue,
        duration: Duration,
        errorMessage: String? = nil
    ) {
        self.callId = callId
        self.duration = duration
        if isSuccess {
            outcome = .success(output)
        } else {
            outcome = .failure(message: errorMessage ?? "Tool execution failed")
        }
    }

    /// Creates a successful result.
    /// - Parameters:
    ///   - callId: The ID of the tool call.
    ///   - output: The output value.
    ///   - duration: Execution duration.
    /// - Returns: A successful ToolResult.
    public static func success(callId: UUID, output: SendableValue, duration: Duration) -> ToolResult {
        ToolResult(callId: callId, duration: duration, outcome: .success(output))
    }

    /// Creates a failed result.
    /// - Parameters:
    ///   - callId: The ID of the tool call.
    ///   - error: The error message.
    ///   - duration: Execution duration.
    /// - Returns: A failed ToolResult.
    public static func failure(callId: UUID, error: String, duration: Duration) -> ToolResult {
        ToolResult(callId: callId, duration: duration, outcome: .failure(message: error))
    }

    private enum CodingKeys: String, CodingKey {
        case callId
        case isSuccess
        case output
        case duration
        case errorMessage
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callId = try container.decode(UUID.self, forKey: .callId)
        duration = try container.decode(Duration.self, forKey: .duration)
        let isSuccess = try container.decode(Bool.self, forKey: .isSuccess)
        if isSuccess {
            let output = try container.decode(SendableValue.self, forKey: .output)
            outcome = .success(output)
        } else {
            let message = try container.decodeIfPresent(String.self, forKey: .errorMessage)
                ?? "Tool execution failed"
            outcome = .failure(message: message)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callId, forKey: .callId)
        try container.encode(isSuccess, forKey: .isSuccess)
        try container.encode(output, forKey: .output)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
    }
}

// MARK: - ToolCall + CustomStringConvertible

extension ToolCall: CustomStringConvertible {
    public var description: String {
        "ToolCall(\(toolName), args: \(arguments))"
    }
}

// MARK: - ToolResult + CustomStringConvertible

extension ToolResult: CustomStringConvertible {
    public var description: String {
        if isSuccess {
            "ToolResult(success: \(output), duration: \(duration))"
        } else {
            "ToolResult(failure: \(errorMessage ?? "unknown"), duration: \(duration))"
        }
    }
}

// MARK: - AgentEvent + Equatable

extension AgentEvent: Equatable {
    public static func == (lhs: AgentEvent, rhs: AgentEvent) -> Bool {
        switch (lhs, rhs) {
        case let (.lifecycle(l), .lifecycle(r)):
            l == r
        case let (.tool(l), .tool(r)):
            l == r
        case let (.output(l), .output(r)):
            l == r
        case let (.handoff(l), .handoff(r)):
            l == r
        case let (.observation(l), .observation(r)):
            l == r
        default:
            false
        }
    }
}

// MARK: - AgentEvent.Lifecycle + Equatable

extension AgentEvent.Lifecycle: Equatable {
    public static func == (lhs: AgentEvent.Lifecycle, rhs: AgentEvent.Lifecycle) -> Bool {
        switch (lhs, rhs) {
        case let (.started(l), .started(r)):
            l == r
        case let (.completed(l), .completed(r)):
            l == r
        case let (.failed(l), .failed(r)):
            l == r
        case (.cancelled, .cancelled):
            true
        case let (.guardrailFailed(l), .guardrailFailed(r)):
            l == r
        case let (.iterationStarted(l), .iterationStarted(r)):
            l == r
        case let (.iterationCompleted(l), .iterationCompleted(r)):
            l == r
        default:
            false
        }
    }
}

// MARK: - AgentEvent.Tool + Equatable

extension AgentEvent.Tool: Equatable {
    public static func == (lhs: AgentEvent.Tool, rhs: AgentEvent.Tool) -> Bool {
        switch (lhs, rhs) {
        case let (.started(l), .started(r)):
            l == r
        case let (.partial(l), .partial(r)):
            l == r
        case let (.completed(lCall, lResult), .completed(rCall, rResult)):
            lCall == rCall && lResult == rResult
        case let (.failed(lCall, lError), .failed(rCall, rError)):
            lCall == rCall && lError == rError
        default:
            false
        }
    }
}

// MARK: - AgentEvent.Output + Equatable

extension AgentEvent.Output: Equatable {
    public static func == (lhs: AgentEvent.Output, rhs: AgentEvent.Output) -> Bool {
        switch (lhs, rhs) {
        case let (.token(l), .token(r)):
            l == r
        case let (.chunk(l), .chunk(r)):
            l == r
        case let (.thinking(l), .thinking(r)):
            l == r
        case let (.thinkingPartial(l), .thinkingPartial(r)):
            l == r
        default:
            false
        }
    }
}

// MARK: - AgentEvent.Handoff + Equatable

extension AgentEvent.Handoff: Equatable {
    public static func == (lhs: AgentEvent.Handoff, rhs: AgentEvent.Handoff) -> Bool {
        switch (lhs, rhs) {
        case let (.requested(lFrom, lTo, lReason), .requested(rFrom, rTo, rReason)):
            lFrom == rFrom && lTo == rTo && lReason == rReason
        case let (.completed(lFrom, lTo), .completed(rFrom, rTo)):
            lFrom == rFrom && lTo == rTo
        case let (.started(lFrom, lTo, lInput), .started(rFrom, rTo, rInput)):
            lFrom == rFrom && lTo == rTo && lInput == rInput
        case let (.completedWithResult(lFrom, lTo, lResult), .completedWithResult(rFrom, rTo, rResult)):
            lFrom == rFrom && lTo == rTo && lResult == rResult
        case let (.skipped(lFrom, lTo, lReason), .skipped(rFrom, rTo, rReason)):
            lFrom == rFrom && lTo == rTo && lReason == rReason
        default:
            false
        }
    }
}

// MARK: - AgentEvent.Observation + Equatable

extension AgentEvent.Observation: Equatable {
    public static func == (lhs: AgentEvent.Observation, rhs: AgentEvent.Observation) -> Bool {
        switch (lhs, rhs) {
        case let (.decision(lD, lO), .decision(rD, rO)):
            lD == rD && lO == rO
        case let (.planUpdated(lP, lC), .planUpdated(rP, rC)):
            lP == rP && lC == rC
        case let (.guardrailStarted(lN, lT), .guardrailStarted(rN, rT)):
            lN == rN && lT == rT
        case let (.guardrailPassed(lN, lT), .guardrailPassed(rN, rT)):
            lN == rN && lT == rT
        case let (.guardrailTriggered(lN, lT, lM), .guardrailTriggered(rN, rT, rM)):
            lN == rN && lT == rT && lM == rM
        case let (.memoryAccessed(lO, lC), .memoryAccessed(rO, rC)):
            lO == rO && lC == rC
        case let (.llmStarted(lM, lP), .llmStarted(rM, rP)):
            lM == rM && lP == rP
        case let (.llmCompleted(lM, lP, lC, lD), .llmCompleted(rM, rP, rC, rD)):
            lM == rM && lP == rP && lC == rC && lD == rD
        case let (.inferenceRetry(lA, lM), .inferenceRetry(rA, rM)):
            lA == rA && lM == rM
        default:
            false
        }
    }
}

// MARK: - AgentEvent + Comparison Helper

extension AgentEvent {
    /// Compares this event to another for equality.
    ///
    /// This is a convenience method that enables comparison in contexts
    /// where the static `==` operator is inconvenient.
    ///
    /// - Parameter other: The event to compare with.
    /// - Returns: True if the events are equal.
    func isEqual(to other: AgentEvent) -> Bool {
        self == other
    }
}
