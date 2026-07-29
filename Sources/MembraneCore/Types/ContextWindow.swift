public struct ContextWindow: Sendable {
    public var systemPrompt: ContextSlice
    public var memory: [ContextSlice]
    public var tools: [ToolManifest]
    public var toolPlan: ToolPlan
    public var history: [ContextSlice]
    public var retrieval: [ContextSlice]
    public var pointers: [MemoryPointer]
    public var metadata: ContextMetadata

    public init(
        systemPrompt: ContextSlice,
        memory: [ContextSlice],
        tools: [ToolManifest],
        toolPlan: ToolPlan,
        history: [ContextSlice],
        retrieval: [ContextSlice],
        pointers: [MemoryPointer],
        metadata: ContextMetadata
    ) {
        self.systemPrompt = systemPrompt
        self.memory = memory
        self.tools = tools
        self.toolPlan = toolPlan
        self.history = history
        self.retrieval = retrieval
        self.pointers = pointers
        self.metadata = metadata
    }

    public var totalTokenCount: Int {
        systemPrompt.tokenCount
        + memory.reduce(0) { $0 + $1.tokenCount }
        + history.reduce(0) { $0 + $1.tokenCount }
        + retrieval.reduce(0) { $0 + $1.tokenCount }
    }
}

public struct ContextMetadata: Sendable, Equatable {
    public var turnNumber: Int
    public var sessionID: String
    public var modelProfile: BudgetProfile

    public init(
        turnNumber: Int = 0,
        sessionID: String = "",
        modelProfile: BudgetProfile = .foundationModels4K
    ) {
        self.turnNumber = turnNumber
        self.sessionID = sessionID
        self.modelProfile = modelProfile
    }
}
