/// Retry strategy for node execution.
public enum HiveRetryPolicy: Sendable {
    case none
    case exponentialBackoff(
        initialNanoseconds: UInt64,
        factor: Double,
        maxAttempts: Int,
        maxNanoseconds: UInt64
    )
}
