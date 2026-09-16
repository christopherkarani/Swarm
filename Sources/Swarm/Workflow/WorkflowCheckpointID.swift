import Foundation

/// Stable identifier for a durable workflow checkpoint thread.
///
/// Wraps the checkpoint string used with Hive durable execution. Prefer this type
/// over raw strings when configuring ``DurableWorkflow``.
public struct WorkflowCheckpointID: Hashable, Sendable, RawRepresentable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }
}
