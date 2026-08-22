// RateLimiter.swift
// Swarm Framework
//
// Token bucket rate limiter for API calls.

import Foundation

// MARK: - RateLimiterClock

/// Time source driving token refill and acquisition waits for `RateLimiter`.
///
/// The default reads the continuous clock and sleeps with `Task.sleep`.
/// Tests inject fixed or stepped instants plus a no-op (or clock-advancing)
/// sleep to exercise refill math deterministically without real waiting.
public struct RateLimiterClock: Sendable {
    // MARK: Private

    private let nowProvider: @Sendable () -> ContinuousClock.Instant
    private let sleepHandler: @Sendable (Duration) async throws -> Void

    // MARK: - Initialization

    /// Creates a clock backed by custom instant and sleep handlers.
    /// - Parameters:
    ///   - now: Closure producing the current instant (default: `ContinuousClock.now`).
    ///   - sleep: Async suspension handler (default: `Task.sleep(for:)`).
    public init(
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.nowProvider = now
        self.sleepHandler = sleep
    }

    // MARK: - Public API

    /// Returns the current instant.
    public func now() -> ContinuousClock.Instant {
        nowProvider()
    }

    /// Suspends for the requested duration.
    public func sleep(for duration: Duration) async throws {
        try await sleepHandler(duration)
    }
}

// MARK: - RateLimiter

/// Token bucket rate limiter for API calls
///
/// Implements the token bucket algorithm for rate limiting:
/// - Tokens are added at a fixed rate
/// - Each request consumes one token
/// - If no tokens available, the request waits
///
/// Usage:
/// ```swift
/// let limiter = RateLimiter(maxRequestsPerMinute: 60)
///
/// // In your API calls
/// try await limiter.acquire()  // Waits if rate limit reached
/// let response = try await apiClient.call()
///
/// // Or check without waiting
/// if limiter.tryAcquire() {
///     let response = try await apiClient.call()
/// }
/// ```
public actor RateLimiter {
    // MARK: Public

    /// Current available tokens
    public var available: Int {
        refill()
        return Int(availableTokens)
    }

    /// Create rate limiter with requests per minute
    /// - Parameters:
    ///   - maxRequestsPerMinute: Requests allowed per minute.
    ///   - clock: Time source for refill and acquisition waits (default: wall clock).
    public init(
        maxRequestsPerMinute: Int,
        clock: RateLimiterClock = RateLimiterClock()
    ) {
        let normalizedMaxRequests = max(1, maxRequestsPerMinute)
        maxTokens = normalizedMaxRequests
        refillRate = max(1.0 / 60.0, Double(normalizedMaxRequests) / 60.0)
        availableTokens = Double(normalizedMaxRequests)
        lastRefillTime = clock.now()
        self.clock = clock
    }

    /// Create rate limiter with custom token bucket parameters
    /// - Parameters:
    ///   - maxTokens: Bucket capacity.
    ///   - refillRatePerSecond: Tokens added per second.
    ///   - clock: Time source for refill and acquisition waits (default: wall clock).
    public init(
        maxTokens: Int,
        refillRatePerSecond: Double,
        clock: RateLimiterClock = RateLimiterClock()
    ) {
        let normalizedMaxTokens = max(1, maxTokens)
        let normalizedRefillRate = refillRatePerSecond.isFinite && refillRatePerSecond > 0
            ? refillRatePerSecond
            : 1.0

        self.maxTokens = normalizedMaxTokens
        refillRate = normalizedRefillRate
        availableTokens = Double(normalizedMaxTokens)
        lastRefillTime = clock.now()
        self.clock = clock
    }

    /// Acquire a token, waiting if necessary
    public func acquire() async throws {
        try Task.checkCancellation()
        refill()

        while availableTokens < 1 {
            let rawWaitTime = (1 - availableTokens) / refillRate
            let waitTime = rawWaitTime.isFinite && rawWaitTime > 0 ? rawWaitTime : 0
            try await clock.sleep(for: .seconds(waitTime))
            try Task.checkCancellation()
            refill()
        }

        availableTokens -= 1
    }

    /// Try to acquire without waiting
    public func tryAcquire() -> Bool {
        refill()
        if availableTokens >= 1 {
            availableTokens -= 1
            return true
        }
        return false
    }

    /// Reset the limiter to full capacity
    public func reset() {
        availableTokens = Double(maxTokens)
        lastRefillTime = clock.now()
    }

    // MARK: Private

    private let maxTokens: Int
    private let refillRate: Double // tokens per second
    private var availableTokens: Double
    private var lastRefillTime: ContinuousClock.Instant

    /// Time source driving refill and acquisition waits.
    private let clock: RateLimiterClock

    private func refill() {
        let now = clock.now()
        let elapsed = now - lastRefillTime
        let tokensToAdd = elapsed.seconds * refillRate
        availableTokens = min(Double(maxTokens), availableTokens + tokensToAdd)
        lastRefillTime = now
    }
}

private extension Duration {
    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1_000_000_000_000_000_000
    }
}
