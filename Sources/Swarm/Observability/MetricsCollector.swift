// MetricsCollector.swift
// Swarm Framework
//
// Metrics collection system for aggregating agent execution data.
// Provides counters, gauges, histograms, and timers for comprehensive observability.

import Foundation

// MARK: - MetricsSnapshot

/// A point-in-time snapshot of collected metrics.
///
/// `MetricsSnapshot` provides a read-only view of all collected metrics,
/// including computed statistics like success rates and averages.
///
/// ## Features
///
/// - All metrics are immutable (read-only)
/// - Computed properties for derived metrics
/// - `Sendable` for safe concurrent access
/// - `Codable` for serialization to JSON/other formats
///
/// ## Example
///
/// ```swift
/// let snapshot = await collector.snapshot()
/// print("Success rate: \(snapshot.successRate)%")
/// print("Average duration: \(snapshot.averageExecutionDuration)ms")
/// ```
public struct MetricsSnapshot: Sendable, Codable, Equatable {
    // MARK: - Execution Counters

    /// Total number of agent executions started.
    public let totalExecutions: Int

    /// Number of successful agent executions.
    public let successfulExecutions: Int

    /// Number of failed agent executions.
    public let failedExecutions: Int

    /// Number of cancelled agent executions.
    public let cancelledExecutions: Int

    // MARK: - Duration Tracking

    /// Array of all execution durations (in seconds).
    public let executionDurations: [TimeInterval]

    // MARK: - Tool Metrics

    /// Tool call counts by tool name.
    public let toolCalls: [String: Int]

    /// Tool error counts by tool name.
    public let toolErrors: [String: Int]

    /// Tool execution durations by tool name (in seconds).
    public let toolDurations: [String: [TimeInterval]]

    /// Accumulated provider-reported input tokens. Zero when providers omit usage.
    public let inputTokens: Int

    /// Accumulated provider-reported output tokens. Zero when providers omit usage.
    public let outputTokens: Int

    // MARK: - Timestamp

    /// When this snapshot was taken.
    public let timestamp: Date

    // MARK: - Computed Statistics

    /// Success rate as a percentage (0-100).
    public var successRate: Double {
        guard totalExecutions > 0 else { return 0.0 }
        return (Double(successfulExecutions) / Double(totalExecutions)) * 100.0
    }

    /// Error rate as a percentage (0-100).
    public var errorRate: Double {
        guard totalExecutions > 0 else { return 0.0 }
        return (Double(failedExecutions) / Double(totalExecutions)) * 100.0
    }

    /// Cancellation rate as a percentage (0-100).
    public var cancellationRate: Double {
        guard totalExecutions > 0 else { return 0.0 }
        return (Double(cancelledExecutions) / Double(totalExecutions)) * 100.0
    }

    /// Total number of tool calls across all tools.
    public var totalToolCalls: Int {
        toolCalls.values.reduce(0, +)
    }

    /// Total number of tool errors across all tools.
    public var totalToolErrors: Int {
        toolErrors.values.reduce(0, +)
    }

    /// Total provider-reported tokens (input + output).
    public var totalTokens: Int {
        inputTokens + outputTokens
    }

    /// Average execution duration in seconds.
    public var averageExecutionDuration: TimeInterval {
        guard !executionDurations.isEmpty else { return 0.0 }
        return executionDurations.reduce(0.0, +) / Double(executionDurations.count)
    }

    /// Minimum execution duration in seconds.
    public var minimumExecutionDuration: TimeInterval? {
        executionDurations.min()
    }

    /// Maximum execution duration in seconds.
    public var maximumExecutionDuration: TimeInterval? {
        executionDurations.max()
    }

    /// Median execution duration in seconds.
    public var medianExecutionDuration: TimeInterval? {
        guard !executionDurations.isEmpty else { return nil }
        let sorted = executionDurations.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        } else {
            return sorted[count / 2]
        }
    }

    /// 95th percentile execution duration in seconds.
    public var p95ExecutionDuration: TimeInterval? {
        percentile(0.95)
    }

    /// 99th percentile execution duration in seconds.
    public var p99ExecutionDuration: TimeInterval? {
        percentile(0.99)
    }

    /// Computes a percentile from execution durations.
    private func percentile(_ p: Double) -> TimeInterval? {
        guard !executionDurations.isEmpty else { return nil }
        let sorted = executionDurations.sorted()
        let index = Int(Double(sorted.count) * p)
        return sorted[min(index, sorted.count - 1)]
    }

    // MARK: - Initialization

    /// Creates a new metrics snapshot.
    public init(
        totalExecutions: Int,
        successfulExecutions: Int,
        failedExecutions: Int,
        cancelledExecutions: Int,
        executionDurations: [TimeInterval],
        toolCalls: [String: Int],
        toolErrors: [String: Int],
        toolDurations: [String: [TimeInterval]],
        timestamp: Date = Date(),
        inputTokens: Int = 0,
        outputTokens: Int = 0
    ) {
        self.totalExecutions = totalExecutions
        self.successfulExecutions = successfulExecutions
        self.failedExecutions = failedExecutions
        self.cancelledExecutions = cancelledExecutions
        self.executionDurations = executionDurations
        self.toolCalls = toolCalls
        self.toolErrors = toolErrors
        self.toolDurations = toolDurations
        self.timestamp = timestamp
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    private enum CodingKeys: String, CodingKey {
        case totalExecutions
        case successfulExecutions
        case failedExecutions
        case cancelledExecutions
        case executionDurations
        case toolCalls
        case toolErrors
        case toolDurations
        case inputTokens
        case outputTokens
        case timestamp
    }

    /// Decodes a snapshot, defaulting missing token fields to zero so JSON written
    /// before token metrics existed remains readable.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalExecutions = try container.decode(Int.self, forKey: .totalExecutions)
        successfulExecutions = try container.decode(Int.self, forKey: .successfulExecutions)
        failedExecutions = try container.decode(Int.self, forKey: .failedExecutions)
        cancelledExecutions = try container.decode(Int.self, forKey: .cancelledExecutions)
        executionDurations = try container.decode([TimeInterval].self, forKey: .executionDurations)
        toolCalls = try container.decode([String: Int].self, forKey: .toolCalls)
        toolErrors = try container.decode([String: Int].self, forKey: .toolErrors)
        toolDurations = try container.decode([String: [TimeInterval]].self, forKey: .toolDurations)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(totalExecutions, forKey: .totalExecutions)
        try container.encode(successfulExecutions, forKey: .successfulExecutions)
        try container.encode(failedExecutions, forKey: .failedExecutions)
        try container.encode(cancelledExecutions, forKey: .cancelledExecutions)
        try container.encode(executionDurations, forKey: .executionDurations)
        try container.encode(toolCalls, forKey: .toolCalls)
        try container.encode(toolErrors, forKey: .toolErrors)
        try container.encode(toolDurations, forKey: .toolDurations)
        try container.encode(inputTokens, forKey: .inputTokens)
        try container.encode(outputTokens, forKey: .outputTokens)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

// MARK: - MetricsCollector

/// Actor-based metrics collector for aggregating agent execution data.
///
/// `MetricsCollector` implements the `AgentTracer` protocol to automatically
/// collect metrics from trace events. It tracks execution counts, durations,
/// tool usage, error rates, and provider-reported token usage when present.
///
/// ## Features
///
/// - Thread-safe metrics collection using actor isolation
/// - Automatic metric updates from trace events
/// - Counters, gauges, histograms, and timers
/// - Point-in-time snapshots for reporting
/// - Reset capability for bounded memory usage
///
/// ## Example
///
/// ```swift
/// let collector = MetricsCollector()
///
/// // Automatically collect metrics from events
/// await collector.trace(.agentStart(traceId: id, agentName: "MyAgent"))
/// await collector.trace(.agentComplete(traceId: id, spanId: id, agentName: "MyAgent", duration: 1.5))
///
/// // Get current metrics
/// let snapshot = await collector.snapshot()
/// print("Total executions: \(snapshot.totalExecutions)")
/// print("Success rate: \(snapshot.successRate)%")
///
/// // Reset metrics
/// await collector.reset()
/// ```
public actor MetricsCollector: Tracer {
    // MARK: Public

    // MARK: - Initialization

    /// Maximum number of duration samples to retain per metric.
    public let maxMetricsHistory: Int

    /// Creates a new metrics collector.
    ///
    /// - Parameter maxMetricsHistory: Maximum number of duration samples to retain.
    ///   When exceeded, oldest samples are discarded. Default: 10,000.
    public init(maxMetricsHistory: Int = 10000) {
        self.maxMetricsHistory = maxMetricsHistory
        executionDurations = CircularBuffer<TimeInterval>(capacity: maxMetricsHistory)
    }

    // MARK: - AgentTracer Protocol

    /// Traces an event and updates metrics based on the event kind.
    ///
    /// This method automatically extracts relevant metrics from trace events:
    /// - `agentStart`: Increments total executions
    /// - `agentComplete`: Increments successful executions, records duration,
    ///   and accumulates `input_tokens` / `output_tokens` from that span only
    /// - `agentError`: Increments failed executions
    /// - `agentCancelled`: Increments cancelled executions
    /// - `toolCall`: Increments tool call counter
    /// - `toolResult`: Records tool duration
    /// - `toolError`: Increments tool error counter
    ///
    /// - Parameter event: The trace event to process.
    public func trace(_ event: TraceEvent) async {
        switch event.kind {
        case .agentStart:
            totalExecutions += 1
            spanStartTimes[event.spanId] = event.timestamp

        case .agentComplete:
            successfulExecutions += 1
            if let duration = event.duration {
                executionDurations.append(duration)
            } else if let startTime = spanStartTimes[event.spanId] {
                let duration = event.timestamp.timeIntervalSince(startTime)
                executionDurations.append(duration)
            }
            if let input = event.metadata[.inputTokens] {
                inputTokens += input
            }
            if let output = event.metadata[.outputTokens] {
                outputTokens += output
            }
            spanStartTimes.removeValue(forKey: event.spanId)

        case .agentError:
            failedExecutions += 1
            spanStartTimes.removeValue(forKey: event.spanId)

        case .agentCancelled:
            cancelledExecutions += 1
            spanStartTimes.removeValue(forKey: event.spanId)

        case .toolCall:
            if let toolName = event.toolName {
                toolCalls[toolName, default: 0] += 1
                spanStartTimes[event.spanId] = event.timestamp
            }

        case .toolResult:
            if let toolName = event.toolName {
                let duration: TimeInterval? = if let eventDuration = event.duration {
                    eventDuration
                } else if let startTime = spanStartTimes[event.spanId] {
                    event.timestamp.timeIntervalSince(startTime)
                } else {
                    nil
                }

                if let duration {
                    if toolDurations[toolName] == nil {
                        toolDurations[toolName] = CircularBuffer<TimeInterval>(capacity: maxMetricsHistory)
                    }
                    toolDurations[toolName]?.append(duration)
                }
                spanStartTimes.removeValue(forKey: event.spanId)
            }

        case .toolError:
            if let toolName = event.toolName {
                toolErrors[toolName, default: 0] += 1
                spanStartTimes.removeValue(forKey: event.spanId)
            }

        case .checkpoint,
             .custom,
             .decision,
             .memoryRead,
             .memoryWrite,
             .metric,
             .plan,
             .thought:
            // These events don't directly affect core metrics
            break
        }
    }

    /// Flushes any buffered events.
    ///
    /// Default implementation does nothing. Override if needed.
    public func flush() async {
        // No-op: MetricsCollector doesn't buffer events
    }

    // MARK: - Snapshot

    /// Returns a point-in-time snapshot of all metrics.
    ///
    /// The snapshot is immutable and safe to pass across actor boundaries.
    ///
    /// - Returns: A metrics snapshot containing all current metrics.
    public func snapshot() -> MetricsSnapshot {
        // Convert CircularBuffer to arrays for the snapshot
        let toolDurationArrays = toolDurations.mapValues { $0.elements }

        return MetricsSnapshot(
            totalExecutions: totalExecutions,
            successfulExecutions: successfulExecutions,
            failedExecutions: failedExecutions,
            cancelledExecutions: cancelledExecutions,
            executionDurations: executionDurations.elements,
            toolCalls: toolCalls,
            toolErrors: toolErrors,
            toolDurations: toolDurationArrays,
            timestamp: Date(),
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }

    // MARK: - Reset

    /// Resets all metrics to their initial state.
    ///
    /// This is useful for:
    /// - Periodic metric resets to bound memory usage
    /// - Starting fresh metric collection for a new time window
    /// - Testing scenarios
    public func reset() {
        totalExecutions = 0
        successfulExecutions = 0
        failedExecutions = 0
        cancelledExecutions = 0
        executionDurations = CircularBuffer<TimeInterval>(capacity: maxMetricsHistory)
        toolCalls.removeAll()
        toolErrors.removeAll()
        toolDurations.removeAll()
        spanStartTimes.removeAll()
        inputTokens = 0
        outputTokens = 0
    }

    // MARK: - Individual Metric Accessors

    /// Returns the current total execution count.
    public func getTotalExecutions() -> Int {
        totalExecutions
    }

    /// Returns the current successful execution count.
    public func getSuccessfulExecutions() -> Int {
        successfulExecutions
    }

    /// Returns the current failed execution count.
    public func getFailedExecutions() -> Int {
        failedExecutions
    }

    /// Returns the current cancelled execution count.
    public func getCancelledExecutions() -> Int {
        cancelledExecutions
    }

    /// Returns tool call counts.
    public func getToolCalls() -> [String: Int] {
        toolCalls
    }

    /// Returns tool error counts.
    public func getToolErrors() -> [String: Int] {
        toolErrors
    }

    /// Returns tool durations.
    public func getToolDurations() -> [String: [TimeInterval]] {
        toolDurations.mapValues { $0.elements }
    }

    // MARK: Private

    // MARK: - Execution Counters

    /// Total number of agent executions started.
    private var totalExecutions: Int = 0

    /// Number of successful agent executions.
    private var successfulExecutions: Int = 0

    /// Number of failed agent executions.
    private var failedExecutions: Int = 0

    /// Number of cancelled agent executions.
    private var cancelledExecutions: Int = 0

    /// Accumulated provider-reported input tokens.
    private var inputTokens: Int = 0

    /// Accumulated provider-reported output tokens.
    private var outputTokens: Int = 0

    // MARK: - Duration Tracking

    /// Circular buffer of execution durations (in seconds).
    /// Uses CircularBuffer to prevent unbounded memory growth in long-running processes.
    private var executionDurations: CircularBuffer<TimeInterval>

    // MARK: - Tool Metrics

    /// Tool call counts by tool name.
    private var toolCalls: [String: Int] = [:]

    /// Tool error counts by tool name.
    private var toolErrors: [String: Int] = [:]

    /// Tool execution durations by tool name (in seconds).
    /// Uses CircularBuffer per tool to prevent unbounded memory growth.
    private var toolDurations: [String: CircularBuffer<TimeInterval>] = [:]

    // MARK: - Span Tracking

    /// Track start times for spans to calculate durations.
    private var spanStartTimes: [UUID: Date] = [:]
}

// MARK: - MetricsReporter

/// Protocol for exporting metrics to external systems.
///
/// `MetricsReporter` defines the contract for formatting and exporting
/// metrics snapshots to various destinations (files, APIs, telemetry systems).
///
/// ## Example Implementation
///
/// ```swift
/// struct LogMetricsReporter: MetricsReporter {
///     func report(_ snapshot: MetricsSnapshot) async throws {
///         print("=== Metrics Report ===")
///         print("Total Executions: \(snapshot.totalExecutions)")
///         print("Success Rate: \(snapshot.successRate)%")
///     }
/// }
/// ```
protocol MetricsReporter: Sendable {
    /// Reports a metrics snapshot.
    ///
    /// - Parameter snapshot: The metrics snapshot to report.
    /// - Throws: Any error encountered during reporting.
    func report(_ snapshot: MetricsSnapshot) async throws
}

// MARK: - JSONMetricsReporter

/// A metrics reporter that exports metrics as JSON.
///
/// `JSONMetricsReporter` serializes metrics snapshots to JSON format,
/// optionally writing to a file or returning the data for custom handling.
///
/// ## Example
///
/// ```swift
/// let reporter = JSONMetricsReporter(
///     outputPath: "/tmp/metrics.json",
///     prettyPrint: true
/// )
///
/// await reporter.report(snapshot)
/// ```
package struct JSONMetricsReporter: MetricsReporter {
    /// Optional file path to write JSON output.
    package let outputPath: String?

    /// Whether to format JSON with indentation.
    package let prettyPrint: Bool

    /// Creates a JSON metrics reporter.
    ///
    /// - Parameters:
    ///   - outputPath: Optional file path to write JSON. If nil, returns data.
    ///   - prettyPrint: Whether to format JSON with indentation. Default: `true`.
    package init(outputPath: String? = nil, prettyPrint: Bool = true) {
        self.outputPath = outputPath
        self.prettyPrint = prettyPrint
    }

    /// Reports metrics by serializing to JSON.
    ///
    /// - Parameter snapshot: The metrics snapshot to report.
    /// - Throws: Encoding errors or file write errors.
    package func report(_ snapshot: MetricsSnapshot) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        if prettyPrint {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = .sortedKeys
        }

        let data = try encoder.encode(snapshot)

        if let outputPath {
            // Validate path: block traversal attempts
            let resolved = (outputPath as NSString).standardizingPath
            guard !resolved.contains("..") else {
                throw AgentError.invalidInput(reason: "Path traversal not allowed in metrics output path")
            }
            let url = URL(fileURLWithPath: resolved)
            try data.write(to: url, options: .atomic)
        } else {
            // Print to console
            if let jsonString = String(data: data, encoding: .utf8) {
                Log.metrics.info("\(jsonString)")
            }
        }
    }

    /// Returns JSON data without writing to file.
    ///
    /// - Parameter snapshot: The metrics snapshot to serialize.
    /// - Returns: JSON data.
    /// - Throws: Encoding errors.
    package func jsonData(from snapshot: MetricsSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        if prettyPrint {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = .sortedKeys
        }

        return try encoder.encode(snapshot)
    }

    /// Returns JSON string without writing to file.
    ///
    /// - Parameter snapshot: The metrics snapshot to serialize.
    /// - Returns: JSON string.
    /// - Throws: Encoding errors.
    package func jsonString(from snapshot: MetricsSnapshot) throws -> String {
        let data = try jsonData(from: snapshot)
        guard let string = String(data: data, encoding: .utf8) else {
            throw MetricsReporterError.encodingFailed
        }
        return string
    }
}

// MARK: - MetricsReporterError

/// Errors that can occur during metrics reporting.
public enum MetricsReporterError: Error, Sendable {
    case encodingFailed
    case writeFailed(String)
    case invalidPath(String)
}

// MARK: - MetricsSnapshot + CustomStringConvertible

extension MetricsSnapshot: CustomStringConvertible {
    public var description: String {
        """
        MetricsSnapshot(
          totalExecutions: \(totalExecutions),
          successfulExecutions: \(successfulExecutions),
          failedExecutions: \(failedExecutions),
          cancelledExecutions: \(cancelledExecutions),
          successRate: \(String(format: "%.2f", successRate))%,
          errorRate: \(String(format: "%.2f", errorRate))%,
          averageExecutionDuration: \(String(format: "%.3f", averageExecutionDuration))s,
          totalToolCalls: \(totalToolCalls),
          totalToolErrors: \(totalToolErrors),
          inputTokens: \(inputTokens),
          outputTokens: \(outputTokens)
        )
        """
    }
}
