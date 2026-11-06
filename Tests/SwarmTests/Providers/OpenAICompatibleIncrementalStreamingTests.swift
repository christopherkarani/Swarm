import Foundation
@testable import Swarm
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("OpenAI-compatible incremental SSE streaming", .serialized)
struct OpenAICompatibleIncrementalStreamingTests {
    private let endpoint = URL(string: "https://api.example.test/v1")!

    // swift-corelibs-foundation buffers the SSE body (no reliable
    // `bytes(for:)`), so incremental delivery is only asserted on Darwin.
    #if !canImport(FoundationNetworking)
    @Test("First token is yielded before the response body completes")
    func firstTokenArrivesBeforeBodyCompletes() async throws {
        let gate = GatedSSEURLProtocol.install(
            head: #"data: {"choices":[{"delta":{"content":"first"}}]}"# + "\n\n",
            tail: #"data: {"choices":[{"delta":{"content":"second"}}]}"# + "\n\ndata: [DONE]\n\n"
        )
        defer { GatedSSEURLProtocol.uninstall() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GatedSSEURLProtocol.self]
        let provider = OpenAICompatibleProvider(
            configuration: .init(baseURL: endpoint, apiKey: "sk-test", model: "gpt-test"),
            session: URLSession(configuration: configuration)
        )

        let stream = provider.stream(messages: [.user("Hi")], options: .default)
        var iterator = stream.makeAsyncIterator()

        let first = try await iterator.next()
        #expect(first == "first")
        #expect(gate.isOpen == false)
        #expect(gate.didTimeOut == false, "first token must arrive while the body is still open")

        gate.open()
        var rest: [String] = []
        while let chunk = try await iterator.next() {
            rest.append(chunk)
        }
        #expect(rest == ["second"])
    }
    #endif

    @Test("Invalid UTF-8 in the SSE body throws instead of completing empty")
    func invalidUTF8Throws() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }
        var body = Data("data: {\"choices\":[{\"delta\":{\"content\":\"".utf8)
        body.append(contentsOf: [0xFF, 0xFE, 0xC3])
        body.append(contentsOf: Data("\"}}]}\n\ndata: [DONE]\n\n".utf8))
        OpenAICompatibleURLProtocol.enqueue(
            headers: ["Content-Type": "text/event-stream"],
            body: body
        )

        let provider = OpenAICompatibleProvider(
            configuration: .init(baseURL: endpoint, apiKey: "sk-test", model: "gpt-test"),
            session: OpenAICompatibleURLProtocol.makeSession()
        )

        await #expect(throws: AgentError.self) {
            for try await _ in provider.stream(messages: [.user("Hi")], options: .default) {}
        }
    }
}

#if !canImport(FoundationNetworking)
/// Serves an SSE head immediately and holds the tail until ``Gate/open()``.
private final class GatedSSEURLProtocol: URLProtocol, @unchecked Sendable {
    final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private let semaphore = DispatchSemaphore(value: 0)
        private var opened = false
        private var timedOut = false

        var isOpen: Bool {
            lock.withLock { opened }
        }

        /// `true` when the tail was released by the timeout instead of ``open()``.
        var didTimeOut: Bool {
            lock.withLock { timedOut }
        }

        func open() {
            lock.withLock { opened = true }
            semaphore.signal()
        }

        /// Waits for ``open()``; gives up after `timeout` so a buffering
        /// regression fails instead of hanging the suite.
        func wait(timeout: DispatchTime) {
            if semaphore.wait(timeout: timeout) == .timedOut {
                lock.withLock { timedOut = true }
            }
        }
    }

    private struct Script: Sendable {
        let head: Data
        let tail: Data
        let gate: Gate
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var script: Script?

    static func install(head: String, tail: String) -> Gate {
        let gate = Gate()
        lock.withLock {
            script = Script(head: Data(head.utf8), tail: Data(tail.utf8), gate: gate)
        }
        return gate
    }

    static func uninstall() {
        lock.withLock { script = nil }
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let script = Self.lock.withLock({ Self.script }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: script.head)
        DispatchQueue.global().async {
            script.gate.wait(timeout: .now() + 3)
            self.client?.urlProtocol(self, didLoad: script.tail)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
#endif
