import Foundation

/// Portable SHA-256 for lean Swarm.
///
/// Linux has no CryptoKit, and `swift-crypto` is Integrations-only, so core
/// hashing cannot import either. This implementation backs
/// `SwarmTranscript.transcriptHash()`.
enum SwarmSHA256: Sendable {
    static func hash(_ data: Data) -> [UInt8] {
        var hasher = Hasher()
        hasher.update(data)
        return hasher.finalize()
    }

    static func hex(_ data: Data) -> String {
        hash(data).map { String(format: "%02x", $0) }.joined()
    }

    struct Hasher {
        private var state: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]
        private var bitCount: UInt64 = 0
        private var buffer: [UInt8] = []

        mutating func update(_ data: Data) {
            bitCount += UInt64(data.count) * 8
            if buffer.isEmpty {
                consume(data)
                return
            }
            var combined = Data(buffer)
            combined.append(data)
            buffer.removeAll(keepingCapacity: true)
            consume(combined)
        }

        mutating func finalize() -> [UInt8] {
            var tail = Data(buffer)
            tail.append(0x80)
            while (tail.count % 64) != 56 {
                tail.append(0x00)
            }
            var length = bitCount.bigEndian
            withUnsafeBytes(of: &length) { tail.append(contentsOf: $0) }
            consume(tail)
            var digest = [UInt8]()
            digest.reserveCapacity(32)
            for word in state {
                digest.append(UInt8(truncatingIfNeeded: word >> 24))
                digest.append(UInt8(truncatingIfNeeded: word >> 16))
                digest.append(UInt8(truncatingIfNeeded: word >> 8))
                digest.append(UInt8(truncatingIfNeeded: word))
            }
            return digest
        }

        private mutating func consume(_ data: Data) {
            var offset = 0
            let bytes = [UInt8](data)
            while offset + 64 <= bytes.count {
                compress(Array(bytes[offset..<(offset + 64)]))
                offset += 64
            }
            if offset < bytes.count {
                buffer = Array(bytes[offset...])
            }
        }

        private mutating func compress(_ chunk: [UInt8]) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let base = i * 4
                w[i] = (UInt32(chunk[base]) << 24)
                    | (UInt32(chunk[base + 1]) << 16)
                    | (UInt32(chunk[base + 2]) << 8)
                    | UInt32(chunk[base + 3])
            }
            for i in 16..<64 {
                let s0 = rotateRight(w[i - 15], 7) ^ rotateRight(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotateRight(w[i - 2], 17) ^ rotateRight(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }

            var a = state[0]
            var b = state[1]
            var c = state[2]
            var d = state[3]
            var e = state[4]
            var f = state[5]
            var g = state[6]
            var h = state[7]

            for i in 0..<64 {
                let s1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = h &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj

                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }

            state[0] &+= a
            state[1] &+= b
            state[2] &+= c
            state[3] &+= d
            state[4] &+= e
            state[5] &+= f
            state[6] &+= g
            state[7] &+= h
        }
    }
}

private func rotateRight(_ value: UInt32, _ amount: UInt32) -> UInt32 {
    (value >> amount) | (value << (32 - amount))
}

private let k: [UInt32] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]
