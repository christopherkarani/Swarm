import Foundation

/// Ordering policies for arranging context chunks.
public enum OrderingStrategy: Sendable {
    /// Group by source type and place guaranteed recent turns last.
    case typeGrouped
    /// Order by ascending relevance score.
    case relevanceAscending
    /// Order by timestamp ascending.
    case chronological
}

/// Orders chunks after packing to optimize downstream model attention.
public struct ChunkOrderer: Sendable {
    /// Creates a chunk orderer.
    public init() {}

    /// Orders chunks using a selected strategy.
    ///
    /// - Parameters:
    ///   - chunks: Packed chunks to arrange.
    ///   - strategy: Ordering strategy to apply.
    /// - Returns: Reordered chunks.
    public func order(
        _ chunks: [ContextChunk],
        strategy: OrderingStrategy = .typeGrouped
    ) -> [ContextChunk] {
        guard chunks.count > 1 else {
            return chunks
        }

        let systemPrompt = chunks.first { $0.isSystemPrompt }
        let remainingChunks: [ContextChunk]
        if let systemPrompt {
            remainingChunks = chunks.filter { $0.id != systemPrompt.id }
        } else {
            remainingChunks = chunks
        }

        let orderedRemaining: [ContextChunk]
        switch strategy {
        case .typeGrouped:
            let semantic = remainingChunks
                .filter { $0.source == .semantic && !$0.isGuaranteedRecent }
                .sorted(by: chronologicalSort)
            let episodic = remainingChunks
                .filter { $0.source == .episodic && !$0.isGuaranteedRecent }
                .sorted(by: chronologicalSort)
            let procedural = remainingChunks
                .filter { $0.source == .procedural && !$0.isGuaranteedRecent }
                .sorted(by: chronologicalSort)
            let recentTurns = remainingChunks
                .filter(\ .isGuaranteedRecent)
                .sorted(by: chronologicalSort)

            let groupedIDs = Set((semantic + episodic + procedural + recentTurns).map(\ .id))
            let fallback = remainingChunks
                .filter { !groupedIDs.contains($0.id) }
                .sorted(by: chronologicalSort)

            orderedRemaining = semantic + episodic + procedural + fallback + recentTurns

        case .relevanceAscending:
            orderedRemaining = remainingChunks.sorted(by: relevanceAscendingSort)

        case .chronological:
            orderedRemaining = remainingChunks.sorted(by: chronologicalSort)
        }

        if let systemPrompt {
            return [systemPrompt] + orderedRemaining
        }
        return orderedRemaining
    }

    private func chronologicalSort(_ lhs: ContextChunk, _ rhs: ContextChunk) -> Bool {
        if lhs.timestamp == rhs.timestamp {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.timestamp < rhs.timestamp
    }

    private func relevanceAscendingSort(_ lhs: ContextChunk, _ rhs: ContextChunk) -> Bool {
        if lhs.score == rhs.score {
            return chronologicalSort(lhs, rhs)
        }
        return lhs.score < rhs.score
    }
}
