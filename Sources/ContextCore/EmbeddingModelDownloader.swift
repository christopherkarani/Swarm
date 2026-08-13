import CoreML
import CryptoKit
import Foundation

/// Progress of an explicit MiniLM download / compile.
public struct EmbeddingModelDeliveryProgress: Sendable, Equatable {
    /// Delivery stage.
    public enum Stage: String, Sendable, Equatable {
        /// Checking the Application Support cache.
        case checkingCache
        /// Downloading the release asset.
        case downloading
        /// Verifying SHA-256 of the downloaded bytes.
        case verifying
        /// Compiling the `.mlpackage` into `.mlmodelc`.
        case compiling
        /// Compiled model is in the cache and ready to load.
        case ready
    }

    /// Current stage.
    public var stage: Stage
    /// Approximate fraction in `0...1`.
    public var fractionCompleted: Double

    public init(stage: Stage, fractionCompleted: Double) {
        self.stage = stage
        self.fractionCompleted = min(1, max(0, fractionCompleted))
    }
}

/// Failures from ``SemanticEmbeddingAvailability/ensureModelAvailable(configuration:progressHandler:)``.
public enum EmbeddingModelDeliveryError: Error, Sendable, CustomStringConvertible {
    /// The download response was missing or not HTTP 2xx (when applicable).
    case invalidResponse(String)
    /// Downloaded bytes did not match the pinned SHA-256.
    case integrityFailure(expected: String, actual: String)
    /// Compilation or unzip failed.
    case compilationFailed(String)
    /// The compiled model could not be moved into the cache.
    case cacheWriteFailed(String)

    public var description: String {
        switch self {
        case let .invalidResponse(reason):
            return "Embedding model download failed: \(reason)"
        case let .integrityFailure(expected, actual):
            return "Embedding model SHA-256 mismatch: expected \(expected), got \(actual)"
        case let .compilationFailed(reason):
            return "Embedding model compilation failed: \(reason)"
        case let .cacheWriteFailed(reason):
            return "Embedding model cache write failed: \(reason)"
        }
    }
}

/// Where ``CoreMLEmbeddingProvider`` resolved the MiniLM artifact.
public enum EmbeddingModelLoadSource: String, Sendable, Equatable {
    /// Compiled `.mlmodelc` in Application Support.
    case compiledCache
    /// `.mlpackage` bundled with the ContextCore module.
    case bundle
    /// No artifact found.
    case missing
}

/// Configuration for MiniLM download-on-demand.
///
/// Network I/O happens only when ``SemanticEmbeddingAvailability/ensureModelAvailable(configuration:progressHandler:)``
/// is called, or when memory is configured with `downloadsEmbeddingModelAutomatically`
/// (default `false`).
public struct EmbeddingModelDeliveryConfiguration: Sendable {
    /// Source of the MiniLM asset (file or https). Default is the GitHub publishing target.
    public var sourceURL: URL
    /// Pinned SHA-256 (lowercase hex) of the downloaded bytes.
    public var expectedSHA256: String
    /// Directory that stores the compiled `.mlmodelc` and hash sidecar.
    public var cacheDirectory: URL
    /// Session used for the download. Tests inject a `URLProtocol` stub here.
    var session: URLSession
    /// Compiler used after hash verification. Tests inject a stub.
    var compiler: any EmbeddingModelCompiling

    /// Production defaults: GitHub publishing-target URL, pinned hash, Application Support cache.
    public static var `default`: EmbeddingModelDeliveryConfiguration {
        EmbeddingModelDeliveryConfiguration()
    }

    public init(
        sourceURL: URL = EmbeddingModelCatalog.defaultSourceURL,
        expectedSHA256: String = EmbeddingModelCatalog.expectedSHA256,
        cacheDirectory: URL = EmbeddingModelCatalog.defaultCacheDirectory
    ) {
        self.sourceURL = sourceURL
        self.expectedSHA256 = expectedSHA256.lowercased()
        self.cacheDirectory = cacheDirectory
        self.session = URLSession(configuration: .ephemeral)
        self.compiler = CoreMLEmbeddingModelCompiler()
    }

    init(
        sourceURL: URL,
        expectedSHA256: String,
        cacheDirectory: URL,
        session: URLSession,
        compiler: any EmbeddingModelCompiling
    ) {
        self.sourceURL = sourceURL
        self.expectedSHA256 = expectedSHA256.lowercased()
        self.cacheDirectory = cacheDirectory
        self.session = session
        self.compiler = compiler
    }
}

/// Process-wide MiniLM cache location and last load-source probe.
///
/// Mutable fields live on `State`, protected by `lock`. `@unchecked Sendable`
/// matches `EmbeddingAvailabilityState` in `EmbeddingProviders.swift`.
enum EmbeddingModelCache {
    private static let state = State()

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var directoryOverride: URL?
        var lastSource: EmbeddingModelLoadSource = .missing
    }

    static var defaultDirectory: URL {
        EmbeddingModelCatalog.defaultCacheDirectory
    }

    static var directory: URL {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.directoryOverride ?? defaultDirectory
    }

    static func setDirectoryOverride(_ url: URL?) {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.directoryOverride = url
    }

    static var lastLoadSource: EmbeddingModelLoadSource {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.lastSource
    }

    static func recordLoadSource(_ source: EmbeddingModelLoadSource) {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.lastSource = source
    }

    static func resetForTesting() {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.directoryOverride = nil
        state.lastSource = .missing
    }

    static var compiledModelURL: URL {
        directory.appendingPathComponent(
            EmbeddingModelCatalog.compiledModelDirectoryName,
            isDirectory: true
        )
    }

    static var hashSidecarURL: URL {
        directory.appendingPathComponent(EmbeddingModelCatalog.hashSidecarFileName)
    }

    static func compiledModelExists(expectedSHA256: String? = nil) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: compiledModelURL.path,
            isDirectory: &isDirectory
        )
        guard exists, isDirectory.boolValue else {
            return false
        }
        guard let expectedSHA256 else {
            return true
        }
        guard let sidecar = try? String(contentsOf: hashSidecarURL, encoding: .utf8) else {
            return false
        }
        return sidecar.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == expectedSHA256.lowercased()
    }
}

protocol EmbeddingModelCompiling: Sendable {
    func compileModel(at sourceURL: URL) throws -> URL
}

struct CoreMLEmbeddingModelCompiler: EmbeddingModelCompiling {
    func compileModel(at sourceURL: URL) throws -> URL {
        do {
            return try MLModel.compileModel(at: sourceURL)
        } catch {
            throw EmbeddingModelDeliveryError.compilationFailed(error.localizedDescription)
        }
    }
}

/// Downloads, verifies, and compiles the MiniLM embedding model into Application Support.
actor EmbeddingModelDownloader {
    static let shared = EmbeddingModelDownloader()

    @discardableResult
    func ensureAvailable(
        configuration: EmbeddingModelDeliveryConfiguration,
        progressHandler: (@Sendable (EmbeddingModelDeliveryProgress) -> Void)?
    ) async throws -> URL {
        EmbeddingModelCache.setDirectoryOverride(configuration.cacheDirectory)
        report(progressHandler, .checkingCache, 0)

        if EmbeddingModelCache.compiledModelExists(expectedSHA256: configuration.expectedSHA256) {
            report(progressHandler, .ready, 1)
            return EmbeddingModelCache.compiledModelURL
        }

        try FileManager.default.createDirectory(
            at: configuration.cacheDirectory,
            withIntermediateDirectories: true
        )

        let stagingRoot = configuration.cacheDirectory.appendingPathComponent(
            ".staging-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingRoot) }

        report(progressHandler, .downloading, 0.15)
        let downloadURL = stagingRoot.appendingPathComponent("download.bin")
        try await download(from: configuration.sourceURL, to: downloadURL, session: configuration.session)

        report(progressHandler, .verifying, 0.65)
        let actualHash = try Self.sha256Hex(ofFile: downloadURL)
        guard actualHash == configuration.expectedSHA256 else {
            throw EmbeddingModelDeliveryError.integrityFailure(
                expected: configuration.expectedSHA256,
                actual: actualHash
            )
        }

        report(progressHandler, .compiling, 0.8)
        let compileSource = try Self.prepareCompileSource(downloadedFile: downloadURL, stagingRoot: stagingRoot)
        let compiledTemp = try configuration.compiler.compileModel(at: compileSource)
        let destination = configuration.cacheDirectory.appendingPathComponent(
            EmbeddingModelCatalog.compiledModelDirectoryName,
            isDirectory: true
        )
        try Self.installAtomically(from: compiledTemp, to: destination)
        let sidecar = configuration.cacheDirectory.appendingPathComponent(
            EmbeddingModelCatalog.hashSidecarFileName
        )
        try configuration.expectedSHA256.write(to: sidecar, atomically: true, encoding: .utf8)

        report(progressHandler, .ready, 1)
        return destination
    }

    private func download(from source: URL, to destination: URL, session: URLSession) async throws {
        let (tempURL, response) = try await session.download(from: source)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: tempURL)
            throw EmbeddingModelDeliveryError.invalidResponse("HTTP \(http.statusCode)")
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    private func report(
        _ handler: (@Sendable (EmbeddingModelDeliveryProgress) -> Void)?,
        _ stage: EmbeddingModelDeliveryProgress.Stage,
        _ fraction: Double
    ) {
        handler?(EmbeddingModelDeliveryProgress(stage: stage, fractionCompleted: fraction))
    }

    private static func sha256Hex(ofFile url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func prepareCompileSource(downloadedFile: URL, stagingRoot: URL) throws -> URL {
        let magic = try readPrefix(downloadedFile, count: 4)
        guard EmbeddingModelZip.isZip(magic) else {
            return downloadedFile
        }
        let data = try Data(contentsOf: downloadedFile, options: [.mappedIfSafe])
        let unzipped = stagingRoot.appendingPathComponent("unzipped", isDirectory: true)
        try EmbeddingModelZip.extract(archive: data, to: unzipped)
        return try EmbeddingModelZip.locateModelPackage(in: unzipped)
    }

    private static func readPrefix(_ url: URL, count: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: count) ?? Data()
    }

    private static func installAtomically(from compiled: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staged = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).tmp-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: staged) }

        if fileManager.fileExists(atPath: staged.path) {
            try fileManager.removeItem(at: staged)
        }
        try fileManager.moveItem(at: compiled, to: staged)

        if fileManager.fileExists(atPath: destination.path) {
            do {
                _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
            } catch {
                throw EmbeddingModelDeliveryError.cacheWriteFailed(error.localizedDescription)
            }
        } else {
            do {
                try fileManager.moveItem(at: staged, to: destination)
            } catch {
                throw EmbeddingModelDeliveryError.cacheWriteFailed(error.localizedDescription)
            }
        }
    }
}
