/// Deterministic cache of channel initial values.
struct HiveInitialCache<Schema: HiveSchema>: Sendable {
    private let access: HiveStoreSupport<Schema>
    private let valuesByID: [HiveChannelID: any Sendable]

    init(registry: HiveSchemaRegistry<Schema>) {
        self.access = HiveStoreSupport(registry: registry)
        var values: [HiveChannelID: any Sendable] = [:]
        values.reserveCapacity(registry.channelSpecs.count)
        for spec in registry.sortedChannelSpecs {
            values[spec.id] = spec._initialBox()
        }
        self.valuesByID = values
    }

    func get<Value: Sendable>(_ key: HiveChannelKey<Schema, Value>) throws -> Value {
        let spec = try access.requireSpec(for: key.id)
        let value = try valueAny(for: key.id)
        return try access.cast(value, for: key, spec: spec)
    }

    func valueAny(for id: HiveChannelID) throws -> any Sendable {
        _ = try access.requireSpec(for: id)
        guard let value = valuesByID[id] else {
            throw HiveRuntimeError.storeValueMissing(channelID: id)
        }
        return value
    }
}
