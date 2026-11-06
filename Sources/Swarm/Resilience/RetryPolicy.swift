// RetryPolicy.swift
// Swarm Framework
//
// Configurable retry strategies with backoff patterns for robust agent execution.

import Foundation

// MARK: - ResilienceError

/// Errors specific to resilience patterns.
public enum ResilienceError: Error, Sendable, Equatable {
    /// All retry attempts have been exhausted.
    case retriesExhausted(attempts: Int, lastError: String)

    /// The circuit breaker is open, preventing execution.
    case circuitBreakerOpen(serviceName: String)

    /// All fallback strategies failed.
    case allFallbacksFailed(errors: [String])

    /// A retry configuration requested an invalid attempt budget.
    ///
    /// `maxAttempts` counts total attempts including the initial attempt and
    /// must be at least 1. Values below 1 are rejected instead of clamping or
    /// silently succeeding with zero attempts.
    case invalidMaxAttempts(Int)
}

// MARK: LocalizedError

extension ResilienceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .retriesExhausted(attempts, lastError):
            "Retries exhausted after \(attempts) attempts. Last error: \(lastError)"
        case let .circuitBreakerOpen(serviceName):
            "Circuit breaker is open for service: \(serviceName)"
        case let .allFallbacksFailed(errors):
            "All fallback strategies failed. Errors: \(errors.joined(separator: "; "))"
        case let .invalidMaxAttempts(value):
            "Invalid maxAttempts \(value): must be at least 1 total attempt including the initial attempt."
        }
    }
}

// MARK: CustomDebugStringConvertible

extension ResilienceError: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case let .retriesExhausted(attempts, lastError):
            "ResilienceError.retriesExhausted(attempts: \(attempts), lastError: \(lastError))"
        case let .circuitBreakerOpen(serviceName):
            "ResilienceError.circuitBreakerOpen(serviceName: \(serviceName))"
        case let .allFallbacksFailed(errors):
            "ResilienceError.allFallbacksFailed(errors: \(errors))"
        case let .invalidMaxAttempts(value):
            "ResilienceError.invalidMaxAttempts(\(value))"
        }
    }
}

// MARK: - BackoffStrategy

/// Strategies for calculating retry delays.
public enum BackoffStrategy: Sendable {
    // MARK: Public

    /// Calculate the delay for a given retry attempt.
    ///
    /// The computation is total: it never traps, and always returns a finite,
    /// non-negative delay. Non-finite or negative parameters and `.custom`
    /// results are treated as `0`; a negative or NaN `maxDelay` caps at `0`,
    /// while an infinite `maxDelay` means "uncapped". Growth from finite
    /// parameters that overflows saturates at `Double.greatestFiniteMagnitude`.
    /// ``RetryPolicy`` additionally caps each sleep at one hour.
    /// - Parameter attempt: The attempt number (1-indexed).
    /// - Returns: The delay in seconds before the next retry.
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        delay(forAttempt: attempt, random: { Double.random(in: $0) })
    }

    /// Calculates the delay using an explicit randomness source so that
    /// jittered strategies produce reproducible sequences (e.g. seeded
    /// generators under test).
    ///
    /// Shares the totality guarantees of ``delay(forAttempt:)``: `random`
    /// always receives a finite, well-ordered range, and its result is
    /// clamped back into that range.
    /// - Parameters:
    ///   - attempt: The attempt number (1-indexed).
    ///   - random: Replacement for `Double.random(in:)`; receives the legal
    ///     range for the drawn value.
    /// - Returns: The delay in seconds before the next retry.
    func delay(
        forAttempt attempt: Int,
        random: @Sendable (ClosedRange<Double>) -> Double
    ) -> TimeInterval {
        // `Double(attempt) - 1` instead of `Double(attempt - 1)`: the integer
        // subtraction traps for `Int.min`.
        let exponent = Double(attempt) - 1
        switch self {
        case let .fixed(delay):
            return Self.parameter(delay)

        case let .linear(initial, increment, maxDelay):
            let delay = Self.saturated(Self.parameter(initial) + (Self.parameter(increment) * exponent))
            return min(delay, Self.saturated(maxDelay))

        case let .exponential(base, multiplier, maxDelay):
            let delay = Self.saturated(Self.parameter(base) * pow(Self.parameter(multiplier), exponent))
            return min(delay, Self.saturated(maxDelay))

        case let .exponentialWithJitter(base, multiplier, maxDelay):
            let exponentialDelay = Self.saturated(Self.parameter(base) * pow(Self.parameter(multiplier), exponent))
            let cappedDelay = min(exponentialDelay, Self.saturated(maxDelay))
            // Add random jitter between 0 and the calculated delay
            return Self.draw(in: 0...cappedDelay, using: random)

        case let .decorrelatedJitter(base, maxDelay):
            // Decorrelated jitter: sleep = min(cap, random_between(base, sleep * 3))
            // For the first attempt, use base as the previous sleep
            let lower = Self.parameter(base)
            let previousSleep = attempt == 1 ? lower : Self.saturated(lower * pow(3.0, exponent - 1))
            let upper = max(lower, Self.saturated(previousSleep * 3.0))
            let delay = Self.draw(in: lower...upper, using: random)
            return min(delay, Self.saturated(maxDelay))

        case .immediate:
            return 0

        case let .custom(calculator):
            return Self.parameter(calculator(attempt))
        }
    }

    /// A caller-supplied delay or factor: usable only when finite and
    /// non-negative, otherwise `0`.
    private static func parameter(_ value: Double) -> Double {
        value.isFinite && value > 0 ? value : 0
    }

    /// A computed delay or `maxDelay` cap: NaN and negative values are `0`;
    /// overflow (and an uncapped `+infinity` maxDelay) saturates at
    /// `Double.greatestFiniteMagnitude`.
    private static func saturated(_ value: Double) -> TimeInterval {
        guard !value.isNaN else { return 0 }
        return min(max(value, 0), .greatestFiniteMagnitude)
    }

    /// Draws from `range` and clamps the (possibly injected) result back into it.
    private static func draw(
        in range: ClosedRange<Double>,
        using random: @Sendable (ClosedRange<Double>) -> Double
    ) -> TimeInterval {
        let value = random(range)
        guard !value.isNaN else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// Fixed delay between retries.
    case fixed(delay: TimeInterval)

    /// Linear backoff with configurable increment.
    case linear(initial: TimeInterval, increment: TimeInterval, maxDelay: TimeInterval)

    /// Exponential backoff with base and multiplier.
    case exponential(base: TimeInterval, multiplier: Double, maxDelay: TimeInterval)

    /// Exponential backoff with jitter to prevent thundering herd.
    case exponentialWithJitter(base: TimeInterval, multiplier: Double, maxDelay: TimeInterval)

    /// Decorrelated jitter for better distribution.
    case decorrelatedJitter(base: TimeInterval, maxDelay: TimeInterval)

    /// No delay between retries.
    case immediate

    /// Custom delay calculation using a closure.
    ///
    /// - Important: Two `.custom` values are **never equal** (`==` always returns `false`)
    ///   because Swift cannot compare closures for equality. Avoid using `.custom` in
    ///   contexts where `Equatable` equality is load-bearing (e.g., `Set`, `Dictionary` keys,
    ///   or equality-checked retry policy comparisons).
    case custom(@Sendable (Int) -> TimeInterval)
}

// MARK: Equatable

extension BackoffStrategy: Equatable {
    public static func == (lhs: BackoffStrategy, rhs: BackoffStrategy) -> Bool {
        switch (lhs, rhs) {
        case let (.fixed(lDelay), .fixed(rDelay)):
            lDelay == rDelay
        case let (.linear(lInitial, lIncrement, lMax), .linear(rInitial, rIncrement, rMax)):
            lInitial == rInitial && lIncrement == rIncrement && lMax == rMax
        case let (.exponential(lBase, lMult, lMax), .exponential(rBase, rMult, rMax)):
            lBase == rBase && lMult == rMult && lMax == rMax
        case let (.exponentialWithJitter(lBase, lMult, lMax), .exponentialWithJitter(rBase, rMult, rMax)):
            lBase == rBase && lMult == rMult && lMax == rMax
        case let (.decorrelatedJitter(lBase, lMax), .decorrelatedJitter(rBase, rMax)):
            lBase == rBase && lMax == rMax
        case (.immediate, .immediate):
            true
        case (.custom, .custom):
            // Cannot compare closures, return false
            false
        default:
            false
        }
    }
}

// MARK: - RetryPolicy

/// Configurable retry policy with backoff strategies.
///
/// `maxAttempts` counts total attempts including the initial attempt and must
/// be at least 1. This is the single unified retry semantic shared by
/// ``RetryPolicy``, `AsyncThrowingStream.retry(maxAttempts:delay:factory:)`,
/// and `HiveRetryPolicy`: `1` means run once with no retries, `3` means one
/// initial attempt plus up to two retries. Values below 1 throw
/// ``ResilienceError/invalidMaxAttempts(_:)`` from ``RetryPolicy/execute(_:)``
/// (and fail the stream from `AsyncThrowingStream.retry`) instead of clamping
/// or silently succeeding with zero attempts.
public struct RetryPolicy: Sendable {
    // MARK: Private

    private static let maxBackoffNanoseconds: UInt64 = 3_600_000_000_000 // 1 hour

    // MARK: - Static Conveniences

    /// No retry policy - exactly one total attempt, fails immediately on first error.
    public static let noRetry = RetryPolicy(maxAttempts: 1)

    /// Standard retry policy with exponential backoff (3 total attempts, max 60s delay).
    public static let standard = RetryPolicy(
        maxAttempts: 3,
        backoff: .exponential(base: 1.0, multiplier: 2.0, maxDelay: 60.0)
    )

    /// Aggressive retry policy with more attempts and jitter (5 total attempts, max 30s delay).
    public static let aggressive = RetryPolicy(
        maxAttempts: 5,
        backoff: .exponentialWithJitter(base: 0.5, multiplier: 2.0, maxDelay: 30.0)
    )

    /// Total attempts including the initial attempt. Must be at least 1.
    ///
    /// `1` runs the operation once with no retries. Values below 1 are
    /// invalid and throw ``ResilienceError/invalidMaxAttempts(_:)`` from
    /// ``RetryPolicy/execute(_:)``.
    public let maxAttempts: Int

    /// The backoff strategy to use between retries.
    public let backoff: BackoffStrategy

    /// Closure to determine if a retry should be attempted for a given error.
    public let shouldRetry: @Sendable (Error) -> Bool

    /// Optional callback invoked before each retry attempt.
    public let onRetry: (@Sendable (Int, Error) async -> Void)?

    // MARK: Private

    /// Clock used to suspend between retries. Defaults to `LiveSwarmClock`
    /// (plain `Task.sleep`) so existing behavior is unchanged when nil.
    private let clock: any SwarmClock

    /// Randomness source consulted by jittered backoff strategies. Defaults
    /// to `Double.random(in:)` so existing behavior is unchanged when nil.
    private let randomSource: @Sendable (ClosedRange<Double>) -> Double

    // MARK: - Initialization

    /// Creates a new retry policy.
    /// - Parameters:
    ///   - maxAttempts: Total attempts including the initial attempt (default: 3).
    ///     Must be at least 1; values below 1 are stored as-is and throw
    ///     ``ResilienceError/invalidMaxAttempts(_:)`` from ``RetryPolicy/execute(_:)``.
    ///   - backoff: The backoff strategy to use (default: exponential).
    ///   - shouldRetry: Closure to determine if retry should be attempted (default: always retry).
    ///   - onRetry: Optional callback invoked before each retry. Receives the
    ///     1-indexed retry number (1 for the first retry).
    public init(
        maxAttempts: Int = 3,
        backoff: BackoffStrategy = .exponential(base: 1.0, multiplier: 2.0, maxDelay: 60.0),
        shouldRetry: @escaping @Sendable (Error) -> Bool = { _ in true },
        onRetry: (@Sendable (Int, Error) async -> Void)? = nil
    ) {
        self.init(
            maxAttempts: maxAttempts,
            backoff: backoff,
            shouldRetry: shouldRetry,
            onRetry: onRetry,
            clock: nil,
            random: nil
        )
    }

    /// Package-internal injection point for deterministic tests.
    ///
    /// `clock` replaces the default `Task.sleep(nanoseconds:)` suspension path;
    /// `random` replaces `Double.random(in:)` for jittered backoff strategies.
    /// Both default to the live behaviors when `nil`. Kept internal because
    /// `SwarmClock` is `@_spi(ColonyInternal)` and cannot appear in a public
    /// signature.
    init(
        maxAttempts: Int = 3,
        backoff: BackoffStrategy = .exponential(base: 1.0, multiplier: 2.0, maxDelay: 60.0),
        shouldRetry: @escaping @Sendable (Error) -> Bool = { _ in true },
        onRetry: (@Sendable (Int, Error) async -> Void)? = nil,
        clock: (any SwarmClock)? = nil,
        random: (@Sendable (ClosedRange<Double>) -> Double)? = nil
    ) {
        self.maxAttempts = maxAttempts
        self.backoff = backoff
        self.shouldRetry = shouldRetry
        self.onRetry = onRetry
        self.clock = clock ?? LiveSwarmClock.live
        self.randomSource = random ?? { Double.random(in: $0) }
    }

    // MARK: - Execution

    /// Executes an operation with retry logic.
    ///
    /// Canonical agent-inference retry seam: `maxAttempts` counts total attempts
    /// including the initial attempt, `CancellationError` rethrows immediately,
    /// exhaustion wraps `ResilienceError.retriesExhausted`, and backoff sleeps
    /// on the injected `SwarmClock`. A server `Retry-After` hint carried by
    /// ``AgentError/rateLimitExceeded(retryAfter:)`` extends the computed
    /// delay but never shortens it. `ChatGraph.withRetry` shares the same
    /// total-attempt counting and keeps a local loop only for its documented
    /// differences (verbatim rethrow, unconditional gating, different backoff
    /// math).
    /// - Parameter operation: The async operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: `ResilienceError.invalidMaxAttempts` when `maxAttempts` is
    ///   below 1 (the operation is not invoked), `ResilienceError.retriesExhausted`
    ///   if all attempts fail, or the original error when `shouldRetry` declines.
    public func execute<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        guard maxAttempts >= 1 else {
            throw ResilienceError.invalidMaxAttempts(maxAttempts)
        }

        var attempt = 1
        var lastError: Error?

        while true {
            try Task.checkCancellation()
            do {
                return try await operation()
            } catch {
                // Durable approval pauses are not failures; retrying would
                // re-ask without a human decision.
                if error is CancellationError || error is WorkflowToolApprovalRequest || Task.isCancelled {
                    throw error
                }

                lastError = error

                // No budget left for another total attempt.
                guard attempt < maxAttempts else {
                    break
                }

                guard shouldRetry(error) else {
                    throw error
                }

                // `attempt` is the 1-indexed number of the failed attempt, which
                // equals the 1-indexed retry number for the upcoming retry.
                await onRetry?(attempt, error)
                try Task.checkCancellation()

                // Calculate and apply backoff delay. A server-provided
                // Retry-After hint extends the policy delay but never
                // shortens it; the run timeout still bounds the wait.
                let policyDelay = backoff.delay(forAttempt: attempt, random: randomSource)
                let delay = sanitizeBackoffDelay(
                    max(policyDelay, Self.retryAfterHint(for: error) ?? 0)
                )
                if delay > 0 {
                    try await clock.sleep(nanoseconds: delay)
                    try Task.checkCancellation()
                }

                attempt += 1
            }
        }

        // All retries exhausted
        throw ResilienceError.retriesExhausted(
            attempts: attempt,
            lastError: lastError?.localizedDescription ?? "Unknown error"
        )
    }

    /// Server-provided retry delay carried by the error, when any.
    ///
    /// Only ``AgentError/rateLimitExceeded(retryAfter:)`` carries a hint.
    /// Non-positive and non-finite hints are ignored so a malformed
    /// `Retry-After` value can never shorten or break the policy delay.
    private static func retryAfterHint(for error: Error) -> TimeInterval? {
        guard case let .rateLimitExceeded(retryAfter) = error as? AgentError,
              let retryAfter,
              retryAfter.isFinite,
              retryAfter > 0
        else {
            return nil
        }
        return retryAfter
    }

    private func sanitizeBackoffDelay(_ delaySeconds: TimeInterval) -> UInt64 {
        guard delaySeconds.isFinite, delaySeconds > 0 else {
            return 0
        }

        let nanoseconds = delaySeconds * 1_000_000_000
        // Overflow of a positive finite delay saturates to the ceiling, not 0.
        guard nanoseconds.isFinite else {
            return Self.maxBackoffNanoseconds
        }
        guard nanoseconds > 0 else {
            return 0
        }

        if nanoseconds >= Double(Self.maxBackoffNanoseconds) {
            return Self.maxBackoffNanoseconds
        }

        return UInt64(nanoseconds)
    }
}

// MARK: Equatable

extension RetryPolicy: Equatable {
    public static func == (lhs: RetryPolicy, rhs: RetryPolicy) -> Bool {
        lhs.maxAttempts == rhs.maxAttempts && lhs.backoff == rhs.backoff
        // Note: Cannot compare closures (shouldRetry, onRetry)
    }
}
