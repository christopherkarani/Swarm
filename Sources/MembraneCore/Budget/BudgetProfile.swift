public enum BudgetProfile: Sendable, Equatable {
    case foundationModels4K
    case openModel8K
    case cloud200K
    case custom(buckets: [BucketID: Int])

    public func ceilings(for totalTokens: Int) -> [BucketID: Int] {
        switch self {
        case .foundationModels4K:
            return [
                .system: 400,
                .history: 800,
                .memory: 300,
                .tools: 500,
                .retrieval: 900,
                .toolIO: 0,
                .outputReserve: 1000,
                .protocolOverhead: 0,
                .safetyMargin: 196,
            ]
        case .openModel8K:
            return [
                .system: 500,
                .history: 1500,
                .memory: 800,
                .tools: 800,
                .retrieval: 2500,
                .toolIO: 0,
                .outputReserve: 2000,
                .protocolOverhead: 0,
                .safetyMargin: 92,
            ]
        case .cloud200K:
            let system = totalTokens / 20
            let outputReserve = totalTokens / 5
            let tools = totalTokens / 10
            let history = totalTokens / 4
            let retrieval = totalTokens / 4
            let memory = totalTokens / 10
            let accounted = system + outputReserve + tools + history + retrieval + memory
            return [
                .system: system,
                .history: history,
                .memory: memory,
                .tools: tools,
                .retrieval: retrieval,
                .toolIO: 0,
                .outputReserve: outputReserve,
                .protocolOverhead: 0,
                .safetyMargin: max(totalTokens - accounted, 0),
            ]
        case .custom(let buckets):
            return buckets
        }
    }
}
