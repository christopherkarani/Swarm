/// Validated schema registry used by compilation and runtime.
public struct HiveSchemaRegistry<Schema: HiveSchema>: Sendable {
    /// Original order as declared by the schema.
    public let channelSpecs: [AnyHiveChannelSpec<Schema>]
    /// Lookup by channel ID.
    public let channelSpecsByID: [HiveChannelID: AnyHiveChannelSpec<Schema>]
    /// Deterministic iteration by `HiveChannelID.rawValue` (lexicographic by UTF-8).
    public let sortedChannelSpecs: [AnyHiveChannelSpec<Schema>]

    public init(_ schemaType: Schema.Type = Schema.self) throws {
        try self.init(channelSpecs: schemaType.channelSpecs)
    }

    public init(channelSpecs: [AnyHiveChannelSpec<Schema>]) throws {
        self.channelSpecs = channelSpecs

        if let duplicateID = HiveSchemaRegistry.firstDuplicateID(in: channelSpecs) {
            throw HiveCompilationError.duplicateChannelID(duplicateID)
        }
        if let invalidID = HiveSchemaRegistry.firstInvalidTaskLocalUntrackedID(in: channelSpecs) {
            throw HiveCompilationError.invalidTaskLocalUntracked(channelID: invalidID)
        }

        var byID: [HiveChannelID: AnyHiveChannelSpec<Schema>] = [:]
        byID.reserveCapacity(channelSpecs.count)
        for spec in channelSpecs {
            byID[spec.id] = spec
        }
        self.channelSpecsByID = byID

        self.sortedChannelSpecs = channelSpecs.sorted { lhs, rhs in
            HiveSchemaRegistry.lexicographicallyPrecedes(lhs.id.rawValue, rhs.id.rawValue)
        }
    }

    /// Returns the smallest channel ID with a missing required codec, if any.
    public func firstMissingRequiredCodecID() -> HiveChannelID? {
        HiveSchemaRegistry.firstMissingRequiredCodecID(in: channelSpecs)
    }

    private static func firstDuplicateID(in specs: [AnyHiveChannelSpec<Schema>]) -> HiveChannelID? {
        var counts: [String: Int] = [:]
        counts.reserveCapacity(specs.count)
        for spec in specs {
            counts[spec.id.rawValue, default: 0] += 1
        }

        var smallestDuplicate: String?
        for (id, count) in counts where count > 1 {
            if let currentSmallest = smallestDuplicate {
                if lexicographicallyPrecedes(id, currentSmallest) {
                    smallestDuplicate = id
                }
            } else {
                smallestDuplicate = id
            }
        }

        if let smallestDuplicate {
            return HiveChannelID(smallestDuplicate)
        }
        return nil
    }

    private static func firstInvalidTaskLocalUntrackedID(in specs: [AnyHiveChannelSpec<Schema>]) -> HiveChannelID? {
        var smallest: String?
        for spec in specs where spec.scope == .taskLocal && spec.persistence == .untracked {
            let id = spec.id.rawValue
            if let currentSmallest = smallest {
                if lexicographicallyPrecedes(id, currentSmallest) {
                    smallest = id
                }
            } else {
                smallest = id
            }
        }
        if let smallest {
            return HiveChannelID(smallest)
        }
        return nil
    }

    private static func firstMissingRequiredCodecID(in specs: [AnyHiveChannelSpec<Schema>]) -> HiveChannelID? {
        var smallest: String?
        for spec in specs {
            let requiresCodec = (spec.scope == .taskLocal) || (spec.scope == .global && spec.persistence == .checkpointed)
            guard requiresCodec, spec.codecID == nil else { continue }
            let id = spec.id.rawValue
            if let currentSmallest = smallest {
                if lexicographicallyPrecedes(id, currentSmallest) {
                    smallest = id
                }
            } else {
                smallest = id
            }
        }
        if let smallest {
            return HiveChannelID(smallest)
        }
        return nil
    }

    private static func lexicographicallyPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }
}
