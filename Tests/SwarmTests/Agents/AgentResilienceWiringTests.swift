// AgentResilienceWiringTests.swift
// SwarmTests
//
// End-to-end proof that Agent.run honors ResilienceConfiguration.

import Foundation
@testable import Swarm
import Testing

@Suite("Agent resilience wiring")
struct AgentResilienceWiringTests {
    private static let transient = AgentError.generationFailed(reason: "transient 503")

    @Test(".standard retries a transient failure; .noRetry does not")
    func standardRetrySucceedsWhereNoRetryFails() async throws {
        let noRetryProvider = MockInferenceProvider(responses: ["should not appear"])
        await noRetryProvider.setErrorSequence([Self.transient])
        let noRetryAgent = try Agent(
            tools: [],
            instructions: "Retry wiring",
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .timeout(.seconds(15))
                .resilience(ResilienceConfiguration(retryPolicy: .noRetry)),
            inferenceProvider: noRetryProvider
        )

        await #expect(throws: AgentError.self) {
            _ = try await noRetryAgent.run("hello")
        }
        #expect(await noRetryProvider.recordedInferenceCallCount == 1)

        let retryProvider = MockInferenceProvider(responses: ["recovered"])
        await retryProvider.setErrorSequence([Self.transient])
        let retryObserver = RetryRecordingObserver()
        let retryAgent = try Agent(
            tools: [],
            instructions: "Retry wiring",
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .timeout(.seconds(15))
                .resilience(ResilienceConfiguration(retryPolicy: .standard)),
            inferenceProvider: retryProvider
        )

        let result = try await retryAgent.run("hello", observer: retryObserver)
        #expect(result.output == "recovered")
        #expect(await retryProvider.recordedInferenceCallCount == 2)
        #expect(await retryObserver.retryAttempts == [1])
    }

    @Test("Circuit breaker short-circuits later runs after the failure threshold")
    func circuitBreakerFailsFastOnSubsequentRuns() async throws {
        let provider = MockInferenceProvider(responses: ["unused"])
        await provider.setError(Self.transient)

        let agent = try Agent(
            tools: [],
            instructions: "Breaker wiring",
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .resilience(ResilienceConfiguration(
                    retryPolicy: .noRetry,
                    circuitBreaker: CircuitBreakerSettings(
                        failureThreshold: 2,
                        resetTimeout: 60,
                        name: "test-breaker"
                    )
                )),
            inferenceProvider: provider
        )

        await #expect(throws: AgentError.self) {
            _ = try await agent.run("one")
        }
        await #expect(throws: AgentError.self) {
            _ = try await agent.run("two")
        }
        #expect(await provider.recordedInferenceCallCount == 2)

        do {
            _ = try await agent.run("three")
            Issue.record("Expected circuit breaker to short-circuit the third run")
        } catch let error as ResilienceError {
            #expect(error == .circuitBreakerOpen(serviceName: "test-breaker"))
        } catch {
            Issue.record("Expected ResilienceError.circuitBreakerOpen, got \(error)")
        }

        #expect(await provider.recordedInferenceCallCount == 2)
    }

    @Test("Rate limiter spaces successive inference calls")
    func rateLimiterEnforcesFloorDuration() async throws {
        let provider = MockInferenceProvider(responses: ["a", "b", "c"])
        let agent = try Agent(
            tools: [],
            instructions: "Limiter wiring",
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .resilience(ResilienceConfiguration(
                    rateLimit: RateLimitSettings(maxTokens: 1, refillRatePerSecond: 20)
                )),
            inferenceProvider: provider
        )

        let start = ContinuousClock.now
        _ = try await agent.run("one")
        _ = try await agent.run("two")
        _ = try await agent.run("three")
        let elapsed = ContinuousClock.now - start

        #expect(await provider.recordedInferenceCallCount == 3)
        // Two refills at 50ms each (≥100ms). Lower bound is generous for clock slack;
        // upper bound only guards against a hung limiter.
        #expect(elapsed >= .milliseconds(40))
        #expect(elapsed < .seconds(5))
    }

    @Test("Tool execution is not retried even with aggressive inference retry")
    func toolExecutionIsNotRetried() async throws {
        let tool = CountingFailingTool(name: "boom")
        let provider = MockInferenceProvider()
        await provider.configureToolCallingSequence(
            toolCalls: [(name: "boom", args: [:])],
            finalAnswer: "should not be reached"
        )

        let agent = try Agent(
            tools: [tool],
            instructions: "Do not retry tools",
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .stopOnToolError(true)
                .resilience(ResilienceConfiguration(retryPolicy: .aggressive)),
            inferenceProvider: provider
        )

        await #expect(throws: AgentError.self) {
            _ = try await agent.run("call the tool")
        }

        #expect(await tool.callCount == 1)
        #expect(await provider.recordedInferenceCallCount == 1)
    }

    @Test("Default resilience configuration is a no-op")
    func defaultResilienceIsDisabled() {
        let config = AgentConfiguration.default
        #expect(config.resilience == .disabled)
        #expect(config.resilience.retryPolicy == .noRetry)
        #expect(config.resilience.circuitBreaker == nil)
        #expect(config.resilience.rateLimit == nil)
        #expect(config.resilience.hasActivePolicies == false)
    }

    @Test("resilience builder is additive and does not mutate the original")
    func resilienceBuilderIsAdditive() {
        let original = AgentConfiguration.default
        let modified = original.resilience(ResilienceConfiguration(retryPolicy: .standard))

        #expect(original.resilience.retryPolicy == .noRetry)
        #expect(modified.resilience.retryPolicy == .standard)
        #expect(modified.maxIterations == original.maxIterations)
    }

    @Test("Custom shouldRetry can restrict retries but cannot expand them")
    func shouldRetryIsAndedWithClassification() async throws {
        let provider = MockInferenceProvider(responses: ["should not appear"])
        await provider.setErrorSequence([Self.transient])
        let restrictive = RetryPolicy(
            maxAttempts: 3,
            backoff: .immediate,
            shouldRetry: { _ in false }
        )
        let agent = try Agent(
            tools: [],
            instructions: "Restrict retries",
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .timeout(.seconds(15))
                .resilience(ResilienceConfiguration(retryPolicy: restrictive)),
            inferenceProvider: provider
        )

        await #expect(throws: AgentError.self) {
            _ = try await agent.run("hello")
        }
        #expect(await provider.recordedInferenceCallCount == 1)
    }

    @Test("Copies of the same Agent share the circuit breaker")
    func agentCopiesShareCircuitBreaker() async throws {
        let provider = MockInferenceProvider(responses: ["unused"])
        await provider.setError(Self.transient)

        let agent = try Agent(
            tools: [],
            instructions: "Shared breaker",
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .resilience(ResilienceConfiguration(
                    retryPolicy: .noRetry,
                    circuitBreaker: CircuitBreakerSettings(
                        failureThreshold: 2,
                        resetTimeout: 60,
                        name: "shared-breaker"
                    )
                )),
            inferenceProvider: provider
        )

        await #expect(throws: AgentError.self) {
            _ = try await agent.run("one")
        }
        await #expect(throws: AgentError.self) {
            _ = try await agent.run("two")
        }

        let copy = agent
        do {
            _ = try await copy.run("three")
            Issue.record("Expected the copied agent to share the open breaker")
        } catch let error as ResilienceError {
            #expect(error == .circuitBreakerOpen(serviceName: "shared-breaker"))
        } catch {
            Issue.record("Expected ResilienceError.circuitBreakerOpen, got \(error)")
        }

        #expect(await provider.recordedInferenceCallCount == 2)
    }
}

// MARK: - Helpers

private actor RetryRecordingObserver: AgentObserver {
    private(set) var retryAttempts: [Int] = []

    func onInferenceRetry(
        context _: AgentContext?,
        agent _: any AgentRuntime,
        attempt: Int,
        error _: Error
    ) async {
        retryAttempts.append(attempt)
    }
}

private actor CountingFailingTool: AnyJSONTool {
    nonisolated let name: String
    nonisolated let description = "A tool that fails once per call"
    nonisolated let parameters: [ToolParameter] = []
    nonisolated let inputGuardrails: [any ToolInputGuardrail] = []
    nonisolated let outputGuardrails: [any ToolOutputGuardrail] = []

    private(set) var callCount = 0

    init(name: String) {
        self.name = name
    }

    func execute(arguments _: [String: SendableValue]) async throws -> SendableValue {
        callCount += 1
        throw AgentError.toolExecutionFailed(toolName: name, underlyingError: "intentional")
    }
}
