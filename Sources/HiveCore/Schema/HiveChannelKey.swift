/// Typed key for reading and writing channel values.
public struct HiveChannelKey<Schema: HiveSchema, Value: Sendable>: Hashable, Sendable {
    public let id: HiveChannelID

    public init(_ id: HiveChannelID) {
        self.id = id
    }
}
