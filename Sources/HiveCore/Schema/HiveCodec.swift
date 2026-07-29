import Foundation

/// Deterministic encoder/decoder for checkpointing and hashing.
public protocol HiveCodec: Sendable {
    associatedtype Value: Sendable

    /// Stable identifier included in schema versioning.
    var id: String { get }

    /// Returns canonical bytes for the provided value.
    func encode(_ value: Value) throws -> Data
    /// Decodes a value from canonical bytes.
    func decode(_ data: Data) throws -> Value
}

/// Type-erased codec wrapper.
public struct HiveAnyCodec<Value: Sendable>: Sendable {
    public let id: String
    private let _encode: @Sendable (Value) throws -> Data
    private let _decode: @Sendable (Data) throws -> Value

    public init<C: HiveCodec>(_ codec: C) where C.Value == Value {
        self.id = codec.id
        self._encode = codec.encode
        self._decode = codec.decode
    }

    public func encode(_ value: Value) throws -> Data {
        try _encode(value)
    }

    public func decode(_ data: Data) throws -> Value {
        try _decode(data)
    }
}
