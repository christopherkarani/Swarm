public enum BucketID: String, Sendable, CaseIterable, Codable, Hashable {
    case system
    case history
    case memory
    case tools
    case retrieval
    case toolIO
    case outputReserve
    case protocolOverhead
    case safetyMargin
}
