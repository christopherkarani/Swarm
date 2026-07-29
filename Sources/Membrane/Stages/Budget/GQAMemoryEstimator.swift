import MembraneCore

/// Stage 2 helper that annotates context budgets with architecture-aware
/// KV memory sizing when architecture metadata is explicitly provided.
public actor GQAMemoryEstimator: BudgetStage {
    private let architecture: ModelArchitectureInfo?
    private let kvMemoryBudgetBytes: Int?

    public init(architecture: ModelArchitectureInfo?, kvMemoryBudgetBytes: Int?) {
        self.architecture = architecture
        self.kvMemoryBudgetBytes = kvMemoryBudgetBytes
    }

    public func process(_ input: ContextWindow, budget: ContextBudget) async throws -> BudgetedContext {
        guard let architecture else {
            return BudgetedContext(window: input, budget: budget)
        }

        let kvBytesPerToken = architecture.kvBytesPerToken
        guard kvBytesPerToken > 0 else {
            return BudgetedContext(window: input, budget: budget)
        }

        let updatedBudget = budget.withKVSizing(
            kvBytesPerToken: kvBytesPerToken,
            kvMemoryBudgetBytes: kvMemoryBudgetBytes
        )

        return BudgetedContext(window: input, budget: updatedBudget)
    }
}
