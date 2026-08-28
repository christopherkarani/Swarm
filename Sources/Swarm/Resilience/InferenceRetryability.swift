// InferenceRetryability.swift
// Swarm Framework
//
// Classification of errors that Agent may retry on provider inference calls.

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - InferenceRetryability

/// Classifies whether a provider-inference failure may be retried by ``Agent``.
///
/// ``Agent`` wraps **provider inference only**. This helper is the hard
/// retryability gate: a ``RetryPolicy``'s `shouldRetry` may further restrict
/// retries, but even if it returns `true`, permanent failures listed below are
/// never retried.
///
/// ## Retryable (transient)
///
/// | Error | Reason |
/// |---|---|
/// | ``AgentError/rateLimitExceeded(retryAfter:)`` | Provider rate limit |
/// | ``AgentError/inferenceProviderUnavailable(reason:)`` | Transient backend unavailability |
/// | ``AgentError/generationFailed(reason:)`` | Provider 5xx / internal generation failure |
/// | ``AgentError/embeddingFailed(reason:)`` | Transient embedding backend failure |
/// | `URLError` network / timeout codes | Connectivity loss, DNS, TCP, idle timeout |
///
/// ## Not retryable (permanent)
///
/// | Error | Reason |
/// |---|---|
/// | `CancellationError`, ``AgentError/cancelled`` | Caller aborted the run |
/// | ``AgentError/timeout(duration:)`` | The **run** deadline expired; retries must not outlive it |
/// | ``AgentError/invalidInput(reason:)``, ``AgentError/invalidLoop(reason:)`` | Caller / configuration error |
/// | ``AgentError/maxIterationsExceeded(iterations:)`` | Loop bound, not a transient blip |
/// | ``AgentError/guardrailViolation(reason:)``, ``GuardrailError`` | Safety rejection |
/// | ``AgentError/contentFiltered(reason:)`` | Provider safety filter |
/// | ``AgentError/invalidToolArguments(toolName:reason:)`` | Schema / parse failure |
/// | ``AgentError/toolFailure(toolName:message:cause:)``, ``AgentError/toolNotFound(name:)`` | Tool path (never wrapped) |
/// | ``AgentError/contextWindowExceeded(tokenCount:limit:)`` | Input too large |
/// | ``AgentError/unsupportedLanguage(language:)``, ``AgentError/modelNotAvailable(model:)`` | Configuration / capability |
/// | ``AgentError/agentNotFound(name:)``, ``AgentError/internalError(reason:)``, ``AgentError/toolCallingUnsupported`` | Non-transient |
/// | ``ResilienceError/circuitBreakerOpen(serviceName:)`` | Breaker already short-circuited |
/// | ``ResilienceError/retriesExhausted(attempts:lastError:)`` | Budget already spent |
/// | Unknown `Error` types | Fail closed — do not retry unclassified failures |
///
/// Provider timeouts surface as ``AgentError/generationFailed(reason:)`` or
/// `URLError.timedOut`, which **are** retryable, as long as the run deadline
/// has not fired.
public enum InferenceRetryability: Sendable {
    /// Returns whether ``Agent`` may retry this error on a provider inference call.
    ///
    /// - Parameter error: The error thrown by inference (or a wrapper around it).
    /// - Returns: `true` only for the transient failures listed above.
    public static func isRetryable(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }

        if let agentError = error as? AgentError {
            return agentError.isRetryable
        }

        if let resilienceError = error as? ResilienceError {
            switch resilienceError {
            case .circuitBreakerOpen, .retriesExhausted, .allFallbacksFailed:
                return false
            }
        }

        if error is GuardrailError {
            return false
        }

        if let urlError = error as? URLError {
            return isRetryable(urlError)
        }

        return false
    }

    private static func isRetryable(_ urlError: URLError) -> Bool {
        switch urlError.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet:
            true
        default:
            false
        }
    }
}
