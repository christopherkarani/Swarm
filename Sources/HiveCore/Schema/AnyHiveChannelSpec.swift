import Foundation

public struct AnyHiveChannelSpec<Schema: HiveSchema>: Sendable {
    public let id: HiveChannelID
    public let scope: HiveChannelScope
    public let persistence: HiveChannelPersistence
    public let updatePolicy: HiveUpdatePolicy

    /// Diagnostic only; typically String(reflecting: Value.self).
    public let valueTypeID: String

    /// Equal to `codec?.id`, else nil.
    public let codecID: String?

    internal let _initialBox: @Sendable () -> any Sendable
    internal let _reduceBox: @Sendable (any Sendable, any Sendable) throws -> any Sendable
    internal let _encodeBox: (@Sendable (any Sendable) throws -> Data)?
    internal let _decodeBox: (@Sendable (Data) throws -> any Sendable)?

    public init<Value: Sendable>(
        _ spec: HiveChannelSpec<Schema, Value>,
        valueTypeID: String = String(reflecting: Value.self)
    ) {
        self.id = spec.key.id
        self.scope = spec.scope
        self.persistence = spec.persistence
        self.updatePolicy = spec.updatePolicy
        self.valueTypeID = valueTypeID
        self.codecID = spec.codec?.id

        self._initialBox = { spec.initial() }
        self._reduceBox = { current, update in
            guard let typedCurrent = current as? Value else {
                throw HiveChannelSpecTypeMismatchError.expected(Value.self, actual: type(of: current))
            }
            guard let typedUpdate = update as? Value else {
                throw HiveChannelSpecTypeMismatchError.expected(Value.self, actual: type(of: update))
            }
            return try spec.reducer.reduce(current: typedCurrent, update: typedUpdate)
        }

        if let codec = spec.codec {
            self._encodeBox = { value in
                guard let typedValue = value as? Value else {
                    throw HiveChannelSpecTypeMismatchError.expected(Value.self, actual: type(of: value))
                }
                return try codec.encode(typedValue)
            }
            self._decodeBox = { data in
                try codec.decode(data)
            }
        } else {
            self._encodeBox = nil
            self._decodeBox = nil
        }
    }
}

internal enum HiveChannelSpecTypeMismatchError: Error {
    case expected(Any.Type, actual: Any.Type)
}
