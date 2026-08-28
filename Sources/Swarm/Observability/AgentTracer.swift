// AgentTracer.swift
// Swarm Framework
//
// Tracer protocol and implementations for agent observability.
// Provides composite tracers, no-op tracers, and buffered tracers for flexible tracing strategies.

import Foundation

// MARK: - Tracer

/// Protocol defining the contract for tracing agent execution events.
///
/// `Tracer` is the core abstraction for observability in Swarm.
/// Implementations can log to console, send to telemetry systems, or store events for analysis.
///
/// ## Conformance Requirements
///
/// - Must be an `actor` (inherited from protocol requirements)
/// - Must be `Sendable` for safe concurrent access
/// - All methods are implicitly `async` due to actor isolation
///
/// ## Example Implementation
///
/// ```swift
/// public actor CustomTracer: Tracer {
///     private var events: [TraceEvent] = []
///
///     public func trace(_ event: TraceEvent) async {
///         events.append(event)
///         print("[TRACE] \(event)")
///     }
///
///     public func flush() async {
///         print("Flushing \(events.count) events")
///         events.removeAll()
///     }
/// }
/// ```
///
/// ## Usage Example
///
/// ```swift
/// let tracer: Tracer = ConsoleTracer(minimumLevel: .info)
///
/// await tracer.trace(.agentStart(
///     traceId: traceId,
///     agentName: "MyAgent"
/// ))
/// ```
public protocol Tracer: Actor, Sendable {
    /// Traces an event.
    ///
    /// Implementations should handle the event appropriately based on their purpose
    /// (e.g., logging, storing, forwarding to telemetry systems).
    ///
    /// - Parameter event: The trace event to record.
    func trace(_ event: TraceEvent) async

    /// Flushes any buffered events.
    ///
    /// This method provides a hook for tracers that buffer events to ensure
    /// they are persisted or transmitted. The default implementation is a no-op.
    func flush() async
}

// MARK: - Default Implementation

public extension Tracer {
    /// Default flush implementation that does nothing.
    ///
    /// Override this method in your tracer if you need to flush buffered events.
    func flush() async {
        // Default: no-op
    }
}

// MARK: - CompositeTracer

/// A tracer that forwards events to multiple child tracers.
///
/// `CompositeTracer` enables fan-out tracing patterns, where a single event
/// is sent to multiple destinations (e.g., console + file + telemetry service).
///
/// ## Features
///
/// - Filters events by minimum level before forwarding
/// - Supports parallel or sequential event forwarding
/// - Gracefully handles failures in individual tracers
///
/// ## Example
///
/// ```swift
/// let tracer = CompositeTracer(
///     tracers: [consoleTracer, fileTracer, telemetryTracer],
///     minimumLevel: .info,
///     shouldExecuteInParallel: true
/// )
///
/// await tracer.trace(event) // Forwards to all three tracers in parallel
/// ```
package actor CompositeTracer: Tracer {
    // MARK: Package

    /// Creates a composite tracer.
    ///
    /// - Parameters:
    ///   - tracers: The child tracers to forward events to.
    ///   - minimumLevel: Minimum event level to forward. Default: `.trace` (all events).
    ///   - shouldExecuteInParallel: Whether to forward events in parallel. Default: `true`.
    package init(
        tracers: [any Tracer],
        minimumLevel: EventLevel = .trace,
        shouldExecuteInParallel: Bool = true
    ) {
        self.tracers = tracers
        self.minimumLevel = minimumLevel
        self.shouldExecuteInParallel = shouldExecuteInParallel
    }

    package func trace(_ event: TraceEvent) async {
        // Filter events below minimum level
        guard event.level >= minimumLevel else { return }

        if shouldExecuteInParallel {
            // Forward to all tracers in parallel using TaskGroup
            await withTaskGroup(of: Void.self) { group in
                for tracer in tracers {
                    group.addTask {
                        await tracer.trace(event)
                    }
                }
            }
        } else {
            // Forward to tracers sequentially
            for tracer in tracers {
                await tracer.trace(event)
            }
        }
    }

    package func flush() async {
        if shouldExecuteInParallel {
            // Flush all tracers in parallel
            await withTaskGroup(of: Void.self) { group in
                for tracer in tracers {
                    group.addTask {
                        await tracer.flush()
                    }
                }
            }
        } else {
            // Flush tracers sequentially
            for tracer in tracers {
                await tracer.flush()
            }
        }
    }

    // MARK: Private

    /// The child tracers to forward events to.
    private let tracers: [any Tracer]

    /// The minimum event level to forward. Events below this level are discarded.
    private let minimumLevel: EventLevel

    /// Whether to forward events in parallel (true) or sequentially (false).
    private let shouldExecuteInParallel: Bool
}

// MARK: - NoOpTracer

/// A tracer that discards all events.
///
/// `NoOpTracer` is useful for:
/// - Testing scenarios where tracing is not needed
/// - Disabling tracing in production without code changes
/// - Default tracer values in APIs
///
/// ## Example
///
/// ```swift
/// let tracer: Tracer = NoOpTracer()
/// await tracer.trace(event) // Event is discarded
/// ```
package actor NoOpTracer: Tracer {
    /// Creates a no-op tracer.
    package init() {}

    /// Discards the event without processing.
    package func trace(_: TraceEvent) async {
        // Intentionally empty - discard all events
    }

    /// No-op flush implementation.
    package func flush() async {
        // Intentionally empty
    }
}

// MARK: - BufferedTracer

/// A tracer that buffers events and flushes them in batches to a destination tracer.
///
/// `BufferedTracer` reduces overhead by batching trace events and flushing them
/// periodically or when the buffer reaches capacity. This is particularly useful
/// for high-throughput scenarios or when sending events to remote systems.
///
/// ## Features
///
/// - Automatic flush when buffer reaches `maxBufferSize`
/// - Periodic flush based on `flushInterval`
/// - Thread-safe buffering using actor isolation
///
/// ## Example
///
/// ```swift
/// let destination = ConsoleTracer()
/// let buffered = BufferedTracer(
///     destination: destination,
///     maxBufferSize: 100,
///     flushInterval: .seconds(5)
/// )
///
/// // Events are buffered until 100 events or 5 seconds
/// await buffered.trace(event1)
/// await buffered.trace(event2)
/// // ... more events ...
///
/// // Manually flush if needed
/// await buffered.flush()
/// ```
package actor BufferedTracer: Tracer {
    // MARK: Package

    /// Creates a buffered tracer.
    ///
    /// - Parameters:
    ///   - destination: The tracer to forward buffered events to.
    ///   - maxBufferSize: Maximum events to buffer before auto-flush. Default: `100`.
    ///   - flushInterval: Time between automatic flushes. Default: `5 seconds`.
    package init(
        destination: any Tracer,
        maxBufferSize: Int = 100,
        flushInterval: Duration = .seconds(5)
    ) {
        self.destination = destination
        self.maxBufferSize = maxBufferSize
        self.flushInterval = flushInterval
        lastFlushTime = ContinuousClock.now
        flushTask = nil
    }

    /// Starts the periodic flush task. Call this after initialization.
    package func start() {
        guard flushTask == nil else { return }
        // Note: Actors don't need [weak self] - the Task is cancelled in deinit
        // and actor isolation guarantees safe access
        flushTask = Task {
            await periodicFlush()
        }
    }

    package func trace(_ event: TraceEvent) async {
        buffer.append(event)

        // Auto-flush if buffer is full
        if buffer.count >= maxBufferSize {
            await flush()
        }
    }

    package func flush() async {
        guard !buffer.isEmpty else { return }

        // Copy buffer and clear it
        let eventsToFlush = buffer
        buffer.removeAll()
        lastFlushTime = ContinuousClock.now

        // Forward all buffered events to destination
        for event in eventsToFlush {
            await destination.trace(event)
        }

        // Flush the destination as well
        await destination.flush()
    }

    // MARK: Internal

    deinit {
        // Cancel the periodic flush task
        flushTask?.cancel()
    }

    // MARK: Private

    /// The buffered events waiting to be flushed.
    private var buffer: [TraceEvent] = []

    /// The maximum number of events to buffer before auto-flushing.
    private let maxBufferSize: Int

    /// The time interval between automatic flushes.
    private let flushInterval: Duration

    /// The destination tracer to forward events to.
    private let destination: any Tracer

    /// The task that handles periodic flushing.
    private var flushTask: Task<Void, Never>?

    /// The last time the buffer was flushed.
    private var lastFlushTime: ContinuousClock.Instant

    /// Periodically flushes the buffer based on the flush interval.
    private func periodicFlush() async {
        while !Task.isCancelled {
            // Sleep for the flush interval
            do {
                try await Task.sleep(for: flushInterval)
            } catch {
                // Task was cancelled during sleep
                break
            }

            // Check cancellation before performing potentially expensive flush
            guard !Task.isCancelled else { break }

            // Check if enough time has passed since last flush
            let now = ContinuousClock.now
            let elapsed = now - lastFlushTime

            if elapsed >= flushInterval {
                await flush()
            }
        }
    }
}

// MARK: - Convenience Extensions

public extension Tracer {
    /// Traces multiple events sequentially.
    ///
    /// - Parameter events: The events to trace.
    func trace(_ events: [TraceEvent]) async {
        for event in events {
            await trace(event)
        }
    }
}

// MARK: - AnyTracer

/// Type-erased wrapper for `Tracer` protocol.
///
/// This allows storing heterogeneous tracers in collections while maintaining
/// the actor-based interface.
public actor AnyTracer: Tracer {
    // MARK: Public

    /// Creates a type-erased tracer.
    ///
    /// - Parameter tracer: The tracer to wrap.
    public init(_ tracer: some Tracer) {
        _trace = { event in
            await tracer.trace(event)
        }
        _flush = {
            await tracer.flush()
        }
    }

    public func trace(_ event: TraceEvent) async {
        await _trace(event)
    }

    public func flush() async {
        await _flush()
    }

    // MARK: Private

    private let _trace: @Sendable (TraceEvent) async -> Void
    private let _flush: @Sendable () async -> Void
}

// MARK: - V3 Tracer Factory Extensions

extension Tracer where Self == ConsoleTracer {
    /// Creates a console tracer that prints events to stdout.
    public static func console(
        minimumLevel: EventLevel = .trace,
        colorized: Bool = true,
        includeTimestamp: Bool = true
    ) -> ConsoleTracer {
        ConsoleTracer(
            minimumLevel: minimumLevel,
            colorized: colorized,
            includeTimestamp: includeTimestamp
        )
    }
}

extension Tracer where Self == SwiftLogTracer {
    /// Creates a tracer backed by swift-log.
    public static func swiftLog(
        minimumLevel: EventLevel = .info
    ) -> SwiftLogTracer {
        SwiftLogTracer(minimumLevel: minimumLevel)
    }
}
