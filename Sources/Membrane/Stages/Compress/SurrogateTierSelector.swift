import MembraneCore

public struct SurrogateCandidate: Sendable, Equatable {
    public let id: String
    public let accessFrequency: Int
    public let recencyScore: Double
    public let relevanceScore: Double
    public let full: ContextSlice
    public let gist: ContextSlice
    public let micro: ContextSlice

    public init(
        id: String,
        accessFrequency: Int,
        recencyScore: Double,
        relevanceScore: Double,
        full: ContextSlice,
        gist: ContextSlice,
        micro: ContextSlice
    ) {
        self.id = id
        self.accessFrequency = accessFrequency
        self.recencyScore = recencyScore
        self.relevanceScore = relevanceScore
        self.full = full
        self.gist = gist
        self.micro = micro
    }
}

public struct SurrogateTierSelector: Sendable {
    public init() {}

    public func select(
        candidates: [SurrogateCandidate],
        retrievalTokenBudget: Int,
        querySpecificity: Double
    ) -> [ContextSlice] {
        let specificity = min(max(querySpecificity, 0.0), 1.0)
        let preferFullTier = specificity >= 0.7

        let ranked = candidates.sorted { lhs, rhs in
            let lhsScore = score(lhs)
            let rhsScore = score(rhs)

            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }

            return lhs.id < rhs.id
        }

        var remaining = max(0, retrievalTokenBudget)
        var selected: [ContextSlice] = []

        for candidate in ranked where remaining > 0 {
            let preferredTier = preferFullTier ? candidate.full : candidate.gist
            let secondaryTier = preferFullTier ? candidate.gist : candidate.full
            let tiers = [preferredTier, secondaryTier, candidate.micro]
            guard let chosen = tiers.first(where: { $0.tokenCount <= remaining }) else {
                continue
            }

            selected.append(chosen)
            remaining -= chosen.tokenCount
        }

        return selected
    }

    private func score(_ candidate: SurrogateCandidate) -> Double {
        Double(candidate.accessFrequency) * 0.4
        + candidate.recencyScore * 0.2
        + candidate.relevanceScore * 0.4
    }
}
