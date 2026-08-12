import ContextCoreEngine
import CoreML
import Foundation
import Logging

/// Runtime status of ContextCore's default CoreML MiniLM embedder.
///
/// When the model is missing, fails to load, or the process is running in the
/// Simulator, ContextCore falls back to hash-seeded pseudo-vectors. Rankings
/// from that path are not semantically meaningful.
public enum SemanticEmbeddingAvailability: Sendable {
    /// Whether the default CoreML MiniLM model can produce real embeddings.
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

    /// Resets process-wide fallback diagnostics. Intended for tests.
    public static func resetForTesting() {
        CoreMLEmbeddingProvider.resetAvailabilityForTesting()
    }
}

internal struct CoreMLEmbeddingProvider: EmbeddingProvider, Sendable {
    internal let dimension: Int = 384

    internal init() {
        Self.probeAndWarnIfNeeded()
    }

    func embed(_ text: String) async throws -> [Float] {
#if targetEnvironment(simulator)
        Self.takeFallback(
            reason: "CoreML embeddings are unavailable in the Simulator"
        )
        return Self.deterministicVector(for: text, dimension: dimension)
#else
        do {
            let model = try Self.loadModel()
            Self.markRealModelAvailable()
            let inputName = try Self.resolveInputName(for: model)
            let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: text])
            let output = try await model.prediction(from: provider)
            return try Self.extractEmbedding(from: output, model: model)
        } catch {
            Self.takeFallback(
                reason: "CoreML model minilm-l6-v2.mlpackage is missing or failed to load (\(error.localizedDescription))"
            )
            return Self.deterministicVector(for: text, dimension: dimension)
        }
#endif
    }

    func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else {
            return []
        }

#if targetEnvironment(simulator)
        Self.takeFallback(
            reason: "CoreML embeddings are unavailable in the Simulator"
        )
        return texts.map { Self.deterministicVector(for: $0, dimension: dimension) }
#else
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
                reason: "CoreML model minilm-l6-v2.mlpackage is missing or failed to load (\(error.localizedDescription))"
            )
            return texts.map { Self.deterministicVector(for: $0, dimension: dimension) }
        }
#endif
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
#if targetEnvironment(simulator)
        return (false, "CoreML embeddings are unavailable in the Simulator")
#else
        do {
            _ = try loadModel()
            return (true, nil)
        } catch {
            return (
                false,
                "CoreML model minilm-l6-v2.mlpackage is missing or failed to load (\(error.localizedDescription))"
            )
        }
#endif
    }

    private static func markRealModelAvailable() {
        availability.storeProbe(available: true, reason: nil)
    }

    private static func takeFallback(reason: String) {
        let message = """
        Real embeddings are unavailable (\(reason)). Semantic recall quality is degraded — \
        vector rankings are not meaningful until a real embedding model is available.
        """
        if availability.recordWarning(message, reason: reason) {
            embeddingLogger.warning("\(message)")
        }
    }

    private static func loadModel() throws -> MLModel {
        let candidates: [URL?] = [
            Bundle.module.url(forResource: "minilm-l6-v2", withExtension: "mlpackage", subdirectory: "Embeddings"),
            Bundle.module.url(forResource: "minilm-l6-v2", withExtension: "mlpackage", subdirectory: "Resources/Embeddings"),
            Bundle.module.url(forResource: "minilm-l6-v2", withExtension: "mlpackage"),
        ]

        guard let modelURL = candidates.compactMap({ $0 }).first else {
            throw ContextCoreError.embeddingFailed("Missing minilm-l6-v2.mlpackage in bundle resources")
        }

        return try MLModel(contentsOf: modelURL)
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

    var dimension: Int {
        base.dimension
    }

    func embed(_ text: String) async throws -> [Float] {
        if let cached = await cache.get(text) {
            return cached
        }

        let embedded = try await base.embed(text)
        await cache.set(text, value: embedded)
        return embedded
    }

    func embedBatch(_ texts: [String]) async throws -> [[Float]] {
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
            let embeddedMisses = try await base.embedBatch(missOrder)
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
