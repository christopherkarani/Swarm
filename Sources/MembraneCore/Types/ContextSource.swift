public enum ContextSource: String, Sendable, Codable, Hashable {
    case system
    case history
    case memory
    case tool
    case retrieval
    case pointer
}
