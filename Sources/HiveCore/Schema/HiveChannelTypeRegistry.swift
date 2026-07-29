/// Type registry keyed by channel ID for runtime type validation.
struct HiveChannelTypeRegistry<Schema: HiveSchema>: Sendable {
    private let valueTypeIDsByID: [HiveChannelID: String]

    init(_ registry: HiveSchemaRegistry<Schema>) {
        var ids: [HiveChannelID: String] = [:]
        ids.reserveCapacity(registry.channelSpecs.count)
        for spec in registry.channelSpecs {
            ids[spec.id] = spec.valueTypeID
        }
        self.valueTypeIDsByID = ids
    }

    func cast<Value: Sendable>(
        _ value: any Sendable,
        for key: HiveChannelKey<Schema, Value>
    ) throws -> Value {
        let expectedValueTypeID = String(reflecting: Value.self)
        guard let registered = valueTypeIDsByID[key.id] else {
            return try HiveChannelTypeRegistry.failUnknown(channelID: key.id)
        }
        if registered != expectedValueTypeID {
            return try HiveChannelTypeRegistry.fail(
                channelID: key.id,
                expected: registered,
                actual: expectedValueTypeID
            )
        }
        guard let typed = value as? Value else {
            let actualValueTypeID = String(reflecting: type(of: value))
            return try HiveChannelTypeRegistry.fail(
                channelID: key.id,
                expected: expectedValueTypeID,
                actual: actualValueTypeID
            )
        }
        return typed
    }

    private static func failUnknown<T>(channelID: HiveChannelID) throws -> T {
        throw HiveRuntimeError.unknownChannelID(channelID)
    }

    private static func fail<T>(
        channelID: HiveChannelID,
        expected: String,
        actual: String
    ) throws -> T {
        throw HiveRuntimeError.channelTypeMismatch(
            channelID: channelID,
            expectedValueTypeID: expected,
            actualValueTypeID: actual
        )
    }
}
