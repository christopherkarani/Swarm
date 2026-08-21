/// Internal helper for scope/type validation in store access.
internal struct HiveStoreSupport<Schema: HiveSchema>: Sendable {
    let registry: HiveSchemaRegistry<Schema>

    init(registry: HiveSchemaRegistry<Schema>) {
        self.registry = registry
    }

    func requireSpec(for id: HiveChannelID) throws -> AnyHiveChannelSpec<Schema> {
        guard let spec = registry.channelSpecsByID[id] else {
            throw HiveRuntimeError.unknownChannelID(id)
        }
        return spec
    }

    func requireScope(_ expected: HiveChannelScope, for id: HiveChannelID) throws -> AnyHiveChannelSpec<Schema> {
        let spec = try requireSpec(for: id)
        guard spec.scope == expected else {
            throw HiveRuntimeError.scopeMismatch(channelID: id, expected: expected, actual: spec.scope)
        }
        return spec
    }

    func validateKeyType<Value: Sendable>(
        _ key: HiveChannelKey<Schema, Value>,
        spec: AnyHiveChannelSpec<Schema>
    ) throws {
        guard spec.matchesValueType(Value.self) else {
            throw HiveRuntimeError.channelTypeMismatch(
                channelID: key.id,
                expectedValueTypeID: spec.valueTypeID,
                actualValueTypeID: String(reflecting: Value.self)
            )
        }
    }

    func validateValueType(
        _ value: any Sendable,
        spec: AnyHiveChannelSpec<Schema>
    ) throws {
        guard spec.matchesStoredValue(value) else {
            throw HiveRuntimeError.channelTypeMismatch(
                channelID: spec.id,
                expectedValueTypeID: spec.valueTypeID,
                actualValueTypeID: String(reflecting: type(of: value))
            )
        }
    }

    func cast<Value: Sendable>(
        _ value: any Sendable,
        for key: HiveChannelKey<Schema, Value>,
        spec: AnyHiveChannelSpec<Schema>
    ) throws -> Value {
        try validateKeyType(key, spec: spec)
        guard let typed = value as? Value else {
            throw HiveRuntimeError.channelTypeMismatch(
                channelID: key.id,
                expectedValueTypeID: spec.valueTypeID,
                actualValueTypeID: String(reflecting: type(of: value))
            )
        }
        return typed
    }
}
