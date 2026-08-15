#if SWARM_INTEGRATIONS
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Swarm
import Testing

@Suite("WebSearchSupport")
struct WebSearchSupportTests {
    @Test("HTML parser prefers semantic content over boilerplate")
    func htmlParserExtractsStructuredSections() throws {
        let html = """
        <html>
          <head>
            <title>Install Swarm</title>
            <meta name="description" content="Install guide">
            <link rel="canonical" href="https://example.com/docs/install">
          </head>
          <body>
            <nav>Home Docs Pricing</nav>
            <main>
              <h1>Install</h1>
              <p>Run swift build to compile the package.</p>
              <h2>Usage</h2>
              <p>Use websearch in grounded mode for research tasks.</p>
            </main>
            <script>console.log('ignore me')</script>
          </body>
        </html>
        """

        let parsed = HTMLDocumentParser.parse(html, url: try #require(URL(string: "https://example.com/docs/install")))

        #expect(parsed.title == "Install Swarm")
        #expect(parsed.canonicalURL == "https://example.com/docs/install")
        #expect(parsed.description == "Install guide")
        #expect(parsed.sections.count == 2)
        #expect(parsed.sections[0].heading == "Install")
        #expect(parsed.sections[0].text.contains("Run swift build"))
        #expect(parsed.sections[0].text.contains("Home Docs Pricing") == false)
    }

    @Test("Web content extractor writes raw artifacts into the provided store root")
    func extractorUsesProvidedRawRoot() throws {
        let rawRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-web-extractor-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rawRoot.deletingLastPathComponent()) }

        let html = """
        <html>
          <head><title>API Reference</title></head>
          <body>
            <main>
              <h1>fetch()</h1>
              <p>Parameters are query and detail.</p>
              <pre><code>websearch(mode: "fetch", url: "...")</code></pre>
            </main>
          </body>
        </html>
        """

        let url = try #require(URL(string: "https://docs.example.com/reference/fetch"))
        let payload = WebFetchPayload(
            requestedURL: url,
            finalURL: url,
            statusCode: 200,
            contentType: "text/html; charset=utf-8",
            data: Data(html.utf8),
            etag: "etag-1",
            lastModified: nil,
            notModified: false
        )

        let stored = try WebContentExtractor().extract(
            payload: payload,
            goal: "fetch parameters",
            existingArtifactID: nil,
            rawRootURL: rawRoot
        )

        #expect(stored.artifact.pageType == .apiReference)
        #expect(stored.artifact.rawArtifactRef.hasPrefix(rawRoot.path))
        #expect(FileManager.default.fileExists(atPath: stored.artifact.rawArtifactRef))
        #expect(stored.document.sections.isEmpty == false)
        #expect(stored.document.summary.contains("Parameters"))
    }

    @Test("Web content extractor can skip raw byte persistence")
    func extractorCanSkipRawPersistence() throws {
        let rawRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-web-extractor-skip-raw-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rawRoot.deletingLastPathComponent()) }

        let url = try #require(URL(string: "https://docs.example.com/private"))
        let payload = WebFetchPayload(
            requestedURL: url,
            finalURL: url,
            statusCode: 200,
            contentType: "text/plain; charset=utf-8",
            data: Data("sensitive raw body".utf8),
            etag: nil,
            lastModified: nil,
            notModified: false
        )

        let stored = try WebContentExtractor().extract(
            payload: payload,
            goal: nil,
            existingArtifactID: nil,
            rawRootURL: nil
        )

        #expect(stored.artifact.rawArtifactRef.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: rawRoot.path))
    }

    @Test("Safe web fetcher rejects alternate loopback address forms before fetching")
    func fetcherRejectsAlternateLoopbackAddressForms() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-web-fetcher-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let configuration = WebSearchTool.Configuration(
            apiKey: nil,
            persistFetchedArtifacts: false,
            storeURL: root,
            enabled: true
        )
        let fetcher = SafeWebFetcher(configuration: configuration)
        let decimalLoopback = try #require(URL(string: "http://2130706433/secret"))

        await #expect(throws: AgentError.self) {
            _ = try await fetcher.fetch(
                url: decimalLoopback,
                conditionalEtag: nil,
                conditionalLastModified: nil
            )
        }
    }

    // FoundationNetworking on Linux asserts inside
    // `urlProtocol(_:wasRedirectedTo:redirectResponse:)`.
    #if !os(Linux)
    @Test("Safe web fetcher rejects private redirects before accepting body bytes")
    func fetcherRejectsPrivateRedirectBeforeBodyRead() async throws {
        RedirectWebFetchURLProtocol.reset()
        defer { RedirectWebFetchURLProtocol.reset() }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-web-final-url-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let configuration = WebSearchTool.Configuration(
            apiKey: nil,
            persistFetchedArtifacts: false,
            storeURL: root,
            enabled: true
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RedirectWebFetchURLProtocol.self]
        let fetcher = SafeWebFetcher(configuration: configuration, sessionConfiguration: sessionConfiguration)
        let publicURL = try #require(URL(string: "https://example.com/redirected"))

        await #expect(throws: AgentError.self) {
            _ = try await fetcher.fetch(
                url: publicURL,
                conditionalEtag: nil,
                conditionalLastModified: nil
            )
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(RedirectWebFetchURLProtocol.didLoadBody == false)
    }
    #endif

    @Test("Safe web fetcher injects current W3C traceparent")
    func fetcherInjectsTraceparent() async throws {
        TraceparentWebFetchURLProtocol.reset()
        defer { TraceparentWebFetchURLProtocol.reset() }

        let headers = try #require(
            TraceContextHeaders(
                traceId: "4bf92f3577b34da6a3ce929d0e0e4736",
                spanId: "00f067aa0ba902b7",
                tracestate: "rojo=00f067aa0ba902b7"
            )
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-web-traceparent-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let configuration = WebSearchTool.Configuration(
            apiKey: nil,
            persistFetchedArtifacts: false,
            storeURL: root,
            enabled: true
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [TraceparentWebFetchURLProtocol.self]
        let fetcher = SafeWebFetcher(configuration: configuration, sessionConfiguration: sessionConfiguration)
        let url = try #require(URL(string: "https://example.com/docs"))

        _ = try await TraceContextHeaders.withCurrent(headers) {
            try await fetcher.fetch(url: url, conditionalEtag: nil, conditionalLastModified: nil)
        }

        #expect(TraceparentWebFetchURLProtocol.traceparent == headers.traceparent)
        #expect(TraceparentWebFetchURLProtocol.tracestate == "rojo=00f067aa0ba902b7")
    }

    @Test("Safe web fetcher cancels URLSession task when caller cancels")
    func fetcherCancelsURLSessionTaskWhenCallerCancels() async throws {
        CancellableWebFetchURLProtocol.reset()
        defer { CancellableWebFetchURLProtocol.reset() }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-web-cancellation-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let configuration = WebSearchTool.Configuration(
            apiKey: nil,
            persistFetchedArtifacts: false,
            storeURL: root,
            enabled: true
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [CancellableWebFetchURLProtocol.self]
        let fetcher = SafeWebFetcher(configuration: configuration, sessionConfiguration: sessionConfiguration)
        let url = try #require(URL(string: "https://example.com/slow"))

        let fetchTask = Task {
            try await fetcher.fetch(url: url, conditionalEtag: nil, conditionalLastModified: nil)
        }
        for _ in 0 ..< 100 where !CancellableWebFetchURLProtocol.didStartLoading {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(CancellableWebFetchURLProtocol.didStartLoading)
        fetchTask.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await fetchTask.value
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(CancellableWebFetchURLProtocol.didStopLoading)
    }

    @Test("Safe web fetch body accumulator rejects overflow chunks before appending")
    func bodyAccumulatorRejectsOverflowBeforeAppend() throws {
        var accumulator = SafeWebBodyAccumulator()
        try accumulator.append(Data(repeating: 0x41, count: 5), maxBodyBytes: 5)

        #expect(accumulator.data.count == 5)
        #expect(throws: AgentError.self) {
            try accumulator.append(Data([0x42]), maxBodyBytes: 5)
        }
        #expect(accumulator.data == Data(repeating: 0x41, count: 5))
    }

    @Test("Merged hits prefer close cached results")
    func mergeHitsPrefersUsefulCachedHits() {
        let cached = WebSearchHit(
            id: "cached-1",
            title: "Cached Docs",
            url: "https://example.com/docs",
            snippet: "Cached result",
            score: 0.82,
            source: "wax",
            cached: true,
            artifactID: "artifact-1"
        )
        let remote = WebSearchHit(
            id: "remote-1",
            title: "Remote Docs",
            url: "https://example.com/docs?ref=search",
            snippet: "Remote result",
            score: 0.90,
            source: "tavily",
            cached: false
        )

        let merged = mergeHits(localHits: [cached], remoteHits: [remote], maxResults: 2)

        #expect(merged.first?.cached == true)
        #expect(merged.first?.artifactID == "artifact-1")
    }

    #if canImport(SQLite3)
    @Test("Saving a fetched artifact replaces old indexed sections")
    func savingArtifactReplacesIndexedSections() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-web-store-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let configuration = WebSearchTool.Configuration(
            apiKey: nil,
            persistFetchedArtifacts: true,
            storeURL: root,
            enabled: true
        )
        let store = try await WaxWebArtifactStore(configuration: configuration)
        let extractor = WebContentExtractor()
        let url = try #require(URL(string: "https://example.com/docs/install"))

        func payload(_ text: String, etag: String) -> WebFetchPayload {
            let html = """
            <html>
              <head><title>Install</title></head>
              <body>
                <main>
                  <h1>Install</h1>
                  <p>\(text)</p>
                </main>
              </body>
            </html>
            """
            return WebFetchPayload(
                requestedURL: url,
                finalURL: url,
                statusCode: 200,
                contentType: "text/html; charset=utf-8",
                data: Data(html.utf8),
                etag: etag,
                lastModified: nil,
                notModified: false
            )
        }

        let first = try extractor.extract(
            payload: payload("Initial instructions", etag: "etag-1"),
            goal: "install instructions",
            existingArtifactID: nil,
            rawRootURL: root.appendingPathComponent("raw", isDirectory: true)
        )
        let savedFirst = try await store.save(first)
        _ = try await store.save(
            extractor.extract(
                payload: payload("Updated instructions", etag: "etag-2"),
                goal: "updated instructions",
                existingArtifactID: savedFirst.artifact.artifactID,
                rawRootURL: root.appendingPathComponent("raw", isDirectory: true)
            )
        )

        let matches = try await store.searchSections(query: "updated instructions", topK: 10)
        #expect(matches.count == 1)
        #expect(matches.first?.section.text.contains("Updated instructions") == true)
    }
    #endif
}

private final class TraceparentWebFetchURLProtocol: URLProtocol {
    private static let state = TraceHeaderState()

    static var traceparent: String? { state.traceparent }
    static var tracestate: String? { state.tracestate }

    static func reset() {
        state.reset()
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.state.record(
            traceparent: request.value(forHTTPHeaderField: "traceparent"),
            tracestate: request.value(forHTTPHeaderField: "tracestate")
        )
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("<html><body>ok</body></html>".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class TraceHeaderState: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedTraceparent: String?
    private var recordedTracestate: String?

    var traceparent: String? { lock.withLock { recordedTraceparent } }
    var tracestate: String? { lock.withLock { recordedTracestate } }

    func record(traceparent: String?, tracestate: String?) {
        lock.withLock {
            recordedTraceparent = traceparent
            recordedTracestate = tracestate
        }
    }

    func reset() {
        lock.withLock {
            recordedTraceparent = nil
            recordedTracestate = nil
        }
    }
}

private final class RedirectWebFetchURLProtocol: URLProtocol {
    private static let state = BodyLoadState()

    static var didLoadBody: Bool {
        state.didLoadBody
    }

    static func reset() {
        state.reset()
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard request.url?.host != "127.0.0.1" else {
            Self.state.markBodyLoaded()
            client?.urlProtocol(self, didLoad: Data("private body".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        guard let redirectURL = URL(string: "http://127.0.0.1/private") else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let redirectRequest = URLRequest(url: redirectURL)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 302,
            httpVersion: nil,
            headerFields: ["Location": redirectURL.absoluteString]
        )!
        client?.urlProtocol(self, wasRedirectedTo: redirectRequest, redirectResponse: response)
    }

    override func stopLoading() {}
}

private final class BodyLoadState: @unchecked Sendable {
    private let lock = NSLock()
    private var bodyLoaded = false

    var didLoadBody: Bool {
        lock.withLock { bodyLoaded }
    }

    func markBodyLoaded() {
        lock.withLock { bodyLoaded = true }
    }

    func reset() {
        lock.withLock { bodyLoaded = false }
    }
}

private final class CancellableWebFetchURLProtocol: URLProtocol {
    private static let state = CancellationState()

    static var didStopLoading: Bool {
        state.didStopLoading
    }

    static var didStartLoading: Bool {
        state.didStartLoading
    }

    static func reset() {
        state.reset()
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.state.markStarted()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/plain"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    override func stopLoading() {
        Self.state.markStopped()
    }
}

private final class CancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var stopped = false

    var didStartLoading: Bool {
        lock.withLock { started }
    }

    var didStopLoading: Bool {
        lock.withLock { stopped }
    }

    func markStarted() {
        lock.withLock { started = true }
    }

    func markStopped() {
        lock.withLock { stopped = true }
    }

    func reset() {
        lock.withLock {
            started = false
            stopped = false
        }
    }
}
#endif
