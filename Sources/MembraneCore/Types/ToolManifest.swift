public struct ToolManifest: Sendable, Equatable {
    public let name: String
    public let description: String
    public var fullSchema: String?

    public init(name: String, description: String, fullSchema: String? = nil) {
        self.name = name
        self.description = description
        self.fullSchema = fullSchema
    }

    public var estimatedTokens: Int {
        if let fullSchema {
            return max(fullSchema.count / 4, 1)
        }

        return max((name.count + description.count) / 4, 1)
    }
}
