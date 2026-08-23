// RateLimiter.swift
// Swarm Framework
//
// Token bucket rate limiter for API calls.

import Foundation

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
    public init(maxRequestsPerMinute: Int) {
        let normalizedMaxRequests = max(1, maxRequestsPerMinute)
        maxTokens = normalizedMaxRequests
        refillRate = max(1.0 / 60.0, Double(normalizedMaxRequests) / 60.0)
        availableTokens = Double(normalizedMaxRequests)
        lastRefillTime = .now
    }

    /// Create rate limiter with custom token bucket parameters
    public init(maxTokens: Int, refillRatePerSecond: Double) {
        let normalizedMaxTokens = max(1, maxTokens)
        let normalizedRefillRate = refillRatePerSecond.isFinite && refillRatePerSecond > 0
            ? refillRatePerSecond
            : 1.0

        self.maxTokens = normalizedMaxTokens
        refillRate = normalizedRefillRate
        availableTokens = Double(normalizedMaxTokens)
        lastRefillTime = .now
    }

    /// Acquire a token, waiting if necessary
    public func acquire() async throws {
        try Task.checkCancellation()
        refill()

        while availableTokens < 1 {
            let rawWaitTime = (1 - availableTokens) / refillRate
            let waitTime = rawWaitTime.isFinite && rawWaitTime > 0 ? rawWaitTime : 0
            try await Task.sleep(for: .seconds(waitTime))
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
        lastRefillTime = .now
    }

    // MARK: Private

    private let maxTokens: Int
    private let refillRate: Double // tokens per second
    private var availableTokens: Double
    private var lastRefillTime: ContinuousClock.Instant

    private func refill() {
        let now = ContinuousClock.now
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
