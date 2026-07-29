/// Compact dynamic bitset backed by 64-bit machine words.
///
/// The bitset size is fixed at initialization by `wordCount`.
struct HiveBitset: Sendable, Equatable {
    private var words: [UInt64]

    init(wordCount: Int) {
        self.words = Array(repeating: 0, count: max(wordCount, 0))
    }

    init(bitCapacity: Int) {
        let wordsNeeded = max((max(bitCapacity, 0) + 63) / 64, 1)
        self.init(wordCount: wordsNeeded)
    }

    var isEmpty: Bool {
        words.allSatisfy { $0 == 0 }
    }

    mutating func removeAll() {
        for index in words.indices {
            words[index] = 0
        }
    }

    mutating func insert(_ bitIndex: Int) {
        guard let location = wordLocation(for: bitIndex) else { return }
        words[location.word] |= location.mask
    }

    func contains(_ bitIndex: Int) -> Bool {
        guard let location = wordLocation(for: bitIndex) else { return false }
        return (words[location.word] & location.mask) != 0
    }

    private func wordLocation(for bitIndex: Int) -> (word: Int, mask: UInt64)? {
        guard bitIndex >= 0 else { return nil }
        let word = bitIndex / 64
        guard words.indices.contains(word) else { return nil }
        let bitOffset = bitIndex % 64
        return (word: word, mask: UInt64(1) << UInt64(bitOffset))
    }
}
