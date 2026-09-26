import Foundation

/// Typed identifier for an embedding model.
///
/// Keeps model names out of raw strings at call sites; the raw value is what
/// ``EmbeddingProvider/modelIdentifier`` and cache keys carry.
public struct EmbeddingModelID: Hashable, Codable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    /// Raw model identifier.
    public let rawValue: String

    /// Creates an ID from a raw identifier.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Deterministic hash-seeded fallback vectors.
    public static let hashFallback = EmbeddingModelID("hash-fallback-v1")

    /// Names a remote or injected compute backend.
    public static func remote(_ name: String) -> EmbeddingModelID {
        EmbeddingModelID("remote:\(name)")
    }

    /// Names a caller-defined local model.
    public static func custom(_ name: String) -> EmbeddingModelID {
        EmbeddingModelID(name)
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String {
        rawValue
    }
}

/// Typed failures for the portable embedding providers.
public enum PortableEmbeddingError: Error, Sendable, Equatable {
    /// A vector did not match the provider dimensionality.
    case invalidDimensions(expected: Int, got: Int)
    /// A batch result did not match the batch input count.
    case batchCountMismatch(expected: Int, got: Int)
    /// The injected remote/compute backend failed.
    case remoteFailed(reason: String)
    /// A cache snapshot could not be restored.
    case snapshotIncompatible(reason: String)
}

/// Deterministic hash-seeded embedding provider.
///
/// Pure Swift with no model files, no network, and no CoreML: the portable
/// local fallback used where no real embedding model is available (Linux).
/// Vectors are L2-normalized and stable per input, so behavior is identical
/// on every platform. Rankings from this path are not semantically meaningful.
public struct DeterministicHashEmbeddingProvider: EmbeddingProvider, Sendable {
    /// Dimensionality produced by this provider.
    public let dimensions: Int
    /// Model identity carried by `modelIdentifier`.
    public let modelID: EmbeddingModelID

    /// Human-readable model identifier.
    public var modelIdentifier: String {
        modelID.rawValue
    }

    /// Creates a hash-seeded provider.
    public init(dimensions: Int = 384, modelID: EmbeddingModelID = .hashFallback) {
        self.dimensions = dimensions
        self.modelID = modelID
    }

    /// Produces a deterministic pseudo-vector for a single text input.
    ///
    /// `async` (not sync) so this shadows the protocol-extension default on
    /// the concrete type; a sync method satisfies the requirement but loses
    /// overload resolution to the default.
    public func embed(_ text: String) async -> [Float] {
        Self.deterministicVector(for: text, dimension: dimensions)
    }

    /// Produces deterministic pseudo-vectors for multiple inputs.
    public func embed(_ texts: [String]) async -> [[Float]] {
        texts.map { Self.deterministicVector(for: $0, dimension: dimensions) }
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

    private static func l2Normalize(_ vector: [Float]) -> [Float] {
        let norm = vector.reduce(0) { partial, value in
            partial + (value * value)
        }.squareRoot()

        guard norm > 0 else {
            return vector
        }

        return vector.map { $0 / norm }
    }
}

/// Injectable embedding seam over a caller-supplied batch handler.
///
/// This is how remote models, GPU compute, or test doubles plug into the
/// portable stack without touching provider call sites. Handler output is
/// validated: count must match the batch and every vector must match
/// `dimensions`.
public struct ClosureEmbeddingProvider: EmbeddingProvider, Sendable {
    /// Dimensionality produced by this provider.
    public let dimensions: Int
    /// Model identity carried by `modelIdentifier`.
    public let modelID: EmbeddingModelID
    private let handler: @Sendable ([String]) async throws -> [[Float]]

    /// Human-readable model identifier.
    public var modelIdentifier: String {
        modelID.rawValue
    }

    /// Creates a provider backed by a batch handler.
    ///
    /// - Parameters:
    ///   - dimensions: Expected vector width; handler output is validated.
    ///   - modelID: Model identity.
    ///   - handler: Batch embedder. May throw provider-specific errors, which
    ///     are wrapped in ``PortableEmbeddingError/remoteFailed(reason:)``.
    public init(
        dimensions: Int,
        modelID: EmbeddingModelID = .remote("closure"),
        handler: @Sendable @escaping ([String]) async throws -> [[Float]]
    ) {
        self.dimensions = dimensions
        self.modelID = modelID
        self.handler = handler
    }

    /// Creates a provider from a single-text handler.
    public init(
        dimensions: Int,
        modelID: EmbeddingModelID = .remote("closure"),
        embedOne: @Sendable @escaping (String) async throws -> [Float]
    ) {
        self.init(dimensions: dimensions, modelID: modelID) { texts in
            var vectors: [[Float]] = []
            vectors.reserveCapacity(texts.count)
            for text in texts {
                vectors.append(try await embedOne(text))
            }
            return vectors
        }
    }

    /// Embeds a single text via the injected handler.
    public func embed(_ text: String) async throws -> [Float] {
        try await embed([text])[0]
    }

    /// Embeds a batch via the injected handler.
    public func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else {
            return []
        }
        let vectors: [[Float]]
        do {
            vectors = try await handler(texts)
        } catch let error as PortableEmbeddingError {
            throw error
        } catch {
            throw PortableEmbeddingError.remoteFailed(reason: String(describing: error))
        }
        guard vectors.count == texts.count else {
            throw PortableEmbeddingError.batchCountMismatch(expected: texts.count, got: vectors.count)
        }
        for vector in vectors where vector.count != dimensions {
            throw PortableEmbeddingError.invalidDimensions(expected: dimensions, got: vector.count)
        }
        return vectors
    }
}

/// Embedding provider that falls back to deterministic local vectors.
///
/// Tries `primary` (typically a ``ClosureEmbeddingProvider`` over remote or
/// accelerated compute) and falls back to `fallback` when the primary throws,
/// so recall keeps working — degraded — when the model path is down.
public struct CompositeEmbeddingProvider: EmbeddingProvider, Sendable {
    private let primary: any EmbeddingProvider
    private let fallback: any EmbeddingProvider

    /// Dimensionality of the primary provider.
    public var dimensions: Int {
        primary.dimensions
    }

    /// Identity of the primary provider.
    public var modelIdentifier: String {
        primary.modelIdentifier
    }

    /// Creates a primary/fallback pair.
    ///
    /// - Parameters:
    ///   - primary: Preferred provider (remote/compute seam).
    ///   - fallback: Local fallback. Defaults to hash-seeded vectors sized to
    ///     the primary's dimensionality.
    public init(
        primary: any EmbeddingProvider,
        fallback: (any EmbeddingProvider)? = nil
    ) {
        self.primary = primary
        self.fallback = fallback ?? DeterministicHashEmbeddingProvider(dimensions: primary.dimensions)
    }

    /// Embeds via the primary, or the fallback when the primary throws.
    public func embed(_ text: String) async throws -> [Float] {
        do {
            return try await primary.embed(text)
        } catch {
            return try await fallback.embed(text)
        }
    }

    /// Batch-embeds via the primary, or the fallback when the primary throws.
    public func embed(_ texts: [String]) async throws -> [[Float]] {
        do {
            return try await primary.embed(texts)
        } catch {
            return try await fallback.embed(texts)
        }
    }
}

/// Codable snapshot of a ``PortableCachingEmbeddingProvider`` cache.
///
/// Entries are sorted by key so snapshots are deterministic for a given state.
public struct EmbeddingCacheSnapshot: Sendable, Codable, Equatable {
    /// A single cached entry.
    public struct Entry: Sendable, Codable, Equatable {
        /// Cached input text.
        public let key: String
        /// Cached vector.
        public let vector: [Float]

        /// Creates a cache entry.
        public init(key: String, vector: [Float]) {
            self.key = key
            self.vector = vector
        }
    }

    /// Model identity of the snapshotted provider.
    public let modelID: EmbeddingModelID
    /// Provider dimensionality.
    public let dimensions: Int
    /// Entries sorted by key.
    public let entries: [Entry]

    /// Creates a cache snapshot.
    public init(modelID: EmbeddingModelID, dimensions: Int, entries: [Entry]) {
        self.modelID = modelID
        self.dimensions = dimensions
        self.entries = entries.sorted { $0.key < $1.key }
    }
}

/// Portable caching decorator over any embedding provider.
///
/// Pure-Swift FIFO cache with snapshot/restore, so Linux hosts get the same
/// embed-cache behavior as the CoreML-backed path without Engine imports.
public actor PortableCachingEmbeddingProvider: EmbeddingProvider {
    private let base: any EmbeddingProvider
    private let capacity: Int
    private var cached: [String: [Float]] = [:]
    private var insertionOrder: [String] = []

    /// Dimensionality of the wrapped provider.
    public nonisolated var dimensions: Int {
        base.dimensions
    }

    /// Identity of the wrapped provider.
    public nonisolated var modelIdentifier: String {
        base.modelIdentifier
    }

    /// Number of cached entries.
    public var count: Int {
        cached.count
    }

    /// Creates a caching provider.
    ///
    /// - Parameters:
    ///   - base: Wrapped provider.
    ///   - capacity: Maximum entries retained. Oldest entries evict first.
    public init(base: any EmbeddingProvider, capacity: Int = 512) {
        self.base = base
        self.capacity = max(1, capacity)
    }

    /// Embeds a single text, serving cache hits without calling the base.
    public func embed(_ text: String) async throws -> [Float] {
        if let hit = cached[text] {
            return hit
        }
        let vector = try await base.embed(text)
        store(text, vector: vector)
        return vector
    }

    /// Batch-embeds, fanning cache misses out to a single base call.
    public func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else {
            return []
        }
        var ordered = Array(repeating: [Float](), count: texts.count)
        var missOrder: [String] = []
        var missPositions: [String: [Int]] = [:]
        for (index, text) in texts.enumerated() {
            if let hit = cached[text] {
                ordered[index] = hit
                continue
            }
            missPositions[text, default: []].append(index)
            if missPositions[text]?.count == 1 {
                missOrder.append(text)
            }
        }
        if !missOrder.isEmpty {
            let misses = try await base.embed(missOrder)
            guard misses.count == missOrder.count else {
                throw PortableEmbeddingError.batchCountMismatch(expected: missOrder.count, got: misses.count)
            }
            for (offset, text) in missOrder.enumerated() {
                store(text, vector: misses[offset])
                for position in missPositions[text] ?? [] {
                    ordered[position] = misses[offset]
                }
            }
        }
        return ordered
    }

    /// Captures a deterministic snapshot of cached entries.
    public func snapshot() -> EmbeddingCacheSnapshot {
        EmbeddingCacheSnapshot(
            modelID: EmbeddingModelID(base.modelIdentifier),
            dimensions: base.dimensions,
            entries: cached.map { EmbeddingCacheSnapshot.Entry(key: $0.key, vector: $0.value) }
        )
    }

    /// Replaces cache state with `snapshot`.
    ///
    /// - Throws: ``PortableEmbeddingError/snapshotIncompatible(reason:)`` when
    ///   the snapshot targets a different model or dimensionality.
    public func restore(_ snapshot: EmbeddingCacheSnapshot) throws {
        guard snapshot.modelID.rawValue == base.modelIdentifier else {
            throw PortableEmbeddingError.snapshotIncompatible(
                reason: "snapshot model \(snapshot.modelID) does not match \(base.modelIdentifier)"
            )
        }
        guard snapshot.dimensions == base.dimensions else {
            throw PortableEmbeddingError.snapshotIncompatible(
                reason: "snapshot dimensions \(snapshot.dimensions) do not match \(base.dimensions)"
            )
        }
        for entry in snapshot.entries where entry.vector.count != base.dimensions {
            throw PortableEmbeddingError.snapshotIncompatible(
                reason: "snapshot entry \(entry.key) has width \(entry.vector.count)"
            )
        }
        cached = [:]
        insertionOrder = []
        for entry in snapshot.entries.prefix(capacity) {
            store(entry.key, vector: entry.vector)
        }
    }

    private func store(_ key: String, vector: [Float]) {
        if cached[key] == nil {
            insertionOrder.append(key)
            while insertionOrder.count > capacity {
                let evicted = insertionOrder.removeFirst()
                cached.removeValue(forKey: evicted)
            }
        }
        cached[key] = vector
    }
}
