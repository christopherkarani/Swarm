import Foundation

/// A stable, deterministic description of a compiled Hive graph.
public struct HiveGraphDescription: Codable, Sendable, Equatable {
    public struct StaticEdge: Codable, Sendable, Equatable {
        public let from: HiveNodeID
        public let to: HiveNodeID

        public init(from: HiveNodeID, to: HiveNodeID) {
            self.from = from
            self.to = to
        }
    }

    public struct JoinEdge: Codable, Sendable, Equatable {
        public let id: String
        public let parents: [HiveNodeID]
        public let target: HiveNodeID

        public init(id: String, parents: [HiveNodeID], target: HiveNodeID) {
            self.id = id
            self.parents = parents
            self.target = target
        }
    }

    public enum OutputProjection: Codable, Sendable, Equatable {
        case fullStore
        case channels([String])

        private enum CodingKeys: String, CodingKey {
            case fullStore
            case channels
        }

        private struct Empty: Codable, Sendable {}

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.fullStore) {
                _ = try container.decode(Empty.self, forKey: .fullStore)
                self = .fullStore
                return
            }
            if container.contains(.channels) {
                let ids = try container.decode([String].self, forKey: .channels)
                self = .channels(ids)
                return
            }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected one of: fullStore, channels"
                )
            )
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .fullStore:
                try container.encode(Empty(), forKey: .fullStore)
            case .channels(let ids):
                try container.encode(ids, forKey: .channels)
            }
        }
    }

    public let schemaVersion: String
    public let graphVersion: String
    /// Start node IDs in builder order.
    public let start: [HiveNodeID]
    /// All node IDs sorted lexicographically by UTF-8 on `rawValue`.
    public let nodes: [HiveNodeID]
    /// Static edges in builder insertion order.
    public let staticEdges: [StaticEdge]
    /// Join edges in builder insertion order, with canonical join IDs and sorted parents.
    public let joinEdges: [JoinEdge]
    /// Router "from" nodes sorted lexicographically by UTF-8 on `rawValue`.
    public let routers: [HiveNodeID]
    public let outputProjection: OutputProjection

    public init(
        schemaVersion: String,
        graphVersion: String,
        start: [HiveNodeID],
        nodes: [HiveNodeID],
        staticEdges: [StaticEdge],
        joinEdges: [JoinEdge],
        routers: [HiveNodeID],
        outputProjection: OutputProjection
    ) {
        self.schemaVersion = schemaVersion
        self.graphVersion = graphVersion
        self.start = start
        self.nodes = nodes
        self.staticEdges = staticEdges
        self.joinEdges = joinEdges
        self.routers = routers
        self.outputProjection = outputProjection
    }
}

public extension CompiledHiveGraph {
    /// Returns a deterministic description of the compiled graph.
    ///
    /// Determinism rules:
    /// - Node listing order: lexicographic UTF-8 by `nodeID.rawValue`.
    /// - Router listing order: lexicographic UTF-8 by `nodeID.rawValue`.
    /// - Edge listing order: preserves builder insertion order for static and join edges.
    func graphDescription() -> HiveGraphDescription {
        let sortedNodes = nodesByID.keys.sorted { HiveOrdering.lexicographicallyPrecedes($0.rawValue, $1.rawValue) }
        let staticEdges = staticEdgesInOrder.map { HiveGraphDescription.StaticEdge(from: $0.from, to: $0.to) }
        let joinEdges = joinEdges.map {
            HiveGraphDescription.JoinEdge(id: $0.id, parents: $0.parents, target: $0.target)
        }
        let sortedRouters = routersByFrom.keys.sorted { HiveOrdering.lexicographicallyPrecedes($0.rawValue, $1.rawValue) }

        let projection: HiveGraphDescription.OutputProjection = switch outputProjection {
        case .fullStore:
            .fullStore
        case .channels(let ids):
            .channels(ids.map(\.rawValue))
        }

        return HiveGraphDescription(
            schemaVersion: schemaVersion,
            graphVersion: graphVersion,
            start: start,
            nodes: sortedNodes,
            staticEdges: staticEdges,
            joinEdges: joinEdges,
            routers: sortedRouters,
            outputProjection: projection
        )
    }
}
