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

    @Test("auto-download failure still starts a ContextCore session")
    func autoDownloadFailureStillStartsSession() async throws {
        SemanticEmbeddingAvailability.resetForTesting()
        let harness = try DownloadTestHarness(expectedSHA256: "deadbeef")
        defer { harness.tearDown() }

        var memoryConfig = ContextCoreMemoryConfiguration()
        memoryConfig.downloadsEmbeddingModelAutomatically = true
        memoryConfig.embeddingModelDelivery = harness.configuration

        let sessionEnded = LockingFlag()
        let memory = try ContextCoreMemory(configuration: memoryConfig) { context in
            sessionEnded.mark()
            try await context.endSession()
        }

        await memory.beginMemorySession()
        await memory.add(.user("hello"))
        #expect(await memory.count == 1)

        await memory.endMemorySession()
        #expect(sessionEnded.value)
    }

    @Test("probe treats an unloadable compiled cache as unavailable")
    func probeTreatsUnloadableCacheAsUnavailable() throws {
        SemanticEmbeddingAvailability.resetForTesting()
        let harness = try DownloadTestHarness()
        defer { harness.tearDown() }

        try FileManager.default.createDirectory(at: harness.compiledModelURL, withIntermediateDirectories: true)
        try Data("stub".utf8).write(to: harness.compiledModelURL.appendingPathComponent("swarm-stub"))
        EmbeddingModelCache.setDirectoryOverride(harness.cacheDirectory)

        SemanticEmbeddingAvailability.reprobe()
        #expect(SemanticEmbeddingAvailability.isAvailable == false)
        #expect(SemanticEmbeddingAvailability.lastLoadSource == .compiledCache)
    }

    @Test("ZIP extract rejects path traversal")
    func zipExtractRejectsPathTraversal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "zip-slip-\(UUID().uuidString)",
            isDirectory: true
        )
        let destination = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let archive = storedZip(entries: [(name: "../evil.txt", data: Data("pwned".utf8))])
        do {
            try EmbeddingModelZip.extract(archive: archive, to: destination)
            Issue.record("Expected unsafe path to fail")
        } catch let error as EmbeddingModelDeliveryError {
            guard case .compilationFailed(let reason) = error else {
                Issue.record("Expected compilationFailed, got \(error)")
                return
            }
            #expect(reason.contains("not safe"))
        }

        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("evil.txt").path) == false)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("evil.txt").path) == false)
    }

    @Test("ZIP extract inflates deflated entries")
    func zipExtractInflatesDeflatedEntries() throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(
            "zip-deflate-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        try EmbeddingModelZip.extract(archive: deflatedMiniLMZipFixture, to: destination)
        let model = try EmbeddingModelZip.locateModelPackage(in: destination)
        let contents = try String(contentsOf: model, encoding: .utf8)
        #expect(contents == "not-a-real-model")
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

private final class LockingFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var marked = false

    func mark() {
        lock.lock()
        defer { lock.unlock() }
        marked = true
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return marked
    }
}

/// Python `zipfile.ZIP_DEFLATED` archive containing `minilm-l6-v2.mlmodel` → `not-a-real-model`.
private let deflatedMiniLMZipFixture = Data(hex: """
504b0304140000000800f2180d5db3c73a04120000001000000014000000\
6d696e696c6d2d6c362d76322e6d6c6d6f64656ccbcb2fd14dd42d4a4dcc\
d1cdcd4f49cd0100504b01021403140000000800f2180d5db3c73a041200\
0000100000001400000000000000000000008001000000006d696e696c6d\
2d6c362d76322e6d6c6d6f64656c504b0506000000000100010042000000\
440000000000
""")

private func storedZip(entries: [(name: String, data: Data)]) -> Data {
    var locals = Data()
    var centrals = Data()
    for entry in entries {
        let nameData = Data(entry.name.utf8)
        let localOffset = UInt32(locals.count)
        locals.append(contentsOf: zipU32(0x0403_4B50))
        locals.append(contentsOf: zipU16(20))
        locals.append(contentsOf: zipU16(0))
        locals.append(contentsOf: zipU16(0))
        locals.append(contentsOf: zipU16(0))
        locals.append(contentsOf: zipU16(0))
        locals.append(contentsOf: zipU32(0))
        locals.append(contentsOf: zipU32(UInt32(entry.data.count)))
        locals.append(contentsOf: zipU32(UInt32(entry.data.count)))
        locals.append(contentsOf: zipU16(UInt16(nameData.count)))
        locals.append(contentsOf: zipU16(0))
        locals.append(nameData)
        locals.append(entry.data)

        centrals.append(contentsOf: zipU32(0x0201_4B50))
        centrals.append(contentsOf: zipU16(20))
        centrals.append(contentsOf: zipU16(20))
        centrals.append(contentsOf: zipU16(0))
        centrals.append(contentsOf: zipU16(0))
        centrals.append(contentsOf: zipU16(0))
        centrals.append(contentsOf: zipU16(0))
        centrals.append(contentsOf: zipU32(0))
        centrals.append(contentsOf: zipU32(UInt32(entry.data.count)))
        centrals.append(contentsOf: zipU32(UInt32(entry.data.count)))
        centrals.append(contentsOf: zipU16(UInt16(nameData.count)))
        centrals.append(contentsOf: zipU16(0))
        centrals.append(contentsOf: zipU16(0))
        centrals.append(contentsOf: zipU16(0))
        centrals.append(contentsOf: zipU16(0))
        centrals.append(contentsOf: zipU32(0))
        centrals.append(contentsOf: zipU32(localOffset))
        centrals.append(nameData)
    }

    var eocd = Data()
    eocd.append(contentsOf: zipU32(0x0605_4B50))
    eocd.append(contentsOf: zipU16(0))
    eocd.append(contentsOf: zipU16(0))
    eocd.append(contentsOf: zipU16(UInt16(entries.count)))
    eocd.append(contentsOf: zipU16(UInt16(entries.count)))
    eocd.append(contentsOf: zipU32(UInt32(centrals.count)))
    eocd.append(contentsOf: zipU32(UInt32(locals.count)))
    eocd.append(contentsOf: zipU16(0))
    return locals + centrals + eocd
}

private func zipU16(_ value: UInt16) -> [UInt8] {
    [UInt8(value & 0xFF), UInt8(value >> 8)]
}

private func zipU32(_ value: UInt32) -> [UInt8] {
    [
        UInt8(value & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 24) & 0xFF),
    ]
}

private extension Data {
    init(hex: String) {
        let digits = hex.filter(\.isHexDigit)
        var bytes = [UInt8]()
        bytes.reserveCapacity(digits.count / 2)
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard next <= digits.endIndex, let byte = UInt8(String(digits[index..<next]), radix: 16) else {
                break
            }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
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
