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
        }
    }
}

// MARK: - BackoffStrategy

/// Strategies for calculating retry delays.
public enum BackoffStrategy: Sendable {
    // MARK: Public

    /// Calculate the delay for a given retry attempt.
    /// - Parameter attempt: The attempt number (1-indexed).
    /// - Returns: The delay in seconds before the next retry.
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        switch self {
        case let .fixed(delay):
            return delay

        case let .linear(initial, increment, maxDelay):
            let delay = initial + (increment * Double(attempt - 1))
            return min(delay, maxDelay)

        case let .exponential(base, multiplier, maxDelay):
            let delay = base * pow(multiplier, Double(attempt - 1))
            return min(delay, maxDelay)

        case let .exponentialWithJitter(base, multiplier, maxDelay):
            let exponentialDelay = base * pow(multiplier, Double(attempt - 1))
            let cappedDelay = min(exponentialDelay, maxDelay)
            // Add random jitter between 0 and the calculated delay
            let jitter = Double.random(in: 0...cappedDelay)
            return jitter

        case let .decorrelatedJitter(base, maxDelay):
            // Decorrelated jitter: sleep = min(cap, random_between(base, sleep * 3))
            // For the first attempt, use base as the previous sleep
            let previousSleep = attempt == 1 ? base : base * pow(3.0, Double(attempt - 2))
            let delay = Double.random(in: base...(previousSleep * 3.0))
            return min(delay, maxDelay)

        case .immediate:
            return 0

        case let .custom(calculator):
            return calculator(attempt)
        }
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
public struct RetryPolicy: Sendable {
    // MARK: Private

    private static let maxBackoffNanoseconds: UInt64 = 3_600_000_000_000 // 1 hour

    // MARK: - Static Conveniences

    /// No retry policy - fails immediately on first error.
    public static let noRetry = RetryPolicy(maxAttempts: 0)

    /// Standard retry policy with exponential backoff (3 retries, max 60s delay).
    public static let standard = RetryPolicy(
        maxAttempts: 3,
        backoff: .exponential(base: 1.0, multiplier: 2.0, maxDelay: 60.0)
    )

    /// Aggressive retry policy with more attempts and jitter (5 retries, max 30s delay).
    public static let aggressive = RetryPolicy(
        maxAttempts: 5,
        backoff: .exponentialWithJitter(base: 0.5, multiplier: 2.0, maxDelay: 30.0)
    )

    /// Maximum number of retry attempts (excluding the initial attempt).
    public let maxAttempts: Int

    /// The backoff strategy to use between retries.
    public let backoff: BackoffStrategy

    /// Closure to determine if a retry should be attempted for a given error.
    public let shouldRetry: @Sendable (Error) -> Bool

    /// Optional callback invoked before each retry attempt.
    public let onRetry: (@Sendable (Int, Error) async -> Void)?

    // MARK: - Initialization

    /// Creates a new retry policy.
    /// - Parameters:
    ///   - maxAttempts: Maximum number of retry attempts (default: 3).
    ///   - backoff: The backoff strategy to use (default: exponential).
    ///   - shouldRetry: Closure to determine if retry should be attempted (default: always retry).
    ///   - onRetry: Optional callback invoked before each retry.
    public init(
        maxAttempts: Int = 3,
        backoff: BackoffStrategy = .exponential(base: 1.0, multiplier: 2.0, maxDelay: 60.0),
        shouldRetry: @escaping @Sendable (Error) -> Bool = { _ in true },
        onRetry: (@Sendable (Int, Error) async -> Void)? = nil
    ) {
        self.maxAttempts = max(0, maxAttempts)
        self.backoff = backoff
        self.shouldRetry = shouldRetry
        self.onRetry = onRetry
    }

    // MARK: - Execution

    /// Executes an operation with retry logic.
    /// - Parameter operation: The async operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: `ResilienceError.retriesExhausted` if all attempts fail, or the original error if retries are
    /// disabled.
    public func execute<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        var retryCount = 0
        var lastError: Error?

        while true {
            do {
                return try await operation()
            } catch {
                if error is CancellationError || Task.isCancelled {
                    throw error
                }

                lastError = error

                // Check if we should retry
                guard retryCount < maxAttempts else {
                    break
                }

                guard shouldRetry(error) else {
                    throw error
                }

                retryCount += 1

                // Invoke retry callback
                await onRetry?(retryCount, error)

                // Calculate and apply backoff delay
                let delay = sanitizeBackoffDelay(backoff.delay(forAttempt: retryCount))
                if delay > 0 {
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }

        // All retries exhausted
        throw ResilienceError.retriesExhausted(
            attempts: retryCount + 1,
            lastError: lastError?.localizedDescription ?? "Unknown error"
        )
    }

    private func sanitizeBackoffDelay(_ delaySeconds: TimeInterval) -> UInt64 {
        guard delaySeconds.isFinite, delaySeconds > 0 else {
            return 0
        }

        let nanoseconds = delaySeconds * 1_000_000_000
        guard nanoseconds.isFinite, nanoseconds > 0 else {
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
