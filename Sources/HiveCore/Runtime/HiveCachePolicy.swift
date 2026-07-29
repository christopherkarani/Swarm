import Foundation

// MARK: - Protocol

/// Protocol for custom cache key generation.
/// Implement to control which store values influence whether a cached output is reused.
public protocol HiveCacheKeyProviding<Schema>: Sendable {
    associatedtype Schema: HiveSchema
    func cacheKey(forNode nodeID: HiveNodeID, store: HiveStoreView<Schema>) throws -> String
}

// MARK: - Type-erased key provider

/// Type-erased wrapper for `HiveCacheKeyProviding`, following `AnyHiveCheckpointStore` pattern.
public struct AnyHiveCacheKeyProvider<Schema: HiveSchema>: Sendable {
    private let _cacheKey: @Sendable (HiveNodeID, HiveStoreView<Schema>) throws -> String

    public init<P: HiveCacheKeyProviding>(_ provider: P) where P.Schema == Schema {
        self._cacheKey = { node, store in try provider.cacheKey(forNode: node, store: store) }
    }

    /// Closure-based convenience initializer.
    public init(_ keyFunction: @escaping @Sendable (HiveNodeID, HiveStoreView<Schema>) throws -> String) {
        self._cacheKey = keyFunction
    }

    public func cacheKey(forNode nodeID: HiveNodeID, store: HiveStoreView<Schema>) throws -> String {
        try _cacheKey(nodeID, store)
    }
}

// MARK: - Cache entry

/// A single cached node output.
struct HiveCacheEntry<Schema: HiveSchema>: Sendable {
    let key: String
    let output: HiveNodeOutput<Schema>
    let expiresAt: UInt64?  // ContinuousClock.Instant nanoseconds; nil = no expiry
    var lastUsedOrder: UInt64  // for LRU eviction
}

// MARK: - Cache policy

/// Per-node result caching configuration.
/// Reuses the SHA-256 key derivation approach from `HiveTaskLocalFingerprint`.
public struct HiveCachePolicy<Schema: HiveSchema>: Sendable {
    public let maxEntries: Int
    public let ttlNanoseconds: UInt64?
    public let keyProvider: AnyHiveCacheKeyProvider<Schema>

    public init(
        maxEntries: Int,
        ttlNanoseconds: UInt64?,
        keyProvider: AnyHiveCacheKeyProvider<Schema>
    ) {
        self.maxEntries = max(1, maxEntries)
        self.ttlNanoseconds = ttlNanoseconds
        self.keyProvider = keyProvider
    }

    /// LRU cache keyed by SHA-256 of all global channel version counters.
    /// Zero I/O overhead — uses version counters already maintained by the runtime.
    public static func lru(maxEntries: Int = 128) -> HiveCachePolicy<Schema> {
        // Capture sorted global specs at factory time — once, not per call.
        // If registry construction fails the specs list is empty, producing a per-nodeID
        // constant key rather than a store-content-aware key. This is a safe degradation
        // (no cross-node collisions) but caching becomes less selective.
        let sortedGlobalSpecs = (try? HiveSchemaRegistry<Schema>())?
            .sortedChannelSpecs.filter { $0.scope == .global } ?? []
        return HiveCachePolicy(
            maxEntries: maxEntries,
            ttlNanoseconds: nil,
            keyProvider: AnyHiveCacheKeyProvider { nodeID, store in
                Self.versionBasedKey(nodeID: nodeID, store: store, sortedGlobalSpecs: sortedGlobalSpecs)
            }
        )
    }

    /// LRU cache with a time-to-live. Entries older than `ttl` are invalidated.
    public static func lruTTL(maxEntries: Int = 128, ttl: Duration) -> HiveCachePolicy<Schema> {
        // Cap seconds at ~292 years before converting to avoid UInt64 overflow.
        let cappedSeconds = min(UInt64(max(0, ttl.components.seconds)), 9_000_000_000)
        let subSecondNs = UInt64(ttl.components.attoseconds / 1_000_000_000)
        let ttlNs = cappedSeconds &* 1_000_000_000 &+ subSecondNs
        // Capture sorted global specs at factory time — same rationale as lru().
        let sortedGlobalSpecs = (try? HiveSchemaRegistry<Schema>())?
            .sortedChannelSpecs.filter { $0.scope == .global } ?? []
        return HiveCachePolicy(
            maxEntries: maxEntries,
            ttlNanoseconds: ttlNs,
            keyProvider: AnyHiveCacheKeyProvider { nodeID, store in
                Self.versionBasedKey(nodeID: nodeID, store: store, sortedGlobalSpecs: sortedGlobalSpecs)
            }
        )
    }

    /// Cache keyed by a specific subset of channels (cheaper than hashing the full store).
    public static func channels(
        _ channelIDs: HiveChannelID...,
        maxEntries: Int = 128
    ) -> HiveCachePolicy<Schema> {
        let ids = channelIDs
        return HiveCachePolicy(
            maxEntries: maxEntries,
            ttlNanoseconds: nil,
            keyProvider: AnyHiveCacheKeyProvider { nodeID, store in
                Self.channelSubsetKey(nodeID: nodeID, channelIDs: ids, store: store)
            }
        )
    }

    // MARK: - Key helpers

    private static func versionBasedKey(
        nodeID: HiveNodeID,
        store: HiveStoreView<Schema>,
        sortedGlobalSpecs: [AnyHiveChannelSpec<Schema>]
    ) -> String {
        // Use nodeID as salt so two different nodes with identical state produce different keys.
        nodeID.rawValue + ":" + storeHashKey(store: store, sortedGlobalSpecs: sortedGlobalSpecs)
    }

    private static func channelSubsetKey(
        nodeID: HiveNodeID,
        channelIDs: [HiveChannelID],
        store: HiveStoreView<Schema>
    ) -> String {
        var hasher = HiveSHA256.Hasher()
        hasher.update(data: Data(nodeID.rawValue.utf8))
        for id in channelIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
            hasher.update(data: Data(id.rawValue.utf8))
            // Best-effort: encode to data if codec available, else use channel ID only.
            if let value = try? store.valueAny(for: id),
               let data = try? _sharedCacheKeyEncoder.encode(AnySendableWrapper(value)) {
                hasher.update(data: data)
            }
        }
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Hashes the store's current values via best-effort JSON encoding.
    /// `sortedGlobalSpecs` must be pre-computed at factory time (not per call) to avoid
    /// per-invocation registry construction and the silent-empty-hash failure mode.
    private static func storeHashKey(
        store: HiveStoreView<Schema>,
        sortedGlobalSpecs: [AnyHiveChannelSpec<Schema>]
    ) -> String {
        var hasher = HiveSHA256.Hasher()
        for spec in sortedGlobalSpecs {
            hasher.update(data: Data(spec.id.rawValue.utf8))
            if let encodeBox = spec._encodeBox,
               let value = try? store.valueAny(for: spec.id),
               let encoded = try? encodeBox(value) {
                hasher.update(data: encoded)
            }
        }
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Internal helpers

/// Shared encoder used for cache key hashing — avoids per-call allocation.
private let _sharedCacheKeyEncoder = JSONEncoder()

/// Thin `Encodable` wrapper for `any Sendable` — used only in cache key hashing.
private struct AnySendableWrapper: Encodable {
    let value: any Sendable
    init(_ value: any Sendable) { self.value = value }
    func encode(to encoder: Encoder) throws {
        if let encodable = value as? any Encodable {
            try encodable.encode(to: encoder)
        }
    }
}

// MARK: - Per-node cache store (used by HiveRuntime)

/// In-memory LRU cache for a single node's outputs.
struct HiveNodeCache<Schema: HiveSchema>: Sendable {
    private(set) var entries: [HiveCacheEntry<Schema>] = []
    private var accessOrder: UInt64 = 0

    init() {}

    mutating func lookup(
        key: String,
        policy: HiveCachePolicy<Schema>,
        nowNanoseconds: UInt64
    ) -> HiveNodeOutput<Schema>? {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        let entry = entries[index]
        if let expiry = entry.expiresAt, nowNanoseconds > expiry {
            entries.remove(at: index)
            return nil
        }
        accessOrder &+= 1
        entries[index].lastUsedOrder = accessOrder
        return entry.output
    }

    mutating func store(
        key: String,
        output: HiveNodeOutput<Schema>,
        policy: HiveCachePolicy<Schema>,
        nowNanoseconds: UInt64
    ) {
        let expiry = policy.ttlNanoseconds.map { nowNanoseconds &+ $0 }
        accessOrder &+= 1
        if let index = entries.firstIndex(where: { $0.key == key }) {
            entries[index] = HiveCacheEntry(key: key, output: output, expiresAt: expiry, lastUsedOrder: accessOrder)
        } else {
            if entries.count >= policy.maxEntries {
                evictLRU()
            }
            entries.append(HiveCacheEntry(key: key, output: output, expiresAt: expiry, lastUsedOrder: accessOrder))
        }
    }

    private mutating func evictLRU() {
        guard !entries.isEmpty else { return }
        if let idx = entries.indices.min(by: { entries[$0].lastUsedOrder < entries[$1].lastUsedOrder }) {
            entries.remove(at: idx)
        }
    }
}
