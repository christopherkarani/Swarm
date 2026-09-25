/// Retry strategy for node execution.
///
/// `maxAttempts` counts total attempts including the initial attempt and must
/// be at least 1. This matches `RetryPolicy.maxAttempts` and
/// `AsyncThrowingStream.retry(maxAttempts:delay:factory:)`: `1` runs once with
/// no retries. `HiveRuntime` rejects `maxAttempts < 1` during validation.
public enum HiveRetryPolicy: Sendable {
    case none
    case exponentialBackoff(
        initialNanoseconds: UInt64,
        factor: Double,
        maxAttempts: Int,
        maxNanoseconds: UInt64
    )
}
