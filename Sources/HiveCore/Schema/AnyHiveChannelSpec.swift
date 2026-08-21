import Foundation

public struct AnyHiveChannelSpec<Schema: HiveSchema>: Sendable {
    public let id: HiveChannelID
    public let scope: HiveChannelScope
    public let persistence: HiveChannelPersistence
    public let updatePolicy: HiveUpdatePolicy

    /// Diagnostic / schema-fingerprint only; typically `String(reflecting: Value.self)`.
    /// Type equality uses ``valueTypeIdentifier`` and boxed `Value` checks.
    public let valueTypeID: String

    /// Compiler-level identity of the spec’s `Value`, used for key/value matching.
    public let valueTypeIdentifier: ObjectIdentifier

    /// Equal to `codec?.id`, else nil.
    public let codecID: String?

    internal let _initialBox: @Sendable () -> any Sendable
    internal let _reduceBox: @Sendable (any Sendable, any Sendable) throws -> any Sendable
    internal let _encodeBox: (@Sendable (any Sendable) throws -> Data)?
    internal let _decodeBox: (@Sendable (Data) throws -> any Sendable)?
    internal let _matchesBox: @Sendable (any Sendable) -> Bool
    internal let _castBox: @Sendable (any Sendable) throws -> any Sendable

    public init<Value: Sendable>(
        _ spec: HiveChannelSpec<Schema, Value>,
        valueTypeID: String = String(reflecting: Value.self)
    ) {
        self.id = spec.key.id
        self.scope = spec.scope
        self.persistence = spec.persistence
        self.updatePolicy = spec.updatePolicy
        self.valueTypeID = valueTypeID
        self.valueTypeIdentifier = ObjectIdentifier(Value.self)
        self.codecID = spec.codec?.id

        self._initialBox = { spec.initial() }
        self._matchesBox = { $0 is Value }
        self._castBox = { value in
            guard let typedValue = value as? Value else {
                throw HiveChannelSpecTypeMismatchError.expected(Value.self, actual: type(of: value))
            }
            return typedValue
        }
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

    /// Returns whether `value` is the spec’s boxed `Value` (`as?` / `is`), not a reflected type string.
    public func matchesStoredValue(_ value: any Sendable) -> Bool {
        _matchesBox(value)
    }

    /// Returns whether `type` is the spec’s `Value`.
    public func matchesValueType(_ type: Any.Type) -> Bool {
        ObjectIdentifier(type) == valueTypeIdentifier
    }

    /// Casts a stored value to the spec’s `Value`, then re-boxes it.
    public func castStoredValue(_ value: any Sendable) throws -> any Sendable {
        try _castBox(value)
    }
}

internal enum HiveChannelSpecTypeMismatchError: Error {
    case expected(Any.Type, actual: Any.Type)
}
