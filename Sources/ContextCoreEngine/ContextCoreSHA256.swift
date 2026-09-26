import Foundation

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// SHA-256 helper with the same `canImport(CryptoKit)`-else-swift-crypto shape as `HiveSHA256`.
///
/// `SHA256` has a compatible streaming API in both CryptoKit and swift-crypto's
/// `Crypto` module, so this shim compiles on platforms with and without CryptoKit.
public enum ContextCoreSHA256 {
    /// Streaming SHA-256 hasher.
    ///
    /// Not `Sendable`: swift-crypto's `SHA256` (Linux) does not conform, so a
    /// conformance here would only compile on CryptoKit platforms. Same shape
    /// as `HiveSHA256`; all uses are function-local.
    public struct Hasher {
        private var hasher = SHA256()

        /// Creates a hasher.
        public init() {}

        /// Feeds data into the hash.
        public mutating func update(data: Data) {
            hasher.update(data: data)
        }

        /// Finalizes the hash and returns the raw digest bytes.
        public mutating func finalize() -> [UInt8] {
            Array(hasher.finalize())
        }

        /// Finalizes the hash and returns lowercase hex.
        public mutating func finalizeHex() -> String {
            finalize().map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Returns the raw SHA-256 digest bytes of `data`.
    public static func hash(data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }

    /// Returns the lowercase hex SHA-256 of `data`.
    public static func hex(data: Data) -> String {
        hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Returns the lowercase hex SHA-256 of `string`'s UTF-8 bytes.
    public static func hex(string: String) -> String {
        hex(data: Data(string.utf8))
    }
}
