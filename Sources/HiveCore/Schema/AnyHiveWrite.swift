/// Type-erased write to a channel.
public struct AnyHiveWrite<Schema: HiveSchema>: Sendable {
    public let channelID: HiveChannelID
    public let value: any Sendable

    public init<Value: Sendable>(_ key: HiveChannelKey<Schema, Value>, _ value: Value) {
        self.channelID = key.id
        self.value = value
    }
}

/// Deterministic ordering key inside a task output writes array.
public typealias HiveWriteEmissionIndex = Int
