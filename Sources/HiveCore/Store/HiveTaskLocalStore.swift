/// Overlay-only store for task-local channels.
public struct HiveTaskLocalStore<Schema: HiveSchema>: Sendable {
    public static var empty: HiveTaskLocalStore<Schema> {
        do {
            let registry = try HiveSchemaRegistry<Schema>()
            return HiveTaskLocalStore(registry: registry)
        } catch {
            return HiveTaskLocalStore(initializationError: error)
        }
    }

    private let access: HiveStoreSupport<Schema>?
    private let initializationError: Error?
    private var valuesByID: [HiveChannelID: any Sendable]

    init(
        registry: HiveSchemaRegistry<Schema>,
        valuesByID: [HiveChannelID: any Sendable] = [:]
    ) {
        self.access = HiveStoreSupport(registry: registry)
        self.initializationError = nil
        self.valuesByID = valuesByID
    }

    private init(initializationError: Error) {
        self.access = nil
        self.initializationError = initializationError
        self.valuesByID = [:]
    }

    private func requireAccess() throws -> HiveStoreSupport<Schema> {
        guard let access else {
            throw initializationError ?? HiveRuntimeError.internalInvariantViolation(
                "HiveTaskLocalStore was not initialized with a schema registry."
            )
        }
        return access
    }

    public func get<Value: Sendable>(_ key: HiveChannelKey<Schema, Value>) throws -> Value? {
        let access = try requireAccess()
        let spec = try access.requireScope(.taskLocal, for: key.id)
        guard let value = valuesByID[key.id] else {
            return nil
        }
        return try access.cast(value, for: key, spec: spec)
    }

    public mutating func set<Value: Sendable>(_ key: HiveChannelKey<Schema, Value>, _ value: Value) throws {
        let access = try requireAccess()
        let spec = try access.requireScope(.taskLocal, for: key.id)
        try access.validateKeyType(key, spec: spec)
        valuesByID[key.id] = value
    }

    mutating func setAny(_ value: any Sendable, for id: HiveChannelID) throws {
        let access = try requireAccess()
        let spec = try access.requireScope(.taskLocal, for: id)
        try access.validateValueType(value, spec: spec)
        valuesByID[id] = value
    }

    func valueAny(for id: HiveChannelID) -> (any Sendable)? {
        valuesByID[id]
    }
}
