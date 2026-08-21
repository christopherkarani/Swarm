/// Type registry keyed by channel ID for runtime type validation.
///
/// Identity is ``ObjectIdentifier`` of the spec’s `Value`, not reflected type strings.
struct HiveChannelTypeRegistry<Schema: HiveSchema>: Sendable {
    private let identifiersByID: [HiveChannelID: ObjectIdentifier]
    private let diagnosticTypeIDsByID: [HiveChannelID: String]

    init(_ registry: HiveSchemaRegistry<Schema>) {
        var identifiers: [HiveChannelID: ObjectIdentifier] = [:]
        var diagnostics: [HiveChannelID: String] = [:]
        identifiers.reserveCapacity(registry.channelSpecs.count)
        diagnostics.reserveCapacity(registry.channelSpecs.count)
        for spec in registry.channelSpecs {
            identifiers[spec.id] = spec.valueTypeIdentifier
            diagnostics[spec.id] = spec.valueTypeID
        }
        self.identifiersByID = identifiers
        self.diagnosticTypeIDsByID = diagnostics
    }

    func cast<Value: Sendable>(
        _ value: any Sendable,
        for key: HiveChannelKey<Schema, Value>
    ) throws -> Value {
        guard let registered = identifiersByID[key.id] else {
            return try HiveChannelTypeRegistry.failUnknown(channelID: key.id)
        }
        let expected = ObjectIdentifier(Value.self)
        if registered != expected {
            return try HiveChannelTypeRegistry.fail(
                channelID: key.id,
                expected: diagnosticTypeIDsByID[key.id] ?? String(reflecting: Value.self),
                actual: String(reflecting: Value.self)
            )
        }
        guard let typed = value as? Value else {
            return try HiveChannelTypeRegistry.fail(
                channelID: key.id,
                expected: diagnosticTypeIDsByID[key.id] ?? String(reflecting: Value.self),
                actual: String(reflecting: type(of: value))
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
