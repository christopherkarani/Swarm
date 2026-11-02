// TraceEvent.swift
// Swarm Framework
//
// Detailed trace events for agent execution monitoring.
// Provides comprehensive event tracking with metadata, spans, and source location.

import Foundation
import Synchronization

// MARK: - EventLevel

/// The severity level of a trace event.
public enum EventLevel: Int, Sendable, Codable, Comparable, CaseIterable {
    // MARK: Public

    public static func < (lhs: EventLevel, rhs: EventLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    case trace = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case critical = 5
}

// MARK: - EventKind

/// The kind of event being traced.
public enum EventKind: String, Sendable, Codable, CaseIterable {
    /// LegacyAgent execution started
    case agentStart
    /// LegacyAgent execution completed successfully
    case agentComplete
    /// LegacyAgent execution encountered an error
    case agentError
    /// LegacyAgent execution was cancelled
    case agentCancelled

    /// Tool invocation started
    case toolCall
    /// Tool returned a result
    case toolResult
    /// Tool execution failed
    case toolError

    /// LegacyAgent reasoning/thinking step
    case thought
    /// LegacyAgent made a decision
    case decision
    /// LegacyAgent created or updated a plan
    case plan

    /// Memory read operation
    case memoryRead
    /// Memory write operation
    case memoryWrite

    /// Execution checkpoint
    case checkpoint
    /// Performance or custom metric
    case metric
    /// Custom event type
    case custom
}

// MARK: - SourceLocation

/// Source code location information for debugging.
public struct SourceLocation: Sendable, Codable, Equatable, Hashable {
    public let file: String
    public let function: String
    public let line: Int

    /// Returns just the filename without the full path.
    public var filename: String {
        (file as NSString).lastPathComponent
    }

    /// Returns a formatted string representation.
    public var formatted: String {
        "\(filename):\(line) - \(function)"
    }

    /// Creates a source location with the provided information.
    public init(
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        self.file = file
        self.function = function
        self.line = line
    }
}

// MARK: - ErrorInfo

/// Detailed error information for trace events.
public struct ErrorInfo: Sendable, Codable, Equatable, Hashable {
    public let type: String
    public let message: String
    public let stackTrace: [String]?
    public let underlyingError: String?

    /// Creates error information from an error instance.
    public init(
        type: String,
        message: String,
        stackTrace: [String]? = nil,
        underlyingError: String? = nil
    ) {
        self.type = type
        self.message = message
        self.stackTrace = stackTrace
        self.underlyingError = underlyingError
    }

    /// Creates error information from a Swift Error.
    public init(from error: Error) {
        type = String(reflecting: Swift.type(of: error))
        message = error.localizedDescription
        stackTrace = nil

        // Attempt to extract underlying error
        if let underlyingError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error {
            self.underlyingError = String(describing: underlyingError)
        } else {
            underlyingError = nil
        }
    }
}

// MARK: - TraceEvent

/// A detailed trace event for agent execution monitoring.
public struct TraceEvent: Sendable, Codable, Identifiable, Equatable, Hashable {
    /// Unique identifier for this event
    public let id: UUID

    /// Trace ID - groups related events across an entire operation
    public let traceId: UUID

    /// Span ID - identifies this specific event/operation
    public let spanId: UUID

    /// Parent span ID - links to the parent operation
    public let parentSpanId: UUID?

    /// Timestamp when the event occurred
    public let timestamp: Date

    /// Duration of the operation (nil for instantaneous events)
    public let duration: TimeInterval?

    /// The kind of event
    public let kind: EventKind

    /// The severity level
    public let level: EventLevel

    /// Human-readable message
    public let message: String

    /// Additional metadata
    public let metadata: [String: SendableValue]

    /// Name of the agent that generated this event
    public let agentName: String?

    /// Name of the tool being executed (for tool events)
    public let toolName: String?

    /// Error information (for error events)
    public let error: ErrorInfo?

    /// Source code location
    public let source: SourceLocation?

    /// Creates a new trace event.
    public init(
        id: UUID = UUID(),
        traceId: UUID,
        spanId: UUID = UUID(),
        parentSpanId: UUID? = nil,
        timestamp: Date = Date(),
        duration: TimeInterval? = nil,
        kind: EventKind,
        level: EventLevel = .info,
        message: String,
        metadata: [String: SendableValue] = [:],
        agentName: String? = nil,
        toolName: String? = nil,
        error: ErrorInfo? = nil,
        source: SourceLocation? = nil
    ) {
        self.id = id
        self.traceId = traceId
        self.spanId = spanId
        self.parentSpanId = parentSpanId
        self.timestamp = timestamp
        self.duration = duration
        self.kind = kind
        self.level = level
        self.message = message
        self.metadata = metadata
        self.agentName = agentName
        self.toolName = toolName
        self.error = error
        self.source = source
    }
}

// MARK: TraceEvent.Builder

public extension TraceEvent {
    /// Fluent builder for creating trace events.
    ///
    /// All builder state lives behind a `Mutex`, so a builder can be shared
    /// across concurrency domains: each setter and ``build()`` is atomic.
    final class Builder: Sendable {
        // MARK: Public

        /// Creates a new builder with required parameters.
        public init(
            traceId: UUID,
            kind: EventKind,
            message: String,
            id: UUID = UUID(),
            spanId: UUID = UUID(),
            timestamp: Date = Date(),
            level: EventLevel = .info
        ) {
            state = Mutex(State(
                id: id,
                traceId: traceId,
                spanId: spanId,
                timestamp: timestamp,
                kind: kind,
                level: level,
                message: message
            ))
        }

        /// Sets the parent span ID.
        @discardableResult
        public func parentSpan(_ id: UUID) -> Builder {
            state.withLock { $0.parentSpanId = id }
            return self
        }

        /// Sets the timestamp.
        @discardableResult
        public func timestamp(_ date: Date) -> Builder {
            state.withLock { $0.timestamp = date }
            return self
        }

        /// Sets the duration.
        @discardableResult
        public func duration(_ duration: TimeInterval) -> Builder {
            state.withLock { $0.duration = duration }
            return self
        }

        /// Sets the event level.
        @discardableResult
        public func level(_ level: EventLevel) -> Builder {
            state.withLock { $0.level = level }
            return self
        }

        /// Sets the message.
        @discardableResult
        public func message(_ message: String) -> Builder {
            state.withLock { $0.message = message }
            return self
        }

        /// Adds a metadata key-value pair.
        @discardableResult
        public func metadata(key: String, value: SendableValue) -> Builder {
            state.withLock { $0.metadata[key] = value }
            return self
        }

        /// Replaces all metadata.
        @discardableResult
        public func metadata(_ metadata: [String: SendableValue]) -> Builder {
            state.withLock { $0.metadata = metadata }
            return self
        }

        /// Adds multiple metadata entries.
        @discardableResult
        public func addingMetadata(_ additional: [String: SendableValue]) -> Builder {
            state.withLock { $0.metadata.merge(additional) { _, new in new } }
            return self
        }

        /// Sets the agent name.
        @discardableResult
        public func agent(_ name: String) -> Builder {
            state.withLock { $0.agentName = name }
            return self
        }

        /// Sets the tool name.
        @discardableResult
        public func tool(_ name: String) -> Builder {
            state.withLock { $0.toolName = name }
            return self
        }

        /// Sets error information from an Error.
        @discardableResult
        public func error(_ error: Error) -> Builder {
            let info = ErrorInfo(from: error)
            state.withLock { $0.error = info }
            return self
        }

        /// Sets error information directly.
        @discardableResult
        public func error(_ errorInfo: ErrorInfo) -> Builder {
            state.withLock { $0.error = errorInfo }
            return self
        }

        /// Sets the source location.
        @discardableResult
        public func source(
            file: String = #file,
            function: String = #function,
            line: Int = #line
        ) -> Builder {
            let location = SourceLocation(file: file, function: function, line: line)
            state.withLock { $0.source = location }
            return self
        }

        /// Sets the source location directly.
        @discardableResult
        public func source(_ location: SourceLocation) -> Builder {
            state.withLock { $0.source = location }
            return self
        }

        /// Builds the trace event.
        public func build() -> TraceEvent {
            state.withLock { $0.event() }
        }

        // MARK: Private

        /// Mutable builder fields, guarded by `state`.
        private struct State: Sendable {
            let id: UUID
            let traceId: UUID
            let spanId: UUID
            var parentSpanId: UUID?
            var timestamp: Date
            var duration: TimeInterval?
            let kind: EventKind
            var level: EventLevel
            var message: String
            var metadata: [String: SendableValue] = [:]
            var agentName: String?
            var toolName: String?
            var error: ErrorInfo?
            var source: SourceLocation?

            func event() -> TraceEvent {
                TraceEvent(
                    id: id,
                    traceId: traceId,
                    spanId: spanId,
                    parentSpanId: parentSpanId,
                    timestamp: timestamp,
                    duration: duration,
                    kind: kind,
                    level: level,
                    message: message,
                    metadata: metadata,
                    agentName: agentName,
                    toolName: toolName,
                    error: error,
                    source: source
                )
            }
        }

        private let state: Mutex<State>
    }
}

// MARK: - Convenience Constructors

public extension TraceEvent {
    /// Creates an agent start event.
    static func agentStart(
        traceId: UUID,
        spanId: UUID = UUID(),
        agentName: String,
        metadata: [String: SendableValue] = [:],
        source: SourceLocation? = nil
    ) -> TraceEvent {
        Builder(traceId: traceId, kind: .agentStart, message: "LegacyAgent started", spanId: spanId)
            .agent(agentName)
            .metadata(metadata)
            .source(source ?? SourceLocation())
            .build()
    }

    /// Creates an agent complete event.
    static func agentComplete(
        traceId: UUID,
        spanId: UUID,
        agentName: String,
        duration: TimeInterval,
        metadata: [String: SendableValue] = [:],
        source: SourceLocation? = nil
    ) -> TraceEvent {
        Builder(traceId: traceId, kind: .agentComplete, message: "LegacyAgent completed", spanId: spanId)
            .agent(agentName)
            .duration(duration)
            .metadata(metadata)
            .source(source ?? SourceLocation())
            .build()
    }

    /// Creates an agent error event.
    static func agentError(
        traceId: UUID,
        spanId: UUID,
        agentName: String,
        error: Error,
        metadata: [String: SendableValue] = [:],
        source: SourceLocation? = nil
    ) -> TraceEvent {
        Builder(traceId: traceId, kind: .agentError, message: "LegacyAgent error", spanId: spanId, level: .error)
            .agent(agentName)
            .error(error)
            .metadata(metadata)
            .source(source ?? SourceLocation())
            .build()
    }

    /// Creates a tool call event.
    static func toolCall(
        traceId: UUID,
        spanId: UUID = UUID(),
        parentSpanId: UUID?,
        toolName: String,
        metadata: [String: SendableValue] = [:],
        source: SourceLocation? = nil
    ) -> TraceEvent {
        Builder(traceId: traceId, kind: .toolCall, message: "Tool call", spanId: spanId, level: .debug)
            .parentSpan(parentSpanId ?? UUID())
            .tool(toolName)
            .metadata(metadata)
            .source(source ?? SourceLocation())
            .build()
    }

    /// Creates a tool result event.
    static func toolResult(
        traceId: UUID,
        spanId: UUID,
        toolName: String,
        duration: TimeInterval,
        metadata: [String: SendableValue] = [:],
        source: SourceLocation? = nil
    ) -> TraceEvent {
        Builder(traceId: traceId, kind: .toolResult, message: "Tool result", spanId: spanId, level: .debug)
            .tool(toolName)
            .duration(duration)
            .metadata(metadata)
            .source(source ?? SourceLocation())
            .build()
    }

    /// Creates a thought event.
    static func thought(
        traceId: UUID,
        spanId: UUID,
        agentName: String,
        thought: String,
        metadata: [String: SendableValue] = [:],
        source: SourceLocation? = nil
    ) -> TraceEvent {
        var meta = metadata
        meta["thought"] = .string(thought)

        return Builder(traceId: traceId, kind: .thought, message: thought, spanId: spanId, level: .trace)
            .agent(agentName)
            .metadata(meta)
            .source(source ?? SourceLocation())
            .build()
    }

    /// Creates a custom event.
    static func custom(
        traceId: UUID,
        spanId: UUID = UUID(),
        message: String,
        level: EventLevel = .info,
        metadata: [String: SendableValue] = [:],
        source: SourceLocation? = nil
    ) -> TraceEvent {
        Builder(traceId: traceId, kind: .custom, message: message, spanId: spanId, level: level)
            .metadata(metadata)
            .source(source ?? SourceLocation())
            .build()
    }
}

// MARK: CustomStringConvertible

extension TraceEvent: CustomStringConvertible {
    public var description: String {
        var parts = [
            "[\(level)]",
            kind.rawValue,
        ]

        if let agentName {
            parts.append("agent=\(agentName)")
        }

        if let toolName {
            parts.append("tool=\(toolName)")
        }

        parts.append(message)

        if let duration {
            parts.append("(\(String(format: "%.2f", duration * 1000))ms)")
        }

        return parts.joined(separator: " ")
    }
}

// MARK: - EventLevel + CustomStringConvertible

extension EventLevel: CustomStringConvertible {
    public var description: String {
        switch self {
        case .trace: "TRACE"
        case .debug: "DEBUG"
        case .info: "INFO"
        case .warning: "WARN"
        case .error: "ERROR"
        case .critical: "CRITICAL"
        }
    }
}
