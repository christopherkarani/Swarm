/// Combines multiple writes targeting the same channel.
public struct HiveReducer<Value: Sendable>: Sendable {
    private let _reduce: @Sendable (Value, Value) throws -> Value

    public init(_ reduce: @escaping @Sendable (Value, Value) throws -> Value) {
        self._reduce = reduce
    }

    public func reduce(current: Value, update: Value) throws -> Value {
        try _reduce(current, update)
    }
}
