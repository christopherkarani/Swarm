import Foundation

/// Stable identifier for a channel within a schema.
public struct HiveChannelID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
