#if SWARM_OTEL
// OTLPHTTPTraceExporter.swift
// SwarmOpenTelemetry

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal in-house OTLP/HTTP JSON ``SpanExporter``.
///
/// Posts completed spans to ``OTLPHTTPExporterConfiguration/endpoint`` as
/// `application/json`. Batching is size- and timer-based. Transient failures
/// (HTTP 5xx and network errors) retry once by default; HTTP 4xx does not.
///
/// This exporter does **not** pull gRPC or the first-party
/// `OpenTelemetryProtocolExporterHTTP` package.
///
/// ```swift
/// let exporter = OTLPHTTPTraceExporter()
/// OpenTelemetry.registerTracerProvider(
///     tracerProvider: TracerProviderBuilder()
///         .add(spanProcessor: SimpleSpanProcessor(spanExporter: exporter))
///         .build()
/// )
/// ```
///
/// ## Delivery Semantics
///
/// - `export` only enqueues. Reaching ``OTLPHTTPExporterConfiguration/maxBatchSize``
///   starts a background flush; the synchronous `export` never waits on the
///   network.
/// - The queue holds at most ``OTLPHTTPExporterConfiguration/maxQueueSize``
///   spans. When full, the oldest spans are dropped and counted in
///   ``droppedSpanCount``.
/// - A batch that fails transiently (5xx or network error, after
///   ``OTLPHTTPExporterConfiguration/maxRetries``) is requeued for the next
///   flush, up to ``OTLPHTTPExporterConfiguration/maxExportAttempts`` flushes
///   per span; spans that exhaust it, or that the collector rejects with 4xx,
///   are dropped and counted.
/// - The synchronous `flush`/`shutdown` required by `SpanExporter` wait for
///   the POST for at most `explicitTimeout` (default
///   ``OTLPHTTPExporterConfiguration/syncTimeout``) and return `.failure` on
///   timeout; the POST keeps running in the background and requeues on
///   failure. Prefer the `async` overloads from Swift concurrency code: the
///   synchronous ones block their calling thread for up to that timeout.
///
/// Queue, timer, and counter state are guarded by `lock`. `@unchecked Sendable`
/// is required because `SpanExporter` is a non-`Sendable` class protocol
/// invoked from the SDK's export queue.
///
/// - SeeAlso: ``OTLPHTTPExporterConfiguration``, ``OpenTelemetryTracing``
public final class OTLPHTTPTraceExporter: SpanExporter, @unchecked Sendable {
    /// The configuration used by this exporter.
    public let configuration: OTLPHTTPExporterConfiguration

    /// Creates an OTLP/HTTP JSON exporter.
    ///
    /// - Parameters:
    ///   - configuration: Endpoint, headers, batching, and retry settings.
    ///   - session: Session used for POST requests. Inject a `URLProtocol`
    ///     stub in tests.
    public init(
        configuration: OTLPHTTPExporterConfiguration = .default,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
        startTimer()
    }

    deinit {
        flushTask?.cancel()
    }

    /// Spans dropped because the queue overflowed, the collector rejected
    /// them, or they exhausted ``OTLPHTTPExporterConfiguration/maxExportAttempts``.
    public var droppedSpanCount: Int {
        lock.withLock { dropped }
    }

    /// Number of spans waiting for the next flush.
    public var queuedSpanCount: Int {
        lock.withLock { pending.count }
    }

    /// Enqueues spans without blocking; a full batch starts a background flush.
    public func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        if enqueue(spans) {
            Task { [self] in
                _ = await flush(explicitTimeout: explicitTimeout)
            }
        }
        return .success
    }

    /// Enqueues spans; a full batch is flushed before returning.
    public func export(spans: [SpanData], explicitTimeout: TimeInterval?) async -> SpanExporterResultCode {
        if enqueue(spans) {
            return await flush(explicitTimeout: explicitTimeout)
        }
        return .success
    }

    /// Flushes queued spans, waiting at most `explicitTimeout` (default
    /// ``OTLPHTTPExporterConfiguration/syncTimeout``).
    ///
    /// Returns `.failure` on timeout; the POST continues in the background.
    /// Blocks the calling thread, so prefer the `async` overload from Swift
    /// concurrency code.
    public func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        let batch = drain()
        guard !batch.isEmpty else { return .success }
        let timeout = explicitTimeout ?? configuration.syncTimeout
        let box = ExportResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task { [self] in
            box.set(await send(batch, explicitTimeout: explicitTimeout))
            semaphore.signal()
        }
        // DispatchTime arithmetic traps on non-finite intervals; cap at one day.
        let seconds = timeout.isNaN ? 0 : min(max(0, timeout), 86_400)
        guard semaphore.wait(timeout: .now() + seconds) == .success else {
            return .failure
        }
        return box.value
    }

    /// Flushes queued spans, awaiting the POST (including retries).
    public func flush(explicitTimeout: TimeInterval?) async -> SpanExporterResultCode {
        let batch = drain()
        guard !batch.isEmpty else { return .success }
        return await send(batch, explicitTimeout: explicitTimeout)
    }

    /// Stops the flush timer and flushes, bounded like ``flush(explicitTimeout:)``.
    public func shutdown(explicitTimeout: TimeInterval?) {
        stopTimer()
        _ = flush(explicitTimeout: explicitTimeout)
    }

    /// Stops the flush timer and awaits a final flush.
    public func shutdown(explicitTimeout: TimeInterval?) async {
        stopTimer()
        _ = await flush(explicitTimeout: explicitTimeout)
    }

    private let session: URLSession
    private let lock = NSLock()
    private var pending: [QueuedSpan] = []
    private var dropped = 0
    private var flushTask: Task<Void, Never>?

    private func startTimer() {
        let delay = configuration.scheduleDelay
        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { break }
                _ = await self?.flush(explicitTimeout: nil)
            }
        }
        lock.withLock { flushTask = task }
    }

    private func stopTimer() {
        let task = lock.withLock {
            let task = flushTask
            flushTask = nil
            return task
        }
        task?.cancel()
    }

    /// Appends spans, dropping the oldest beyond `maxQueueSize`.
    /// - Returns: Whether the queue reached `maxBatchSize`.
    private func enqueue(_ spans: [SpanData]) -> Bool {
        lock.withLock {
            pending.append(contentsOf: spans.map { QueuedSpan(span: $0, failedExports: 0) })
            trimToCapacity()
            return pending.count >= configuration.maxBatchSize
        }
    }

    /// Requeues a transiently failed batch ahead of newer spans.
    private func requeue(_ batch: [QueuedSpan]) {
        lock.withLock {
            var retained: [QueuedSpan] = []
            for item in batch {
                let next = QueuedSpan(span: item.span, failedExports: item.failedExports + 1)
                if next.failedExports < configuration.maxExportAttempts {
                    retained.append(next)
                } else {
                    dropped += 1
                }
            }
            pending.insert(contentsOf: retained, at: 0)
            trimToCapacity()
        }
    }

    /// Drops the oldest spans beyond `maxQueueSize`. Caller holds `lock`.
    private func trimToCapacity() {
        let overflow = pending.count - configuration.maxQueueSize
        guard overflow > 0 else { return }
        pending.removeFirst(overflow)
        dropped += overflow
    }

    private func drain() -> [QueuedSpan] {
        lock.withLock {
            let batch = pending
            pending = []
            return batch
        }
    }

    private func recordDropped(_ count: Int) {
        lock.withLock { dropped += count }
    }

    /// Posts a drained batch, requeueing it on transient failure.
    private func send(_ batch: [QueuedSpan], explicitTimeout: TimeInterval?) async -> SpanExporterResultCode {
        switch await post(spans: batch.map(\.span), explicitTimeout: explicitTimeout) {
        case .success:
            return .success
        case .permanentFailure:
            recordDropped(batch.count)
            return .failure
        case .transientFailure:
            requeue(batch)
            return .failure
        }
    }

    private func makeRequest(body: Data, timeout: TimeInterval?) -> URLRequest {
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        if let timeout {
            request.timeoutInterval = timeout
        }
        for (name, value) in configuration.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    private func post(spans: [SpanData], explicitTimeout: TimeInterval?) async -> ExportClassification {
        let body: Data
        do {
            body = try OTLPJSON.payload(
                spans: spans,
                resourceAttributes: configuration.resourceAttributes
            )
        } catch {
            return .permanentFailure
        }

        let request = makeRequest(body: body, timeout: explicitTimeout)
        let attempts = 1 + configuration.maxRetries
        for attempt in 0 ..< attempts {
            let outcome: ExportClassification
            do {
                let (_, response) = try await session.data(for: request)
                outcome = classify(response: response)
            } catch {
                outcome = .transientFailure
            }
            guard outcome == .transientFailure, attempt + 1 < attempts else {
                return outcome
            }
            try? await Task.sleep(for: configuration.retryBackoff)
        }
        return .transientFailure
    }

    private func classify(response: URLResponse) -> ExportClassification {
        guard let http = response as? HTTPURLResponse else {
            return .transientFailure
        }
        if (200 ..< 300).contains(http.statusCode) {
            return .success
        }
        if (400 ..< 500).contains(http.statusCode) {
            return .permanentFailure
        }
        return .transientFailure
    }
}

private enum ExportClassification {
    case success
    case transientFailure
    case permanentFailure
}

/// A queued span plus how many flushes have already failed to deliver it.
private struct QueuedSpan: Sendable {
    let span: SpanData
    let failedExports: Int
}

/// Result handoff from the export `Task` to a blocked synchronous caller.
private final class ExportResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SpanExporterResultCode = .failure

    var value: SpanExporterResultCode {
        lock.withLock { stored }
    }

    func set(_ value: SpanExporterResultCode) {
        lock.withLock { stored = value }
    }
}

/// Registers a tracer provider that exports spans over OTLP/HTTP JSON.
public enum OpenTelemetryTracing {
    /// Installs ``OTLPHTTPTraceExporter`` as the process tracer provider.
    ///
    /// Uses ``SimpleSpanProcessor`` so the exporter owns batching. Call once
    /// during app startup.
    ///
    /// - Parameters:
    ///   - configuration: Endpoint, headers, batching, and retry settings.
    ///   - session: Session used for export POSTs.
    /// - Returns: The installed exporter (keep it if you need to ``SpanExporter/flush()``).
    @discardableResult
    public static func configureOTLPHTTPExport(
        configuration: OTLPHTTPExporterConfiguration = .default,
        session: URLSession = .shared
    ) -> OTLPHTTPTraceExporter {
        let exporter = OTLPHTTPTraceExporter(configuration: configuration, session: session)
        let processor = SimpleSpanProcessor(spanExporter: exporter)
        OpenTelemetry.registerTracerProvider(
            tracerProvider: TracerProviderBuilder()
                .add(spanProcessor: processor)
                .build()
        )
        return exporter
    }
}
#endif
