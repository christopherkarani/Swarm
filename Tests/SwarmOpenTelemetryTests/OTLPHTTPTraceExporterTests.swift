import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import Testing
import Swarm
@testable import SwarmOpenTelemetry

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("OTLP/HTTP JSON exporter")
struct OTLPHTTPTraceExporterTests {
    @Test("Exports OTLP JSON with Swarm span attributes and resource overlay")
    func exportsOTLPJSONPayloadShape() async throws {
        let stub = OTLPRecordingURLProtocol.makeSession()
        defer { OTLPRecordingURLProtocol.reset() }

        let span = try await harvestSpan(
            name: "swarm.agent.run support-agent",
            attributes: [
                "swarm.agent.name": .string("support-agent"),
                "gen_ai.usage.input_tokens": .int(11),
                "gen_ai.usage.output_tokens": .int(7),
            ]
        )

        let exporter = OTLPHTTPTraceExporter(
            configuration: .default
                .endpoint(URL(string: "http://127.0.0.1:4318/v1/traces")!)
                .maxBatchSize(1)
                .scheduleDelay(.seconds(60))
                .headers(["Authorization": "Bearer collector-token"])
                .resourceAttributes(["service.name": "swarm-tests"]),
            session: stub
        )
        defer { exporter.shutdown() }

        OTLPRecordingURLProtocol.enqueue(status: 200)
        let result = await exporter.export(spans: [span])
        #expect(result == .success)

        let request = try #require(OTLPRecordingURLProtocol.requests.first)
        #expect(request.url?.absoluteString == "http://127.0.0.1:4318/v1/traces")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer collector-token")

        let payload = try #require(OTLPRecordingURLProtocol.bodies.first)
        let json = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let resourceSpans = try #require(json["resourceSpans"] as? [[String: Any]])
        #expect(resourceSpans.count == 1)

        let resource = try #require(resourceSpans[0]["resource"] as? [String: Any])
        let resourceAttrs = try #require(resource["attributes"] as? [[String: Any]])
        #expect(attribute(resourceAttrs, key: "service.name") == "swarm-tests")

        let scopeSpans = try #require(resourceSpans[0]["scopeSpans"] as? [[String: Any]])
        let spans = try #require(scopeSpans[0]["spans"] as? [[String: Any]])
        #expect(spans.count == 1)

        let exported = spans[0]
        #expect(exported["name"] as? String == "swarm.agent.run support-agent")
        #expect(exported["kind"] as? Int == 1)
        #expect((exported["traceId"] as? String)?.count == 32)
        #expect((exported["spanId"] as? String)?.count == 16)
        #expect(exported["startTimeUnixNano"] is String)
        #expect(exported["endTimeUnixNano"] is String)

        let status = try #require(exported["status"] as? [String: Any])
        #expect(status["code"] as? Int == 1)

        let attrs = try #require(exported["attributes"] as? [[String: Any]])
        #expect(attribute(attrs, key: "swarm.agent.name") == "support-agent")
        #expect(intAttribute(attrs, key: "gen_ai.usage.input_tokens") == "11")
        #expect(intAttribute(attrs, key: "gen_ai.usage.output_tokens") == "7")
    }

    @Test("Flushes when the batch size is reached and not before")
    func batchesBySize() async throws {
        let stub = OTLPRecordingURLProtocol.makeSession()
        defer { OTLPRecordingURLProtocol.reset() }

        let first = try await harvestSpan(name: "one")
        let second = try await harvestSpan(name: "two")

        let exporter = OTLPHTTPTraceExporter(
            configuration: .default
                .maxBatchSize(2)
                .scheduleDelay(.seconds(60)),
            session: stub
        )
        defer { exporter.shutdown() }

        OTLPRecordingURLProtocol.enqueue(status: 200)
        _ = await exporter.export(spans: [first])
        #expect(OTLPRecordingURLProtocol.requests.isEmpty)

        _ = await exporter.export(spans: [second])
        #expect(OTLPRecordingURLProtocol.requests.count == 1)

        let payload = try #require(OTLPRecordingURLProtocol.bodies.first)
        let names = try spanNames(in: payload)
        #expect(Set(names) == ["one", "two"])
    }

    @Test("Retries once on HTTP 500 and succeeds")
    func retriesOnceOn500() async throws {
        let stub = OTLPRecordingURLProtocol.makeSession()
        defer { OTLPRecordingURLProtocol.reset() }

        let span = try await harvestSpan(name: "retry-me")
        let exporter = OTLPHTTPTraceExporter(
            configuration: .default
                .maxBatchSize(1)
                .scheduleDelay(.seconds(60))
                .retryBackoff(.milliseconds(1)),
            session: stub
        )
        defer { exporter.shutdown() }

        OTLPRecordingURLProtocol.enqueue(status: 500)
        OTLPRecordingURLProtocol.enqueue(status: 200)

        let result = await exporter.export(spans: [span])
        #expect(result == .success)
        #expect(OTLPRecordingURLProtocol.requests.count == 2)
    }

    @Test("Does not retry on HTTP 400")
    func doesNotRetryOn400() async throws {
        let stub = OTLPRecordingURLProtocol.makeSession()
        defer { OTLPRecordingURLProtocol.reset() }

        let span = try await harvestSpan(name: "bad-request")
        let exporter = OTLPHTTPTraceExporter(
            configuration: .default
                .maxBatchSize(1)
                .scheduleDelay(.seconds(60))
                .retryBackoff(.milliseconds(1)),
            session: stub
        )
        defer { exporter.shutdown() }

        OTLPRecordingURLProtocol.enqueue(status: 400)

        let result = await exporter.export(spans: [span])
        #expect(result == .failure)
        #expect(OTLPRecordingURLProtocol.requests.count == 1)
    }
}

@Test("W3C traceparent matches the current LLM span and shares the agent trace")
func traceparentPropagatesAgentToOutboundHeaders() async throws {
    let recorder = RecordingSpanExporter()
    let tracerProvider = TracerProviderBuilder()
        .add(
            spanProcessor: SimpleSpanProcessor(spanExporter: recorder)
                .reportingOnlySampled(sampled: false)
        )
        .build()

    let capturing = HeaderCapturingProvider()
    let agent = HeaderCapturingAgent(provider: capturing)
        .instrumentedWithOpenTelemetry(
            tracer: tracerProvider.get(instrumentationName: "test.agent"),
            llmTracer: tracerProvider.get(instrumentationName: "test.llm")
        )

    _ = try await agent.run("hello")
    tracerProvider.forceFlush()

    let headers = try #require(capturing.headers())
    #expect(TraceContextHeaders.isValidTraceparent(headers.traceparent))
    #expect(headers.traceparent.wholeMatch(of: try Regex(TraceContextHeaders.traceparentPattern)) != nil)

    let spans = recorder.spans
    let agentSpan = try #require(spans.first { $0.name == "swarm.agent.run header-agent" })
    let llmSpan = try #require(spans.first { $0.name == "chat llm" })

    #expect(headers.traceId == agentSpan.traceId.hexString)
    #expect(headers.traceId == llmSpan.traceId.hexString)
    #expect(headers.spanId == llmSpan.spanId.hexString)
    #expect(llmSpan.parentSpanId == agentSpan.spanId)
}

private func harvestSpan(
    name: String,
    attributes: [String: AttributeValue] = [:]
) async throws -> SpanData {
    let recorder = RecordingSpanExporter()
    let provider = TracerProviderBuilder()
        .add(
            spanProcessor: SimpleSpanProcessor(spanExporter: recorder)
                .reportingOnlySampled(sampled: false)
        )
        .build()
    let tracer = provider.get(instrumentationName: "test.harvest")
    let builder = tracer.spanBuilder(spanName: name)
    builder.setSpanKind(spanKind: .internal)
    for (key, value) in attributes {
        builder.setAttribute(key: key, value: value)
    }
    builder.withActiveSpan { span in
        span.status = .ok
    }
    provider.forceFlush()
    return try #require(recorder.spans.first)
}

private func attribute(_ attributes: [[String: Any]], key: String) -> String? {
    guard let match = attributes.first(where: { $0["key"] as? String == key }),
          let value = match["value"] as? [String: Any]
    else {
        return nil
    }
    return value["stringValue"] as? String
}

private func intAttribute(_ attributes: [[String: Any]], key: String) -> String? {
    guard let match = attributes.first(where: { $0["key"] as? String == key }),
          let value = match["value"] as? [String: Any]
    else {
        return nil
    }
    return value["intValue"] as? String
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

private struct HeaderCapturingAgent: AgentRuntime {
    let provider: any InferenceProvider

    var tools: [any AnyJSONTool] { [] }
    var instructions: String { "test" }
    var configuration: AgentConfiguration { .default.name("header-agent") }
    var inferenceProvider: (any InferenceProvider)? { provider }

    func run(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) async throws -> AgentResult {
        let provider = AgentEnvironmentValues.current.inferenceProviderTransform?(provider) ?? provider
        _ = try await provider.generate(prompt: input, options: .default)
        return AgentResult(output: "done", iterationCount: 1)
    }

    func stream(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func cancel() async {}
}

private final class HeaderCapturingProvider: InferenceProvider, @unchecked Sendable {
    nonisolated(unsafe) private var captured: TraceContextHeaders?

    func headers() -> TraceContextHeaders? {
        captured
    }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        captured = TraceContextHeaders.current ?? OpenTelemetryTracePropagation.current
        return prompt
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(prompt)
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        InferenceResponse(content: prompt)
    }
}

private final class RecordingSpanExporter: SpanExporter, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SpanData] = []

    var spans: [SpanData] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        lock.lock()
        storage.append(contentsOf: spans)
        lock.unlock()
        return .success
    }

    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        .success
    }

    func shutdown(explicitTimeout: TimeInterval?) {}
}

private final class OTLPRecordingState: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []
    private var recordedBodies: [Data] = []
    private var statuses: [Int] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    var bodies: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return recordedBodies
    }

    func reset() {
        lock.lock()
        recordedRequests = []
        recordedBodies = []
        statuses = []
        lock.unlock()
    }

    func enqueue(status: Int) {
        lock.lock()
        statuses.append(status)
        lock.unlock()
    }

    func record(request: URLRequest, body: Data) -> Int {
        lock.lock()
        defer { lock.unlock() }
        recordedRequests.append(request)
        recordedBodies.append(body)
        return statuses.isEmpty ? 200 : statuses.removeFirst()
    }
}

private final class OTLPRecordingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let state = OTLPRecordingState()

    static var requests: [URLRequest] {
        state.requests
    }

    static var bodies: [Data] {
        state.bodies
    }

    static func reset() {
        state.reset()
    }

    static func enqueue(status: Int) {
        state.enqueue(status: status)
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OTLPRecordingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = Self.requestBody(from: request)
        let status = Self.state.record(request: request, body: body)

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1/v1/traces")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func requestBody(from request: URLRequest) -> Data {
        if let httpBody = request.httpBody {
            return httpBody
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: 1024)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }
}
