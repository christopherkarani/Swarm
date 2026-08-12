// AgentResult.swift
// Swarm Framework
//
// Result type for agent execution.

import Foundation

// MARK: - AgentResult

/// The result of an agent execution.
///
/// AgentResult captures all information about a completed agent run,
/// including the output, tool calls made, timing, and optional metadata.
///
/// Example:
/// ```swift
/// let result = try await agent.run("Calculate 2+2")
/// print(result.output)              // "4"
/// print(result.iterationCount)      // 2
/// print(result.toolCalls.count)     // 1
/// print(result.duration)            // 1.234 seconds
/// ```
public struct AgentResult: Sendable, Equatable {
    /// The final output text from the agent.
    public let output: String

    /// All tool calls made during execution.
    public let toolCalls: [ToolCall]

    /// Results of all tool executions.
    public let toolResults: [ToolResult]

    /// The number of iterations performed.
    public let iterationCount: Int

    /// Total duration of the execution.
    public let duration: Duration

    /// Token usage statistics, if available.
    public let tokenUsage: TokenUsage?

    /// Metadata about the execution.
    public let metadata: [String: SendableValue]

    /// Creates a new agent result.
    /// - Parameters:
    ///   - output: The final output text.
    ///   - toolCalls: Tool calls made. Default: []
    ///   - toolResults: Tool execution results. Default: []
    ///   - iterationCount: Number of iterations. Default: 1
    ///   - duration: Execution duration. Default: .zero
    ///   - tokenUsage: Token usage stats. Default: nil
    ///   - metadata: Additional metadata. Default: [:]
    public init(
        output: String,
        toolCalls: [ToolCall] = [],
        toolResults: [ToolResult] = [],
        iterationCount: Int = 1,
        duration: Duration = .zero,
        tokenUsage: TokenUsage? = nil,
        metadata: [String: SendableValue] = [:]
    ) {
        self.output = output
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.iterationCount = iterationCount
        self.duration = duration
        self.tokenUsage = tokenUsage
        self.metadata = metadata
    }
}

// MARK: - AgentResult.Builder

extension AgentResult {
    /// Builder for constructing AgentResult incrementally during execution.
    ///
    /// Use this builder to accumulate results as an agent runs, then
    /// call `build()` to create the final result.
    package final class Builder: @unchecked Sendable {
        // MARK: Internal

        /// Creates a new result builder.
        package init() {}

        /// Sets the output text.
        @discardableResult
        package func setOutput(_ value: String) -> Builder {
            lock.lock()
            defer { lock.unlock() }
            output = value
            return self
        }

        /// Appends to the output text.
        @discardableResult
        package func appendOutput(_ value: String) -> Builder {
            lock.lock()
            defer { lock.unlock() }
            output += value
            return self
        }

        /// Adds a tool call.
        @discardableResult
        package func addToolCall(_ call: ToolCall) -> Builder {
            lock.lock()
            defer { lock.unlock() }
            toolCalls.append(call)
            return self
        }

        /// Adds a tool result.
        @discardableResult
        package func addToolResult(_ result: ToolResult) -> Builder {
            lock.lock()
            defer { lock.unlock() }
            toolResults.append(result)
            return self
        }

        /// Increments the iteration count.
        @discardableResult
        package func incrementIteration() -> Builder {
            lock.lock()
            defer { lock.unlock() }
            iterationCount += 1
            return self
        }

        /// Marks the start time.
        @discardableResult
        package func start() -> Builder {
            lock.lock()
            defer { lock.unlock() }
            startTime = ContinuousClock.now
            return self
        }

        /// Sets this agent's own token usage, replacing any previously recorded value.
        @discardableResult
        package func setTokenUsage(_ usage: TokenUsage) -> Builder {
            lock.lock()
            defer { lock.unlock() }
            tokenUsage = usage
            return self
        }

        /// Adds provider-reported usage from this agent's own LLM calls.
        ///
        /// Nested handoff usage must go through ``addNestedTokenUsage(_:)`` so
        /// ``AgentResult/tokenUsage`` can still report the combined cost while
        /// traces attribute tokens to the agent that actually consumed them.
        @discardableResult
        package func addTokenUsage(_ usage: TokenUsage) -> Builder {
            lock.lock()
            defer { lock.unlock() }
            tokenUsage = tokenUsage.map { $0.merging(usage) } ?? usage
            return self
        }

        /// Adds usage from a nested handoff target into the combined result total.
        ///
        /// This does not change ``ownTokenUsage()`` — the child agent already
        /// traced its own span.
        @discardableResult
        package func addNestedTokenUsage(_ usage: TokenUsage) -> Builder {
            lock.lock()
            defer { lock.unlock() }
            nestedTokenUsage = nestedTokenUsage.map { $0.merging(usage) } ?? usage
            return self
        }

        /// Token usage from this agent's own LLM calls, excluding nested handoffs.
        package func ownTokenUsage() -> TokenUsage? {
            lock.lock()
            defer { lock.unlock() }
            return tokenUsage
        }

        /// Sets a metadata value.
        @discardableResult
        package func setMetadata(_ key: String, _ value: SendableValue) -> Builder {
            lock.lock()
            defer { lock.unlock() }
            metadata[key] = value
            return self
        }

        /// Gets the current output.
        package func getOutput() -> String {
            lock.lock()
            defer { lock.unlock() }
            return output
        }

        /// Gets the current iteration count.
        package func getIterationCount() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return iterationCount
        }

        /// Builds the final AgentResult.
        package func build() -> AgentResult {
            lock.lock()
            defer { lock.unlock() }

            let duration: Duration = if let start = startTime {
                ContinuousClock.now - start
            } else {
                .zero
            }

            let combinedUsage: TokenUsage? = switch (tokenUsage, nestedTokenUsage) {
            case let (own?, nested?): own.merging(nested)
            case let (own?, nil): own
            case let (nil, nested?): nested
            case (nil, nil): nil
            }

            return AgentResult(
                output: output,
                toolCalls: toolCalls,
                toolResults: toolResults,
                iterationCount: iterationCount,
                duration: duration,
                tokenUsage: combinedUsage,
                metadata: metadata
            )
        }

        // MARK: Private

        private var output: String = ""
        private var toolCalls: [ToolCall] = []
        private var toolResults: [ToolResult] = []
        private var iterationCount: Int = 0
        private var startTime: ContinuousClock.Instant?
        private var tokenUsage: TokenUsage?
        private var nestedTokenUsage: TokenUsage?
        private var metadata: [String: SendableValue] = [:]
        private let lock = NSLock()
    }
}

// MARK: - AgentResult + CustomStringConvertible

extension AgentResult: CustomStringConvertible {
    public var description: String {
        """
        AgentResult(
            output: "\(output.prefix(100))\(output.count > 100 ? "..." : "")",
            toolCalls: \(toolCalls.count),
            iterations: \(iterationCount),
            duration: \(duration)
        )
        """
    }
}

// MARK: - AgentResult + Runtime Metadata

public extension AgentResult {
    /// The runtime engine that produced this result, if recorded.
    /// Returns `"graph"` when the graph runtime was used, `"native"` otherwise.
    var runtimeEngine: String? {
        guard case let .string(value) = metadata["runtime.engine"] else { return nil }
        return value
    }
}
