import ContextCoreEngine
import CoreML
import Foundation
import Logging

/// Runtime status of ContextCore's default CoreML MiniLM embedder.
///
/// When the model is missing, fails to load, or compilation has not been
/// performed, ContextCore falls back to hash-seeded pseudo-vectors. Rankings
/// from that path are not semantically meaningful.
///
/// Swarm does **not** bundle the ~43 MB MiniLM package. Call
/// ``ensureModelAvailable(configuration:progressHandler:)`` (explicit network
/// I/O) or opt in via `downloadsEmbeddingModelAutomatically` on the memory
/// configuration (default `false`).
public enum SemanticEmbeddingAvailability: Sendable {
    /// Whether the default CoreML MiniLM model can produce real embeddings.
    ///
    /// Becomes `true` in-process after a successful
    /// ``ensureModelAvailable(configuration:progressHandler:)`` without requiring
    /// a restart.
    public static var isAvailable: Bool {
        CoreMLEmbeddingProvider.isRealModelAvailable
    }

    /// Why real embeddings are unavailable, if they are.
    public static var unavailabilityReason: String? {
        CoreMLEmbeddingProvider.unavailabilityReason
    }

    /// Most recent fallback warning in this process, if any.
    public static var lastWarningMessage: String? {
        CoreMLEmbeddingProvider.lastWarningMessage
    }

    /// Where the default provider last resolved the MiniLM artifact.
    public static var lastLoadSource: EmbeddingModelLoadSource {
        EmbeddingModelCache.lastLoadSource
    }

    /// Whether `provider` can produce real semantic embeddings.
    ///
    /// Custom embedders are treated as available. The default CoreML MiniLM
    /// path reports ``isAvailable``.
    public static func isAvailable(for provider: any EmbeddingProvider) -> Bool {
        if provider is CoreMLEmbeddingProvider {
            return CoreMLEmbeddingProvider.isRealModelAvailable
        }
        if let caching = provider as? CachingEmbeddingProvider {
            return isAvailable(for: caching.base)
        }
        return true
    }

    /// Whether `provider` is the default CoreML MiniLM path (possibly cached).
    public static func tracksDefaultCoreML(for provider: any EmbeddingProvider) -> Bool {
        if provider is CoreMLEmbeddingProvider {
            return true
        }
        if let caching = provider as? CachingEmbeddingProvider {
            return tracksDefaultCoreML(for: caching.base)
        }
        return false
    }

    /// Downloads, verifies, and compiles the MiniLM model if it is not cached.
    ///
    /// This is the **explicit** delivery API. Swarm never performs this network
    /// I/O unless you call this method or set `downloadsEmbeddingModelAutomatically`
    /// on the memory configuration.
    ///
    /// After a successful return, ``isAvailable`` is re-probed in this process
    /// so callers do not need to restart.
    ///
    /// - Parameters:
    ///   - configuration: Download URL, pinned SHA-256, and cache directory.
    ///   - progressHandler: Optional stage/fraction callback.
    /// - Throws: ``EmbeddingModelDeliveryError`` when download, hash, or compile fails.
    public static func ensureModelAvailable(
        configuration: EmbeddingModelDeliveryConfiguration = .default,
        progressHandler: (@Sendable (EmbeddingModelDeliveryProgress) -> Void)? = nil
    ) async throws {
        _ = try await EmbeddingModelDownloader.shared.ensureAvailable(
            configuration: configuration,
            progressHandler: progressHandler
        )
        reprobe()
    }

    /// Clears the last probe and checks the cache / bundle again.
    ///
    /// Called automatically by ``ensureModelAvailable(configuration:progressHandler:)``.
    public static func reprobe() {
        CoreMLEmbeddingProvider.reprobeAvailability()
    }

    /// Resets process-wide fallback diagnostics. Intended for tests.
    public static func resetForTesting() {
        CoreMLEmbeddingProvider.resetAvailabilityForTesting()
        EmbeddingModelCache.resetForTesting()
    }
}

internal struct CoreMLEmbeddingProvider: EmbeddingProvider, Sendable {
    internal let dimensions: Int = 384
    internal let modelIdentifier = "minilm-l6-v2"

    internal init() {
        Self.probeAndWarnIfNeeded()
    }

    func embed(_ text: String) async throws -> [Float] {
        do {
            let model = try Self.loadModel()
            Self.markRealModelAvailable()
            let inputName = try Self.resolveInputName(for: model)
            let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: text])
            let output = try await model.prediction(from: provider)
            return try Self.extractEmbedding(from: output, model: model)
        } catch {
            Self.takeFallback(
                reason: "CoreML model minilm-l6-v2 is missing or failed to load (\(error.localizedDescription))"
            )
            return Self.deterministicVector(for: text, dimension: dimensions)
        }
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else {
            return []
        }

        do {
            let model = try Self.loadModel()
            Self.markRealModelAvailable()
            let inputName = try Self.resolveInputName(for: model)
            let providers = try texts.map { text in
                try MLDictionaryFeatureProvider(dictionary: [inputName: text]) as MLFeatureProvider
            }
            let batch = MLArrayBatchProvider(array: providers)
            let outputs = try model.predictions(fromBatch: batch)

            var vectors: [[Float]] = []
            vectors.reserveCapacity(outputs.count)
            for index in 0..<outputs.count {
                let output = outputs.features(at: index)
                vectors.append(try Self.extractEmbedding(from: output, model: model))
            }
            return vectors
        } catch {
            Self.takeFallback(
                reason: "CoreML model minilm-l6-v2 is missing or failed to load (\(error.localizedDescription))"
            )
            return texts.map { Self.deterministicVector(for: $0, dimension: dimensions) }
        }
    }

    fileprivate static var isRealModelAvailable: Bool {
        probeAndWarnIfNeeded()
        return availability.snapshot().isRealModelAvailable
    }

    fileprivate static var unavailabilityReason: String? {
        probeAndWarnIfNeeded()
        return availability.snapshot().reason
    }

    fileprivate static var lastWarningMessage: String? {
        availability.snapshot().lastWarning
    }

    fileprivate static func resetAvailabilityForTesting() {
        availability.reset()
    }

    fileprivate static func reprobeAvailability() {
        availability.reset()
        _ = probeAndWarnIfNeeded()
    }

    private static let availability = EmbeddingAvailabilityState()
    private static let embeddingLogger = Logger(label: "com.swarm.memory")

    @discardableResult
    private static func probeAndWarnIfNeeded() -> Bool {
        let probed = availability.snapshot()
        if probed.didProbe {
            return probed.isRealModelAvailable
        }

        let result = probeModel()
        availability.storeProbe(available: result.available, reason: result.reason)
        if !result.available, let reason = result.reason {
            takeFallback(reason: reason)
        }
        return result.available
    }

    private static func probeModel() -> (available: Bool, reason: String?) {
        let resolution = resolveModelURL()
        EmbeddingModelCache.recordLoadSource(resolution.source)
        switch resolution.source {
        case .compiledCache, .bundle:
            return (true, nil)
        case .missing:
            return (
                false,
                "CoreML model minilm-l6-v2 is not cached and is not in bundle resources. Call SemanticEmbeddingAvailability.ensureModelAvailable() to download it"
            )
        }
    }

    private static func markRealModelAvailable() {
        availability.storeProbe(available: true, reason: nil)
    }

    private static func takeFallback(reason: String) {
        let message = """
        Real embeddings are unavailable (\(reason)). Semantic recall quality is degraded — \
        vector rankings are not meaningful until a real embedding model is available. \
        Call SemanticEmbeddingAvailability.ensureModelAvailable() to download the MiniLM model, \
        or set downloadsEmbeddingModelAutomatically on the memory configuration.
        """
        if availability.recordWarning(message, reason: reason) {
            embeddingLogger.warning("\(message)")
        }
    }

    private static func loadModel() throws -> MLModel {
        let resolution = resolveModelURL()
        EmbeddingModelCache.recordLoadSource(resolution.source)
        guard let modelURL = resolution.url else {
            throw ContextCoreError.embeddingFailed(
                "Missing minilm-l6-v2. Call SemanticEmbeddingAvailability.ensureModelAvailable() to download it"
            )
        }

        let configuration = MLModelConfiguration()
#if targetEnvironment(simulator)
        // Simulator has no Neural Engine and often no MPSGraph GPU backend.
        // CPU inference works for MiniLM; do not skip the real model path.
        configuration.computeUnits = .cpuOnly
#else
        configuration.computeUnits = .all
#endif
        return try MLModel(contentsOf: modelURL, configuration: configuration)
    }

    private static func resolveModelURL() -> (url: URL?, source: EmbeddingModelLoadSource) {
        let compiled = EmbeddingModelCache.compiledModelURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: compiled.path, isDirectory: &isDirectory),
           isDirectory.boolValue
        {
            return (compiled, .compiledCache)
        }

        let candidates: [URL?] = [
            Bundle.module.url(forResource: "minilm-l6-v2", withExtension: "mlpackage", subdirectory: "Embeddings"),
            Bundle.module.url(forResource: "minilm-l6-v2", withExtension: "mlpackage", subdirectory: "Resources/Embeddings"),
            Bundle.module.url(forResource: "minilm-l6-v2", withExtension: "mlpackage"),
        ]
        if let bundled = candidates.compactMap({ $0 }).first {
            return (bundled, .bundle)
        }
        return (nil, .missing)
    }

    private static func resolveInputName(for model: MLModel) throws -> String {
        guard let inputName = model.modelDescription.inputDescriptionsByName.keys.first else {
            throw ContextCoreError.embeddingFailed("Model input description is missing")
        }
        return inputName
    }

    private static func resolveOutputName(for model: MLModel) throws -> String {
        guard let outputName = model.modelDescription.outputDescriptionsByName.keys.first else {
            throw ContextCoreError.embeddingFailed("Model output description is missing")
        }
        return outputName
    }

    private static func extractEmbedding(from provider: MLFeatureProvider, model: MLModel) throws -> [Float] {
        let outputName = try resolveOutputName(for: model)
        guard let featureValue = provider.featureValue(for: outputName) else {
            throw ContextCoreError.embeddingFailed("Prediction output is missing embedding feature")
        }

        if let multiArray = featureValue.multiArrayValue {
            let vector = Self.vector(from: multiArray)
            return Self.l2Normalize(vector)
        }

        throw ContextCoreError.embeddingFailed("Unsupported embedding feature type")
    }

    private static func vector(from multiArray: MLMultiArray) -> [Float] {
        var vector = [Float]()
        vector.reserveCapacity(multiArray.count)

        switch multiArray.dataType {
        case .float32:
            let pointer = multiArray.dataPointer.bindMemory(to: Float.self, capacity: multiArray.count)
            vector = Array(UnsafeBufferPointer(start: pointer, count: multiArray.count))
        case .double:
            let pointer = multiArray.dataPointer.bindMemory(to: Double.self, capacity: multiArray.count)
            vector = Array(UnsafeBufferPointer(start: pointer, count: multiArray.count)).map(Float.init)
        default:
            for index in 0..<multiArray.count {
                vector.append(multiArray[index].floatValue)
            }
        }

        return vector
    }

    private static func l2Normalize(_ vector: [Float]) -> [Float] {
        let norm = vector.reduce(0) { partial, value in
            partial + (value * value)
        }.squareRoot()

        guard norm > 0 else {
            return vector
        }

        return vector.map { $0 / norm }
    }

    private static func deterministicVector(for text: String, dimension: Int) -> [Float] {
        var state = stableSeed(from: text)
        var values = [Float](repeating: 0, count: dimension)

        for index in values.indices {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            let component = Float(Int64(bitPattern: state & 0x0000_FFFF_FFFF_FFFF) % 10_000) / 5_000.0 - 1.0
            values[index] = component
        }

        return l2Normalize(values)
    }

    private static func stableSeed(from text: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }
}

internal struct CachingEmbeddingProvider: EmbeddingProvider, Sendable {
    fileprivate let base: any EmbeddingProvider
    private let cache: EmbeddingCache

    internal init(
        base: any EmbeddingProvider,
        cache: EmbeddingCache = EmbeddingCache(capacity: 512)
    ) {
        self.base = base
        self.cache = cache
    }

    var dimensions: Int {
        base.dimensions
    }

    var modelIdentifier: String {
        base.modelIdentifier
    }

    func embed(_ text: String) async throws -> [Float] {
        if let cached = await cache.get(text) {
            return cached
        }

        let embedded = try await base.embed(text)
        await cache.set(text, value: embedded)
        return embedded
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else {
            return []
        }

        var orderedResults = Array(repeating: [Float](), count: texts.count)
        var missOrder: [String] = []
        var missPositions: [String: [Int]] = [:]

        for (index, text) in texts.enumerated() {
            if let cached = await cache.get(text) {
                orderedResults[index] = cached
                continue
            }

            missPositions[text, default: []].append(index)
            if missPositions[text]?.count == 1 {
                missOrder.append(text)
            }
        }

        if !missOrder.isEmpty {
            let embeddedMisses = try await base.embed(missOrder)
            guard embeddedMisses.count == missOrder.count else {
                throw ContextCoreError.embeddingFailed("embedBatch returned mismatched result count")
            }

            for (offset, text) in missOrder.enumerated() {
                let vector = embeddedMisses[offset]
                await cache.set(text, value: vector)
                for position in missPositions[text] ?? [] {
                    orderedResults[position] = vector
                }
            }
        }

        return orderedResults
    }
}

private final class EmbeddingAvailabilityState: @unchecked Sendable {
    struct Snapshot {
        var didProbe = false
        var isRealModelAvailable = false
        var reason: String?
        var didWarn = false
        var lastWarning: String?
    }

    private let lock = NSLock()
    private var state = Snapshot()

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    func storeProbe(available: Bool, reason: String?) {
        lock.lock()
        defer { lock.unlock() }
        state.didProbe = true
        state.isRealModelAvailable = available
        if !available {
            state.reason = reason
        } else {
            state.reason = nil
        }
    }

    func recordWarning(_ message: String, reason: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        state.didProbe = true
        state.isRealModelAvailable = false
        state.reason = reason
        state.lastWarning = message
        guard !state.didWarn else {
            return false
        }
        state.didWarn = true
        return true
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        state = Snapshot()
    }
}
