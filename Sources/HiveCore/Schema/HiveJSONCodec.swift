import Foundation

/// JSON-based codec for Codable values with deterministic key ordering.
public struct HiveJSONCodec<Value: Codable & Sendable>: HiveCodec {
    public let id: String

    public init(id: String? = nil) {
        self.id = id ?? "hive.json.v1:\(String(reflecting: Value.self))"
    }

    public func encode(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    public func decode(_ data: Data) throws -> Value {
        let decoder = JSONDecoder()
        return try decoder.decode(Value.self, from: data)
    }
}
