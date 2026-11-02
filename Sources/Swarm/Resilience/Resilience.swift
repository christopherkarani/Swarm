// Resilience.swift
// Swarm Framework
//
// Resilience patterns for robust agent execution.
// Includes:
// - Retry policies with exponential backoff (see RetryPolicy.swift)
// - Fallback chains for graceful degradation (see FallbackChain.swift)
// - Circuit breaker pattern (see CircuitBreaker.swift)
// - Rate limiting (see RateLimiter.swift)
// - Agent.run wiring via ResilienceConfiguration (inference only; tools are not retried)


// Export Foundation's TimeInterval for resilience API signatures.
@_exported import struct Foundation.TimeInterval
