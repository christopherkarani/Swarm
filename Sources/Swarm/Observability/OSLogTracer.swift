// OSLogTracer.swift
// Swarm Framework
//
// A tracer that integrates with Apple's unified logging system (os.log).
// Provides structured logging with signposts for performance analysis in Instruments.

#if canImport(os)
    import Foundation
    import os.log

    // MARK: - OSLog Tracer

    /// A tracer that integrates with Apple's unified logging system.
    ///
    /// `OSLogTracer` leverages `OSLog` and `OSSignposter` to provide:
    /// - Structured logging visible in Console.app and Instruments
    /// - Performance measurement via signpost intervals
    /// - Automatic log level mapping from `EventLevel` to `OSLogType`
    /// - Span-based event correlation
    ///
    /// ## Features
    ///
    /// - **Unified Logging**: Events are logged to Apple's unified logging system
    /// - **Signpost Intervals**: LegacyAgent and tool executions create signpost intervals for Instruments
    /// - **Configurable Filtering**: Set minimum log level to reduce noise
    /// - **Subsystem Organization**: Events are organized by subsystem and category
    ///
    /// ## Example
    ///
    /// ```swift
    /// let tracer = OSLogTracer(
    ///     subsystem: "com.example.app",
    ///     category: "agent",
    ///     minimumLevel: .info,
    ///     emitSignposts: true
    /// )
    ///
    /// await tracer.trace(.agentStart(
    ///     traceId: traceId,
    ///     agentName: "MyAgent"
    /// ))
    /// ```
    ///
    /// ## Signpost Intervals
    ///
    /// The following event pairs create signpost intervals:
    /// - `agentStart` → `agentComplete/agentError/agentCancelled`
    /// - `toolCall` → `toolResult/toolError`
    ///
    /// These intervals are visible in Instruments' "os_signpost" instrument.
    public actor OSLogTracer: Tracer {
        // MARK: Public

        // MARK: - Initialization

        /// Creates an OSLog tracer with the specified configuration.
        ///
        /// - Parameters:
        ///   - subsystem: The subsystem identifier (e.g., "com.example.app").
        ///   - category: The category within the subsystem (e.g., "agent", "tools").
        ///   - minimumLevel: Minimum event level to log. Default: `.info`.
        ///   - emitSignposts: Whether to emit signpost intervals. Default: `true`.
        public init(
            subsystem: String,
            category: String,
            minimumLevel: EventLevel = .info,
            emitSignposts: Bool = true
        ) {
            self.subsystem = subsystem
            self.category = category
            self.minimumLevel = minimumLevel
            self.emitSignposts = emitSignposts
            logger = Logger(subsystem: subsystem, category: category)
            signposter = OSSignposter(subsystem: subsystem, category: category)
        }

        // MARK: - AgentTracer Conformance

        public func trace(_ event: TraceEvent) async {
            // Filter events below minimum level
            guard event.level >= minimumLevel else { return }

            // Map event level to OSLogType
            let logType = mapEventLevelToOSLogType(event.level)

            // Format the log message
            let message = formatLogMessage(event)

            // Emit the log message
            logger.log(level: logType, "\(message, privacy: .private)")

            // Handle signpost intervals if enabled
            if emitSignposts {
                handleSignpostEvent(event)
            }
        }

        // MARK: Private

        /// The underlying logger for emitting log messages.
        private let logger: Logger

        /// The signposter for creating performance intervals.
        private let signposter: OSSignposter

        /// The subsystem identifier for this tracer.
        private let subsystem: String

        /// The category within the subsystem.
        private let category: String

        /// The minimum event level to log. Events below this level are discarded.
        private let minimumLevel: EventLevel

        /// Whether to emit signpost intervals for span-based events.
        private let emitSignposts: Bool

        /// Active signpost intervals tracked by span ID.
        private var activeIntervals: [UUID: OSSignpostIntervalState] = [:]

        // MARK: - Private Helpers

        /// Maps an EventLevel to the corresponding OSLogType.
        ///
        /// Mapping:
        /// - `.trace`, `.debug` → `.debug`
        /// - `.info` → `.info`
        /// - `.warning` → `.default`
        /// - `.error` → `.error`
        /// - `.critical` → `.fault`
        private func mapEventLevelToOSLogType(_ level: EventLevel) -> OSLogType {
            switch level {
            case .debug,
                 .trace:
                .debug
            case .info:
                .info
            case .warning:
                .default
            case .error:
                .error
            case .critical:
                .fault
            }
        }

        /// Formats a trace event into a human-readable log message.
        private func formatLogMessage(_ event: TraceEvent) -> String {
            var parts: [String] = []

            // Add event kind
            parts.append("[\(event.kind.rawValue)]")

            // Add agent name if present
            if let agentName = event.agentName {
                parts.append("agent=\(agentName)")
            }

            // Add tool name if present
            if let toolName = event.toolName {
                parts.append("tool=\(toolName)")
            }

            // Add message
            parts.append(TraceEventPublicLogSanitizer.message(for: event))

            // Add duration if present
            if let duration = event.duration {
                let durationMs = duration * 1000
                parts.append("(\(String(format: "%.2f", durationMs))ms)")
            }

            // Add error information if present
            if let error = event.error {
                parts.append("error=\(TraceEventPublicLogSanitizer.errorSummary(for: error))")
            }

            // Add trace/span IDs for debugging
            parts.append("trace=\(event.traceId.uuidString.prefix(8))")
            parts.append("span=\(event.spanId.uuidString.prefix(8))")

            return parts.joined(separator: " ")
        }

        /// Handles signpost interval creation and completion for span-based events.
        private func handleSignpostEvent(_ event: TraceEvent) {
            switch event.kind {
            // Start signpost intervals
            case .agentStart,
                 .toolCall:
                startSignpostInterval(for: event)

            // End signpost intervals
            case .agentCancelled,
                 .agentComplete,
                 .agentError,
                 .toolError,
                 .toolResult:
                endSignpostInterval(for: event)

            // Other events don't create intervals
            default:
                break
            }
        }

        /// Starts a signpost interval for the given event.
        private func startSignpostInterval(for event: TraceEvent) {
            let name: StaticString
            let description: String

            switch event.kind {
            case .agentStart:
                name = "LegacyAgent Execution"
                description = event.agentName ?? "Unknown LegacyAgent"
            case .toolCall:
                name = "Tool Execution"
                description = event.toolName ?? "Unknown Tool"
            default:
                return
            }

            let state = signposter.beginInterval(name, id: signpostID(for: event.spanId))
            activeIntervals[event.spanId] = state

            signposter.emitEvent("Start", id: signpostID(for: event.spanId), "\(description, privacy: .private)")
        }

        /// Ends a signpost interval for the given event.
        private func endSignpostInterval(for event: TraceEvent) {
            guard let state = activeIntervals.removeValue(forKey: event.spanId) else {
                // No active interval for this span - this is okay for orphaned events
                return
            }

            let name: StaticString
            let description: String

            switch event.kind {
            case .agentCancelled,
                 .agentComplete,
                 .agentError:
                name = "LegacyAgent Execution"
                description = TraceEventPublicLogSanitizer.message(for: event)
            case .toolError,
                 .toolResult:
                name = "Tool Execution"
                description = TraceEventPublicLogSanitizer.message(for: event)
            default:
                return
            }

            signposter.endInterval(name, state)

            // Emit completion event
            let status = event.kind.rawValue
            signposter.emitEvent("End", id: signpostID(for: event.spanId), "\(status): \(description, privacy: .private)")
        }

        /// Creates a signpost ID from a UUID.
        ///
        /// OSSignposter requires an OSSignpostID, which we derive from the span's UUID.
        private func signpostID(for uuid: UUID) -> OSSignpostID {
            // Convert UUID to UInt64 for OSSignpostID
            // We use the first 8 bytes of the UUID
            let uuidBytes = withUnsafeBytes(of: uuid.uuid) { buffer in
                buffer.load(as: UInt64.self)
            }
            return OSSignpostID(uuidBytes)
        }
    }

    // MARK: - Configuration Builder

    public extension OSLogTracer {
        /// A builder for configuring `OSLogTracer` instances.
        ///
        /// Provides a fluent API for creating tracers with custom configurations.
        /// Uses value semantics (struct) for Swift 6 concurrency safety.
        ///
        /// ## Example
        ///
        /// ```swift
        /// let tracer = OSLogTracer.Builder(subsystem: "com.example.app")
        ///     .category("agent")
        ///     .minimumLevel(.info)
        ///     .emitSignposts(true)
        ///     .build()
        /// ```
        struct Builder: Sendable {
            // MARK: Public

            /// Creates a new builder with the required subsystem.
            ///
            /// - Parameter subsystem: The subsystem identifier (e.g., "com.example.app").
            public init(subsystem: String) {
                self.subsystem = subsystem
                category = "agent"
                minimumLevel = .info
                emitSignposts = true
            }

            /// Sets the category within the subsystem.
            ///
            /// - Parameter category: The category name.
            /// - Returns: A new builder with the updated category.
            public func category(_ category: String) -> Builder {
                var copy = self
                copy.category = category
                return copy
            }

            /// Sets the minimum event level to log.
            ///
            /// - Parameter level: The minimum event level.
            /// - Returns: A new builder with the updated level.
            public func minimumLevel(_ level: EventLevel) -> Builder {
                var copy = self
                copy.minimumLevel = level
                return copy
            }

            /// Sets whether to emit signpost intervals.
            ///
            /// - Parameter emit: Whether to emit signposts.
            /// - Returns: A new builder with the updated setting.
            public func emitSignposts(_ emit: Bool) -> Builder {
                var copy = self
                copy.emitSignposts = emit
                return copy
            }

            /// Builds the configured `OSLogTracer`.
            ///
            /// - Returns: A new `OSLogTracer` instance.
            public func build() -> OSLogTracer {
                OSLogTracer(
                    subsystem: subsystem,
                    category: category,
                    minimumLevel: minimumLevel,
                    emitSignposts: emitSignposts
                )
            }

            // MARK: Private

            private let subsystem: String
            private var category: String
            private var minimumLevel: EventLevel
            private var emitSignposts: Bool
        }
    }

    // MARK: - Convenience Constructors

    public extension OSLogTracer {
        /// Creates an OSLog tracer with default configuration for the specified subsystem.
        ///
        /// Default configuration:
        /// - Category: "agent"
        /// - Minimum level: `.debug`
        /// - Emit signposts: `true`
        ///
        /// - Parameter subsystem: The subsystem identifier.
        /// - Returns: A new `OSLogTracer` instance.
        static func `default`(subsystem: String) -> OSLogTracer {
            Builder(subsystem: subsystem).build()
        }

        /// Creates an OSLog tracer optimized for production use.
        ///
        /// Production configuration:
        /// - Category: "agent"
        /// - Minimum level: `.info`
        /// - Emit signposts: `false`
        ///
        /// - Parameter subsystem: The subsystem identifier.
        /// - Returns: A new `OSLogTracer` instance.
        static func production(subsystem: String) -> OSLogTracer {
            Builder(subsystem: subsystem)
                .minimumLevel(.info)
                .emitSignposts(false)
                .build()
        }

        /// Creates an OSLog tracer optimized for debugging.
        ///
        /// Debug configuration:
        /// - Category: "agent"
        /// - Minimum level: `.trace`
        /// - Emit signposts: `true`
        ///
        /// - Parameter subsystem: The subsystem identifier.
        /// - Returns: A new `OSLogTracer` instance.
        static func debug(subsystem: String) -> OSLogTracer {
            Builder(subsystem: subsystem)
                .minimumLevel(.trace)
                .emitSignposts(true)
                .build()
        }
    }
#endif
