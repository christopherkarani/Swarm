import MembraneCore

public protocol RAPTORIndex: Sendable {
    func search(query: String, topK: Int) async throws -> [RAPTORNode]
}

public struct RAPTORRetriever: Sendable {
    private let index: any RAPTORIndex
    private let topK: Int
    private let defaultImportance: Double
    private let defaultTier: CompressionTier

    public init(
        index: any RAPTORIndex,
        topK: Int = 8,
        defaultImportance: Double = 0.6,
        defaultTier: CompressionTier = .gist
    ) {
        self.index = index
        self.topK = max(0, topK)
        self.defaultImportance = defaultImportance
        self.defaultTier = defaultTier
    }

    public func retrieve(query: String, budget: ContextBudget) async throws -> [ContextSlice] {
        let candidates = try await index.search(query: query, topK: topK)
        let ordered = candidates.sorted(by: Self.isOrderedBefore(lhs:rhs:))

        var remaining = max(0, budget.ceiling(for: .retrieval))
        var output: [ContextSlice] = []

        for node in ordered {
            if node.tokenCount > remaining {
                break
            }

            output.append(
                ContextSlice(
                    content: node.text,
                    tokenCount: node.tokenCount,
                    importance: defaultImportance,
                    source: .retrieval,
                    tier: defaultTier,
                    timestamp: .now
                )
            )
            remaining -= node.tokenCount
        }

        return output
    }

    private static func isOrderedBefore(lhs: RAPTORNode, rhs: RAPTORNode) -> Bool {
        if lhs.depth != rhs.depth {
            return lhs.depth < rhs.depth
        }
        return lhs.id < rhs.id
    }
}

// Task 21 integration note: MembraneWax will provide a RAPTORIndex implementation
// backed by Wax persistence so retrieval uses durable tree nodes.
