import Foundation

/// Error surface for ContextCore operations.
public enum ContextCoreError: Error, Sendable, Equatable {
    /// Embedding generation failed.
    case embeddingFailed(String)
    /// A store reached capacity and cannot accept more entries.
    case storeFull
    /// The effective token budget is too small to fit required content.
    case tokenBudgetTooSmall
    /// A session-scoped API was called before starting a session.
    case sessionNotStarted
    /// Compression processing failed.
    case compressionFailed(String)
    /// Checkpoint data is missing or malformed.
    case checkpointCorrupt
    /// No Metal-capable device is available.
    case metalDeviceUnavailable
    /// Input vectors had inconsistent dimensionality.
    case dimensionMismatch(expected: Int, got: Int)
    /// Requested chunk ID was not found.
    case chunkNotFound(id: UUID)
}
