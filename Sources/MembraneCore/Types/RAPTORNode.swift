public struct RAPTORNode: Sendable, Codable, Equatable {
    public let id: String
    public let parentID: String?
    public let depth: Int
    public let text: String
    public let tokenCount: Int

    public init(
        id: String,
        parentID: String?,
        depth: Int,
        text: String,
        tokenCount: Int
    ) {
        self.id = id
        self.parentID = parentID
        self.depth = depth
        self.text = text
        self.tokenCount = tokenCount
    }
}
