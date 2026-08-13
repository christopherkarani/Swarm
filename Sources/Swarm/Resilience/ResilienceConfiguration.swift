// ResilienceConfiguration.swift
// Swarm Framework
//
// Agent-facing resilience settings for retry, circuit breaking, and rate limiting.

import Foundation

// MARK: - CircuitBreakerSettings

/// Configuration for an agent-scoped inference circuit breaker.
///
/// When set on ``ResilienceConfiguration/circuitBreaker``, ``Agent`` creates a
/// ``CircuitBreaker`` **once per agent instance** and reuses it across `run()` /
/// `stream()` calls. Copies of the same `Agent` value share that breaker because
/// it is an actor. Distinct `Agent` values do not share state.
///
/// Circuit breaking applies only to **provider inference** calls, never to tool
/// execution.
public struct CircuitBreakerSettings: Sendable, Equatable {
    /// Consecutive inference failures before the breaker opens.
    ///
    /// Default: `5`.
    public var failureThreshold: Int

    /// Consecutive successes in half-open state required to close the breaker.
    ///
    /// Default: `2`.
    public var successThreshold: Int

    /// Seconds to wait after opening before probing half-open recovery.
    ///
    /// Default: `60`.
    public var resetTimeout: TimeInterval

    /// Maximum concurrent probes allowed while half-open.
    ///
    /// Default: `1`.
    public var halfOpenMaxRequests: Int

    /// Optional breaker name used in ``ResilienceError/circuitBreakerOpen(serviceName:)``.
    ///
    /// When `nil`, Swarm uses `agent:<configuration.name>:inference`.
    public var name: String?

    /// Creates circuit-breaker settings for agent inference.
    ///
    /// - Parameters:
    ///   - failureThreshold: Consecutive failures before opening. Default: `5`
    ///   - successThreshold: Consecutive half-open successes to close. Default: `2`
    ///   - resetTimeout: Seconds before a half-open probe. Default: `60`
    ///   - halfOpenMaxRequests: Concurrent half-open probes. Default: `1`
    ///   - name: Optional breaker name. Default: `nil` (derived from the agent name)
    public init(
        failureThreshold: Int = 5,
        successThreshold: Int = 2,
        resetTimeout: TimeInterval = 60.0,
        halfOpenMaxRequests: Int = 1,
        name: String? = nil
    ) {
        self.failureThreshold = max(1, failureThreshold)
        self.successThreshold = max(1, successThreshold)
        self.resetTimeout = max(0, resetTimeout)
        self.halfOpenMaxRequests = max(1, halfOpenMaxRequests)
        self.name = name
    }
}

// MARK: - RateLimitSettings

/// Token-bucket settings for agent inference rate limiting.
///
/// When set on ``ResilienceConfiguration/rateLimit``, ``Agent`` creates a
/// ``RateLimiter`` **once per agent instance** and reuses it across runs.
/// Each logical provider inference call acquires one token **before** retries;
/// retry attempts of that call do not acquire additional tokens.
///
/// Rate limiting applies only to **provider inference** calls, never to tool
/// execution.
public struct RateLimitSettings: Sendable, Equatable {
    /// Maximum tokens the bucket can hold.
    public var maxTokens: Int

    /// Tokens added per second.
    public var refillRatePerSecond: Double

    /// Creates token-bucket settings.
    ///
    /// - Parameters:
    ///   - maxTokens: Bucket capacity. Values below `1` are clamped to `1`.
    ///   - refillRatePerSecond: Refill rate. Non-finite or non-positive values
    ///     become `1.0`.
    public init(maxTokens: Int, refillRatePerSecond: Double) {
        self.maxTokens = max(1, maxTokens)
        self.refillRatePerSecond = refillRatePerSecond.isFinite && refillRatePerSecond > 0
            ? refillRatePerSecond
            : 1.0
    }

    /// Creates settings equivalent to `maxRequestsPerMinute` sustained throughput.
    ///
    /// - Parameter maxRequestsPerMinute: Permitted inference calls per minute.
    public init(maxRequestsPerMinute: Int) {
        let normalized = max(1, maxRequestsPerMinute)
        self.init(
            maxTokens: normalized,
            refillRatePerSecond: Double(normalized) / 60.0
        )
    }
}

// MARK: - ResilienceConfiguration

/// Resilience policies applied to provider inference inside ``Agent/run(_:session:observer:)``.
///
/// Default ``disabled`` is a no-op: ``RetryPolicy/noRetry``, no circuit breaker,
/// and no rate limiter. Unconfigured agents behave identically to Swarm before
/// this API existed.
///
/// ## What is wrapped
///
/// Rate limiting, circuit breaking, and retry apply **only** to provider
/// inference (`generate`, `generateWithToolCalls`, streaming inference, and
/// Foundation Models native-session generation). Tool execution is never
/// retried — tools can have side effects.
///
/// Provider fallback (``FallbackChain``) is **not** wired here. Compose
/// providers yourself, or wait for a dedicated fallback API.
///
/// ## Timeout interaction
///
/// Retries consume the same remaining ``AgentConfiguration/timeout`` budget as
/// the rest of the run. Backoff sleeps and subsequent attempts are cancelled
/// when that deadline expires; a retry cannot outlive the run.
///
/// ## Retryability
///
/// ``Agent`` ignores a policy's `shouldRetry` closure for classification and
/// instead uses ``InferenceRetryability/isRetryable(_:)``. Permanent failures
/// (cancellation, guardrail rejection, schema/parse errors, tool failures) are
/// never retried. See ``InferenceRetryability`` for the table.
///
/// ## Scoping
///
/// Circuit-breaker and rate-limiter actors are created per ``Agent`` instance
/// and shared across that instance's runs. They are not shared globally or
/// per provider type.
///
/// ## Example
///
/// ```swift
/// let config = AgentConfiguration.default
///     .resilience(ResilienceConfiguration(
///         retryPolicy: .standard,
///         circuitBreaker: CircuitBreakerSettings(failureThreshold: 5),
///         rateLimit: RateLimitSettings(maxRequestsPerMinute: 60)
///     ))
///
/// let agent = try Agent("Be concise.", configuration: config, inferenceProvider: provider)
/// ```
public struct ResilienceConfiguration: Sendable, Equatable {
    /// Disabled resilience — no retries, breaker, or limiter.
    ///
    /// This is the default on ``AgentConfiguration`` and must remain
    /// behavior-identical to an agent with no resilience field.
    public static let disabled = ResilienceConfiguration()

    /// Retry policy applied to each provider inference call.
    ///
    /// Default: ``RetryPolicy/noRetry``. Only ``RetryPolicy/maxAttempts`` and
    /// ``RetryPolicy/backoff`` are honored by ``Agent``; retryability is
    /// classified by ``InferenceRetryability``.
    public var retryPolicy: RetryPolicy

    /// Optional circuit-breaker settings for inference.
    ///
    /// `nil` (default) skips circuit breaking entirely.
    public var circuitBreaker: CircuitBreakerSettings?

    /// Optional token-bucket rate limit for inference.
    ///
    /// `nil` (default) skips rate limiting entirely.
    public var rateLimit: RateLimitSettings?

    /// Creates a resilience configuration.
    ///
    /// - Parameters:
    ///   - retryPolicy: Retry policy. Default: ``RetryPolicy/noRetry``
    ///   - circuitBreaker: Optional breaker settings. Default: `nil`
    ///   - rateLimit: Optional rate-limit settings. Default: `nil`
    public init(
        retryPolicy: RetryPolicy = .noRetry,
        circuitBreaker: CircuitBreakerSettings? = nil,
        rateLimit: RateLimitSettings? = nil
    ) {
        self.retryPolicy = retryPolicy
        self.circuitBreaker = circuitBreaker
        self.rateLimit = rateLimit
    }

    /// Whether any policy would change inference execution relative to the default.
    package var hasActivePolicies: Bool {
        retryPolicy.maxAttempts > 0 || circuitBreaker != nil || rateLimit != nil
    }
}
