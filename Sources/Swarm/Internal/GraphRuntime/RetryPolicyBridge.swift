#if SWARM_INTEGRATIONS
// RetryPolicyBridge.swift
// HiveSwarm
//
// Maps Swarm's RetryPolicy to Hive's HiveRetryPolicy for deterministic retry.

import Foundation
import HiveCore

/// Converts between Swarm's `RetryPolicy` and Hive's `HiveRetryPolicy`.
///
/// Hive requires deterministic retry behavior (no jitter), so jitter-based
/// strategies are mapped to their non-jitter equivalents. The bridge preserves
/// `maxAttempts` and base delay while stripping non-deterministic components.
///
/// Example:
/// ```swift
/// let swarmPolicy = RetryPolicy.standard
/// let hivePolicy = RetryPolicyBridge.toHive(swarmPolicy)
/// // .exponentialBackoff(initialNanoseconds: 1_000_000_000, factor: 2.0, maxAttempts: 3, ...)
/// ```
enum RetryPolicyBridge {

    /// Converts a Swarm `RetryPolicy` to a `HiveRetryPolicy`.
    ///
    /// - Parameter policy: The Swarm retry policy to convert.
    /// - Returns: The equivalent `HiveRetryPolicy` for deterministic execution.
    static func toHive(_ policy: RetryPolicy) -> HiveRetryPolicy {
        if policy.maxAttempts <= 0 {
            return .none
        }

        switch policy.backoff {
        case .exponential(let base, let multiplier, let maxDelay):
            return .exponentialBackoff(
                initialNanoseconds: secondsToNanoseconds(base),
                factor: multiplier,
                maxAttempts: policy.maxAttempts,
                maxNanoseconds: secondsToNanoseconds(maxDelay)
            )

        case .exponentialWithJitter(let base, let multiplier, let maxDelay):
            // Strip jitter — Hive requires deterministic retry.
            return .exponentialBackoff(
                initialNanoseconds: secondsToNanoseconds(base),
                factor: multiplier,
                maxAttempts: policy.maxAttempts,
                maxNanoseconds: secondsToNanoseconds(maxDelay)
            )

        case .decorrelatedJitter(let base, let maxDelay):
            // Map to exponential with 2x factor, strip jitter.
            return .exponentialBackoff(
                initialNanoseconds: secondsToNanoseconds(base),
                factor: 2.0,
                maxAttempts: policy.maxAttempts,
                maxNanoseconds: secondsToNanoseconds(maxDelay)
            )

        case .fixed(let delay):
            // Fixed delay = exponential with factor 1.0 (no growth).
            return .exponentialBackoff(
                initialNanoseconds: secondsToNanoseconds(delay),
                factor: 1.0,
                maxAttempts: policy.maxAttempts,
                maxNanoseconds: secondsToNanoseconds(delay)
            )

        case .linear(let initial, _, let maxDelay):
            Log.agents.info("RetryPolicyBridge: linear backoff (step=\(0)) approximated as 1.5x exponential for Hive determinism.")
            return .exponentialBackoff(
                initialNanoseconds: secondsToNanoseconds(initial),
                factor: 1.5,
                maxAttempts: policy.maxAttempts,
                maxNanoseconds: secondsToNanoseconds(maxDelay)
            )

        case .immediate:
            return .exponentialBackoff(
                initialNanoseconds: 0,
                factor: 1.0,
                maxAttempts: policy.maxAttempts,
                maxNanoseconds: 0
            )

        case .custom:
            Log.agents.warning("Custom retry policy cannot be represented in Hive's deterministic model; using default exponential backoff (1s base, 2x factor, 60s max).")
            return .exponentialBackoff(
                initialNanoseconds: 1_000_000_000,
                factor: 2.0,
                maxAttempts: policy.maxAttempts,
                maxNanoseconds: 60_000_000_000
            )
        }
    }

    private static func secondsToNanoseconds(_ seconds: TimeInterval) -> UInt64 {
        guard seconds > 0 else { return 0 }
        return UInt64(clamping: Int64(seconds * 1_000_000_000))
    }
}
#endif
