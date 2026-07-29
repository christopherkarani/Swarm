/// Policy controlling checkpoint save cadence.
public enum HiveCheckpointPolicy: Sendable {
    case disabled
    case everyStep
    case every(steps: Int)
    case onInterrupt
}

/// Controls what additional events the runtime emits after each step.
public enum HiveStreamingMode: Sendable, Equatable {
    /// Default — no additional streaming events beyond the standard event stream.
    case events
    /// Emit a full store snapshot after each step.
    case values
    /// Emit only the channels that were written in each step.
    case updates
    /// Emit both a full store snapshot and channel updates after each step.
    case combined
}

/// Runtime execution options for a run attempt.
public struct HiveRunOptions: Sendable {
    public let maxSteps: Int
    public let maxConcurrentTasks: Int
    public let checkpointPolicy: HiveCheckpointPolicy
    public let debugPayloads: Bool
    public let deterministicStreamBuffering: Bool
    public let eventBufferCapacity: Int
    public let outputProjectionOverride: HiveOutputProjection?
    public let streamingMode: HiveStreamingMode

    public init(
        maxSteps: Int = 100,
        maxConcurrentTasks: Int = 8,
        checkpointPolicy: HiveCheckpointPolicy = .disabled,
        debugPayloads: Bool = false,
        deterministicStreamBuffering: Bool = false,
        eventBufferCapacity: Int = 4096,
        outputProjectionOverride: HiveOutputProjection? = nil,
        streamingMode: HiveStreamingMode = .events
    ) {
        self.maxSteps = maxSteps
        self.maxConcurrentTasks = maxConcurrentTasks
        self.checkpointPolicy = checkpointPolicy
        self.debugPayloads = debugPayloads
        self.deterministicStreamBuffering = deterministicStreamBuffering
        self.eventBufferCapacity = eventBufferCapacity
        self.outputProjectionOverride = outputProjectionOverride
        self.streamingMode = streamingMode
    }
}
