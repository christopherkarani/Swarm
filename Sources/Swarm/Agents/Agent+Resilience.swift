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
    ///   - allowsRetry: When `false`, skip retry (still honor limiter + breaker).
    ///     Used for Foundation Models native session turns that execute tools
    ///     inside Apple's loop so those tools are not replayed.
    ///   - operation: The inference call.
    func executeProviderInference<T: Sendable>(
        startTime: ContinuousClock.Instant,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        allowsRetry: Bool = true,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await executeWithinRemainingTimeout(startTime: startTime) {
            try await self.resilienceRuntime.execute(
                configuration: self.configuration.resilience,
                agentName: self.configuration.name,
                agent: self,
                observer: observer,
                tracing: tracing,
                allowsRetry: allowsRetry,
                operation: operation
            )
        }
    }
}

// MARK: - AgentResilienceRuntime

/// Per-agent actors for circuit breaking and rate limiting.
///
/// Scoped to an ``Agent`` instance and shared across its runs. Distinct agent
/// values get distinct runtimes.
actor AgentResilienceRuntime {
    func execute<T: Sendable>(
        configuration: ResilienceConfiguration,
        agentName: String,
        agent: any AgentRuntime,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        allowsRetry: Bool,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        guard configuration.hasActivePolicies else {
            return try await operation()
        }

        if let limiter = rateLimiter(for: configuration.rateLimit) {
            try await limiter.acquire()
        }

        let invoke: @Sendable () async throws -> T = {
            try await Self.invokeWithRetry(
                configuration: configuration,
                allowsRetry: allowsRetry,
                agent: agent,
                observer: observer,
                tracing: tracing,
                operation: operation
            )
        }

        if let breaker = circuitBreaker(for: configuration.circuitBreaker, agentName: agentName) {
            return try await breaker.execute(invoke)
        }

        return try await invoke()
    }

    // MARK: Private

    private var circuitBreakerInstance: CircuitBreaker?
    private var rateLimiterInstance: RateLimiter?

    private func circuitBreaker(
        for settings: CircuitBreakerSettings?,
        agentName: String
    ) -> CircuitBreaker? {
        guard let settings else { return nil }
        if let circuitBreakerInstance {
            return circuitBreakerInstance
        }

        let resolvedName: String
        if let explicitName = settings.name, !explicitName.isEmpty {
            resolvedName = explicitName
        } else {
            let trimmed = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
            resolvedName = "agent:\(trimmed.isEmpty ? "Agent" : trimmed):inference"
        }

        let breaker = CircuitBreaker(
            name: resolvedName,
            failureThreshold: settings.failureThreshold,
            successThreshold: settings.successThreshold,
            resetTimeout: settings.resetTimeout,
            halfOpenMaxRequests: settings.halfOpenMaxRequests
        )
        circuitBreakerInstance = breaker
        return breaker
    }

    private func rateLimiter(for settings: RateLimitSettings?) -> RateLimiter? {
        guard let settings else { return nil }
        if let rateLimiterInstance {
            return rateLimiterInstance
        }

        let limiter = RateLimiter(
            maxTokens: settings.maxTokens,
            refillRatePerSecond: settings.refillRatePerSecond
        )
        rateLimiterInstance = limiter
        return limiter
    }

    private static func invokeWithRetry<T: Sendable>(
        configuration: ResilienceConfiguration,
        allowsRetry: Bool,
        agent: any AgentRuntime,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let policy = configuration.retryPolicy
        guard allowsRetry, policy.maxAttempts > 0 else {
            return try await operation()
        }

        let retryPolicy = RetryPolicy(
            maxAttempts: policy.maxAttempts,
            backoff: policy.backoff,
            shouldRetry: { error in
                InferenceRetryability.isRetryable(error)
            },
            onRetry: { attempt, error in
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
            }
        )

        return try await retryPolicy.execute(operation)
    }
}
