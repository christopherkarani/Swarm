public protocol IntakeStage: MembraneStage where Input == ContextRequest, Output == ContextWindow {}
public protocol BudgetStage: MembraneStage where Input == ContextWindow, Output == BudgetedContext {}
public protocol CompressStage: MembraneStage where Input == BudgetedContext, Output == CompressedContext {}
public protocol PageStage: MembraneStage where Input == CompressedContext, Output == PagedContext {}
public protocol EmitStage: MembraneStage where Input == PagedContext, Output == ContextPlan {}

public struct BudgetedContext: Sendable {
    public let window: ContextWindow
    public let budget: ContextBudget

    public init(window: ContextWindow, budget: ContextBudget) {
        self.window = window
        self.budget = budget
    }
}

public struct CompressionReport: Sendable {
    public let originalTokens: Int
    public let compressedTokens: Int
    public let techniquesApplied: [String]

    public var ratio: Double {
        Double(compressedTokens) / Double(max(originalTokens, 1))
    }

    public init(originalTokens: Int, compressedTokens: Int, techniquesApplied: [String]) {
        self.originalTokens = originalTokens
        self.compressedTokens = compressedTokens
        self.techniquesApplied = techniquesApplied
    }
}

public struct CompressedContext: Sendable {
    public let window: ContextWindow
    public let budget: ContextBudget
    public let compressionReport: CompressionReport

    public init(window: ContextWindow, budget: ContextBudget, compressionReport: CompressionReport) {
        self.window = window
        self.budget = budget
        self.compressionReport = compressionReport
    }
}

public struct PagedContext: Sendable {
    public let window: ContextWindow
    public let budget: ContextBudget
    public let pagedOut: [ContextSlice]

    public init(window: ContextWindow, budget: ContextBudget, pagedOut: [ContextSlice]) {
        self.window = window
        self.budget = budget
        self.pagedOut = pagedOut
    }
}

public struct ContextPlan: Sendable {
    public let prompt: String
    public let systemPrompt: String
    public let toolPlan: ToolPlan
    public let budget: ContextBudget
    public let metadata: ContextMetadata

    public init(
        prompt: String,
        systemPrompt: String,
        toolPlan: ToolPlan,
        budget: ContextBudget,
        metadata: ContextMetadata
    ) {
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.toolPlan = toolPlan
        self.budget = budget
        self.metadata = metadata
    }
}

public typealias PlannedRequest = ContextPlan
