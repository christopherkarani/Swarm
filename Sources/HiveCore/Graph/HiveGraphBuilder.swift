/// Composable flags for node execution behavior.
public struct HiveNodeOptions: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// Run after all non-deferred frontier nodes complete in the current superstep.
    /// Useful for cleanup, finalization, and summary nodes.
    /// Deferred nodes execute only when the graph would otherwise finish (empty next frontier).
    public static let deferred = HiveNodeOptions(rawValue: 1 << 0)
}

/// Compiled node configuration used by the runtime.
public struct HiveCompiledNode<Schema: HiveSchema>: Sendable {
    public let id: HiveNodeID
    public let retryPolicy: HiveRetryPolicy
    public let runWhen: HiveNodeRunWhen
    public let options: HiveNodeOptions
    public let cachePolicy: HiveCachePolicy<Schema>?
    public let run: NodeAction<Schema>

    public init(
        id: HiveNodeID,
        retryPolicy: HiveRetryPolicy,
        runWhen: HiveNodeRunWhen = .always,
        options: HiveNodeOptions = [],
        cachePolicy: HiveCachePolicy<Schema>? = nil,
        run: @escaping NodeAction<Schema>
    ) {
        self.id = id
        self.retryPolicy = retryPolicy
        self.runWhen = runWhen.normalized
        self.options = options
        self.cachePolicy = cachePolicy
        self.run = run
    }
}

struct HiveStaticEdge: Hashable, Sendable {
    let from: HiveNodeID
    let to: HiveNodeID
}

/// Join edge with canonical ID and sorted parent list.
public struct HiveJoinEdge: Hashable, Sendable {
    public let id: String
    public let parents: [HiveNodeID]
    public let target: HiveNodeID

    public init(parents: [HiveNodeID], target: HiveNodeID) {
        let sorted = parents.sorted { HiveOrdering.lexicographicallyPrecedes($0.rawValue, $1.rawValue) }
        self.parents = sorted
        self.target = target
        self.id = HiveJoinEdge.canonicalID(parents: sorted, target: target)
    }

    static func canonicalID(parents: [HiveNodeID], target: HiveNodeID) -> String {
        let parentIDs = parents.map { $0.rawValue }.joined(separator: "+")
        return "join:\(parentIDs):\(target.rawValue)"
    }
}

/// Fully compiled, validated graph for execution.
public struct CompiledHiveGraph<Schema: HiveSchema>: Sendable {
    public let schemaVersion: String
    public let graphVersion: String
    public let start: [HiveNodeID]
    public let outputProjection: HiveOutputProjection
    public let nodesByID: [HiveNodeID: HiveCompiledNode<Schema>]
    let staticEdgesInOrder: [HiveStaticEdge]
    public let staticEdgesByFrom: [HiveNodeID: [HiveNodeID]]
    public let joinEdges: [HiveJoinEdge]
    public let routersByFrom: [HiveNodeID: HiveRouter<Schema>]
    let nodeOrdinalByID: [HiveNodeID: Int]
    let joinEdgeByID: [String: HiveJoinEdge]
    let joinEdgeOrderByID: [String: Int]
    let joinEdgesByTarget: [HiveNodeID: [HiveJoinEdge]]
    let joinEdgesByParent: [HiveNodeID: [HiveJoinEdge]]
    let joinParentMaskByJoinID: [String: HiveBitset]
    let joinBitsetWordCount: Int
    let staticLayersByNodeID: [HiveNodeID: Int]
    let maxStaticDepth: Int
}

/// Builder for assembling and compiling graphs.
public struct HiveGraphBuilder<Schema: HiveSchema> {
    private var start: [HiveNodeID]
    private var nodes: [HiveNodeID: HiveCompiledNode<Schema>] = [:]
    private var nodeInsertions: [HiveNodeID] = []
    private var staticEdges: [(from: HiveNodeID, to: HiveNodeID)] = []
    private var joinEdges: [(parents: [HiveNodeID], target: HiveNodeID)] = []
    private var routers: [(from: HiveNodeID, router: HiveRouter<Schema>)] = []
    private var outputProjection: HiveOutputProjection = .fullStore

    public init(start: [HiveNodeID]) {
        self.start = start
    }

    public mutating func addNode(
        _ id: HiveNodeID,
        retryPolicy: HiveRetryPolicy = .none,
        runWhen: HiveNodeRunWhen = .always,
        options: HiveNodeOptions = [],
        cachePolicy: HiveCachePolicy<Schema>? = nil,
        _ node: @escaping NodeAction<Schema>
    ) {
        nodeInsertions.append(id)
        nodes[id] = HiveCompiledNode(
            id: id, retryPolicy: retryPolicy, runWhen: runWhen,
            options: options, cachePolicy: cachePolicy, run: node
        )
    }

    public mutating func addEdge(from: HiveNodeID, to: HiveNodeID) {
        staticEdges.append((from: from, to: to))
    }

    public mutating func addJoinEdge(parents: [HiveNodeID], target: HiveNodeID) {
        joinEdges.append((parents: parents, target: target))
    }

    public mutating func addRouter(from: HiveNodeID, _ router: @escaping HiveRouter<Schema>) {
        routers.append((from: from, router: router))
    }

    public mutating func setOutputProjection(_ projection: HiveOutputProjection) {
        outputProjection = projection
    }

    public func compile(graphVersionOverride: String? = nil) throws -> CompiledHiveGraph<Schema> {
        let registry = try HiveSchemaRegistry<Schema>()

        try validateGraphStructure()
        try validateNodeRunWhen(registry: registry)

        let normalizedProjection = outputProjection.normalized()
        try validateOutputProjection(normalizedProjection, registry: registry)

        var edgesByFrom: [HiveNodeID: [HiveNodeID]] = [:]
        for edge in staticEdges {
            edgesByFrom[edge.from, default: []].append(edge.to)
        }
        let staticEdgesInOrder = staticEdges.map { HiveStaticEdge(from: $0.from, to: $0.to) }

        var routersByFrom: [HiveNodeID: HiveRouter<Schema>] = [:]
        for entry in routers {
            routersByFrom[entry.from] = entry.router
        }

        let compiledJoinEdges = joinEdges.map { HiveJoinEdge(parents: $0.parents, target: $0.target) }
        let sortedNodeIDs = nodes.keys.sorted { HiveOrdering.lexicographicallyPrecedes($0.rawValue, $1.rawValue) }
        let nodeOrdinalByID = Dictionary(uniqueKeysWithValues: zip(sortedNodeIDs, sortedNodeIDs.indices))
        let joinBitsetWordCount = max((sortedNodeIDs.count + 63) / 64, 1)

        var joinEdgeByID: [String: HiveJoinEdge] = [:]
        var joinEdgeOrderByID: [String: Int] = [:]
        var joinEdgesByTarget: [HiveNodeID: [HiveJoinEdge]] = [:]
        var joinEdgesByParent: [HiveNodeID: [HiveJoinEdge]] = [:]
        var joinParentMaskByJoinID: [String: HiveBitset] = [:]

        joinEdgeByID.reserveCapacity(compiledJoinEdges.count)
        joinEdgeOrderByID.reserveCapacity(compiledJoinEdges.count)
        joinParentMaskByJoinID.reserveCapacity(compiledJoinEdges.count)
        for (index, edge) in compiledJoinEdges.enumerated() {
            joinEdgeByID[edge.id] = edge
            joinEdgeOrderByID[edge.id] = index
            joinEdgesByTarget[edge.target, default: []].append(edge)

            var parentMask = HiveBitset(wordCount: joinBitsetWordCount)
            for parent in edge.parents {
                if let ordinal = nodeOrdinalByID[parent] {
                    parentMask.insert(ordinal)
                }
                joinEdgesByParent[parent, default: []].append(edge)
            }
            joinParentMaskByJoinID[edge.id] = parentMask
        }

        let staticLayerAnalysis = try computeStaticLayers()

        let schemaVersion = HiveVersioning.schemaVersion(registry: registry)
        let graphVersion = graphVersionOverride ?? HiveVersioning.graphVersion(
            start: start,
            nodesByID: nodes,
            routerFrom: routers.map { $0.from },
            staticEdges: staticEdges,
            joinEdges: joinEdges,
            outputProjection: normalizedProjection
        )

        return CompiledHiveGraph(
            schemaVersion: schemaVersion,
            graphVersion: graphVersion,
            start: start,
            outputProjection: normalizedProjection,
            nodesByID: nodes,
            staticEdgesInOrder: staticEdgesInOrder,
            staticEdgesByFrom: edgesByFrom,
            joinEdges: compiledJoinEdges,
            routersByFrom: routersByFrom,
            nodeOrdinalByID: nodeOrdinalByID,
            joinEdgeByID: joinEdgeByID,
            joinEdgeOrderByID: joinEdgeOrderByID,
            joinEdgesByTarget: joinEdgesByTarget,
            joinEdgesByParent: joinEdgesByParent,
            joinParentMaskByJoinID: joinParentMaskByJoinID,
            joinBitsetWordCount: joinBitsetWordCount,
            staticLayersByNodeID: staticLayerAnalysis.layersByNodeID,
            maxStaticDepth: staticLayerAnalysis.maxDepth
        )
    }

    private func validateGraphStructure() throws {
        if start.isEmpty {
            throw HiveCompilationError.startEmpty
        }

        var startSeen: Set<HiveNodeID> = []
        for node in start {
            if startSeen.contains(node) {
                throw HiveCompilationError.duplicateStartNode(node)
            }
            startSeen.insert(node)
        }

        if let duplicateNode = smallestDuplicateNodeID() {
            throw HiveCompilationError.duplicateNodeID(duplicateNode)
        }

        if let invalidNode = smallestInvalidNodeID() {
            throw HiveCompilationError.invalidNodeIDContainsReservedJoinCharacters(nodeID: invalidNode)
        }

        for node in start {
            guard nodes[node] != nil else {
                throw HiveCompilationError.unknownStartNode(node)
            }
        }

        for edge in staticEdges {
            if nodes[edge.from] == nil {
                throw HiveCompilationError.unknownEdgeEndpoint(from: edge.from, to: edge.to, unknown: edge.from)
            }
            if nodes[edge.to] == nil {
                throw HiveCompilationError.unknownEdgeEndpoint(from: edge.from, to: edge.to, unknown: edge.to)
            }
        }

        var routersByFrom: Set<HiveNodeID> = []
        for entry in routers {
            if nodes[entry.from] == nil {
                throw HiveCompilationError.unknownRouterFrom(entry.from)
            }
            if routersByFrom.contains(entry.from) {
                throw HiveCompilationError.duplicateRouter(from: entry.from)
            }
            routersByFrom.insert(entry.from)
        }

        var seenJoinIDs: Set<String> = []
        for edge in joinEdges {
            let parents = edge.parents
            if parents.isEmpty {
                throw HiveCompilationError.invalidJoinEdgeParentsEmpty(target: edge.target)
            }

            var parentSeen: Set<HiveNodeID> = []
            for parent in parents {
                if parentSeen.contains(parent) {
                    throw HiveCompilationError.invalidJoinEdgeParentsContainsDuplicate(
                        parent: parent,
                        target: edge.target
                    )
                }
                parentSeen.insert(parent)
            }

            if parentSeen.contains(edge.target) {
                throw HiveCompilationError.invalidJoinEdgeParentsContainsTarget(target: edge.target)
            }

            for parent in parents {
                if nodes[parent] == nil {
                    throw HiveCompilationError.unknownJoinParent(parent: parent, target: edge.target)
                }
            }

            if nodes[edge.target] == nil {
                throw HiveCompilationError.unknownJoinTarget(target: edge.target)
            }

            let joinID = HiveJoinEdge.canonicalID(
                parents: parents.sorted { HiveOrdering.lexicographicallyPrecedes($0.rawValue, $1.rawValue) },
                target: edge.target
            )
            if seenJoinIDs.contains(joinID) {
                throw HiveCompilationError.duplicateJoinEdge(joinID: joinID)
            }
            seenJoinIDs.insert(joinID)
        }
    }

    private func validateNodeRunWhen(registry: HiveSchemaRegistry<Schema>) throws {
        let sortedNodeIDs = nodes.keys.sorted { HiveOrdering.lexicographicallyPrecedes($0.rawValue, $1.rawValue) }
        for nodeID in sortedNodeIDs {
            guard let node = nodes[nodeID] else { continue }
            let normalized = node.runWhen.normalized
            switch normalized {
            case .always:
                continue
            case .anyOf(let channels), .allOf(let channels):
                if channels.isEmpty {
                    throw HiveCompilationError.invalidNodeRunWhenChannelsEmpty(nodeID: nodeID)
                }
                for channelID in channels {
                    guard let spec = registry.channelSpecsByID[channelID] else {
                        throw HiveCompilationError.invalidNodeRunWhenUnknownChannel(nodeID: nodeID, channelID: channelID)
                    }
                    if spec.scope != .global {
                        throw HiveCompilationError.invalidNodeRunWhenIncludesTaskLocalChannel(
                            nodeID: nodeID,
                            channelID: channelID
                        )
                    }
                }
            }
        }
    }

    private func smallestDuplicateNodeID() -> HiveNodeID? {
        var counts: [String: Int] = [:]
        for id in nodeInsertions {
            counts[id.rawValue, default: 0] += 1
        }
        var smallest: String?
        for (raw, count) in counts where count > 1 {
            if let current = smallest {
                if HiveOrdering.lexicographicallyPrecedes(raw, current) {
                    smallest = raw
                }
            } else {
                smallest = raw
            }
        }
        if let smallest {
            return HiveNodeID(smallest)
        }
        return nil
    }

    private func smallestInvalidNodeID() -> HiveNodeID? {
        var smallest: String?
        for id in nodeInsertions {
            let raw = id.rawValue
            if raw.contains(":") || raw.contains("+") {
                if let current = smallest {
                    if HiveOrdering.lexicographicallyPrecedes(raw, current) {
                        smallest = raw
                    }
                } else {
                    smallest = raw
                }
            }
        }
        if let smallest {
            return HiveNodeID(smallest)
        }
        return nil
    }

    private func validateOutputProjection(
        _ projection: HiveOutputProjection,
        registry: HiveSchemaRegistry<Schema>
    ) throws {
        switch projection {
        case .fullStore:
            return
        case .channels(let ids):
            for id in ids {
                guard let spec = registry.channelSpecsByID[id] else {
                    throw HiveCompilationError.outputProjectionUnknownChannel(id)
                }
                if spec.scope == .taskLocal {
                    throw HiveCompilationError.outputProjectionIncludesTaskLocal(id)
                }
            }
        }
    }

    private func computeStaticLayers() throws -> (layersByNodeID: [HiveNodeID: Int], maxDepth: Int) {
        var inDegreeByNode: [HiveNodeID: Int] = [:]
        var outgoingByNode: [HiveNodeID: [HiveNodeID]] = [:]
        inDegreeByNode.reserveCapacity(nodes.count)
        outgoingByNode.reserveCapacity(nodes.count)

        for nodeID in nodes.keys {
            inDegreeByNode[nodeID] = 0
            outgoingByNode[nodeID] = []
        }

        for edge in staticEdges {
            outgoingByNode[edge.from, default: []].append(edge.to)
            inDegreeByNode[edge.to, default: 0] += 1
        }

        for (nodeID, neighbors) in outgoingByNode {
            outgoingByNode[nodeID] = neighbors.sorted {
                HiveOrdering.lexicographicallyPrecedes($0.rawValue, $1.rawValue)
            }
        }

        var frontier = inDegreeByNode
            .filter { $0.value == 0 }
            .map(\.key)
            .sorted { HiveOrdering.lexicographicallyPrecedes($0.rawValue, $1.rawValue) }
        var remainingInDegree = inDegreeByNode
        var maxParentDepthByNode: [HiveNodeID: Int] = [:]
        var layersByNodeID: [HiveNodeID: Int] = [:]
        layersByNodeID.reserveCapacity(nodes.count)
        var visitedCount = 0

        while frontier.isEmpty == false {
            var nextFrontier: [HiveNodeID] = []
            for nodeID in frontier {
                visitedCount += 1
                let depth = maxParentDepthByNode[nodeID] ?? 0
                layersByNodeID[nodeID] = depth

                for neighbor in outgoingByNode[nodeID] ?? [] {
                    let candidateDepth = depth + 1
                    if candidateDepth > (maxParentDepthByNode[neighbor] ?? 0) {
                        maxParentDepthByNode[neighbor] = candidateDepth
                    }
                    guard let currentInDegree = remainingInDegree[neighbor] else { continue }
                    let nextInDegree = currentInDegree - 1
                    remainingInDegree[neighbor] = nextInDegree
                    if nextInDegree == 0 {
                        nextFrontier.append(neighbor)
                    }
                }
            }

            frontier = nextFrontier.sorted {
                HiveOrdering.lexicographicallyPrecedes($0.rawValue, $1.rawValue)
            }
        }

        if visitedCount != nodes.count {
            let cycleNodes = remainingInDegree
                .filter { $0.value > 0 }
                .map(\.key)
                .sorted { HiveOrdering.lexicographicallyPrecedes($0.rawValue, $1.rawValue) }
            throw HiveCompilationError.staticGraphCycleDetected(nodes: cycleNodes)
        }

        return (layersByNodeID: layersByNodeID, maxDepth: layersByNodeID.values.max() ?? 0)
    }
}
