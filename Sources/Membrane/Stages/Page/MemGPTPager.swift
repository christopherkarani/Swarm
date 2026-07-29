import MembraneCore

/// Stage 4 pager for open-model pipelines. It evicts low-importance slices
/// from retrieval/memory/history until token pressure is below threshold.
public actor MemGPTPager: PageStage {
    private let pressureThreshold: Double
    private let keepRecentHistoryTurns: Int

    public init(pressureThreshold: Double = 0.85, keepRecentHistoryTurns: Int = 3) {
        self.pressureThreshold = min(max(pressureThreshold, 0.0), 1.0)
        self.keepRecentHistoryTurns = max(keepRecentHistoryTurns, 0)
    }

    public func process(_ input: CompressedContext, budget: ContextBudget) async throws -> PagedContext {
        var window = input.window
        var pagedOut: [ContextSlice] = []

        let thresholdTokens = Int(Double(budget.totalTokens) * pressureThreshold)
        guard window.totalTokenCount > thresholdTokens else {
            return PagedContext(window: window, budget: budget, pagedOut: [])
        }

        while window.totalTokenCount > thresholdTokens {
            guard let candidate = nextEvictionCandidate(from: window) else {
                throw MembraneError.contextWindowExceeded(totalTokens: window.totalTokenCount, limit: thresholdTokens)
            }

            switch candidate.source {
            case .retrieval:
                pagedOut.append(window.retrieval.remove(at: candidate.index))
            case .memory:
                pagedOut.append(window.memory.remove(at: candidate.index))
            case .history:
                pagedOut.append(window.history.remove(at: candidate.index))
            default:
                throw MembraneError.pagingStorageUnavailable(reason: "Unsupported source for paging: \(candidate.source.rawValue)")
            }
        }

        return PagedContext(window: window, budget: budget, pagedOut: pagedOut)
    }

    private func nextEvictionCandidate(from window: ContextWindow) -> EvictionCandidate? {
        var candidates: [EvictionCandidate] = []

        for (index, slice) in window.retrieval.enumerated() {
            candidates.append(EvictionCandidate(source: .retrieval, index: index, slice: slice))
        }

        for (index, slice) in window.memory.enumerated() {
            candidates.append(EvictionCandidate(source: .memory, index: index, slice: slice))
        }

        let evictableHistoryCount = max(0, window.history.count - keepRecentHistoryTurns)
        for (index, slice) in window.history.prefix(evictableHistoryCount).enumerated() {
            candidates.append(EvictionCandidate(source: .history, index: index, slice: slice))
        }

        return candidates.min { lhs, rhs in
            if lhs.slice.importance != rhs.slice.importance {
                return lhs.slice.importance < rhs.slice.importance
            }

            if lhs.sourcePriority != rhs.sourcePriority {
                return lhs.sourcePriority < rhs.sourcePriority
            }

            return lhs.index < rhs.index
        }
    }
}

private struct EvictionCandidate {
    let source: ContextSource
    let index: Int
    let slice: ContextSlice

    var sourcePriority: Int {
        switch source {
        case .retrieval:
            return 0
        case .memory:
            return 1
        case .history:
            return 2
        default:
            return 3
        }
    }
}
