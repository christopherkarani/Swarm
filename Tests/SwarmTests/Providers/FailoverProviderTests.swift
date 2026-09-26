// FailoverProviderTests.swift
// SwarmTests
//
// Tests for ordered provider failover.

import Foundation
@testable import Swarm
import Testing

@Suite("FailoverProvider")
struct FailoverProviderTests {
    @Test("Primary success never touches fallbacks")
    func primarySuccessSkipsFallbacks() async throws {
        let primary = MockInferenceProvider(responses: ["primary wins"])
        let fallback = MockInferenceProvider(responses: ["fallback wins"])
        let failovers = TestRecorder<Int>()
        let provider = FailoverProvider(
            primary: primary,
            fallbacks: [fallback],
            onFailover: { index, _ in await failovers.append(index) }
        )

        let text = try await provider.generate(messages: [.user("hi")], options: .default)

        #expect(text == "primary wins")
        #expect(await primary.recordedInferenceCallCount == 1)
        #expect(await fallback.recordedInferenceCallCount == 0)
        #expect(await failovers.count() == 0)
    }

    @Test("Retryable primary failure advances to the fallback")
    func retryableFailureAdvances() async throws {
        let primary = MockInferenceProvider(responses: ["unused"])
        await primary.setErrorSequence([AgentError.rateLimitExceeded(retryAfter: nil)])
        let fallback = MockInferenceProvider(responses: ["fallback wins"])
        let failovers = TestRecorder<Int>()
        let provider = FailoverProvider(
            primary: primary,
            fallbacks: [fallback],
            onFailover: { index, _ in await failovers.append(index) }
        )

        let text = try await provider.generate(messages: [.user("hi")], options: .default)

        #expect(text == "fallback wins")
        #expect(await primary.recordedInferenceCallCount == 1)
        #expect(await fallback.recordedInferenceCallCount == 1)
        #expect(await failovers.getAll() == [0])
    }

    @Test("Non-retryable primary failure rethrows without failover")
    func nonRetryableFailureRethrows() async throws {
        let primary = MockInferenceProvider(responses: ["unused"])
        await primary.setError(AgentError.authenticationFailed(reason: "bad key"))
        let fallback = MockInferenceProvider(responses: ["fallback wins"])
        let provider = FailoverProvider(primary: primary, fallbacks: [fallback])

        await #expect(throws: AgentError.authenticationFailed(reason: "bad key")) {
            try await provider.generate(messages: [.user("hi")], options: .default)
        }
        #expect(await primary.recordedInferenceCallCount == 1)
        #expect(await fallback.recordedInferenceCallCount == 0)
    }

    @Test("Exhausted chain rethrows the last error")
    func exhaustedChainRethrowsLastError() async throws {
        let primary = MockInferenceProvider(responses: ["unused"])
        await primary.setError(AgentError.rateLimitExceeded(retryAfter: nil))
        let fallback = MockInferenceProvider(responses: ["unused"])
        await fallback.setError(AgentError.generationFailed(reason: "down"))
        let provider = FailoverProvider(primary: primary, fallbacks: [fallback])

        await #expect(throws: AgentError.generationFailed(reason: "down")) {
            try await provider.generate(messages: [.user("hi")], options: .default)
        }
        #expect(await primary.recordedInferenceCallCount == 1)
        #expect(await fallback.recordedInferenceCallCount == 1)
    }

    @Test("Cancellation never advances, even under a permissive predicate")
    func cancellationNeverAdvances() async throws {
        let primary = MockInferenceProvider(responses: ["unused"])
        await primary.setError(CancellationError())
        let fallback = MockInferenceProvider(responses: ["fallback wins"])
        let provider = FailoverProvider(
            primary: primary,
            fallbacks: [fallback],
            shouldFailover: { _ in true }
        )

        await #expect(throws: CancellationError.self) {
            try await provider.generate(messages: [.user("hi")], options: .default)
        }
        #expect(await fallback.recordedInferenceCallCount == 0)
    }

    @Test("Tool calls fail over to the next provider")
    func toolCallsFailOver() async throws {
        let primary = MockInferenceProvider(responses: ["unused"])
        await primary.setError(AgentError.inferenceProviderUnavailable(reason: "down"))
        let fallback = MockInferenceProvider()
        let expected = InferenceResponse(
            content: "done",
            toolCalls: [],
            finishReason: .completed,
            usage: nil
        )
        await fallback.setToolCallResponses([expected])
        let provider = FailoverProvider(primary: primary, fallbacks: [fallback])

        let response = try await provider.generateWithToolCalls(
            messages: [.user("hi")],
            tools: [],
            options: .default
        )

        #expect(response.content == "done")
        #expect(await fallback.recordedInferenceCallCount == 1)
    }

    @Test("Structured output fails over to the next provider")
    func structuredOutputFailsOver() async throws {
        let primary = MockInferenceProvider(responses: ["unused"])
        await primary.setError(AgentError.inferenceProviderUnavailable(reason: "down"))
        let fallback = MockInferenceProvider(responses: [#"{"ok":true}"#])
        let provider = FailoverProvider(primary: primary, fallbacks: [fallback])

        let result = try await provider.generateStructured(
            messages: [.user("hi")],
            request: StructuredOutputRequest(format: .jsonObject),
            options: .default
        )

        #expect(result.rawJSON.contains("true"))
        #expect(await primary.recordedInferenceCallCount == 1)
        #expect(await fallback.recordedInferenceCallCount == 1)
    }

    @Test("Streams inherit failover through generate")
    func streamsInheritFailover() async throws {
        let primary = MockInferenceProvider(responses: ["unused"])
        await primary.setError(AgentError.inferenceProviderUnavailable(reason: "down"))
        let fallback = MockInferenceProvider(responses: ["streamed fallback"])
        let provider = FailoverProvider(primary: primary, fallbacks: [fallback])

        var chunks: [String] = []
        for try await chunk in provider.stream(messages: [.user("hi")], options: .default) {
            chunks.append(chunk)
        }

        #expect(chunks.joined() == "streamed fallback")
    }

    @Test("Capabilities come from the primary provider")
    func capabilitiesComeFromPrimary() async throws {
        let primary = MockInferenceProvider(capabilities: [.conversationMessages, .structuredOutputs])
        let fallback = MockInferenceProvider(capabilities: [])
        let provider = FailoverProvider(primary: primary, fallbacks: [fallback])

        #expect(provider.capabilities == [.conversationMessages, .structuredOutputs])
    }
}
