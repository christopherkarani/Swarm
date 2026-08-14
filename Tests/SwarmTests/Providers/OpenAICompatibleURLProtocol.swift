// OpenAICompatibleURLProtocol.swift
// SwarmTests
//
// URLProtocol stub for OpenAI-compatible HTTP tests.

import Foundation
@testable import Swarm

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class OpenAICompatibleURLProtocol: URLProtocol {
    struct EnqueuedResponse: Sendable {
        var status: Int
        var headers: [String: String]
        var body: Data
    }

    struct RecordedRequest: Sendable {
        var url: URL?
        var method: String?
        var headers: [String: String]
        var body: Data
    }

    private static let state = OpenAICompatibleURLProtocolState()

    static var requests: [RecordedRequest] {
        state.requests
    }

    static func reset() {
        state.reset()
    }

    static func enqueue(
        status: Int = 200,
        headers: [String: String] = ["Content-Type": "application/json"],
        json: String
    ) {
        enqueue(status: status, headers: headers, body: Data(json.utf8))
    }

    static func enqueue(
        status: Int = 200,
        headers: [String: String] = ["Content-Type": "application/json"],
        body: Data
    ) {
        state.enqueue(EnqueuedResponse(status: status, headers: headers, body: body))
    }

    static func enqueueSSE(_ events: String, status: Int = 200) {
        enqueue(
            status: status,
            headers: ["Content-Type": "text/event-stream"],
            body: Data(events.utf8)
        )
    }

    static func handle(_ handler: @escaping @Sendable (URLRequest, Data) -> EnqueuedResponse) {
        state.setHandler(handler)
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAICompatibleURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = request.httpBody
            ?? request.httpBodyStream.flatMap { Self.readAll(from: $0) }
            ?? Data()

        let recorded = RecordedRequest(
            url: request.url,
            method: request.httpMethod,
            headers: request.allHTTPHeaderFields ?? [:],
            body: body
        )
        let response = Self.state.record(recorded, request: request, body: body)

        let url = request.url ?? URL(string: "https://example.invalid")!
        let http = HTTPURLResponse(
            url: url,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readAll(from stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class OpenAICompatibleURLProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [OpenAICompatibleURLProtocol.EnqueuedResponse] = []
    private var recorded: [OpenAICompatibleURLProtocol.RecordedRequest] = []
    private var dynamicHandler: (@Sendable (URLRequest, Data) -> OpenAICompatibleURLProtocol.EnqueuedResponse)?

    var requests: [OpenAICompatibleURLProtocol.RecordedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func reset() {
        lock.lock()
        queued = []
        recorded = []
        dynamicHandler = nil
        lock.unlock()
    }

    func enqueue(_ response: OpenAICompatibleURLProtocol.EnqueuedResponse) {
        lock.lock()
        queued.append(response)
        lock.unlock()
    }

    func setHandler(
        _ handler: @escaping @Sendable (URLRequest, Data) -> OpenAICompatibleURLProtocol.EnqueuedResponse
    ) {
        lock.lock()
        dynamicHandler = handler
        lock.unlock()
    }

    func record(
        _ recordedRequest: OpenAICompatibleURLProtocol.RecordedRequest,
        request: URLRequest,
        body: Data
    ) -> OpenAICompatibleURLProtocol.EnqueuedResponse {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(recordedRequest)
        if let handler = dynamicHandler {
            return handler(request, body)
        }
        if !queued.isEmpty {
            return queued.removeFirst()
        }
        return OpenAICompatibleURLProtocol.EnqueuedResponse(
            status: 500,
            headers: ["Content-Type": "application/json"],
            body: Data(#"{"error":{"message":"no stubbed response"}}"#.utf8)
        )
    }
}

enum OpenAICompatibleJSON {
    static func object(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.generationFailed(reason: "stub body is not a JSON object")
        }
        return object
    }
}
