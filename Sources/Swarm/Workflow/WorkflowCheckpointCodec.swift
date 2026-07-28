#if SWARM_INTEGRATIONS
import Foundation
import HiveCore

/// Deterministic JSON codec used by Workflow's durable checkpoint engine.
///
/// This stays internal so persistence plumbing does not leak into the public Swarm API.
struct WorkflowCheckpointCodec<Value: Codable & Sendable>: HiveCodec, Sendable {
    let id: String

    init(id: String? = nil) {
        self.id = id ?? "Swarm.WorkflowCheckpointCodec<\(String(describing: Value.self))>"
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
