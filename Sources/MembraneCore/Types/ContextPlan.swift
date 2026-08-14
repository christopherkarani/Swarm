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
