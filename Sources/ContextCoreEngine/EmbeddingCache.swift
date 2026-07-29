import CryptoKit
import Foundation

/// Actor-isolated LRU cache for embedding vectors.
public actor EmbeddingCache {
    private let capacity: Int
    private var storage: [String: [Float]] = [:]
    private var lruOrder: [String] = []

    /// Creates an embedding cache.
    ///
    /// - Parameter capacity: Maximum entry count retained.
    public init(capacity: Int = 512) {
        self.capacity = max(1, capacity)
    }

    /// Current number of cached entries.
    public var count: Int {
        storage.count
    }

    /// Retrieves a cached embedding for a key.
    ///
    /// - Parameter key: Raw cache key.
    /// - Returns: Cached embedding when present.
    public func get(_ key: String) -> [Float]? {
        let digest = Self.sha256Hex(key)
        guard let value = storage[digest] else {
            return nil
        }
        touch(digest)
        return value
    }

    /// Inserts or updates a cached embedding.
    ///
    /// - Parameters:
    ///   - key: Raw cache key.
    ///   - value: Embedding vector.
    public func set(_ key: String, value: [Float]) {
        let digest = Self.sha256Hex(key)

        if storage[digest] != nil {
            storage[digest] = value
            touch(digest)
            return
        }

        if storage.count >= capacity, let leastRecent = lruOrder.first {
            storage.removeValue(forKey: leastRecent)
            lruOrder.removeFirst()
        }

        storage[digest] = value
        lruOrder.append(digest)
    }

    private func touch(_ digest: String) {
        guard let index = lruOrder.firstIndex(of: digest) else {
            lruOrder.append(digest)
            return
        }
        if index == lruOrder.index(before: lruOrder.endIndex) {
            return
        }
        lruOrder.remove(at: index)
        lruOrder.append(digest)
    }

    private static func sha256Hex(_ key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
