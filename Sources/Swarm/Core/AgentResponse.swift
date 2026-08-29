// AgentResponse.swift
// Swarm Framework
//
// Response type for agent execution with enhanced tracking capabilities.

import Foundation

// MARK: - ToolCallRecord

/// Record of a tool call execution with its result.
///
/// `ToolCallRecord` provides a complete picture of a single tool invocation,
/// including the tool name, arguments passed, result received, and timing information.
/// This is useful for debugging, logging, and analyzing agent behavior.
///
/// Example:
/// ```swift
/// let record = ToolCallRecord.success(
///     toolName: "calculator",
///     arguments: ["operation": "add", "a": 5, "b": 3],
///     result: .int(8),
///     duration: .seconds(0.05),
///     timestamp: Date()
/// )
///
/// print("Tool: \(record.toolName)")        // "calculator"
/// print("Result: \(record.result)")        // "8"
/// print("Duration: \(record.duration)")    // "0.05 seconds"
/// ```
///
/// `ToolCallRecord` is a closed outcome: execution either succeeded with a value
/// or failed with a message. Name, arguments, duration, and timestamp sit
/// outside the outcome. Compatibility accessors (``isSuccess``, ``result``,
/// ``errorMessage``) preserve the previous stored-property surface.
public struct ToolCallRecord: Sendable, Equatable, Codable {
    /// Closed success-or-failure payload for a recorded tool invocation.
    public enum Outcome: Sendable, Equatable {
        /// The tool returned a value.
        case success(SendableValue)
        /// The tool failed. `message` matches historical ``errorMessage`` semantics.
        case failure(message: String)
    }

    /// The name of the tool that was called.
    public let toolName: String

    /// The arguments passed to the tool.
    public let arguments: [String: SendableValue]

    /// How long the tool execution took.
    public let duration: Duration

    /// When the tool call was initiated.
    public let timestamp: Date

    /// Success value or failure message. Invalid combinations cannot be stored.
    public let outcome: Outcome

    /// The result returned by the tool.
    ///
    /// On failure this is always ``SendableValue/null``.
    public var result: SendableValue {
        switch outcome {
        case let .success(value):
            value
        case .failure:
            .null
        }
    }

    /// Whether the tool execution was successful.
    public var isSuccess: Bool {
        switch outcome {
        case .success:
            true
        case .failure:
            false
        }
    }

    /// Error message if the tool execution failed.
    public var errorMessage: String? {
        switch outcome {
        case .success:
            nil
        case let .failure(message):
            message
        }
    }

    /// Creates a record from a closed outcome.
    ///
    /// Prefer ``success(toolName:arguments:result:duration:timestamp:)`` or
    /// ``failure(toolName:arguments:error:duration:timestamp:)``.
    public init(
        toolName: String,
        arguments: [String: SendableValue] = [:],
        duration: Duration = .zero,
        timestamp: Date = TurnEnvironment.live.now(),
        outcome: Outcome
    ) {
        self.toolName = toolName
        self.arguments = arguments
        self.duration = duration
        self.timestamp = timestamp
        self.outcome = outcome
    }

    /// Creates a new tool call record from independently specified success flags.
    ///
    /// Prefer ``success(toolName:arguments:result:duration:timestamp:)`` or
    /// ``failure(toolName:arguments:error:duration:timestamp:)``.
    /// A failure with a nil message is stored as `"Tool execution failed"`.
    /// Success ignores `errorMessage`; failure ignores `result`.
    @available(*, deprecated, message: "Use ToolCallRecord.success(...) or .failure(...)")
    public init(
        toolName: String,
        arguments: [String: SendableValue] = [:],
        result: SendableValue = .null,
        duration: Duration = .zero,
        timestamp: Date = TurnEnvironment.live.now(),
        isSuccess: Bool = true,
        errorMessage: String? = nil
    ) {
        self.toolName = toolName
        self.arguments = arguments
        self.duration = duration
        self.timestamp = timestamp
        if isSuccess {
            outcome = .success(result)
        } else {
            outcome = .failure(message: errorMessage ?? "Tool execution failed")
        }
    }

    /// Creates a successful tool call record.
    public static func success(
        toolName: String,
        arguments: [String: SendableValue] = [:],
        result: SendableValue,
        duration: Duration = .zero,
        timestamp: Date = TurnEnvironment.live.now()
    ) -> ToolCallRecord {
        ToolCallRecord(
            toolName: toolName,
            arguments: arguments,
            duration: duration,
            timestamp: timestamp,
            outcome: .success(result)
        )
    }

    /// Creates a failed tool call record.
    public static func failure(
        toolName: String,
        arguments: [String: SendableValue] = [:],
        error: String,
        duration: Duration = .zero,
        timestamp: Date = TurnEnvironment.live.now()
    ) -> ToolCallRecord {
        ToolCallRecord(
            toolName: toolName,
            arguments: arguments,
            duration: duration,
            timestamp: timestamp,
            outcome: .failure(message: error)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case toolName
        case arguments
        case result
        case duration
        case timestamp
        case isSuccess
        case errorMessage
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolName = try container.decode(String.self, forKey: .toolName)
        arguments = try container.decode([String: SendableValue].self, forKey: .arguments)
        duration = try container.decode(Duration.self, forKey: .duration)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        let isSuccess = try container.decodeIfPresent(Bool.self, forKey: .isSuccess) ?? true
        if isSuccess {
            let result = try container.decodeIfPresent(SendableValue.self, forKey: .result) ?? .null
            outcome = .success(result)
        } else {
            let message = try container.decodeIfPresent(String.self, forKey: .errorMessage)
                ?? "Tool execution failed"
            outcome = .failure(message: message)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(toolName, forKey: .toolName)
        try container.encode(arguments, forKey: .arguments)
        try container.encode(result, forKey: .result)
        try container.encode(duration, forKey: .duration)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isSuccess, forKey: .isSuccess)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
    }
}

// MARK: CustomStringConvertible

extension ToolCallRecord: CustomStringConvertible {
    public var description: String {
        "ToolCallRecord(\(toolName), result: \(result), duration: \(duration))"
    }
}

// MARK: CustomDebugStringConvertible

extension ToolCallRecord: CustomDebugStringConvertible {
    public var debugDescription: String {
        """
        ToolCallRecord(
            toolName: "\(toolName)",
            arguments: \(arguments),
            result: \(result),
            duration: \(duration),
            timestamp: \(timestamp)
        )
        """
    }
}

// MARK: - AgentResponse

/// Response from an agent execution with tracking metadata.
///
/// `AgentResponse` extends the information in `AgentResult` with response
/// tracking capabilities including unique IDs and timestamps. It provides
/// a complete picture of an agent's execution including output, metadata,
/// tool calls made, and token usage.
///
/// Use `AgentResponse` when you need:
/// - Unique response identification for logging or tracking
/// - LegacyAgent attribution for multi-agent systems
/// - Detailed tool call records with results
/// - Easy conversion to `AgentResult` for backward compatibility
///
/// Example:
/// ```swift
/// let response = AgentResponse(
///     output: "The answer is 42",
///     agentName: "CalculatorAgent",
///     metadata: ["confidence": 0.95],
///     toolCalls: [
///         ToolCallRecord(
///             toolName: "calculator",
///             arguments: ["expression": "6 * 7"],
///             result: .int(42),
///             duration: .milliseconds(50)
///         )
///     ],
///     usage: TokenUsage(inputTokens: 100, outputTokens: 25)
/// )
///
/// print(response.responseId)        // "550e8400-e29b-41d4-a716-446655440000"
/// print(response.output)            // "The answer is 42"
/// print(response.agentName)         // "CalculatorAgent"
/// print(response.toolCalls.count)   // 1
///
/// // Convert to AgentResult for backward compatibility
/// let result = response.asResult
/// ```
public struct AgentResponse: Sendable {
    /// Unique identifier for this response.
    ///
    /// Automatically generated if not provided. Useful for tracking
    /// and correlating responses in logs or databases.
    public let responseId: String

    /// The agent's output text.
    public let output: String

    /// Name of the agent that produced this response.
    public let agentName: String

    /// When this response was created.
    public let timestamp: Date

    /// Additional metadata about the response.
    ///
    /// Can contain any `SendableValue` data for custom tracking,
    /// debugging information, or application-specific needs.
    public let metadata: [String: SendableValue]

    /// Tool calls made during execution with their results.
    ///
    /// Each `ToolCallRecord` contains the complete information about
    /// a tool invocation including arguments, result, and timing.
    public let toolCalls: [ToolCallRecord]

    /// Token usage if available from the underlying model.
    public let usage: TokenUsage?

    /// Number of agent iterations during execution.
    ///
    /// An iteration represents one complete reasoning cycle, which may include
    /// zero or more tool calls. This provides an accurate count rather than
    /// deriving it from tool call count.
    public let iterationCount: Int

    /// Lossy compatibility projection onto ``AgentResult``.
    ///
    /// Prefer ``AgentResult`` from ``Agent/run(_:session:observer:)`` when you
    /// need the canonical execution model. This conversion maps:
    /// - `output` -> `output`
    /// - `toolCalls` -> newly minted `[ToolCall]` and `[ToolResult]` pairs
    /// - `usage` -> `tokenUsage`
    /// - `metadata` -> `metadata`
    /// - `iterationCount` -> `iterationCount`
    ///
    /// It intentionally discards ``responseId``, ``agentName``, and the response
    /// ``timestamp``. ``AgentResult/duration`` is the sum of recorded tool-call
    /// durations, not wall-clock run time, and is `.zero` when no tools ran.
    /// Each access mints new tool-call IDs, so two conversions of the same
    /// response are not identity-equal.
    ///
    /// Example:
    /// ```swift
    /// let response = AgentResponse(output: "Hello", agentName: "Greeter")
    /// let result: AgentResult = response.asResult
    /// print(result.output)  // "Hello"
    /// ```
    public var asResult: AgentResult {
        // Convert ToolCallRecords to ToolCalls and ToolResults
        var convertedToolCalls: [ToolCall] = []
        var convertedToolResults: [ToolResult] = []

        for record in toolCalls {
            let callId = TurnEnvironment.live.newUUID()
            let toolCall = ToolCall(
                id: callId,
                toolName: record.toolName,
                arguments: record.arguments,
                timestamp: record.timestamp
            )
            convertedToolCalls.append(toolCall)

            let toolResult = ToolResult(
                callId: callId,
                duration: record.duration,
                outcome: ToolResult.Outcome(record.outcome)
            )
            convertedToolResults.append(toolResult)
        }

        // Calculate total duration from tool calls
        let totalDuration = toolCalls.reduce(Duration.zero) { $0 + $1.duration }

        return AgentResult(
            output: output,
            toolCalls: convertedToolCalls,
            toolResults: convertedToolResults,
            iterationCount: iterationCount,
            duration: totalDuration,
            tokenUsage: usage,
            metadata: metadata
        )
    }

    /// Creates a new agent response.
    ///
    /// - Parameters:
    ///   - responseId: Unique identifier for this response. Default: new UUID string
    ///   - output: The agent's output text.
    ///   - agentName: Name of the agent that produced this response.
    ///   - timestamp: When this response was created. Default: now
    ///   - metadata: Additional metadata about the response. Default: `[:]`
    ///   - toolCalls: Tool calls made during execution. Default: `[]`
    ///   - usage: Token usage if available. Default: `nil`
    ///   - iterationCount: Number of agent iterations. Default: `1`
    public init(
        responseId: String = TurnEnvironment.live.newID(),
        output: String,
        agentName: String,
        timestamp: Date = TurnEnvironment.live.now(),
        metadata: [String: SendableValue] = [:],
        toolCalls: [ToolCallRecord] = [],
        usage: TokenUsage? = nil,
        iterationCount: Int = 1
    ) {
        self.responseId = responseId
        self.output = output
        self.agentName = agentName
        self.timestamp = timestamp
        self.metadata = metadata
        self.toolCalls = toolCalls
        self.usage = usage
        self.iterationCount = iterationCount
    }
}

// MARK: Equatable

extension AgentResponse: Equatable {
    public static func == (lhs: AgentResponse, rhs: AgentResponse) -> Bool {
        lhs.responseId == rhs.responseId &&
            lhs.output == rhs.output &&
            lhs.agentName == rhs.agentName &&
            lhs.timestamp == rhs.timestamp &&
            lhs.metadata == rhs.metadata &&
            lhs.toolCalls == rhs.toolCalls &&
            lhs.usage == rhs.usage &&
            lhs.iterationCount == rhs.iterationCount
    }
}

// MARK: CustomStringConvertible

extension AgentResponse: CustomStringConvertible {
    public var description: String {
        """
        AgentResponse(
            id: "\(responseId.prefix(8))...",
            agent: "\(agentName)",
            output: "\(output.prefix(100))\(output.count > 100 ? "..." : "")",
            toolCalls: \(toolCalls.count),
            usage: \(usage?.description ?? "nil")
        )
        """
    }
}

// MARK: CustomDebugStringConvertible

extension AgentResponse: CustomDebugStringConvertible {
    public var debugDescription: String {
        """
        AgentResponse(
            responseId: "\(responseId)",
            output: "\(output)",
            agentName: "\(agentName)",
            timestamp: \(timestamp),
            metadata: \(metadata),
            toolCalls: \(toolCalls),
            usage: \(String(describing: usage))
        )
        """
    }
}

extension ToolCallRecord.Outcome {
    /// Maps a ``ToolResult/Outcome`` onto the record's nested outcome.
    public init(_ outcome: ToolResult.Outcome) {
        switch outcome {
        case let .success(value):
            self = .success(value)
        case let .failure(message):
            self = .failure(message: message)
        }
    }
}

extension ToolResult.Outcome {
    /// Maps a ``ToolCallRecord/Outcome`` onto the result's nested outcome.
    public init(_ outcome: ToolCallRecord.Outcome) {
        switch outcome {
        case let .success(value):
            self = .success(value)
        case let .failure(message):
            self = .failure(message: message)
        }
    }
}
