/// Snapshot store for global-scoped channels.
public struct HiveGlobalStore<Schema: HiveSchema>: Sendable {
    private let access: HiveStoreSupport<Schema>
    private var valuesByID: [HiveChannelID: any Sendable]

    public init() throws {
        let registry = try HiveSchemaRegistry<Schema>()
        let initialCache = HiveInitialCache(registry: registry)
        try self.init(registry: registry, initialCache: initialCache)
    }

    init(registry: HiveSchemaRegistry<Schema>, initialCache: HiveInitialCache<Schema>) throws {
        self.access = HiveStoreSupport(registry: registry)
        var values: [HiveChannelID: any Sendable] = [:]
        values.reserveCapacity(registry.channelSpecs.count)
        for spec in registry.channelSpecs where spec.scope == .global {
            values[spec.id] = try initialCache.valueAny(for: spec.id)
        }
        self.valuesByID = values
    }

    init(
        registry: HiveSchemaRegistry<Schema>,
        initialCache: HiveInitialCache<Schema>,
        checkpointedValuesByID: [HiveChannelID: any Sendable]
    ) throws {
        self.access = HiveStoreSupport(registry: registry)
        var values: [HiveChannelID: any Sendable] = [:]
        values.reserveCapacity(registry.channelSpecs.count)
        for spec in registry.channelSpecs where spec.scope == .global {
            values[spec.id] = try initialCache.valueAny(for: spec.id)
        }

        for (id, value) in checkpointedValuesByID {
            let spec = try access.requireScope(.global, for: id)
            guard spec.persistence == .checkpointed else {
                throw HiveRuntimeError.checkpointOverrideNotCheckpointed(channelID: id)
            }
            try access.validateValueType(value, spec: spec)
            values[id] = value
        }

        self.valuesByID = values
    }

    public func get<Value: Sendable>(_ key: HiveChannelKey<Schema, Value>) throws -> Value {
        let spec = try access.requireScope(.global, for: key.id)
        let value = try valueAny(for: key.id)
        return try access.cast(value, for: key, spec: spec)
    }

    mutating func set<Value: Sendable>(_ key: HiveChannelKey<Schema, Value>, _ value: Value) throws {
        let spec = try access.requireScope(.global, for: key.id)
        try access.validateKeyType(key, spec: spec)
        valuesByID[key.id] = value
    }

    mutating func setAny(_ value: any Sendable, for id: HiveChannelID) throws {
        let spec = try access.requireScope(.global, for: id)
        try access.validateValueType(value, spec: spec)
        valuesByID[id] = value
    }

    func valueAny(for id: HiveChannelID) throws -> any Sendable {
        guard let value = valuesByID[id] else {
            throw HiveRuntimeError.storeValueMissing(channelID: id)
        }
        return value
    }
}
