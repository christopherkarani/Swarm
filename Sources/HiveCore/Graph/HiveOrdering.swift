import Foundation

enum HiveOrdering {
    static func lexicographicallyPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }

    static func uniqueChannelIDs(_ ids: [HiveChannelID]) -> [HiveChannelID] {
        var seen: Set<String> = []
        var unique: [HiveChannelID] = []
        unique.reserveCapacity(ids.count)
        for id in ids {
            let raw = id.rawValue
            if seen.insert(raw).inserted {
                unique.append(id)
            }
        }
        unique.sort { lexicographicallyPrecedes($0.rawValue, $1.rawValue) }
        return unique
    }

    static func uniqueNodeIDs(_ ids: [HiveNodeID]) -> [HiveNodeID] {
        var seen: Set<String> = []
        var unique: [HiveNodeID] = []
        unique.reserveCapacity(ids.count)
        for id in ids {
            let raw = id.rawValue
            if seen.insert(raw).inserted {
                unique.append(id)
            }
        }
        unique.sort { lexicographicallyPrecedes($0.rawValue, $1.rawValue) }
        return unique
    }
}
