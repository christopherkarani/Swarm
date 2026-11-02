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
    }

    @Test("A full queue drops the oldest spans and counts them")
    func boundedQueueDropsOldest() async throws {
        let session = DeliveryURLProtocol.makeSession()
        defer { DeliveryURLProtocol.reset() }

        let exporter = OTLPHTTPTraceExporter(
            configuration: .default
                .maxBatchSize(100)
                .maxQueueSize(3)
                .scheduleDelay(.seconds(60)),
            session: session
        )
        for index in 1...5 {
            _ = await exporter.export(spans: [try makeSpan(name: "s\(index)")], explicitTimeout: nil)
        }

        #expect(exporter.queuedSpanCount == 3)
        #expect(exporter.droppedSpanCount == 2)

        #expect(await exporter.flush(explicitTimeout: nil) == .success)
        let body = try #require(DeliveryURLProtocol.bodies.last)
        #expect(try spanNames(in: body) == ["s3", "s4", "s5"])
        await exporter.shutdown(explicitTimeout: nil)
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
}

// MARK: - Helpers

private func makeSpan(name: String) throws -> SpanData {
    let recorder = DeliveryRecordingExporter()
    let provider = TracerProviderBuilder()
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

/// URLProtocol stub that can park responses until released.
///
/// State is guarded by `lock` (`@unchecked Sendable`). Parked requests are
/// released by ``release()`` or a 30-second safety timeout so a regression
/// cannot hang the suite.
private final class DeliveryURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var statuses: [Int] = []
    nonisolated(unsafe) private static var recordedBodies: [Data] = []
    nonisolated(unsafe) private static var responses = 0
    nonisolated(unsafe) private static var gate: DispatchSemaphore?

    static var bodies: [Data] {
        lock.withLock { recordedBodies }
    }

    static var responseCount: Int {
        lock.withLock { responses }
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
        lock.withLock {
            statuses = []
            recordedBodies = []
            responses = 0
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
        let parked = Self.lock.withLock { Self.gate }
        let url = request.url ?? URL(string: "http://localhost")!
        DispatchQueue.global().async { [self] in
            _ = parked?.wait(timeout: .now() + 30)
            let status = Self.lock.withLock {
                Self.recordedBodies.append(body)
                Self.responses += 1
                return Self.statuses.isEmpty ? 200 : Self.statuses.removeFirst()
            }
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
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
