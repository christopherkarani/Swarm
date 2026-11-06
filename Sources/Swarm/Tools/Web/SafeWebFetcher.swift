#if SWARM_INTEGRATIONS
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches public web pages for the web tool with SSRF protection.
///
/// Every request URL, redirect target and final response URL is checked with
/// ``validate(url:)``: IP literals are classified by their numeric value
/// (including IPv4 embedded in IPv6), non-canonical IPv4 spellings are refused,
/// and DNS names are resolved and refused when any address is non-public.
///
/// - Important: Validation resolves DNS separately from `URLSession`, which
///   performs its own lookup when it connects. A hostile DNS server with a
///   short TTL can therefore answer the validation lookup with a public address
///   and the connection lookup with a private one (DNS rebinding). Pinning the
///   connection to the validated address is not possible through `URLSession`
///   without breaking TLS server-name indication and certificate validation.
///   Deployments that must rule this out should route fetches through an
///   egress proxy or firewall that enforces the same policy at connect time.
internal struct SafeWebFetcher: Sendable {
    let configuration: WebSearchTool.Configuration
    private let sessionConfiguration: URLSessionConfiguration

    init(
        configuration: WebSearchTool.Configuration,
        sessionConfiguration: URLSessionConfiguration = .ephemeral
    ) {
        self.configuration = configuration
        self.sessionConfiguration = sessionConfiguration
    }

    func fetch(
        url: URL,
        conditionalEtag: String?,
        conditionalLastModified: String?
    ) async throws -> WebFetchPayload {
        try await Self.validateOffCooperativePool(url: url)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = configuration.fetchTimeout
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        TraceContextHeaders.applyCurrent(to: &request)
        if let conditionalEtag, !conditionalEtag.isEmpty {
            request.setValue(conditionalEtag, forHTTPHeaderField: "If-None-Match")
        }
        if let conditionalLastModified, !conditionalLastModified.isEmpty {
            request.setValue(conditionalLastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let fetchDelegate = SafeWebFetchDelegate(maxBodyBytes: configuration.maxBodyBytes)
        let session = URLSession(
            configuration: sessionConfiguration,
            delegate: fetchDelegate,
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        let data: Data
        let response: URLResponse
        (data, response) = try await fetchDelegate.fetch(request, using: session)
        guard let http = response as? HTTPURLResponse else {
            throw AgentError.toolFailure(toolName: "websearch", message: "Fetch returned a non-HTTP response", cause: nil)
        }
        try await Self.validateOffCooperativePool(url: http.url ?? url)

        if http.statusCode == 304 {
            return WebFetchPayload(
                requestedURL: url,
                finalURL: http.url ?? url,
                statusCode: http.statusCode,
                contentType: http.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream",
                data: Data(),
                etag: http.value(forHTTPHeaderField: "ETag"),
                lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
                notModified: true
            )
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            throw AgentError.toolFailure(
                toolName: "websearch",
                message: "Fetch failed for \(url.absoluteString) (HTTP \(http.statusCode))",
                cause: nil
            )
        }

        guard data.count <= configuration.maxBodyBytes else {
            throw AgentError.toolFailure(
                toolName: "websearch",
                message: "Fetched body exceeded limit of \(configuration.maxBodyBytes) bytes",
                cause: nil
            )
        }

        return WebFetchPayload(
            requestedURL: url,
            finalURL: http.url ?? url,
            statusCode: http.statusCode,
            contentType: http.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream",
            data: data,
            etag: http.value(forHTTPHeaderField: "ETag"),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
            notModified: false
        )
    }

    fileprivate static func isAllowedURL(_ url: URL) -> Bool {
        do {
            try validate(url: url)
            return true
        } catch {
            return false
        }
    }

    /// ``validate(url:)`` runs a blocking `getaddrinfo`. From async code it
    /// goes through ``BlockingWorkQueue`` so DNS latency cannot pin a
    /// cooperative-pool thread. URLSession delegate callbacks already run on
    /// the session's delegate queue and call ``isAllowedURL(_:)`` directly.
    private static func validateOffCooperativePool(url: URL) async throws {
        try await BlockingWorkQueue.run { try validate(url: url) }
    }

    /// Rejects URLs whose scheme is not http(s) or whose host is, or resolves
    /// to, a loopback, private, link-local, multicast or otherwise non-public
    /// address.
    static func validate(url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw AgentError.invalidToolArguments(toolName: "websearch", reason: "Only http/https URLs are allowed")
        }

        guard let host = url.host?.lowercased(), !host.isEmpty else {
            throw AgentError.invalidToolArguments(toolName: "websearch", reason: "URL must include a valid host")
        }

        if host == "localhost" || host == "::1" || host == "[::1]" || host.hasPrefix("127.") {
            throw AgentError.invalidToolArguments(toolName: "websearch", reason: "Loopback hosts are blocked")
        }

        if host.hasPrefix("10.") || host.hasPrefix("192.168.") || host.hasPrefix("169.254.") {
            throw AgentError.invalidToolArguments(toolName: "websearch", reason: "Private-network hosts are blocked")
        }

        if host.hasPrefix("172.") {
            let octets = host.split(separator: ".")
            if octets.count >= 2, let second = Int(octets[1]), (16 ... 31).contains(second) {
                throw AgentError.invalidToolArguments(toolName: "websearch", reason: "Private-network hosts are blocked")
            }
        }

        let addresses = try ResolvedHostAddress.resolve(host: host)
        if addresses.contains(where: \.isBlockedForFetch) {
            throw AgentError.invalidToolArguments(toolName: "websearch", reason: "Private-network hosts are blocked")
        }
    }
}

private final class SafeWebFetchDelegate: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let maxBodyBytes: Int
    private let state = SafeWebFetchDelegateState()

    init(maxBodyBytes: Int) {
        self.maxBodyBytes = maxBodyBytes
    }

    func fetch(_ request: URLRequest, using session: URLSession) async throws -> (Data, URLResponse) {
        let task = SafeWebFetchTask(session.dataTask(with: request))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.start(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
            state.finish(throwing: CancellationError())
        }
    }

    func urlSession(
        _: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let url = response.url, SafeWebFetcher.isAllowedURL(url) else {
            state.finish(
                throwing: AgentError.invalidToolArguments(
                    toolName: "websearch",
                    reason: "Private-network hosts are blocked"
                )
            )
            dataTask.cancel()
            completionHandler(.cancel)
            return
        }
        state.receive(response: response)
        completionHandler(.allow)
    }

    func urlSession(
        _: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        do {
            try state.receive(data: data, maxBodyBytes: maxBodyBytes)
        } catch {
            state.finish(throwing: error)
            dataTask.cancel()
        }
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            state.finish(throwing: error)
        } else {
            state.finish()
        }
    }

    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, SafeWebFetcher.isAllowedURL(url) else {
            state.finish(
                throwing: AgentError.invalidToolArguments(
                    toolName: "websearch",
                    reason: "Private-network hosts are blocked"
                )
            )
            task.cancel()
            completionHandler(nil)
            return
        }
        var redirected = request
        TraceContextHeaders.applyCurrent(to: &redirected)
        completionHandler(redirected)
    }
}

private final class SafeWebFetchTask: @unchecked Sendable {
    private let task: URLSessionDataTask

    init(_ task: URLSessionDataTask) {
        self.task = task
    }

    func resume() {
        task.resume()
    }

    func cancel() {
        task.cancel()
    }
}

private final class SafeWebFetchDelegateState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var response: URLResponse?
    private var accumulator = SafeWebBodyAccumulator()
    private var isFinished = false
    private var finishedResult: Result<(Data, URLResponse), Error>?

    func start(_ continuation: CheckedContinuation<(Data, URLResponse), Error>) {
        let result: Result<(Data, URLResponse), Error>? = lock.withLock {
            if isFinished {
                return finishedResult ?? .failure(CancellationError())
            }
            self.continuation = continuation
            return nil
        }

        if let result {
            Self.resume(continuation, with: result)
        }
    }

    func receive(response: URLResponse) {
        lock.withLock {
            self.response = response
        }
    }

    func receive(data newData: Data, maxBodyBytes: Int) throws {
        try lock.withLock {
            try accumulator.append(newData, maxBodyBytes: maxBodyBytes)
        }
    }

    func finish() {
        let result: Result<(Data, URLResponse), Error> = lock.withLock {
            guard isFinished == false else { return .failure(SafeWebFetchCompletion.alreadyFinished) }
            isFinished = true
            guard let response else {
                let result: Result<(Data, URLResponse), Error> = .failure(
                    AgentError.toolFailure(
                        toolName: "websearch",
                        message: "Fetch returned no response",
                        cause: nil
                    )
                )
                finishedResult = result
                return result
            }
            let result: Result<(Data, URLResponse), Error> = .success((accumulator.data, response))
            finishedResult = result
            return result
        }
        resume(with: result)
    }

    func finish(throwing error: Error) {
        let result: Result<(Data, URLResponse), Error> = lock.withLock {
            guard isFinished == false else { return .failure(SafeWebFetchCompletion.alreadyFinished) }
            isFinished = true
            let result: Result<(Data, URLResponse), Error> = .failure(error)
            finishedResult = result
            return result
        }
        resume(with: result)
    }

    private func resume(with result: Result<(Data, URLResponse), Error>) {
        let continuation = lock.withLock {
            let current = self.continuation
            self.continuation = nil
            return current
        }
        guard let continuation else { return }
        Self.resume(continuation, with: result)
    }

    private static func resume(
        _ continuation: CheckedContinuation<(Data, URLResponse), Error>,
        with result: Result<(Data, URLResponse), Error>
    ) {
        switch result {
        case let .success(value):
            continuation.resume(returning: value)
        case let .failure(error):
            if (error as? SafeWebFetchCompletion) == .alreadyFinished {
                return
            }
            continuation.resume(throwing: error)
        }
    }
}

private enum SafeWebFetchCompletion: Error {
    case alreadyFinished
}

internal struct SafeWebBodyAccumulator: Sendable {
    private(set) var data = Data()

    mutating func append(_ newData: Data, maxBodyBytes: Int) throws {
        let nextCount = data.count + newData.count
        guard nextCount <= maxBodyBytes else {
            throw AgentError.toolFailure(
                toolName: "websearch",
                message: "Fetched body exceeded limit of \(maxBodyBytes) bytes",
                cause: nil
            )
        }
        data.append(newData)
    }
}
#endif
