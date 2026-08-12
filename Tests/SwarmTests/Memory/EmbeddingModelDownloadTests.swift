#if SWARM_INTEGRATIONS && canImport(ContextCore)
import CryptoKit
import Foundation
@testable import ContextCore
@testable import Swarm
import Testing

@Suite("Embedding model download-on-demand")
struct EmbeddingModelDownloadTests {
    @Test("file URL downloads, verifies hash, compiles via stub, and records cache load path")
    func fileURLDownloadVerifiesAndRecordsCachePath() async throws {
        SemanticEmbeddingAvailability.resetForTesting()
        let harness = try DownloadTestHarness()
        defer { harness.tearDown() }

        let stages = LockingStageList()
        try await SemanticEmbeddingAvailability.ensureModelAvailable(configuration: harness.configuration) { progress in
            stages.append(progress.stage)
        }

        #expect(FileManager.default.fileExists(atPath: harness.compiledModelURL.path))
        #expect(FileManager.default.fileExists(atPath: harness.hashSidecarURL.path))
        #expect(SemanticEmbeddingAvailability.isAvailable)
        #expect(SemanticEmbeddingAvailability.lastLoadSource == .compiledCache)
        let recorded = stages.snapshot()
        #expect(recorded.contains(.downloading))
        #expect(recorded.contains(.verifying))
        #expect(recorded.contains(.compiling))
        #expect(recorded.last == .ready)
    }

    @Test("corrupt hash is rejected and leaves no compiled model")
    func corruptHashIsRejectedWithoutCacheResidue() async throws {
        SemanticEmbeddingAvailability.resetForTesting()
        let harness = try DownloadTestHarness(expectedSHA256: "deadbeef")
        defer { harness.tearDown() }

        do {
            try await SemanticEmbeddingAvailability.ensureModelAvailable(configuration: harness.configuration)
            Issue.record("Expected integrity failure")
        } catch let error as EmbeddingModelDeliveryError {
            guard case .integrityFailure = error else {
                Issue.record("Expected integrityFailure, got \(error)")
                return
            }
        }

        #expect(FileManager.default.fileExists(atPath: harness.compiledModelURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: harness.hashSidecarURL.path) == false)
        #expect(stagingResidue(in: harness.cacheDirectory) == false)
    }

    @Test("compile failure leaves no partial compiled model")
    func compileFailureLeavesNoPartialFiles() async throws {
        SemanticEmbeddingAvailability.resetForTesting()
        let harness = try DownloadTestHarness(compiler: ThrowingEmbeddingModelCompiler())
        defer { harness.tearDown() }

        do {
            try await SemanticEmbeddingAvailability.ensureModelAvailable(configuration: harness.configuration)
            Issue.record("Expected compilation failure")
        } catch let error as EmbeddingModelDeliveryError {
            guard case .compilationFailed = error else {
                Issue.record("Expected compilationFailed, got \(error)")
                return
            }
        }

        #expect(FileManager.default.fileExists(atPath: harness.compiledModelURL.path) == false)
        #expect(stagingResidue(in: harness.cacheDirectory) == false)
    }

    @Test("cache hit performs no network I/O")
    func cacheHitPerformsNoNetworkIO() async throws {
        SemanticEmbeddingAvailability.resetForTesting()
        let payload = Data("minilm-cache-hit-payload".utf8)
        let hash = sha256Hex(payload)
        CountingEmbeddingURLProtocol.reset()
        CountingEmbeddingURLProtocol.payload = payload
        defer { CountingEmbeddingURLProtocol.reset() }

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [CountingEmbeddingURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        let harness = try DownloadTestHarness(
            sourceURL: URL(string: "https://example.invalid/minilm-l6-v2.mlpackage.zip")!,
            expectedSHA256: hash,
            session: session
        )
        defer { harness.tearDown() }

        try await SemanticEmbeddingAvailability.ensureModelAvailable(configuration: harness.configuration)
        #expect(CountingEmbeddingURLProtocol.requestCount == 1)

        try await SemanticEmbeddingAvailability.ensureModelAvailable(configuration: harness.configuration)
        #expect(CountingEmbeddingURLProtocol.requestCount == 1)
        #expect(SemanticEmbeddingAvailability.isAvailable)
    }

    @Test("availability flips after ensureModelAvailable without restart")
    func availabilityFlipsAfterEnsure() async throws {
        SemanticEmbeddingAvailability.resetForTesting()
        let harness = try DownloadTestHarness()
        defer { harness.tearDown() }

        #expect(SemanticEmbeddingAvailability.isAvailable == false)

        try await SemanticEmbeddingAvailability.ensureModelAvailable(configuration: harness.configuration)

        #expect(SemanticEmbeddingAvailability.isAvailable)
        #expect(SemanticEmbeddingAvailability.lastLoadSource == .compiledCache)
    }

    @Test("auto-download flag defaults to off")
    func autoDownloadDefaultsOff() {
        #expect(ContextCoreMemoryConfiguration.default.downloadsEmbeddingModelAutomatically == false)
        #expect(DefaultAgentMemory.Configuration.default.downloadsEmbeddingModelAutomatically == false)
    }
}

private struct StubEmbeddingModelCompiler: EmbeddingModelCompiling {
    func compileModel(at _: URL) throws -> URL {
        let compiled = FileManager.default.temporaryDirectory.appendingPathComponent(
            "stub-\(UUID().uuidString).mlmodelc",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
        try Data("stub".utf8).write(to: compiled.appendingPathComponent("swarm-stub"))
        return compiled
    }
}

private struct ThrowingEmbeddingModelCompiler: EmbeddingModelCompiling {
    func compileModel(at _: URL) throws -> URL {
        throw EmbeddingModelDeliveryError.compilationFailed("stub compile failure")
    }
}

private struct DownloadTestHarness {
    let root: URL
    let cacheDirectory: URL
    let configuration: EmbeddingModelDeliveryConfiguration
    let compiledModelURL: URL
    let hashSidecarURL: URL

    init(
        sourceURL: URL? = nil,
        expectedSHA256: String? = nil,
        session: URLSession? = nil,
        compiler: any EmbeddingModelCompiling = StubEmbeddingModelCompiler()
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swarm-embedding-download-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cacheDirectory = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let payload = Data("minilm-test-payload".utf8)
        let fileURL = root.appendingPathComponent("minilm-source.bin")
        try payload.write(to: fileURL)

        self.root = root
        self.cacheDirectory = cacheDirectory
        self.configuration = EmbeddingModelDeliveryConfiguration(
            sourceURL: sourceURL ?? fileURL,
            expectedSHA256: expectedSHA256 ?? sha256Hex(payload),
            cacheDirectory: cacheDirectory,
            session: session ?? URLSession(configuration: .ephemeral),
            compiler: compiler
        )
        self.compiledModelURL = cacheDirectory.appendingPathComponent(
            EmbeddingModelCatalog.compiledModelDirectoryName,
            isDirectory: true
        )
        self.hashSidecarURL = cacheDirectory.appendingPathComponent(
            EmbeddingModelCatalog.hashSidecarFileName
        )
    }

    func tearDown() {
        SemanticEmbeddingAvailability.resetForTesting()
        try? FileManager.default.removeItem(at: root)
    }
}

private final class LockingStageList: @unchecked Sendable {
    private let lock = NSLock()
    private var stages: [EmbeddingModelDeliveryProgress.Stage] = []

    func append(_ stage: EmbeddingModelDeliveryProgress.Stage) {
        lock.lock()
        defer { lock.unlock() }
        stages.append(stage)
    }

    func snapshot() -> [EmbeddingModelDeliveryProgress.Stage] {
        lock.lock()
        defer { lock.unlock() }
        return stages
    }
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func stagingResidue(in directory: URL) -> Bool {
    let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    return contents.contains { $0.lastPathComponent.hasPrefix(".staging-") }
}

private final class CountingEmbeddingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var payload = Data()

    static func reset() {
        requestCount = 0
        payload = Data()
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.invalid")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(Self.payload.count)"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
