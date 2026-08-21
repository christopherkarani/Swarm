/// Typed key for reading and writing channel values.
///
/// Keys are minted by ``HiveChannelSpec`` so `Value` is bound to the schema’s
/// registered channel. Callers must not construct a key with an arbitrary
/// `Value` for an existing channel ID.
public struct HiveChannelKey<Schema: HiveSchema, Value: Sendable>: Hashable, Sendable {
    public let id: HiveChannelID

    /// Bound construction used by ``HiveChannelSpec``.
    init(_ id: HiveChannelID) {
        self.id = id
    }
}
