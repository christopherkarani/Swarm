import Foundation

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

enum HiveSHA256 {
    struct Hasher {
        private var hasher = SHA256()

        mutating func update(data: Data) {
            hasher.update(data: data)
        }

        mutating func finalize() -> [UInt8] {
            Array(hasher.finalize())
        }
    }

    static func hash(data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }

    static func digest(data: Data) -> Data {
        Data(hash(data: data))
    }

    static func hex(data: Data) -> String {
        hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
