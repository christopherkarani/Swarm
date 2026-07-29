/// Controls which parts of the global store are returned as output.
public enum HiveOutputProjection: Sendable {
    case fullStore
    case channels([HiveChannelID])
}

extension HiveOutputProjection {
    func normalized() -> HiveOutputProjection {
        switch self {
        case .fullStore:
            return .fullStore
        case .channels(let ids):
            let unique = HiveOrdering.uniqueChannelIDs(ids)
            return .channels(unique)
        }
    }
}
