// HTTPMCPServer.swift
// Swarm Framework
//
// HTTP-based MCP server client implementation.

import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - HTTPMCPServer

/// An HTTP-based client for Model Context Protocol (MCP) servers.
///
/// HTTPMCPServer speaks the streamable HTTP transport: JSON-RPC over POST
/// with `Accept: application/json, text/event-stream`, `MCP-Protocol-Version`,
/// and `MCP-Session-Id` when the server assigns one. Responses may be a
/// JSON body or an SSE `data:` event. The client negotiates protocol version
/// on initialize and fails loudly on unsupported servers.
///
/// ## Example Usage
///
/// ```swift
/// let server = HTTPMCPServer(
///     url: URL(string: "https://mcp.example.com/api")!,
///     name: "example-server",
///     apiKey: "sk-xxx"
/// )
///
/// // Initialize and discover capabilities
/// let capabilities = try await server.initialize()
///
/// // List available tools
/// if capabilities.tools {
///     let tools = try await server.listTools()
///     for tool in tools {
///         print("\(tool.name): \(tool.description)")
///     }
/// }
///
/// // Call a tool
/// let result = try await server.callTool(
///     name: "search",
///     arguments: ["query": .string("swift concurrency")]
/// )
/// ```
///
/// ## Thread Safety
///
/// HTTPMCPServer is implemented as an actor, ensuring thread-safe access
/// to mutable state such as cached capabilities.
public actor HTTPMCPServer: MCPServerConnection {
    // MARK: Public

    // MARK: - Public Properties

    /// The name of this MCP server.
    public let name: String

    /// The capabilities of this MCP server.
    ///
    /// Returns cached capabilities if available, otherwise returns empty capabilities.
    /// Call `initialize()` to populate capabilities from the server.
    public var capabilities: MCPCapabilities {
        cachedCapabilities ?? MCPCapabilities()
    }

    /// The protocol version negotiated during ``initialize()``.
    ///
    /// `nil` until initialize succeeds.
    public var negotiatedProtocolVersion: String? {
        cachedProtocolVersion
    }

    /// The session identifier assigned by a streamable HTTP server, if any.
    public var sessionID: String? {
        cachedSessionID
    }

    // MARK: - Initialization

    /// Creates an HTTP MCP server client.
    ///
    /// - Parameters:
    ///   - url: The base URL of the MCP server.
    ///   - name: A name for this server instance (used for identification and logging).
    ///   - apiKey: An optional API key for Bearer token authentication.
    ///   - timeout: The request timeout interval in seconds. Default: 30.0
    ///   - maxRetries: The maximum number of retry attempts for failed requests. Default: 3.
    ///     `tools/call` and other side-effecting methods are retried only when
    ///     the connection never opened, never after a timeout or 5xx response.
    ///   - session: The URLSession to use for requests. Default: .shared
    public init(
        url: URL,
        name: String,
        apiKey: String? = nil,
        timeout: TimeInterval = 30.0,
        maxRetries: Int = 3,
        session: URLSession = .shared
    ) throws {
        try self.init(
            url: url,
            name: name,
            apiKey: apiKey,
            timeout: timeout,
            maxRetries: maxRetries,
            session: session,
            sleep: Self.taskSleep
        )
    }

    /// Creates an HTTP MCP server client whose retry backoff runs through `sleep`.
    ///
    /// Tests inject a recording `sleep` to observe the backoff schedule
    /// without waiting on the clock.
    ///
    /// - Parameters:
    ///   - url: The base URL of the MCP server.
    ///   - name: A name for this server instance.
    ///   - apiKey: An optional API key for Bearer token authentication.
    ///   - timeout: The request timeout interval in seconds.
    ///   - maxRetries: The maximum number of retry attempts for failed requests.
    ///   - session: The URLSession to use for requests.
    ///   - sleep: Waits out each backoff delay chosen by ``MCPRetryDecision``.
    init(
        url: URL,
        name: String,
        apiKey: String?,
        timeout: TimeInterval,
        maxRetries: Int,
        session: URLSession,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) throws {
        // Security: Enforce HTTPS when API keys are used to prevent credential exposure.
        if apiKey != nil, url.scheme?.lowercased() != "https" {
            throw MCPError.invalidParams(
                "HTTPS is required when using API keys. URL scheme: \(url.scheme ?? "nil")"
            )
        }

        baseURL = url
        self.name = name
        self.apiKey = apiKey
        apiKeyReference = nil
        secretStore = nil
        self.timeout = timeout
        self.maxRetries = maxRetries
        self.session = session
        backoffSleep = sleep
        cachedCapabilities = nil

        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    /// Creates an HTTP MCP server client that resolves its API key from a ``SecretStore``.
    ///
    /// The reference is resolved lazily on the first request and cached
    /// until ``close()``. Use ``KeychainSecretStore`` on Apple platforms
    /// so the raw key never sits in persisted configuration.
    ///
    /// - Parameters:
    ///   - url: The base URL of the MCP server. Must use HTTPS.
    ///   - name: A name for this server instance (used for identification and logging).
    ///   - apiKeyReference: Pointer to the API key used for Bearer authentication.
    ///   - secretStore: Backend holding the referenced secret.
    ///   - timeout: The request timeout interval in seconds. Default: 30.0
    ///   - maxRetries: The maximum number of retry attempts for failed requests. Default: 3.
    ///     `tools/call` and other side-effecting methods are retried only when
    ///     the connection never opened, never after a timeout or 5xx response.
    ///   - session: The URLSession to use for requests. Default: .shared
    public init(
        url: URL,
        name: String,
        apiKeyReference: SecretReference,
        secretStore: any SecretStore,
        timeout: TimeInterval = 30.0,
        maxRetries: Int = 3,
        session: URLSession = .shared
    ) throws {
        // Security: Enforce HTTPS when API keys are used to prevent credential exposure.
        guard url.scheme?.lowercased() == "https" else {
            throw MCPError.invalidParams(
                "HTTPS is required when using API keys. URL scheme: \(url.scheme ?? "nil")"
            )
        }

        baseURL = url
        self.name = name
        apiKey = nil
        self.apiKeyReference = apiKeyReference
        self.secretStore = secretStore
        self.timeout = timeout
        self.maxRetries = maxRetries
        self.session = session
        backoffSleep = Self.taskSleep
        cachedCapabilities = nil

        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    // MARK: - MCPServerConnection Protocol Implementation

    /// Initializes the connection to the MCP server and negotiates capabilities.
    ///
    /// Sends an "initialize" request offering ``MCPProtocolVersion/current``,
    /// accepts any version in ``MCPProtocolVersion/supported``, and throws
    /// ``MCPError/unsupportedProtocolVersion(_:)`` otherwise.
    ///
    /// - Returns: The capabilities supported by this server.
    /// - Throws: `MCPError` if initialization or version negotiation fails.
    public func initialize() async throws -> MCPCapabilities {
        let request = try MCPRequest(method: "initialize", params: MCPWireCodec.initializeParameters())
        let response = try await sendRequest(request)

        if let error = response.error {
            throw MCPError(code: error.code, message: error.message, data: error.data)
        }

        guard let result = response.result else {
            throw MCPError.internalError("No result in initialize response")
        }

        let version = try MCPWireCodec.negotiatedVersion(from: result)
        let capabilities = try MCPWireCodec.parseCapabilities(from: result)
        cachedProtocolVersion = version
        try await sendNotification(try MCPNotification(method: "notifications/initialized"))
        cachedCapabilities = capabilities
        return capabilities
    }

    /// Lists all tools available from this MCP server.
    ///
    /// - Returns: An array of tool schemas describing available tools.
    /// - Throws: `MCPError` if the request fails.
    public func listTools() async throws -> [ToolSchema] {
        let request = try MCPRequest(method: "tools/list")
        let response = try await sendRequest(request)

        if let error = response.error {
            throw MCPError(code: error.code, message: error.message, data: error.data)
        }

        guard let result = response.result else {
            throw MCPError.internalError("No result in tools/list response")
        }

        return try MCPWireCodec.parseTools(from: result)
    }

    /// Calls a tool and returns unwrapped content blocks.
    ///
    /// A single MCP `text` content block becomes a `.string`. Use
    /// ``callToolRaw(name:arguments:)`` to keep the protocol envelope.
    ///
    /// - Parameters:
    ///   - name: The name of the tool to call.
    ///   - arguments: A dictionary of argument names to values.
    /// - Returns: The unwrapped tool result.
    /// - Throws: `MCPError` if the name is empty, the request fails, or the
    ///   tool reports `isError`.
    public func callTool(name: String, arguments: [String: SendableValue]) async throws -> SendableValue {
        try await invokeTool(name: name, arguments: arguments, style: .unwrappedContent)
    }

    /// Calls a tool and returns the raw `tools/call` envelope.
    ///
    /// - Parameters:
    ///   - name: The name of the tool to call.
    ///   - arguments: A dictionary of argument names to values.
    /// - Returns: The raw result object (`content`, `isError`, …), including
    ///   envelopes where `isError` is `true`.
    /// - Throws: `MCPError` if the name is empty or the request fails.
    public func callToolRaw(name: String, arguments: [String: SendableValue]) async throws -> SendableValue {
        try await invokeTool(name: name, arguments: arguments, style: .rawEnvelope)
    }

    /// Lists all resources available from this MCP server.
    ///
    /// - Returns: An array of resource metadata objects.
    /// - Throws: `MCPError` if the request fails.
    public func listResources() async throws -> [MCPResource] {
        let request = try MCPRequest(method: "resources/list")
        let response = try await sendRequest(request)

        if let error = response.error {
            throw MCPError(code: error.code, message: error.message, data: error.data)
        }

        guard let result = response.result else {
            throw MCPError.internalError("No result in resources/list response")
        }

        return try MCPWireCodec.parseResources(from: result)
    }

    /// Reads the content of a resource from the MCP server.
    ///
    /// - Parameter uri: The URI of the resource to read.
    /// - Returns: The content of the resource.
    /// - Throws: `MCPError` if the request fails.
    public func readResource(uri: String) async throws -> MCPResourceContent {
        // Validate URI format
        guard let url = URL(string: uri),
              let scheme = url.scheme?.lowercased() else {
            throw MCPError.invalidParams("Invalid URI format")
        }

        // Whitelist allowed schemes
        guard ["https", "http", "file"].contains(scheme) else {
            throw MCPError.invalidParams("URI scheme '\(scheme)' not allowed")
        }

        // Block path traversal: check both raw and percent-decoded forms
        let decodedURI = uri.removingPercentEncoding ?? uri
        guard !decodedURI.contains("..") else {
            throw MCPError.invalidParams("Path traversal not allowed")
        }
        // Also check resolved path components for ".." to catch normalized forms
        if url.pathComponents.contains("..") {
            throw MCPError.invalidParams("Path traversal not allowed")
        }

        // For file URLs, ensure they're absolute paths only
        if scheme == "file" {
            guard uri.hasPrefix("file:///") else {
                throw MCPError.invalidParams("File URI must be absolute")
            }
        }

        let params: [String: SendableValue] = [
            "uri": .string(uri)
        ]

        let request = try MCPRequest(method: "resources/read", params: params)
        let response = try await sendRequest(request)

        if let error = response.error {
            throw MCPError(code: error.code, message: error.message, data: error.data)
        }

        guard let result = response.result else {
            throw MCPError.internalError("No result in resources/read response")
        }

        return try MCPWireCodec.parseResourceContent(from: result)
    }

    /// Closes the connection to the MCP server.
    ///
    /// Clears cached capabilities, the negotiated version, the session id,
    /// and the resolved API key (the reference re-resolves on the next
    /// request). It is safe to call multiple times.
    public func close() async throws {
        cachedCapabilities = nil
        cachedProtocolVersion = nil
        cachedSessionID = nil
        resolvedAPIKey = nil
        didResolveAPIKey = false
    }

    // MARK: Private

    // MARK: - Private Properties

    /// The base URL of the MCP server.
    private let baseURL: URL

    /// The URL session used for HTTP requests.
    private let session: URLSession

    /// The optional API key for authentication.
    private let apiKey: String?

    /// Keychain (or other ``SecretStore``) pointer for the API key.
    private let apiKeyReference: SecretReference?

    /// Backend resolving `apiKeyReference`, if any.
    private let secretStore: (any SecretStore)?

    /// Cached key resolved from `apiKeyReference`.
    private var resolvedAPIKey: String?

    /// Whether `apiKeyReference` has been resolved (even to `nil`).
    private var didResolveAPIKey = false

    /// The request timeout interval.
    private let timeout: TimeInterval

    /// The maximum number of retry attempts.
    private let maxRetries: Int

    /// Waits out a retry backoff delay; `Task.sleep` outside tests.
    private let backoffSleep: @Sendable (Duration) async throws -> Void

    /// The production backoff sleep.
    private static let taskSleep: @Sendable (Duration) async throws -> Void = { duration in
        try await Task.sleep(for: duration)
    }

    /// Cached capabilities from the server.
    private var cachedCapabilities: MCPCapabilities?

    /// Protocol version accepted during initialize.
    private var cachedProtocolVersion: String?

    /// Streamable HTTP session identifier, when the server assigned one.
    private var cachedSessionID: String?

    /// JSON encoder for requests.
    private let encoder: JSONEncoder

    /// JSON decoder for responses.
    private let decoder: JSONDecoder

    // MARK: - Private Methods

    /// Sends an MCP request with retry logic.
    ///
    /// Implements exponential backoff for retryable errors. Client errors (4xx)
    /// are not retried. Methods outside ``idempotentMethods`` (notably
    /// `tools/call`) are only retried when the connection never opened, so a
    /// side-effecting call that may have run on the server is never resent.
    ///
    /// - Parameter mcpRequest: The MCP request to send.
    /// - Returns: The MCP response from the server.
    /// - Throws: `MCPError` if all retry attempts fail.
    private func sendRequest(_ mcpRequest: MCPRequest) async throws -> MCPResponse {
        try await sendWithRetry(scope: Self.retryScope(forMethod: mcpRequest.method)) {
            try await self.performRequest(mcpRequest)
        }
    }

    /// Which failures may be retried for a request.
    enum RetryScope: Equatable {
        /// 5xx responses and any transport error: the method is safe to resend.
        case transientFailures
        /// Only failures that prove the request never left the client.
        case connectionNotEstablished
    }

    /// MCP methods without server-side effects, safe to resend after an
    /// ambiguous failure such as a timeout or a 5xx response.
    static let idempotentMethods: Set<String> = [
        "initialize",
        "notifications/initialized",
        "ping",
        "tools/list",
        "resources/list",
        "resources/templates/list",
        "resources/read",
        "prompts/list",
        "prompts/get",
    ]

    static func retryScope(forMethod method: String) -> RetryScope {
        idempotentMethods.contains(method) ? .transientFailures : .connectionNotEstablished
    }

    /// Whether `error` proves the request was never delivered to the server:
    /// DNS failed, the host refused the connection, or there is no network.
    static func isConnectionNotEstablished(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }
        switch urlError.code {
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    /// Sends an MCP notification with retry logic.
    ///
    /// Notifications are JSON-RPC messages without an `id`; successful HTTP responses
    /// do not need to contain a JSON-RPC body.
    ///
    /// - Parameter notification: The MCP notification to send.
    /// - Throws: `MCPError` if all retry attempts fail.
    private func sendNotification(_ notification: MCPNotification) async throws {
        try await sendWithRetry(scope: Self.retryScope(forMethod: notification.method)) {
            try await self.performNotification(notification)
        }
    }

    private func sendWithRetry<T>(
        scope: RetryScope,
        _ operation: () async throws -> T
    ) async throws -> T {
        for attempt in 0..<(maxRetries + 1) {
            do {
                return try await operation()
            } catch {
                switch MCPRetryDecision.decide(error: error, attempt: attempt, maxRetries: maxRetries, scope: scope) {
                case let .retry(delay):
                    // Check for cancellation before sleeping
                    try Task.checkCancellation()
                    try await backoffSleep(delay)
                case .fail:
                    if let mcpError = error as? MCPError {
                        throw mcpError
                    }
                    // Preserve detailed error context for debugging
                    let errorData: [String: SendableValue] = [
                        "originalError": .string(String(describing: error)),
                        "errorType": .string(String(describing: type(of: error))),
                        "attempts": .int(attempt + 1),
                        "maxRetries": .int(maxRetries)
                    ]
                    throw MCPError(
                        code: MCPError.internalErrorCode,
                        message: "Request failed after \(attempt + 1) attempts: \(error.localizedDescription)",
                        data: .dictionary(errorData)
                    )
                }
            }
        }

        throw MCPError.internalError("Request failed after \(maxRetries) retries")
    }

    /// Performs a single HTTP request to the MCP server.
    ///
    /// - Parameter mcpRequest: The MCP request to send.
    /// - Returns: The MCP response from the server.
    /// - Throws: `MCPError` if the request fails.
    private func performRequest(_ mcpRequest: MCPRequest) async throws -> MCPResponse {
        let urlRequest = try await makeStreamableRequest(body: encoder.encode(mcpRequest))
        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.internalError("Invalid response type")
        }

        captureSessionID(from: httpResponse)

        let statusCode = httpResponse.statusCode
        guard (200 ... 299).contains(statusCode) else {
            let errorMessage = if let bodyString = String(data: data, encoding: .utf8), !bodyString.isEmpty {
                "HTTP \(statusCode): \(bodyString)"
            } else {
                "HTTP \(statusCode)"
            }

            throw MCPError(code: statusCode, message: errorMessage)
        }

        let payload = try decodeHTTPBody(data, response: httpResponse)
        return try decoder.decode(MCPResponse.self, from: payload)
    }

    /// Performs a single HTTP notification request to the MCP server.
    ///
    /// - Parameter notification: The JSON-RPC notification to send.
    /// - Throws: `MCPError` if the request fails.
    private func performNotification(_ notification: MCPNotification) async throws {
        let urlRequest = try await makeStreamableRequest(body: encoder.encode(notification))
        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.internalError("Invalid response type")
        }

        captureSessionID(from: httpResponse)

        let statusCode = httpResponse.statusCode
        guard (200 ... 299).contains(statusCode) else {
            let errorMessage = if let bodyString = String(data: data, encoding: .utf8), !bodyString.isEmpty {
                "HTTP \(statusCode): \(bodyString)"
            } else {
                "HTTP \(statusCode)"
            }

            throw MCPError(code: statusCode, message: errorMessage)
        }
    }

    private func invokeTool(
        name: String,
        arguments: [String: SendableValue],
        style: MCPToolResultStyle
    ) async throws -> SendableValue {
        try MCPWireCodec.requireToolName(name)

        let params: [String: SendableValue] = [
            "name": .string(name),
            "arguments": .dictionary(arguments)
        ]

        let request = try MCPRequest(method: "tools/call", params: params)
        let response = try await sendRequest(request)

        if let error = response.error {
            throw MCPError(code: error.code, message: error.message, data: error.data)
        }

        guard let result = response.result else {
            throw MCPError.internalError("No result in tools/call response")
        }

        return try MCPWireCodec.toolCallResult(result, toolName: name, style: style)
    }

    private func makeStreamableRequest(body: Data) async throws -> URLRequest {
        if apiKey == nil, let apiKeyReference, !didResolveAPIKey {
            if let secretStore {
                do {
                    resolvedAPIKey = try await secretStore.secret(for: apiKeyReference)
                } catch {
                    // Leave the reference unresolved so a transient store
                    // failure retries on the next request instead of
                    // permanently de-authing this server.
                    didResolveAPIKey = false
                    throw error
                }
            }
            didResolveAPIKey = true
        }

        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue(
            cachedProtocolVersion ?? MCPProtocolVersion.current,
            forHTTPHeaderField: "MCP-Protocol-Version"
        )
        urlRequest.timeoutInterval = timeout

        if let cachedSessionID {
            urlRequest.setValue(cachedSessionID, forHTTPHeaderField: "MCP-Session-Id")
        }

        if let apiKey = apiKey ?? resolvedAPIKey {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        urlRequest.httpBody = body
        return urlRequest
    }

    private func captureSessionID(from response: HTTPURLResponse) {
        if let session = response.value(forHTTPHeaderField: "MCP-Session-Id"), !session.isEmpty {
            cachedSessionID = session
        }
    }

    private func decodeHTTPBody(_ data: Data, response: HTTPURLResponse) throws -> Data {
        let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.lowercased().contains("text/event-stream") {
            return try MCPWireCodec.jsonRPCPayload(fromSSE: data)
        }
        return data
    }
}

// MARK: - MCPRetryDecision

/// What ``HTTPMCPServer`` does after a failed send attempt.
///
/// ``decide(error:attempt:maxRetries:scope:)`` is the whole retry policy as a
/// pure function. The server's send loop only interprets the result: it checks
/// cancellation, sleeps, and shapes the error it throws.
enum MCPRetryDecision: Sendable, Equatable {
    /// Resend after backing off for the given duration.
    case retry(after: Duration)
    /// Stop and surface the error.
    case fail

    /// Classifies a failed attempt.
    ///
    /// - Client errors (HTTP 4xx, JSON-RPC invalid request, invalid params,
    ///   method not found) never retry.
    /// - Other ``MCPError``s, such as 5xx responses, retry only in
    ///   ``HTTPMCPServer/RetryScope/transientFailures``: the server answered,
    ///   so it received the request.
    /// - Any other error retries in `transientFailures`, and in
    ///   `connectionNotEstablished` only when it proves the request never left
    ///   the client.
    /// - Nothing retries once `attempt` reaches `maxRetries`.
    ///
    /// Backoff doubles from one second: 1s, 2s, 4s, …
    ///
    /// - Parameters:
    ///   - error: The error the attempt threw.
    ///   - attempt: Zero-based index of the attempt that failed.
    ///   - maxRetries: Retries allowed after the first attempt.
    ///   - scope: Which failures the request's method may retry.
    /// - Returns: Whether to resend, and after how long.
    static func decide(
        error: any Error,
        attempt: Int,
        maxRetries: Int,
        scope: HTTPMCPServer.RetryScope
    ) -> MCPRetryDecision {
        let mayResend = if let mcpError = error as? MCPError {
            !isClientError(mcpError) && scope == .transientFailures
        } else {
            scope == .transientFailures || HTTPMCPServer.isConnectionNotEstablished(error)
        }
        guard mayResend, attempt < maxRetries else {
            return .fail
        }
        return .retry(after: .seconds(pow(2.0, Double(attempt))))
    }

    /// Whether `error` is a client error that resending cannot fix.
    private static func isClientError(_ error: MCPError) -> Bool {
        error.code == MCPError.invalidRequestCode ||
            error.code == MCPError.invalidParamsCode ||
            error.code == MCPError.methodNotFoundCode ||
            (400...499).contains(error.code)
    }
}

package struct MCPNotification: Sendable, Encodable, Equatable {
    let jsonrpc: String
    let method: String
    let params: [String: SendableValue]?

    init(method: String, params: [String: SendableValue]? = nil) throws {
        guard !method.isEmpty else {
            throw MCPError.invalidRequest("MCPNotification: method must be non-empty per JSON-RPC 2.0")
        }

        jsonrpc = "2.0"
        self.method = method
        self.params = params
    }

    private enum CodingKeys: String, CodingKey {
        case jsonrpc
        case method
        case params
    }
}
