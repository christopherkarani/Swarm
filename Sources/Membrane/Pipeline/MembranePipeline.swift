import MembraneCore

public enum PipelineMode: Sendable {
    case full
    case budgetOnly
}

public actor MembranePipeline {
    private let baseBudget: ContextBudget
    private let intakeStage: (any IntakeStage)?
    private let allocatorStage: (any BudgetStage)?
    private let compressStage: (any CompressStage)?
    private let pageStage: (any PageStage)?
    private let emitStage: (any EmitStage)?
    private let mode: PipelineMode

    public init(
        budget: ContextBudget,
        intake: (any IntakeStage)? = nil,
        allocator: (any BudgetStage)? = nil,
        compress: (any CompressStage)? = nil,
        page: (any PageStage)? = nil,
        emit: (any EmitStage)? = nil,
        mode: PipelineMode = .full
    ) {
        self.baseBudget = budget
        self.intakeStage = intake
        self.allocatorStage = allocator
        self.compressStage = compress
        self.pageStage = page
        self.emitStage = emit
        self.mode = mode
    }

    public static func foundationModel(
        budget: ContextBudget = ContextBudget(totalTokens: 4096, profile: .foundationModels4K),
        intake: (any IntakeStage)? = nil,
        allocator: (any BudgetStage)? = nil,
        compress: (any CompressStage)? = nil,
        page: (any PageStage)? = nil,
        emit: (any EmitStage)? = nil
    ) -> MembranePipeline {
        MembranePipeline(
            budget: budget,
            intake: intake,
            allocator: allocator,
            compress: compress,
            page: page,
            emit: emit,
            mode: .budgetOnly
        )
    }

    public static func openModel(
        budget: ContextBudget,
        intake: (any IntakeStage)? = nil,
        allocator: (any BudgetStage)? = nil,
        compress: (any CompressStage)? = nil,
        page: (any PageStage)? = nil,
        emit: (any EmitStage)? = nil
    ) -> MembranePipeline {
        MembranePipeline(
            budget: budget,
            intake: intake,
            allocator: allocator,
            compress: compress,
            page: page,
            emit: emit,
            mode: .full
        )
    }

    public func prepare(_ request: ContextRequest) async throws -> ContextPlan {
        var budget = baseBudget

        var window = ContextWindow(
            systemPrompt: ContextSlice(
                content: request.systemPrompt,
                tokenCount: request.systemPrompt.count,
                importance: 1.0,
                source: .system,
                tier: .full,
                timestamp: .now
            ),
            memory: request.memories,
            tools: request.tools,
            toolPlan: request.toolPlan,
            history: request.history,
            retrieval: request.retrieval,
            pointers: request.pointers,
            metadata: request.metadata
        )

        if let intakeStage {
            window = try await intakeStage.process(request, budget: budget)
        }

        var budgeted = BudgetedContext(window: window, budget: budget)
        if let allocatorStage {
            budgeted = try await allocatorStage.process(budgeted.window, budget: budgeted.budget)
        }
        budget = budgeted.budget

        var compressed = CompressedContext(
            window: budgeted.window,
            budget: budgeted.budget,
            compressionReport: CompressionReport(
                originalTokens: budgeted.window.totalTokenCount,
                compressedTokens: budgeted.window.totalTokenCount,
                techniquesApplied: []
            )
        )
        if let compressStage {
            compressed = try await compressStage.process(
                BudgetedContext(window: compressed.window, budget: compressed.budget),
                budget: compressed.budget
            )
        }
        budget = compressed.budget

        var paged = PagedContext(window: compressed.window, budget: compressed.budget, pagedOut: [])
        if mode == .full, let pageStage {
            paged = try await pageStage.process(
                CompressedContext(
                    window: paged.window,
                    budget: paged.budget,
                    compressionReport: compressed.compressionReport
                ),
                budget: paged.budget
            )
        }
        budget = paged.budget

        var plannedRequest = ContextPlan(
            prompt: request.basePrompt.isEmpty ? request.userInput : request.basePrompt,
            systemPrompt: paged.window.systemPrompt.content,
            toolPlan: paged.window.toolPlan,
            budget: budget,
            metadata: paged.window.metadata
        )
        if mode == .full, let emitStage {
            plannedRequest = try await emitStage.process(paged, budget: budget)
        }

        return plannedRequest
    }
}
