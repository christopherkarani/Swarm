/// Checkpoint query operations exposed by optional checkpoint-store query APIs.
public enum HiveCheckpointQueryOperation: Sendable, Equatable {
    case listCheckpoints
    case loadCheckpointByID
}

/// Errors related to optional checkpoint query capabilities.
public enum HiveCheckpointQueryError: Error, Sendable, Equatable {
    /// The configured checkpoint store does not support the requested query operation.
    case unsupported(operation: HiveCheckpointQueryOperation)
}
