import MembraneCore

/// Stage 2 budget allocator that consolidates context demands into deterministic
/// bucket allocations.
public actor UnifiedBudgetAllocator: BudgetStage {
    private let allocationPriority: [BucketID] = [
        .system,
        .history,
        .memory,
        .tools,
        .retrieval,
        .toolIO,
    ]

    public init() {}

    public func process(_ input: ContextWindow, budget: ContextBudget) async throws -> BudgetedContext {
        var mutableBudget = budget

        let demand: [BucketID: Int] = [
            .system: input.systemPrompt.tokenCount,
            .history: input.history.reduce(0) { $0 + $1.tokenCount },
            .memory: input.memory.reduce(0) { $0 + $1.tokenCount },
            .tools: input.tools.reduce(0) { $0 + $1.estimatedTokens },
            .retrieval: input.retrieval.reduce(0) { $0 + $1.tokenCount },
            .toolIO: 0,
        ]

        for bucket in allocationPriority {
            let requested = max(demand[bucket] ?? 0, 0)
            guard requested > 0 else {
                continue
            }

            let toAllocate = min(requested, mutableBudget.remaining(for: bucket), mutableBudget.totalRemaining)
            if toAllocate > 0 {
                try mutableBudget.allocate(toAllocate, to: bucket)
            }
        }

        return BudgetedContext(window: input, budget: mutableBudget)
    }
}
