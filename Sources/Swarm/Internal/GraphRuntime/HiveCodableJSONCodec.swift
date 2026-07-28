#if SWARM_INTEGRATIONS
import Foundation
import HiveCore

/// Deterministic JSON codec for Hive checkpointing and task hashing.
///
/// - Important: Only use for types whose JSON encoding is deterministic under `JSONEncoder(outputFormatting: .sortedKeys)`.
struct HiveCodableJSONCodec<Value: Codable & Sendable>: HiveCodec, Sendable {
    let id: String

    init(id: String? = nil) {
        self.id = id ?? "HiveSwarm.HiveCodableJSONCodec<\(String(describing: Value.self))>"
    }

    func encode(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    func decode(_ data: Data) throws -> Value {
        try JSONDecoder().decode(Value.self, from: data)
    }
}

#endif
