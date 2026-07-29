public struct ContextRequest: Sendable {
    public let systemPrompt: String
    public let basePrompt: String
    public let userInput: String
    public let tools: [ToolManifest]
    public let toolPlan: ToolPlan
    public let history: [ContextSlice]
    public let memories: [ContextSlice]
    public let retrieval: [ContextSlice]
    public let pointers: [MemoryPointer]
    public let metadata: ContextMetadata
    public let recallQuery: String?
    public let recallLimit: Int

    public init(
        systemPrompt: String = "",
        basePrompt: String = "",
        userInput: String,
        tools: [ToolManifest] = [],
        toolPlan: ToolPlan = .allowAll,
        history: [ContextSlice] = [],
        memories: [ContextSlice] = [],
        retrieval: [ContextSlice] = [],
        pointers: [MemoryPointer] = [],
        metadata: ContextMetadata = ContextMetadata(),
        recallQuery: String? = nil,
        recallLimit: Int = 3
    ) {
        self.systemPrompt = systemPrompt
        self.basePrompt = basePrompt
        self.userInput = userInput
        self.tools = tools
        self.toolPlan = toolPlan
        self.history = history
        self.memories = memories
        self.retrieval = retrieval
        self.pointers = pointers
        self.metadata = metadata
        self.recallQuery = recallQuery
        self.recallLimit = max(1, recallLimit)
    }
}
