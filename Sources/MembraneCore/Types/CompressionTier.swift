public enum CompressionTier: String, Sendable, Codable, Comparable {
    case full
    case gist
    case micro

    public var tokenBudgetMultiplier: Double {
        switch self {
        case .full: return 1.0
        case .gist: return 0.25
        case .micro: return 0.08
        }
    }

    public static func < (lhs: CompressionTier, rhs: CompressionTier) -> Bool {
        lhs.tokenBudgetMultiplier < rhs.tokenBudgetMultiplier
    }
}
