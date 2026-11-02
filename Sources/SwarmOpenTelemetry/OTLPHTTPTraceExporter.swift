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
///   network. At most one size-triggered flush runs at a time: it posts
///   batches of at most `maxBatchSize` spans one after another and stops at
///   the first failure, so a struggling collector sees one connection.
/// - The queue holds at most ``OTLPHTTPExporterConfiguration/maxQueueSize``
///   spans, not counting batches already being posted. When full, the oldest
///   spans are dropped and counted in ``droppedSpanCount``.
/// - A batch that fails transiently (5xx or network error, after
///   ``OTLPHTTPExporterConfiguration/maxRetries``) is requeued for the next
///   flush, up to ``OTLPHTTPExporterConfiguration/maxExportAttempts`` flushes
///   per span; spans that exhaust it, or that the collector rejects with 4xx,
///   are dropped and counted.
/// - `flush` and `shutdown` first wait for POSTs already in flight, then post
///   whatever is still queued (including spans those POSTs requeued). The
///   size-triggered flush keeps posting while a full batch is queued, so
///   under sustained load the `async` `flush`/`shutdown` (and the `async`
///   `export` that started that flush) can wait for as long as producers keep
///   the queue full; they have no timeout of their own.
/// - The synchronous `flush`/`shutdown` required by `SpanExporter` wait for
///   that work for at most `explicitTimeout` (default
///   ``OTLPHTTPExporterConfiguration/syncTimeout``) and return `.failure` on
///   timeout; the POST keeps running in the background and requeues on
///   failure. Prefer the `async` overloads from Swift concurrency code: the
///   synchronous ones block their calling thread for up to that timeout.
/// - After `shutdown` completes, nothing flushes again: spans still queued,
///   requeued, or exported later are dropped and counted.
///
/// Queue, timer, in-flight, and counter state are guarded by `lock`. `@unchecked Sendable`
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

    /// Enqueues spans without blocking; a full batch starts a background flush
    /// unless one is already running.
    public func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        if enqueue(spans) {
            _ = track { [self] in await drainBatches(explicitTimeout: explicitTimeout) }
        }
        return .success
    }

    /// Enqueues spans; when this call starts the size-triggered flush, it
    /// awaits that flush before returning.
    public func export(spans: [SpanData], explicitTimeout: TimeInterval?) async -> SpanExporterResultCode {
        if enqueue(spans) {
            return await track { [self] in await drainBatches(explicitTimeout: explicitTimeout) }.value
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
        waitBounded(explicitTimeout: explicitTimeout) { [self] in
            await flushAll(explicitTimeout: explicitTimeout)
        }
    }

    /// Awaits POSTs already in flight, then flushes queued spans, awaiting the
    /// POST (including retries).
    public func flush(explicitTimeout: TimeInterval?) async -> SpanExporterResultCode {
        await flushAll(explicitTimeout: explicitTimeout)
    }

    /// Stops the flush timer and flushes, bounded like ``flush(explicitTimeout:)``.
    public func shutdown(explicitTimeout: TimeInterval?) {
        stopTimer()
        _ = waitBounded(explicitTimeout: explicitTimeout) { [self] in
            await finalFlush(explicitTimeout: explicitTimeout)
            return .success
        }
    }

    /// Stops the flush timer and awaits a final flush.
    public func shutdown(explicitTimeout: TimeInterval?) async {
        stopTimer()
        await finalFlush(explicitTimeout: explicitTimeout)
    }

    private let session: URLSession
    private let lock = NSLock()
    private var pending: [QueuedSpan] = []
    private var dropped = 0
    private var flushTask: Task<Void, Never>?
    /// Every running POST task, so `flush`/`shutdown` can await them.
    private var inFlight: [UUID: Task<SpanExporterResultCode, Never>] = [:]
    /// Whether the size-triggered flush loop is running.
    private var isFlushing = false
    /// Set once `shutdown` finished its final flush; nothing flushes afterwards.
    private var isShutDown = false

    /// Runs `operation` on a `Task` and blocks for at most `explicitTimeout`
    /// (default ``OTLPHTTPExporterConfiguration/syncTimeout``).
    /// - Returns: The operation's result, or `.failure` on timeout.
    private func waitBounded(
        explicitTimeout: TimeInterval?,
        _ operation: @escaping @Sendable () async -> SpanExporterResultCode
    ) -> SpanExporterResultCode {
        let timeout = explicitTimeout ?? configuration.syncTimeout
        let box = ExportResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            box.set(await operation())
            semaphore.signal()
        }
        // DispatchTime arithmetic traps on non-finite intervals; cap at one day.
        let seconds = timeout.isNaN ? 0 : min(max(0, timeout), 86_400)
        guard semaphore.wait(timeout: .now() + seconds) == .success else {
            return .failure
        }
        return box.value
    }

    /// Starts `operation` on a `Task` registered in `inFlight` until it ends.
    private func track(
        _ operation: @escaping @Sendable () async -> SpanExporterResultCode
    ) -> Task<SpanExporterResultCode, Never> {
        lock.withLock { startTracked(operation) }
    }

    /// Starts `operation` on a `Task` registered in `inFlight`. Caller holds
    /// `lock`, so the task's own removal (which takes `lock`) always runs
    /// after this insertion.
    private func startTracked(
        _ operation: @escaping @Sendable () async -> SpanExporterResultCode
    ) -> Task<SpanExporterResultCode, Never> {
        let id = UUID()
        let task = Task { [self] in
            let result = await operation()
            lock.withLock { inFlight[id] = nil }
            return result
        }
        inFlight[id] = task
        return task
    }

    /// Awaits every POST in flight when called.
    private func awaitInFlight() async {
        let tasks = lock.withLock { Array(inFlight.values) }
        for task in tasks {
            _ = await task.value
        }
    }

    /// Awaits in-flight POSTs, then posts everything still queued.
    private func flushAll(explicitTimeout: TimeInterval?) async -> SpanExporterResultCode {
        await awaitInFlight()
        // Drain and register under one `lock` hold, so a concurrent flush's
        // `awaitInFlight` never misses spans that left `pending`.
        let task: Task<SpanExporterResultCode, Never>? = lock.withLock {
            let batch = pending
            guard !batch.isEmpty else { return nil }
            pending = []
            return startTracked { [self] in await send(batch, explicitTimeout: explicitTimeout) }
        }
        return await task?.value ?? .success
    }

    /// Flushes, then marks the exporter shut down and drops anything left
    /// (for example spans requeued by a final POST that failed).
    private func finalFlush(explicitTimeout: TimeInterval?) async {
        _ = await flushAll(explicitTimeout: explicitTimeout)
        await awaitInFlight()
        lock.withLock {
            isShutDown = true
            dropped += pending.count
            pending = []
        }
    }

    /// The size-triggered flush loop. Posts batches of at most `maxBatchSize`
    /// one at a time while a full batch is queued, stopping at the first
    /// failure so a failing collector is not hammered.
    private func drainBatches(explicitTimeout: TimeInterval?) async -> SpanExporterResultCode {
        var result = SpanExporterResultCode.success
        while true {
            let batch: [QueuedSpan]? = lock.withLock {
                guard result == .success, !isShutDown, pending.count >= configuration.maxBatchSize else {
                    isFlushing = false
                    return nil
                }
                let batch = Array(pending.prefix(configuration.maxBatchSize))
                pending.removeFirst(batch.count)
                return batch
            }
            guard let batch else { return result }
            result = await send(batch, explicitTimeout: explicitTimeout)
        }
    }

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

    /// Appends spans, dropping the oldest beyond `maxQueueSize`. After
    /// shutdown the spans are dropped instead.
    /// - Returns: Whether the caller must start the size-triggered flush: the
    ///   queue reached `maxBatchSize` and no flush loop was running (this call
    ///   claimed it).
    private func enqueue(_ spans: [SpanData]) -> Bool {
        lock.withLock {
            guard !isShutDown else {
                dropped += spans.count
                return false
            }
            pending.append(contentsOf: spans.map { QueuedSpan(span: $0, failedExports: 0) })
            trimToCapacity()
            guard pending.count >= configuration.maxBatchSize, !isFlushing else {
                return false
            }
            isFlushing = true
            return true
        }
    }

    /// Requeues a transiently failed batch ahead of newer spans. After
    /// shutdown nothing would flush them again, so they are dropped instead.
    private func requeue(_ batch: [QueuedSpan]) {
        lock.withLock {
            guard !isShutDown else {
                dropped += batch.count
                return
            }
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
