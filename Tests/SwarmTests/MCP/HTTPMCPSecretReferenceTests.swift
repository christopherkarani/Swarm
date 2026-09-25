import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Swarm
import Testing

@Suite("HTTPMCPServer secret references", .serialized)
struct HTTPMCSecretReferenceTests {
    @Test("Referenced keys are sent as the Bearer credential")
    func referencedKeySentAsBearerCredential() async throws {
        SecretRecordingURLProtocol.reset()
        defer { SecretRecordingURLProtocol.reset() }

        let reference = SecretReference(service: "com.swarm.tests", account: "mcp-key")
        let store = InMemorySecretStore(secrets: [reference: "resolved-mcp-value"])
        let server = try HTTPMCPServer(
            url: URL(string: "https://mcp.example.com/api")!,
            name: "secret-test",
            apiKeyReference: reference,
            secretStore: store,
            session: SecretRecordingURLProtocol.makeSession()
        )

        let tools = try await server.listTools()
        #expect(tools.isEmpty)
        #expect(SecretRecordingURLProtocol.authorizationHeaders == ["Bearer resolved-mcp-value"])
    }

    @Test("References resolve once and are cached")
    func referenceResolutionIsCached() async throws {
        SecretRecordingURLProtocol.reset()
        defer { SecretRecordingURLProtocol.reset() }

        let reference = SecretReference(service: "com.swarm.tests", account: "mcp-key")
        let store = CountingSecretStore(secrets: [reference: "cached-mcp-value"])
        let server = try HTTPMCPServer(
            url: URL(string: "https://mcp.example.com/api")!,
            name: "secret-cache-test",
            apiKeyReference: reference,
            secretStore: store,
            session: SecretRecordingURLProtocol.makeSession()
        )

        _ = try await server.listTools()
        _ = try await server.listTools()
        #expect(store.loads == 1)
        #expect(SecretRecordingURLProtocol.authorizationHeaders == ["Bearer cached-mcp-value", "Bearer cached-mcp-value"])
    }

    @Test("Transient store failure retries resolution instead of de-authing")
    func transientStoreFailureRetriesResolution() async throws {
        SecretRecordingURLProtocol.reset()
        defer { SecretRecordingURLProtocol.reset() }

        let reference = SecretReference(service: "com.swarm.tests", account: "mcp-key")
        let store = FailOnceSecretStore(secrets: [reference: "recovered-mcp-value"])
        let server = try HTTPMCPServer(
            url: URL(string: "https://mcp.example.com/api")!,
            name: "secret-retry-test",
            apiKeyReference: reference,
            secretStore: store,
            maxRetries: 1,
            session: SecretRecordingURLProtocol.makeSession()
        )

        // The first resolution throws inside the request builder; the retry
        // must re-resolve (not silently drop the Authorization header).
        let tools = try await server.listTools()
        #expect(tools.isEmpty)
        #expect(store.loads == 2)
        #expect(SecretRecordingURLProtocol.authorizationHeaders == ["Bearer recovered-mcp-value"])
    }

    @Test("close() clears the cached key so the reference re-resolves")
    func closeClearsCachedKey() async throws {
        SecretRecordingURLProtocol.reset()
        defer { SecretRecordingURLProtocol.reset() }

        let reference = SecretReference(service: "com.swarm.tests", account: "mcp-key")
        let store = CountingSecretStore(secrets: [reference: "cached-mcp-value"])
        let server = try HTTPMCPServer(
            url: URL(string: "https://mcp.example.com/api")!,
            name: "secret-close-test",
            apiKeyReference: reference,
            secretStore: store,
            session: SecretRecordingURLProtocol.makeSession()
        )

        _ = try await server.listTools()
        #expect(store.loads == 1)
        try await server.close()
        _ = try await server.listTools()
        #expect(store.loads == 2)
        #expect(SecretRecordingURLProtocol.authorizationHeaders == ["Bearer cached-mcp-value", "Bearer cached-mcp-value"])
    }

    @Test("Reference initializer requires HTTPS")
    func referenceInitializerRequiresHTTPS() {
        let reference = SecretReference(service: "com.swarm.tests", account: "mcp-key")
        #expect(throws: MCPError.self) {
            try HTTPMCPServer(
                url: URL(string: "http://mcp.example.com/api")!,
                name: "insecure-test",
                apiKeyReference: reference,
                secretStore: InMemorySecretStore()
            )
        }
    }
}

private final class SecretRecordingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var authorizationHeaders: [String?] = []

    static func reset() {
        authorizationHeaders = []
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SecretRecordingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization"))
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://mcp.example.com/api")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"jsonrpc":"2.0","id":1,"result":{"tools":[]}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Throws ``SecretStoreError/loadFailed(_:)`` on the first `secret(for:)`
/// call, then behaves like an in-memory store.
private final class FailOnceSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [SecretReference: String]
    private var loadCounter = 0
    private var didFail = false

    init(secrets: [SecretReference: String]) {
        self.secrets = secrets
    }

    var loads: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadCounter
    }

    func secret(for reference: SecretReference) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        loadCounter += 1
        if !didFail {
            didFail = true
            throw SecretStoreError.loadFailed("transient store failure")
        }
        return secrets[reference]
    }

    func save(_ secret: String, for reference: SecretReference) {
        lock.lock()
        defer { lock.unlock() }
        secrets[reference] = secret
    }

    func delete(_ reference: SecretReference) {
        lock.lock()
        defer { lock.unlock() }
        secrets.removeValue(forKey: reference)
    }
}

private final class CountingSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [SecretReference: String]
    private var loadCounter = 0

    init(secrets: [SecretReference: String]) {
        self.secrets = secrets
    }

    var loads: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadCounter
    }

    func secret(for reference: SecretReference) -> String? {
        lock.lock()
        defer { lock.unlock() }
        loadCounter += 1
        return secrets[reference]
    }

    func save(_ secret: String, for reference: SecretReference) {
        lock.lock()
        defer { lock.unlock() }
        secrets[reference] = secret
    }

    func delete(_ reference: SecretReference) {
        lock.lock()
        defer { lock.unlock() }
        secrets.removeValue(forKey: reference)
    }
}
