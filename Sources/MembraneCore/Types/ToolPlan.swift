public struct ToolIndexEntry: Sendable, Equatable, Codable {
    public let name: String
    public let description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }
}

public enum ToolPlan: Sendable, Equatable, Codable {
    case allowAll
    case allowList(toolNames: [String])
    case jit(index: [ToolIndexEntry], loadedToolNames: [String])

    public static func allowList(normalized toolNames: [String]) -> ToolPlan {
        .allowList(toolNames: Array(Set(toolNames)).sorted())
    }

    public static func jit(normalized index: [ToolIndexEntry], loaded loadedToolNames: [String]) -> ToolPlan {
        .jit(
            index: index.sorted { lhs, rhs in
                if lhs.name != rhs.name {
                    return lhs.name < rhs.name
                }
                return lhs.description < rhs.description
            },
            loadedToolNames: Array(Set(loadedToolNames)).sorted()
        )
    }
}
