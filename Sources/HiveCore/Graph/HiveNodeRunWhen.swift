/// Compile-time trigger configuration for whether a node should be scheduled.
///
/// Triggers are evaluated deterministically at commit boundaries and must depend only on
/// committed state (e.g., channel version counters), not dynamic read-tracking.
public enum HiveNodeRunWhen: Sendable, Hashable {
    /// v1 behavior: always schedule when a seed exists.
    case always
    /// Schedule when any referenced channel has advanced since the node last ran.
    case anyOf(channels: [HiveChannelID])
    /// Schedule when all referenced channels have advanced since the node last ran.
    case allOf(channels: [HiveChannelID])

    var normalized: HiveNodeRunWhen {
        switch self {
        case .always:
            return .always
        case .anyOf(let channels):
            return .anyOf(channels: HiveOrdering.uniqueChannelIDs(channels))
        case .allOf(let channels):
            return .allOf(channels: HiveOrdering.uniqueChannelIDs(channels))
        }
    }

    var triggerChannels: [HiveChannelID] {
        switch normalized {
        case .always:
            return []
        case .anyOf(let channels):
            return channels
        case .allOf(let channels):
            return channels
        }
    }

    var isDefaultAlways: Bool {
        if case .always = self { return true }
        return false
    }
}
