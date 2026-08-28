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
/// Queue and timer state are guarded by `lock`. `@unchecked Sendable` is
/// required because `SpanExporter` is invoked from the SDK's export queue.
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

    public func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        enqueue(spans)
        if pendingCount() >= configuration.maxBatchSize {
            return flush(explicitTimeout: explicitTimeout)
        }
        return .success
    }

    public func export(spans: [SpanData], explicitTimeout: TimeInterval?) async -> SpanExporterResultCode {
        enqueue(spans)
        if pendingCount() >= configuration.maxBatchSize {
            return await flush(explicitTimeout: explicitTimeout)
        }
        return .success
    }

    public func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        let spans = drain()
        guard !spans.isEmpty else { return .success }
        return postSync(spans: spans, explicitTimeout: explicitTimeout)
    }

    public func flush(explicitTimeout: TimeInterval?) async -> SpanExporterResultCode {
        let spans = drain()
        guard !spans.isEmpty else { return .success }
        return await post(spans: spans, explicitTimeout: explicitTimeout)
    }

    public func shutdown(explicitTimeout: TimeInterval?) {
        flushTask?.cancel()
        flushTask = nil
        _ = flush(explicitTimeout: explicitTimeout)
    }

    public func shutdown(explicitTimeout: TimeInterval?) async {
        flushTask?.cancel()
        flushTask = nil
        _ = await flush(explicitTimeout: explicitTimeout)
    }

    private let session: URLSession
    private let lock = NSLock()
    private var pending: [SpanData] = []
    private var flushTask: Task<Void, Never>?

    private func startTimer() {
        let delay = configuration.scheduleDelay
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { break }
                _ = await self?.flush(explicitTimeout: nil)
            }
        }
    }

    private func enqueue(_ spans: [SpanData]) {
        lock.lock()
        pending.append(contentsOf: spans)
        lock.unlock()
    }

    private func pendingCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }

    private func drain() -> [SpanData] {
        lock.lock()
        defer { lock.unlock() }
        let spans = pending
        pending = []
        return spans
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

    private func post(spans: [SpanData], explicitTimeout: TimeInterval?) async -> SpanExporterResultCode {
        let body: Data
        do {
            body = try OTLPJSON.payload(
                spans: spans,
                resourceAttributes: configuration.resourceAttributes
            )
        } catch {
            return .failure
        }

        let request = makeRequest(body: body, timeout: explicitTimeout)
        let attempts = 1 + configuration.maxRetries
        for attempt in 0 ..< attempts {
            do {
                let (_, response) = try await session.data(for: request)
                switch classify(response: response, error: nil) {
                case .success:
                    return .success
                case .permanentFailure:
                    return .failure
                case .transientFailure:
                    if attempt + 1 < attempts {
                        try? await Task.sleep(for: configuration.retryBackoff)
                    }
                }
            } catch {
                if attempt + 1 < attempts {
                    try? await Task.sleep(for: configuration.retryBackoff)
                } else {
                    return .failure
                }
            }
        }
        return .failure
    }

    private func postSync(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        let box = ExportResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            box.value = await post(spans: spans, explicitTimeout: explicitTimeout)
            semaphore.signal()
        }
        semaphore.wait()
        return box.value
    }

    private func classify(response: URLResponse, error: Error?) -> ExportClassification {
        if error != nil {
            return .transientFailure
        }
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

private final class ExportResultBox: @unchecked Sendable {
    var value: SpanExporterResultCode = .failure
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
