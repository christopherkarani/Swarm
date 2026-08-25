// ResilienceRetry.swift
// Swarm Framework
//
// Canonical retry/backoff loop for agent provider inference (W3-T3).
//
// Single source of truth for the inference retry path previously inlined in
// `Agent+Resilience.invokeWithRetry` as a derived `RetryPolicy` fed to the
// public `RetryPolicy.execute`. Semantics are identical to the pre-W3-T3
// agent path:
//
// - Attempt budget: one initial attempt plus `policy.maxAttempts` retries;
//   `maxAttempts == 0` short-circuits to a single bare attempt whose error is
//   rethrown verbatim (never wrapped).
// - Hard retryability gate: retries require BOTH
//   ``InferenceRetryability/isRetryable(_:)`` and the user-supplied
//   `RetryPolicy.shouldRetry` predicate.
// - Cancellation: a `CancellationError` or an already-cancelled task rethrows
//   immediately without consuming budget or sleeping.
// - Exhaustion throws `ResilienceError.retriesExhausted(attempts:lastError:)`
//   with `attempts == maxAttempts + 1`.
// - Backoff: `BackoffStrategy.delay(forAttempt:)` sanitized into
//   `[0, 1h]` nanoseconds before each sleep.
//
// Delays suspend through the injected `SwarmClock` seam (wave-1 convention),
// so suites drive exact backoff progression deterministically with a virtual
// clock instead of real sleeps.
//
// Divergence note: `ChatGraph.withRetry`
// (`Sources/Swarm/Internal/GraphRuntime/ChatGraph.swift`) deliberately keeps
// its own local loop for the Hive graph path; its doc comment cites the
// concrete semantic differences (total-attempt counting, verbatim last-error
// rethrow in the graph runtime error domain, unconditional retry gating).

import Foundation

/// Namespace for the canonical agent-inference retry executor.
///
/// See the file header for the pinned semantics and the deliberate
/// `ChatGraph.withRetry` divergence.
enum ResilienceRetry {
    /// Backoff ceiling shared with ``RetryPolicy``: one hour in nanoseconds.
    private static let maxBackoffNanoseconds: UInt64 = 3_600_000_000_000

    /// Runs `operation` under the canonical inference retry policy.
    ///
    /// - Parameters:
    ///   - policy: User retry configuration; `maxAttempts` counts retries
    ///     **after** the initial attempt.
    ///   - clock: Suspension seam for backoff delays; inject a virtual clock
    ///     in tests for deterministic progression.
    ///   - onRetryAttempt: Extra per-retry side effects (logging, observer,
    ///     tracing), invoked after `policy.onRetry` and before the backoff
    ///     sleep, preserving the historical agent-path ordering.
    ///   - operation: The inference call to protect.
    static func run<T: Sendable>(
        policy: RetryPolicy,
        clock: any SwarmClock = LiveSwarmClock.live,
        onRetryAttempt: (@Sendable (Int, Error) async -> Void)? = nil,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        guard policy.maxAttempts > 0 else {
            return try await operation()
        }

        var retryCount = 0
        var lastError: (any Error)?

        while true {
            do {
                return try await operation()
            } catch {
                if error is CancellationError || Task.isCancelled {
                    throw error
                }

                lastError = error

                guard retryCount < policy.maxAttempts else {
                    break
                }

                // Hard retryability gate conjoined with the user predicate;
                // identical composition to the pre-convergence
                // `invokeWithRetry` wrapper.
                guard InferenceRetryability.isRetryable(error) && policy.shouldRetry(error) else {
                    throw error
                }

                retryCount += 1

                await policy.onRetry?(retryCount, error)
                await onRetryAttempt?(retryCount, error)

                let delay = sanitizedBackoffNanoseconds(policy.backoff.delay(forAttempt: retryCount))
                if delay > 0 {
                    try await clock.sleep(nanoseconds: delay)
                }
            }
        }

        throw ResilienceError.retriesExhausted(
            attempts: retryCount + 1,
            lastError: lastError?.localizedDescription ?? "Unknown error"
        )
    }

    private static func sanitizedBackoffNanoseconds(_ delaySeconds: TimeInterval) -> UInt64 {
        guard delaySeconds.isFinite, delaySeconds > 0 else {
            return 0
        }

        let nanoseconds = delaySeconds * 1_000_000_000
        guard nanoseconds.isFinite, nanoseconds > 0 else {
            return 0
        }

        if nanoseconds >= Double(maxBackoffNanoseconds) {
            return maxBackoffNanoseconds
        }

        return UInt64(nanoseconds)
    }
}
