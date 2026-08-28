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


// Re-export key resilience types
@_exported import struct Foundation.TimeInterval
