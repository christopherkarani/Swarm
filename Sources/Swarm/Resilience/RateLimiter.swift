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
        self.init(
            maxRequestsPerMinute: maxRequestsPerMinute,
            clock: LiveSwarmClock.live
        )
    }

    /// Create rate limiter with custom token bucket parameters
    public init(maxTokens: Int, refillRatePerSecond: Double) {
        self.init(
            maxTokens: maxTokens,
            refillRatePerSecond: refillRatePerSecond,
            clock: LiveSwarmClock.live
        )
    }

    // MARK: - Initialization

    /// Creates a new rate limiter driven by an injected time source.
    ///
    /// Injecting a virtual clock makes refill timing deterministic for tests;
    /// production callers use the default initializers backed by the live
    /// clock. Declared under `ColonyInternal` because `SwarmClock` is an SPI
    /// protocol and cannot appear in an unannotated public signature.
    /// - Parameters:
    ///   - maxRequestsPerMinute: Bucket capacity in requests per minute.
    ///   - clock: Time source driving refill timestamps and waits;
    ///     pass `nil` to use the live clock.
    @_spi(ColonyInternal)
    public init(maxRequestsPerMinute: Int, clock: (any SwarmClock)?) {
        let normalizedMaxRequests = max(1, maxRequestsPerMinute)
        maxTokens = normalizedMaxRequests
        refillRate = max(1.0 / 60.0, Double(normalizedMaxRequests) / 60.0)
        availableTokens = Double(normalizedMaxRequests)

        let resolvedClock = clock ?? LiveSwarmClock.live
        self.clock = resolvedClock
        lastRefillTime = resolvedClock.nowNanoseconds()
    }

    /// Creates a new rate limiter with custom bucket parameters and an
    /// injected time source.
    ///
    /// Declared under `ColonyInternal` because `SwarmClock` is an SPI protocol
    /// and cannot appear in an unannotated public signature.
    /// - Parameters:
    ///   - maxTokens: Bucket capacity; values below 1 normalize to 1.
    ///   - refillRatePerSecond: Tokens per second; non-finite or non-positive
    ///     rates normalize to 1.
    ///   - clock: Time source driving refill timestamps and waits;
    ///     pass `nil` to use the live clock.
    @_spi(ColonyInternal)
    public init(
        maxTokens: Int,
        refillRatePerSecond: Double,
        clock: (any SwarmClock)?
    ) {
        let normalizedMaxTokens = max(1, maxTokens)
        let normalizedRefillRate = refillRatePerSecond.isFinite && refillRatePerSecond > 0
            ? refillRatePerSecond
            : 1.0

        self.maxTokens = normalizedMaxTokens
        refillRate = normalizedRefillRate
        availableTokens = Double(normalizedMaxTokens)

        let resolvedClock = clock ?? LiveSwarmClock.live
        self.clock = resolvedClock
        lastRefillTime = resolvedClock.nowNanoseconds()
    }

    /// Acquire a token, waiting if necessary
    public func acquire() async throws {
        try Task.checkCancellation()
        refill()

        while availableTokens < 1 {
            let waitTime = TokenBucketMath.waitSeconds(
                forDeficit: 1 - availableTokens,
                refillRate: refillRate
            )
            try await clock.sleep(nanoseconds: Duration.seconds(waitTime).swarmNanoseconds)
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
        lastRefillTime = clock.nowNanoseconds()
    }

    // MARK: Private

    /// Injected time source; every refill timestamp and wait reads through it.
    private let clock: any SwarmClock

    private let maxTokens: Int
    private let refillRate: Double // tokens per second
    private var availableTokens: Double
    private var lastRefillTime: UInt64

    private func refill() {
        let now = clock.nowNanoseconds()
        availableTokens = TokenBucketMath.refilled(
            tokens: availableTokens,
            elapsedSeconds: TokenBucketMath.elapsedSeconds(from: lastRefillTime, to: now),
            refillRate: refillRate,
            maxTokens: maxTokens
        )
        lastRefillTime = now
    }
}

// MARK: - TokenBucketMath

/// Pure refill and wait-time math for the token bucket.
///
/// Functions are static and side-effect free so every rule is unit-testable
/// without actor code or a live clock. Behavior mirrors the original inline
/// logic exactly, including clamping at capacity and the finite/positive
/// guards on computed wait times.
enum TokenBucketMath {
    /// Post-refill token count after adding `elapsedSeconds * refillRate`
    /// tokens, capped at bucket capacity.
    ///
    /// A negative elapsed interval (clock moved backwards) removes tokens at
    /// the same rate, matching the original signed-duration arithmetic.
    static func refilled(
        tokens: Double,
        elapsedSeconds: Double,
        refillRate: Double,
        maxTokens: Int
    ) -> Double {
        min(Double(maxTokens), tokens + elapsedSeconds * refillRate)
    }

    /// Seconds to wait until `deficit` additional tokens have accumulated,
    /// or `0` when the raw quotient is non-finite or non-positive — preserving
    /// the original guard so pathological inputs never produce invalid sleeps.
    static func waitSeconds(forDeficit deficit: Double, refillRate: Double) -> Double {
        let rawWaitTime = deficit / refillRate
        return rawWaitTime.isFinite && rawWaitTime > 0 ? rawWaitTime : 0
    }

    /// Signed elapsed seconds between two nanosecond readings on one clock's
    /// timeline (`endNanoseconds - startNanoseconds`).
    static func elapsedSeconds(from startNanoseconds: UInt64, to endNanoseconds: UInt64) -> Double {
        Double(Int64(bitPattern: endNanoseconds &- startNanoseconds)) / 1_000_000_000
    }
}
