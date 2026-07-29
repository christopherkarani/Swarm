/// Defines where a channel is stored.
public enum HiveChannelScope: Sendable {
    case global
    case taskLocal
}

/// Defines whether a channel participates in checkpointing.
public enum HiveChannelPersistence: Sendable {
    case checkpointed
    case untracked
    /// Value resets to `initial()` at the start of each superstep.
    /// Distinct from `.untracked` (which skips checkpointing but keeps the value).
    case ephemeral
}

extension HiveChannelPersistence {
    /// `true` for channels whose value is reset to `initial()` at the start of the next superstep.
    public var resetsAfterStep: Bool {
        if case .ephemeral = self { return true }
        return false
    }
}

/// Defines how multiple writes to the same channel are handled.
public enum HiveUpdatePolicy: Sendable {
    case single
    case multi
}

/// Schema-declared channel metadata and behavior.
public struct HiveChannelSpec<Schema: HiveSchema, Value: Sendable>: Sendable {
    public let key: HiveChannelKey<Schema, Value>
    public let scope: HiveChannelScope
    public let reducer: HiveReducer<Value>
    public let updatePolicy: HiveUpdatePolicy
    public let initial: @Sendable () -> Value
    public let codec: HiveAnyCodec<Value>?
    public let persistence: HiveChannelPersistence

    public init(
        key: HiveChannelKey<Schema, Value>,
        scope: HiveChannelScope,
        reducer: HiveReducer<Value>,
        updatePolicy: HiveUpdatePolicy = .single,
        initial: @escaping @Sendable () -> Value,
        codec: HiveAnyCodec<Value>? = nil,
        persistence: HiveChannelPersistence
    ) {
        self.key = key
        self.scope = scope
        self.reducer = reducer
        self.updatePolicy = updatePolicy
        self.initial = initial
        self.codec = codec
        self.persistence = persistence
    }
}
