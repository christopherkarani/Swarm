#if SWARM_OTEL
import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import Testing
@testable import SwarmOpenTelemetry

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Delivery semantics of ``OTLPHTTPTraceExporter``: non-blocking export,
/// bounded sync flush, bounded queue, and bounded requeue of failed spans.
@Suite("OTLP/HTTP exporter delivery", .serialized)
struct OTLPHTTPTraceExporterDeliveryTests {
    @Test("Synchronous export returns before the collector responds")
    func syncExportDoesNotWaitForNetwork() async throws {
        let session = DeliveryURLProtocol.makeSession()
        defer { DeliveryURLProtocol.reset() }
        DeliveryURLProtocol.hold()

        let exporter = OTLPHTTPTraceExporter(
            configuration: .default.maxBatchSize(1).scheduleDelay(.seconds(60)),
            session: session
        )
        let span = try makeSpan(name: "non-blocking")

        let result = await Task.detached {
            exporter.export(spans: [span], explicitTimeout: nil) as SpanExporterResultCode
        }.value

        #expect(result == .success)
        // The POST is still parked in the stub: export did not wait for it.
        #expect(DeliveryURLProtocol.responseCount == 0)

        DeliveryURLProtocol.release()
        await exporter.shutdown(explicitTimeout: nil)
        #expect(DeliveryURLProtocol.responseCount == 1)
    }

    @Test("Synchronous flush without an explicit timeout is bounded by syncTimeout")
    func syncFlushTimesOut() async throws {
        let session = DeliveryURLProtocol.makeSession()
        defer { DeliveryURLProtocol.reset() }
        DeliveryURLProtocol.hold()

        // No explicit timeout, so the URLRequest has no short timeout either:
        // only `syncTimeout` can bound the wait.
        let exporter = OTLPHTTPTraceExporter(
            configuration: .default
                .maxBatchSize(100)
                .syncTimeout(0.2)
                .scheduleDelay(.seconds(60)),
            session: session
        )
        _ = await exporter.export(spans: [try makeSpan(name: "slow")], explicitTimeout: nil)

        let result = await Task.detached {
            exporter.flush(explicitTimeout: nil) as SpanExporterResultCode
        }.value

        #expect(result == .failure)
        #expect(DeliveryURLProtocol.responseCount == 0)

        DeliveryURLProtocol.release()
        await exporter.shutdown(explicitTimeout: nil)
        #expect(DeliveryURLProtocol.responseCount == 1)
    }

    @Test("A full queue drops the oldest spans and counts them")
    func boundedQueueDropsOldest() async throws {
        let session = DeliveryURLProtocol.makeSession()
        defer { DeliveryURLProtocol.reset() }
        DeliveryURLProtocol.hold()

        let exporter = OTLPHTTPTraceExporter(
            configuration: .default
                .maxBatchSize(3)
                .maxQueueSize(3)
                .scheduleDelay(.seconds(60)),
            session: session
        )
        // s1...s3 start a size-triggered POST that stays parked in the stub.
        for index in 1...3 {
            _ = syncExport(exporter, [try makeSpan(name: "s\(index)")])
        }
        try await waitUntil { DeliveryURLProtocol.startCount == 1 }
        for index in 4...8 {
            _ = syncExport(exporter, [try makeSpan(name: "s\(index)")])
        }

        #expect(exporter.queuedSpanCount == 3)
        #expect(exporter.droppedSpanCount == 2)

        DeliveryURLProtocol.release()
        try await waitUntil { DeliveryURLProtocol.responseCount == 2 }
        let body = try #require(DeliveryURLProtocol.bodies.last)
        #expect(try spanNames(in: body) == ["s6", "s7", "s8"])
        await exporter.shutdown(explicitTimeout: nil)
    }

    @Test("maxQueueSize is never smaller than maxBatchSize")
    func queueSizeClampedToBatchSize() {
        #expect(OTLPHTTPExporterConfiguration(maxBatchSize: 100, maxQueueSize: 3).maxQueueSize == 100)
        #expect(OTLPHTTPExporterConfiguration.default.maxBatchSize(100).maxQueueSize(3).maxQueueSize == 100)
        #expect(OTLPHTTPExporterConfiguration.default.maxQueueSize(500).maxBatchSize(1000).maxQueueSize == 1000)
        #expect(OTLPHTTPExporterConfiguration.default.maxBatchSize(10).maxQueueSize(50).maxQueueSize == 50)
    }

    @Test("After a transient failure, size-triggered flushes wait for scheduleDelay")
    func sizeTriggeredFlushBacksOffAfterFailure() async throws {
        let session = DeliveryURLProtocol.makeSession()
        defer { DeliveryURLProtocol.reset() }
        DeliveryURLProtocol.enqueue(status: 503)

        let exporter = OTLPHTTPTraceExporter(
            configuration: .default
                .maxBatchSize(2)
                .maxRetries(0)
                .maxExportAttempts(10)
                .scheduleDelay(.seconds(60)),
            session: session
        )
        _ = syncExport(exporter, [try makeSpan(name: "a"), try makeSpan(name: "b")])
        try await waitUntil { DeliveryURLProtocol.responseCount == 1 && exporter.queuedSpanCount == 2 }

        // The requeued batch keeps the queue full, but a new export must not
        // immediately re-POST during the outage.
        _ = syncExport(exporter, [try makeSpan(name: "c"), try makeSpan(name: "d")])
        try await Task.sleep(for: .milliseconds(200))
        #expect(DeliveryURLProtocol.startCount == 1)
        #expect(exporter.queuedSpanCount == 4)

        // An explicit flush (like the timer) still retries.
        #expect(await exporter.flush(explicitTimeout: nil) == .success)
        let body = try #require(DeliveryURLProtocol.bodies.last)
        #expect(try spanNames(in: body) == ["a", "b", "c", "d"])
        await exporter.shutdown(explicitTimeout: nil)
    }

    @Test("Shutdown is not stalled by producers that keep the queue full")
    func shutdownIsNotStalledByProducers() async throws {
        let session = DeliveryURLProtocol.makeSession()
        defer { DeliveryURLProtocol.reset() }

        let exporter = OTLPHTTPTraceExporter(
            configuration: .default.maxBatchSize(1).scheduleDelay(.seconds(60)),
            session: session
        )
        var burst: [SpanData] = []
        for index in 0 ..< 50 {
            burst.append(try makeSpan(name: "p\(index)"))
        }
        let spans = burst
        let stop = DeliveryFlag()
        // Producer outpaces the one-span-per-POST drain loop for up to 4 s.
        let producer = Task.detached {
            let deadline = ContinuousClock.now + .seconds(4)
            while !stop.isSet, ContinuousClock.now < deadline {
                _ = syncExport(exporter, spans)
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
        try await waitUntil { DeliveryURLProtocol.startCount >= 1 }

        let start = ContinuousClock.now
        await exporter.shutdown(explicitTimeout: nil)
        let elapsed = ContinuousClock.now - start
        stop.set()
        await producer.value

        #expect(elapsed < .seconds(2))
    }

    @Test("Transiently failed spans are requeued and delivered by a later flush")
    func failedSpansAreRequeued() async throws {
        let session = DeliveryURLProtocol.makeSession()
        defer { DeliveryURLProtocol.reset() }

        let exporter = OTLPHTTPTraceExporter(
            configuration: .default
                .maxBatchSize(100)
                .maxRetries(0)
                .scheduleDelay(.seconds(60)),
            session: session
        )
        _ = await exporter.export(spans: [try makeSpan(name: "survivor")], explicitTimeout: nil)

        DeliveryURLProtocol.enqueue(status: 503)
        #expect(await exporter.flush(explicitTimeout: nil) == .failure)
        #expect(exporter.queuedSpanCount == 1)
        #expect(exporter.droppedSpanCount == 0)

        DeliveryURLProtocol.enqueue(status: 200)
        #expect(await exporter.flush(explicitTimeout: nil) == .success)
        #expect(exporter.queuedSpanCount == 0)
        let body = try #require(DeliveryURLProtocol.bodies.last)
        #expect(try spanNames(in: body) == ["survivor"])
        await exporter.shutdown(explicitTimeout: nil)
    }

    @Test("Requeueing is bounded by maxExportAttempts")
    func requeueIsBounded() async throws {
        let session = DeliveryURLProtocol.makeSession()
        defer { DeliveryURLProtocol.reset() }

        let exporter = OTLPHTTPTraceExporter(
            configuration: .default
                .maxBatchSize(100)
                .maxRetries(0)
                .maxExportAttempts(2)
                .scheduleDelay(.seconds(60)),
            session: session
        )
        _ = await exporter.export(spans: [try makeSpan(name: "doomed")], explicitTimeout: nil)

        DeliveryURLProtocol.enqueue(status: 500)
        DeliveryURLProtocol.enqueue(status: 500)
        #expect(await exporter.flush(explicitTimeout: nil) == .failure)
        #expect(await exporter.flush(explicitTimeout: nil) == .failure)

        #expect(exporter.queuedSpanCount == 0)
        #expect(exporter.droppedSpanCount == 1)
        await exporter.shutdown(explicitTimeout: nil)
    }

    @Test("Shutdown waits for a size-triggered batch already in flight")
    func shutdownWaitsForInFlightBatch() async throws {
        let session = DeliveryURLProtocol.makeSession()
        defer { DeliveryURLProtocol.reset() }
        DeliveryURLProtocol.hold()

        let exporter = OTLPHTTPTraceExporter(
            configuration: .default.maxBatchSize(2).scheduleDelay(.seconds(60)),
            session: session
        )
        let spans = [try makeSpan(name: "a"), try makeSpan(name: "b")]
        let result = await Task.detached {
            exporter.export(spans: spans, explicitTimeout: nil) as SpanExporterResultCode
        }.value
        #expect(result == .success)
        try await waitUntil { DeliveryURLProtocol.startCount == 1 }

        let finished = DeliveryFlag()
        let shutdown = Task {
            await exporter.shutdown(explicitTimeout: 5)
            finished.set()
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(!finished.isSet)

        DeliveryURLProtocol.release()
        await shutdown.value
        let body = try #require(DeliveryURLProtocol.bodies.first)
        #expect(try spanNames(in: body) == ["a", "b"])
    }

    @Test("Spans requeued by an in-flight batch are settled by shutdown")
    func requeueDuringShutdownIsSettled() async throws {
        let session = DeliveryURLProtocol.makeSession()
        defer { DeliveryURLProtocol.reset() }
        DeliveryURLProtocol.hold()
        DeliveryURLProtocol.enqueue(status: 503)

        let exporter = OTLPHTTPTraceExporter(
            configuration: .default
                .maxBatchSize(2)
                .maxRetries(0)
                .scheduleDelay(.seconds(60)),
            session: session
        )
        let spans = [try makeSpan(name: "a"), try makeSpan(name: "b")]
        _ = await Task.detached {
            exporter.export(spans: spans, explicitTimeout: nil) as SpanExporterResultCode
        }.value
        try await waitUntil { DeliveryURLProtocol.startCount == 1 }

        let shutdown = Task { await exporter.shutdown(explicitTimeout: 5) }
        try await Task.sleep(for: .milliseconds(100))
        DeliveryURLProtocol.release()
        await shutdown.value
        try await waitUntil { DeliveryURLProtocol.activeCount == 0 }

        #expect(exporter.queuedSpanCount == 0)
        let resent = try DeliveryURLProtocol.bodies.dropFirst().flatMap(spanNames(in:))
        #expect(exporter.droppedSpanCount == 2 || resent == ["a", "b"])

        // Nothing flushes after shutdown, so late spans are dropped and counted.
        let dropped = exporter.droppedSpanCount
        _ = syncExport(exporter, [try makeSpan(name: "late")])
        #expect(exporter.queuedSpanCount == 0)
        #expect(exporter.droppedSpanCount == dropped + 1)
    }

    @Test("SimpleSpanProcessor.forceFlush waits for a batch already in flight")
    func forceFlushWaitsForInFlightBatch() async throws {
        let session = DeliveryURLProtocol.makeSession()
        defer { DeliveryURLProtocol.reset() }
        DeliveryURLProtocol.hold()

        let exporter = OTLPHTTPTraceExporter(
            configuration: .default
                .maxBatchSize(2)
                .syncTimeout(5)
                .scheduleDelay(.seconds(60)),
            session: session
        )
        let processor = SimpleSpanProcessor(spanExporter: exporter)
        _ = syncExport(exporter, [try makeSpan(name: "f1"), try makeSpan(name: "f2")])
        try await waitUntil { DeliveryURLProtocol.startCount == 1 }

        let finished = DeliveryFlag()
        let flush = Task.detached {
            processor.forceFlush()
            finished.set()
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(!finished.isSet)

        DeliveryURLProtocol.release()
        await flush.value
        let body = try #require(DeliveryURLProtocol.bodies.first)
        #expect(try spanNames(in: body) == ["f1", "f2"])
        await exporter.shutdown(explicitTimeout: nil)
    }

    @Test("At most one size-triggered POST is in flight")
    func sizeTriggeredFlushIsSingleFlight() async throws {
        let session = DeliveryURLProtocol.makeSession()
        defer { DeliveryURLProtocol.reset() }
        DeliveryURLProtocol.hold()

        let exporter = OTLPHTTPTraceExporter(
            configuration: .default
                .maxBatchSize(2)
                .maxQueueSize(4)
                .scheduleDelay(.seconds(60)),
            session: session
        )
        var spans: [SpanData] = []
        for index in 0 ..< 40 {
            spans.append(try makeSpan(name: "s\(index)"))
        }
        for pair in stride(from: 0, to: 40, by: 2) {
            _ = syncExport(exporter, Array(spans[pair ..< pair + 2]))
        }
        try await waitUntil { DeliveryURLProtocol.startCount >= 1 }
        try await Task.sleep(for: .milliseconds(200))

        #expect(DeliveryURLProtocol.startCount == 1)
        #expect(exporter.queuedSpanCount <= 4)
        #expect(exporter.droppedSpanCount + exporter.queuedSpanCount + 2 == 40)

        DeliveryURLProtocol.release()
        try await waitUntil {
            exporter.queuedSpanCount < 2 && DeliveryURLProtocol.activeCount == 0
        }
        #expect(DeliveryURLProtocol.peakActiveCount == 1)
        for body in DeliveryURLProtocol.bodies {
            #expect(try spanNames(in: body).count <= 2)
        }

        await exporter.shutdown(explicitTimeout: nil)
        let delivered = try DeliveryURLProtocol.bodies.flatMap(spanNames(in:))
        #expect(delivered.count == 40 - exporter.droppedSpanCount)
    }
}

// MARK: - Helpers

/// Calls the synchronous `export` the SDK's span processors use; from an
/// `async` context the compiler would otherwise pick the `async` overload.
private func syncExport(_ exporter: OTLPHTTPTraceExporter, _ spans: [SpanData]) -> SpanExporterResultCode {
    exporter.export(spans: spans, explicitTimeout: nil)
}

/// Polls `condition` every 10 ms, recording an issue after `timeout`.
private func waitUntil(
    timeout: Duration = .seconds(5),
    _ condition: @Sendable () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// Thread-safe one-way flag for observing when a blocking call returns.
private final class DeliveryFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.withLock { value }
    }

    func set() {
        lock.withLock { value = true }
    }
}

private func makeSpan(name: String) throws -> SpanData {
    let recorder = DeliveryRecordingExporter()
    let provider = TracerProviderBuilder()
        // Ignore an inherited unsampled TRACEPARENT; the SDK uses it as the root parent.
        .with(sampler: Samplers.alwaysOn)
        .add(spanProcessor: SimpleSpanProcessor(spanExporter: recorder).reportingOnlySampled(sampled: false))
        .build()
    let builder = provider.get(instrumentationName: "test.delivery").spanBuilder(spanName: name)
    builder.withActiveSpan { span in
        span.status = .ok
    }
    provider.forceFlush()
    return try #require(recorder.spans.first)
}

private func spanNames(in payload: Data) throws -> [String] {
    let json = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
    let resourceSpans = try #require(json["resourceSpans"] as? [[String: Any]])
    var names: [String] = []
    for resource in resourceSpans {
        let scopeSpans = try #require(resource["scopeSpans"] as? [[String: Any]])
        for scope in scopeSpans {
            let spans = try #require(scope["spans"] as? [[String: Any]])
            names.append(contentsOf: spans.compactMap { $0["name"] as? String })
        }
    }
    return names
}

private final class DeliveryRecordingExporter: SpanExporter, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SpanData] = []

    var spans: [SpanData] {
        lock.withLock { storage }
    }

    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        lock.withLock { storage.append(contentsOf: spans) }
        return .success
    }

    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        .success
    }

    func shutdown(explicitTimeout: TimeInterval?) {}
}

/// Carries a loading `URLProtocol` and its client onto the response queue.
///
/// `@unchecked Sendable` because URLProtocol is not Sendable on Linux; the
/// client is only messaged once, from the single response closure.
private struct DeliveryLoading: @unchecked Sendable {
    let urlProtocol: URLProtocol
    let client: (any URLProtocolClient)?

    func respond(with response: HTTPURLResponse) {
        client?.urlProtocol(urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(urlProtocol, didLoad: Data())
        client?.urlProtocolDidFinishLoading(urlProtocol)
    }
}

/// URLProtocol stub that can park responses until released.
///
/// State is guarded by `lock` (`@unchecked Sendable`). Parked requests are
/// released by ``release()`` or a 30-second safety timeout so a regression
/// cannot hang the suite. ``reset()`` waits for active requests to finish so
/// a late response cannot leak into the next serialized test.
private final class DeliveryURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var statuses: [Int] = []
    nonisolated(unsafe) private static var recordedBodies: [Data] = []
    nonisolated(unsafe) private static var responses = 0
    nonisolated(unsafe) private static var started = 0
    nonisolated(unsafe) private static var active = 0
    nonisolated(unsafe) private static var peakActive = 0
    nonisolated(unsafe) private static var gate: DispatchSemaphore?

    static var bodies: [Data] {
        lock.withLock { recordedBodies }
    }

    static var responseCount: Int {
        lock.withLock { responses }
    }

    /// Requests that reached `startLoading`.
    static var startCount: Int {
        lock.withLock { started }
    }

    /// Requests started but not yet answered.
    static var activeCount: Int {
        lock.withLock { active }
    }

    /// Most requests that were ever active at once.
    static var peakActiveCount: Int {
        lock.withLock { peakActive }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeliveryURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func enqueue(status: Int) {
        lock.withLock { statuses.append(status) }
    }

    static func hold() {
        lock.withLock { gate = DispatchSemaphore(value: 0) }
    }

    static func release() {
        let parked = lock.withLock {
            let parked = gate
            gate = nil
            return parked
        }
        // Wake every parked request; extra signals are harmless.
        for _ in 0 ..< 16 {
            parked?.signal()
        }
    }

    static func reset() {
        release()
        let deadline = Date().addingTimeInterval(5)
        while activeCount > 0, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        lock.withLock {
            statuses = []
            recordedBodies = []
            responses = 0
            started = 0
            peakActive = 0
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = Self.readBody(of: request)
        let parked = Self.lock.withLock {
            Self.started += 1
            Self.active += 1
            Self.peakActive = max(Self.peakActive, Self.active)
            return Self.gate
        }
        let url = request.url ?? URL(string: "http://localhost")!
        // swift-corelibs-foundation marks URLProtocol's Sendable conformance
        // unavailable, so `self` cannot be captured in a @Sendable closure on
        // Linux. Hand the instance and its client over in a box instead.
        let loading = DeliveryLoading(urlProtocol: self, client: client)
        DispatchQueue.global().async {
            _ = parked?.wait(timeout: .now() + 30)
            // Leave `active` before answering: once the client sees the
            // response the exporter may start its next POST, which must not
            // count as overlapping this one.
            let status = DeliveryURLProtocol.lock.withLock {
                DeliveryURLProtocol.recordedBodies.append(body)
                DeliveryURLProtocol.responses += 1
                DeliveryURLProtocol.active -= 1
                return DeliveryURLProtocol.statuses.isEmpty ? 200 : DeliveryURLProtocol.statuses.removeFirst()
            }
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            loading.respond(with: response)
        }
    }

    override func stopLoading() {}

    private static func readBody(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
#endif
