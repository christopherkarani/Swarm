// Agent+Resilience.swift
// Swarm Framework
//
// Wraps provider inference with rate limiting, circuit breaking, and retry.

import Foundation

extension Agent {
    /// Executes a provider inference call under the configured resilience policies.
    ///
    /// Always bounded by the remaining ``AgentConfiguration/timeout``. When no
    /// resilience policies are active, this is equivalent to
    /// ``executeWithinRemainingTimeout(startTime:operation:)``.
    ///
    /// - Parameters:
    ///   - startTime: Run start used to compute remaining timeout.
    ///   - observer: Optional observer; retries fire ``AgentObserver/onInferenceRetry(context:agent:attempt:error:)``.
    ///   - tracing: Optional tracing helper; retries emit a `.metric` trace event.
    ///   - retryPolicy: Override for this call. Pass ``RetryPolicy/noRetry`` to skip
    ///     retry while still honoring limiter and breaker (Foundation Models native
    ///     session turns that execute tools inside Apple's loop). `nil` uses
    ///     ``ResilienceConfiguration/retryPolicy``.
    ///   - operation: The inference call.
    func executeProviderInference<T: Sendable>(
        startTime: ContinuousClock.Instant,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        retryPolicy: RetryPolicy? = nil,
        executionGate: ProviderOwnedLoopGate? = nil,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let policy = retryPolicy ?? configuration.resilience.retryPolicy
        return try await executeWithinRemainingTimeout(startTime: startTime, executionGate: executionGate) {
            try await self.performResilientInference(
                retryPolicy: policy,
                observer: observer,
                tracing: tracing,
                operation: operation
            )
        }
    }

    private func performResilientInference<T: Sendable>(
        retryPolicy: RetryPolicy,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        if inferenceRateLimiter == nil,
           inferenceCircuitBreaker == nil,
           retryPolicy.maxAttempts == 0 {
            return try await operation()
        }

        let agent: any AgentRuntime = self
        let invoke: @Sendable () async throws -> T = {
            try await Self.invokeWithRetry(
                policy: retryPolicy,
                agent: agent,
                observer: observer,
                tracing: tracing,
                operation: operation
            )
        }

        if let limiter = inferenceRateLimiter {
            try await limiter.acquire()
        }

        if let breaker = inferenceCircuitBreaker {
            return try await breaker.execute(invoke)
        }

        return try await invoke()
    }

    /// Retries provider inference under the canonical internal seam
    /// ``ResilienceRetry`` (W3-T3), which pins the historical semantics:
    /// hard gate (`InferenceRetryability`) conjoined with `shouldRetry`,
    /// initial attempt + `maxAttempts` retries, immediate cancellation
    /// rethrow, and `ResilienceError.retriesExhausted` on budget exhaustion.
    /// This wrapper only layers agent-path side effects onto each retry:
    /// warning log, observer callback, trace metric.
    private static func invokeWithRetry<T: Sendable>(
        policy: RetryPolicy,
        agent: any AgentRuntime,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await ResilienceRetry.run(policy: policy, onRetryAttempt: { attempt, error in
            Log.agents.warning(
                "Inference retry attempt \(attempt): \(error.localizedDescription)"
            )
            await observer?.onInferenceRetry(
                context: nil,
                agent: agent,
                attempt: attempt,
                error: error
            )
            await tracing?.traceInferenceRetry(attempt: attempt, error: error)
        }, operation: operation)
    }
}
