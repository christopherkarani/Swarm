import OrderedCollections

public struct ContextBudget: Sendable {
    public struct BucketAllocation: Sendable {
        public let ceiling: Int
        public private(set) var allocated: Int

        public var remaining: Int {
            max(ceiling - allocated, 0)
        }

        public init(ceiling: Int, allocated: Int = 0) {
            self.ceiling = ceiling
            self.allocated = allocated
        }

        mutating func allocate(_ tokens: Int) {
            allocated += tokens
        }
    }

    public let totalTokens: Int
    private var buckets: OrderedDictionary<BucketID, BucketAllocation>
    public private(set) var kvBytesPerToken: Int?
    public private(set) var kvMemoryBudgetBytes: Int?

    public init(
        totalTokens: Int,
        profile: BudgetProfile,
        kvBytesPerToken: Int? = nil,
        kvMemoryBudgetBytes: Int? = nil
    ) {
        self.totalTokens = totalTokens
        self.kvBytesPerToken = kvBytesPerToken
        self.kvMemoryBudgetBytes = kvMemoryBudgetBytes

        let profileCeilings = profile.ceilings(for: totalTokens)
        var ordered = OrderedDictionary<BucketID, BucketAllocation>()
        for bucket in BucketID.allCases {
            let ceiling = max(profileCeilings[bucket] ?? 0, 0)
            ordered[bucket] = BucketAllocation(ceiling: ceiling)
        }
        self.buckets = ordered
    }

    public func ceiling(for bucket: BucketID) -> Int {
        buckets[bucket]?.ceiling ?? 0
    }

    public func remaining(for bucket: BucketID) -> Int {
        buckets[bucket]?.remaining ?? 0
    }

    public func allocated(for bucket: BucketID) -> Int {
        buckets[bucket]?.allocated ?? 0
    }

    private mutating func setKVSizing(kvBytesPerToken: Int?, kvMemoryBudgetBytes: Int?) {
        self.kvBytesPerToken = kvBytesPerToken
        self.kvMemoryBudgetBytes = kvMemoryBudgetBytes
    }

    public func withKVSizing(kvBytesPerToken: Int?, kvMemoryBudgetBytes: Int?) -> ContextBudget {
        var copy = self
        copy.setKVSizing(kvBytesPerToken: kvBytesPerToken, kvMemoryBudgetBytes: kvMemoryBudgetBytes)
        return copy
    }

    public var totalAllocated: Int {
        buckets.values.reduce(0) { partial, allocation in
            partial + allocation.allocated
        }
    }

    public var totalRemaining: Int {
        max(totalTokens - totalAllocated, 0)
    }

    public var maxSequenceLength: Int? {
        guard let bytesPerToken = kvBytesPerToken,
              let memoryBudget = kvMemoryBudgetBytes,
              bytesPerToken > 0 else {
            return nil
        }

        return memoryBudget / bytesPerToken
    }

    public mutating func allocate(_ tokens: Int, to bucket: BucketID) throws {
        guard tokens >= 0 else {
            throw MembraneError.budgetExceeded(bucket: bucket, requested: tokens, available: 0)
        }

        guard var allocation = buckets[bucket] else {
            throw MembraneError.budgetExceeded(bucket: bucket, requested: tokens, available: 0)
        }

        let available = min(allocation.remaining, totalRemaining)
        guard tokens <= available else {
            throw MembraneError.budgetExceeded(bucket: bucket, requested: tokens, available: available)
        }

        allocation.allocate(tokens)
        buckets[bucket] = allocation
    }

    public mutating func reset(_ bucket: BucketID) {
        guard let allocation = buckets[bucket] else {
            return
        }

        buckets[bucket] = BucketAllocation(ceiling: allocation.ceiling)
    }

    public var bucketAllocations: [BucketID: Int] {
        Dictionary(uniqueKeysWithValues: buckets.map { ($0.key, $0.value.allocated) })
    }
}
