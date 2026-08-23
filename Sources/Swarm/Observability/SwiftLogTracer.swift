// SwiftLogTracer.swift
// Swarm Framework
//
// Cross-platform tracer using swift-log.

import Foundation
import Logging

// MARK: - SwiftLogTracer

/// A cross-platform tracer implementation using swift-log.
///
/// `SwiftLogTracer` provides structured logging for agent execution traces
/// that works on both Apple platforms and Linux servers. Use this tracer
/// when deploying to server environments.
///
/// ## Usage
///
/// ```swift
/// let tracer = SwiftLogTracer(minimumLevel: .debug)
/// let agent = Agent(
///     tools: [...],
///     instructions: "...",
///     tracer: tracer
/// )
/// ```
///
/// ## Log Output Format
///
/// Traces are logged with structured metadata including:
/// - `traceId`: Unique identifier for the trace
/// - `spanId`: Unique identifier for the span
/// - `parentSpanId`: Parent span ID (if applicable)
/// - `agentName`: Name of the agent (if applicable)
/// - `toolName`: Name of the tool being invoked (if applicable)
public actor SwiftLogTracer: Tracer {
    // MARK: Public

    /// Creates a new SwiftLogTracer.
    ///
    /// - Parameters:
    ///   - label: The logger label (default: "com.swarm.tracer")
    ///   - minimumLevel: The minimum event level to log (default: .debug)
    public init(
        label: String = "com.swarm.tracer",
        minimumLevel: EventLevel = .debug
    ) {
        logger = Logger(label: label)
        self.minimumLevel = minimumLevel
    }

    // MARK: - AgentTracer Protocol

    public func trace(_ event: TraceEvent) async {
        guard event.level >= minimumLevel else { return }

        let message = formatMessage(event)
        let metadata = buildMetadata(event)

        switch event.level {
        case .trace:
            logger.trace("\(message)", metadata: metadata)
        case .debug:
            logger.debug("\(message)", metadata: metadata)
        case .info:
            logger.info("\(message)", metadata: metadata)
        case .warning:
            logger.warning("\(message)", metadata: metadata)
        case .error:
            logger.error("\(message)", metadata: metadata)
        case .critical:
            logger.critical("\(message)", metadata: metadata)
        }
    }

    public func flush() async {
        // No-op: swift-log handles flushing automatically
    }

    // MARK: Private

    private var logger: Logger
    private let minimumLevel: EventLevel

    // MARK: - Private Helpers

    private func formatMessage(_ event: TraceEvent) -> String {
        var parts = ["[\(event.kind.rawValue)]"]

        if let agentName = event.agentName {
            parts.append("agent=\(agentName)")
        }
        if let toolName = event.toolName {
            parts.append("tool=\(toolName)")
        }

        parts.append(TraceEventPublicLogSanitizer.message(for: event))

        if let duration = event.duration {
            parts.append("(\(String(format: "%.2f", duration * 1000))ms)")
        }

        return parts.joined(separator: " ")
    }

    private func buildMetadata(_ event: TraceEvent) -> Logger.Metadata {
        var metadata: Logger.Metadata = [
            "traceId": "\(event.traceId)",
            "spanId": "\(event.spanId)",
            "eventKind": "\(event.kind.rawValue)"
        ]

        if let parentSpanId = event.parentSpanId {
            metadata["parentSpanId"] = "\(parentSpanId)"
        }
        if let agentName = event.agentName {
            metadata["agentName"] = "\(agentName)"
        }
        if let toolName = event.toolName {
            metadata["toolName"] = "\(toolName)"
        }

        // Extract stepNumber from metadata if present
        if let stepNumber = event.metadata[.stepNumber] {
            metadata["step"] = "\(stepNumber)"
        }

        if let duration = event.duration {
            metadata["durationMs"] = "\(String(format: "%.2f", duration * 1000))"
        }

        // Extract tokenCount from metadata if present
        if let tokenCount = event.metadata[.legacyTokenCount] {
            metadata["tokens"] = "\(tokenCount)"
        }

        return metadata
    }
}

// MARK: - Convenience Constructors

public extension SwiftLogTracer {
    /// Creates a tracer optimized for development with verbose output.
    ///
    /// - Returns: A tracer configured for development.
    static func development() -> SwiftLogTracer {
        SwiftLogTracer(minimumLevel: .trace)
    }

    /// Creates a tracer optimized for production with minimal output.
    ///
    /// - Returns: A tracer configured for production.
    static func production() -> SwiftLogTracer {
        SwiftLogTracer(minimumLevel: .info)
    }
}
