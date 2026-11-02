// InferenceRetryabilityTests.swift
// SwarmTests
//
// Classification table for Agent inference retries.

import Foundation
@testable import Swarm
import Testing

@Suite("Inference retryability")
struct InferenceRetryabilityTests {
    @Test("Transient AgentError cases are retryable")
    func transientAgentErrorsAreRetryable() {
        let retryable: [AgentError] = [
            .rateLimitExceeded(retryAfter: 1),
            .inferenceProviderUnavailable(reason: "down"),
            .generationFailed(reason: "503"),
            .embeddingFailed(reason: "timeout")
        ]

        for error in retryable {
            #expect(error.isRetryable, "expected \(error) to be retryable")
            #expect(InferenceRetryability.isRetryable(error))
        }
    }

    @Test("Permanent AgentError cases are not retryable")
    func permanentAgentErrorsAreNotRetryable() {
        let permanent: [AgentError] = [
            .cancelled,
            .timeout(duration: .seconds(1)),
            .invalidInput(reason: "empty"),
            .invalidLoop(reason: "bad"),
            .maxIterationsExceeded(iterations: 3),
            .guardrailViolation(reason: "blocked"),
            .contentFiltered(reason: "safety"),
            .invalidToolArguments(toolName: "x", reason: "parse"),
            .toolFailure(toolName: "x", message: "boom", cause: nil),
            .toolNotFound(name: "x"),
            .contextWindowExceeded(tokenCount: 10, limit: 8),
            .unsupportedLanguage(language: "zz"),
            .modelNotAvailable(model: "missing"),
            .agentNotFound(name: "x"),
            .internalError(reason: "bug"),
            .toolCallingUnsupported
        ]

        for error in permanent {
            #expect(!error.isRetryable, "expected \(error) not to be retryable")
            #expect(!InferenceRetryability.isRetryable(error))
        }
    }

    @Test("Cancellation, guardrails, and open breakers are not retryable")
    func wrapperErrorsAreNotRetryable() {
        #expect(!InferenceRetryability.isRetryable(CancellationError()))
        #expect(!InferenceRetryability.isRetryable(
            ResilienceError.circuitBreakerOpen(serviceName: "api")
        ))
        #expect(!InferenceRetryability.isRetryable(
            ResilienceError.retriesExhausted(attempts: 3, lastError: "x")
        ))
        #expect(!InferenceRetryability.isRetryable(
            GuardrailError.inputTripwireTriggered(
                guardrailName: "test",
                message: "no",
                outputInfo: nil
            )
        ))
    }

    @Test("URLError retryability follows the cause table")
    func urlErrorCauseTable() {
        let retryable: [URLError.Code] = [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .dnsLookupFailed,
            .notConnectedToInternet,
        ]
        for code in retryable {
            #expect(InferenceRetryability.isRetryable(URLError(code)), "expected \(code.rawValue) to be retryable")
        }
        let permanent: [URLError.Code] = [
            .cancelled,
            .badURL,
            .unsupportedURL,
            .userCancelledAuthentication,
            .fileDoesNotExist,
            .zeroByteResource,
        ]
        for code in permanent {
            #expect(!InferenceRetryability.isRetryable(URLError(code)), "expected \(code.rawValue) to stay non-retryable")
        }
    }

    @Test("Unknown error types fail closed")
    func unknownErrorsAreNotRetryable() {
        struct Mystery: Error {}
        #expect(!InferenceRetryability.isRetryable(Mystery()))
    }
}
