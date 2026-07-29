/// Identifier for a graph node.
public struct HiveNodeID: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Routing decision for the next frontier.
public enum Route: Sendable, Equatable {
    case useGraphEdges
    case end
    case to([HiveNodeID])

    var normalized: Route {
        switch self {
        case .to(let nodes) where nodes.isEmpty:
            return .end
        default:
            return self
        }
    }
}

extension Route: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .to([HiveNodeID(value)])
    }
}

extension Route: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: HiveNodeID...) {
        self = .to(elements)
    }
}

/// Deterministic router used to select next nodes for a task.
public typealias HiveRouter<Schema: HiveSchema> = @Sendable (HiveStoreView<Schema>) -> Route
