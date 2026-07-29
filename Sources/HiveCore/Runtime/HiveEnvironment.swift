/// Monotonic time source for retries and durations.
public protocol HiveClock: Sendable {
    func nowNanoseconds() -> UInt64
    func sleep(nanoseconds: UInt64) async throws
}

/// Minimal logging surface for runtime diagnostics.
public protocol HiveLogger: Sendable {
    func debug(_ message: String, metadata: [String: String])
    func info(_ message: String, metadata: [String: String])
    func error(_ message: String, metadata: [String: String])
}

/// Execution environment injected into nodes.
public struct HiveEnvironment<Schema: HiveSchema>: Sendable {
    public let context: Schema.Context
    public let clock: any HiveClock
    public let logger: any HiveLogger
    public let checkpointStore: AnyHiveCheckpointStore<Schema>?

    public init(
        context: Schema.Context,
        clock: any HiveClock,
        logger: any HiveLogger,
        checkpointStore: AnyHiveCheckpointStore<Schema>? = nil
    ) {
        self.context = context
        self.clock = clock
        self.logger = logger
        self.checkpointStore = checkpointStore
    }
}
