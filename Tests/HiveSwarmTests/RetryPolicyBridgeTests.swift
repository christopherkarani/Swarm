#if SWARM_INTEGRATIONS
// RetryPolicyBridgeTests.swift
// HiveSwarm
//
// Tests for RetryPolicyBridge and ChatGraph retry behavior.

import Foundation
import HiveCore
import Testing
@_spi(ColonyInternal) @testable import Swarm

@Suite("RetryPolicyBridge — Swarm to Hive mapping")
struct RetryPolicyBridgeTests {

    @Test("Maps noRetry to .none")
    func bridge_noRetry() {
        let swarm = RetryPolicy.noRetry
        let hive = RetryPolicyBridge.toHive(swarm)
        switch hive {
        case .none:
            break
        default:
            Issue.record("Expected .none, got \(hive)")
        }
    }

    @Test("Maps standard retry to exponentialBackoff")
    func bridge_standardRetry() {
        let swarm = RetryPolicy.standard
        let hive = RetryPolicyBridge.toHive(swarm)
        switch hive {
        case .exponentialBackoff(let initialNs, let factor, let maxAttempts, let maxNs):
            #expect(maxAttempts == 3)
            #expect(factor == 2.0)
            #expect(initialNs == 1_000_000_000) // 1.0s
            #expect(maxNs == 60_000_000_000) // 60.0s
        default:
            Issue.record("Expected .exponentialBackoff, got \(hive)")
        }
    }

    @Test("Strips jitter from exponentialWithJitter")
    func bridge_stripsJitter() {
        let swarm = RetryPolicy.aggressive
        let hive = RetryPolicyBridge.toHive(swarm)
        switch hive {
        case .exponentialBackoff(_, _, let maxAttempts, _):
            #expect(maxAttempts == 5)
        default:
            Issue.record("Expected .exponentialBackoff (jitter stripped), got \(hive)")
        }
    }

    @Test("Maps fixed delay to exponentialBackoff with factor 1.0")
    func bridge_fixedDelay() {
        let swarm = RetryPolicy(maxAttempts: 2, backoff: .fixed(delay: 0.5))
        let hive = RetryPolicyBridge.toHive(swarm)
        switch hive {
        case .exponentialBackoff(let initialNs, let factor, let maxAttempts, _):
            #expect(maxAttempts == 2)
            #expect(factor == 1.0)
            #expect(initialNs == 500_000_000) // 0.5s
        default:
            Issue.record("Expected .exponentialBackoff for fixed delay, got \(hive)")
        }
    }

    @Test("Maps immediate to zero delay")
    func bridge_immediate() {
        let swarm = RetryPolicy(maxAttempts: 3, backoff: .immediate)
        let hive = RetryPolicyBridge.toHive(swarm)
        switch hive {
        case .exponentialBackoff(let initialNs, _, let maxAttempts, _):
            #expect(maxAttempts == 3)
            #expect(initialNs == 0)
        default:
            Issue.record("Expected .exponentialBackoff for immediate, got \(hive)")
        }
    }

    @Test("Negative base delay maps to zero nanoseconds (no crash)")
    func bridge_negativeBaseDelay_returnsZero() {
        // Issue #2: Negative delay should not crash, return 0 nanoseconds
        let swarm = RetryPolicy(maxAttempts: 3, backoff: .exponential(base: -1.0, multiplier: 2.0, maxDelay: 60.0))
        let hive = RetryPolicyBridge.toHive(swarm)
        switch hive {
        case .exponentialBackoff(let initialNs, _, let maxAttempts, let maxNs):
            #expect(maxAttempts == 3)
            #expect(initialNs == 0) // Negative base maps to 0
            #expect(maxNs == 60_000_000_000) // maxDelay is positive
        default:
            Issue.record("Expected .exponentialBackoff for negative base, got \(hive)")
        }
    }

    @Test("Negative max delay maps to zero nanoseconds (no crash)")
    func bridge_negativeMaxDelay_returnsZero() {
        // Issue #2: Negative maxDelay should not crash, return 0 nanoseconds
        let swarm = RetryPolicy(maxAttempts: 3, backoff: .exponential(base: 1.0, multiplier: 2.0, maxDelay: -10.0))
        let hive = RetryPolicyBridge.toHive(swarm)
        switch hive {
        case .exponentialBackoff(let initialNs, let factor, let maxAttempts, let maxNs):
            #expect(maxAttempts == 3)
            #expect(initialNs == 1_000_000_000) // base is positive
            #expect(factor == 2.0)
            #expect(maxNs == 0) // Negative maxDelay maps to 0
        default:
            Issue.record("Expected .exponentialBackoff for negative maxDelay, got \(hive)")
        }
    }
}

@Suite("ChatGraph retry behavior")
struct HiveAgentsRetryTests {

    @Test("Model node retries on transient failure with retry policy")
    func modelNode_retriesOnFailure() async throws {
        let script = RetryModelScript(failCount: 1, successChunks: [
            .final(HiveChatResponse(message: retryAssistantMsg(id: "m1", content: "success")))
        ])

        let context = RuntimeContext(
            modelName: "test-model",
            toolApprovalPolicy: .never,
            retryPolicy: .exponentialBackoff(
                initialNanoseconds: 1_000,
                factor: 2.0,
                maxAttempts: 3,
                maxNanoseconds: 1_000_000
            )
        )

        let graph = try ChatGraph.makeToolUsingChatAgent()
        let environment = HiveEnvironment<ChatGraph.Schema>(
            context: context,
            clock: RetryTestClock(),
            logger: RetryTestLogger(),
            model: AnyHiveModelClient(RetryScriptedModelClient(script: script)),
            modelRouter: nil,
            tools: AnyHiveToolRegistry(RetryStubToolRegistry(resultContent: "ok")),
            checkpointStore: nil
        )

        let runtime = try HiveRuntime(graph: graph, environment: environment)
        let handle = await runtime.run(
            threadID: HiveThreadID("retry-test"),
            input: "Hello",
            options: HiveRunOptions(maxSteps: 5, checkpointPolicy: .disabled)
        )
        let outcome = try await handle.outcome.value

        switch outcome {
        case .finished(let output, _):
            switch output {
            case .fullStore(let store):
                let answer = try store.get(ChatGraph.Schema.finalAnswerKey)
                #expect(answer == "success")
            case .channels:
                Issue.record("Expected fullStore")
            }
        default:
            Issue.record("Expected finished outcome, got \(outcome)")
        }
    }

    @Test("Huge finite retry delay growth clamps instead of trapping")
    func modelNode_hugeFiniteRetryDelayGrowthClamps() async throws {
        let script = RetryModelScript(failCount: 1, successChunks: [
            .final(HiveChatResponse(message: retryAssistantMsg(id: "m1", content: "success")))
        ])

        let context = RuntimeContext(
            modelName: "test-model",
            toolApprovalPolicy: .never,
            retryPolicy: .exponentialBackoff(
                initialNanoseconds: UInt64.max,
                factor: 2.0,
                maxAttempts: 2,
                maxNanoseconds: 0
            )
        )

        let graph = try ChatGraph.makeToolUsingChatAgent()
        let environment = HiveEnvironment<ChatGraph.Schema>(
            context: context,
            clock: RetryTestClock(),
            logger: RetryTestLogger(),
            model: AnyHiveModelClient(RetryScriptedModelClient(script: script)),
            modelRouter: nil,
            tools: AnyHiveToolRegistry(RetryStubToolRegistry(resultContent: "ok")),
            checkpointStore: nil
        )

        let runtime = try HiveRuntime(graph: graph, environment: environment)
        let handle = await runtime.run(
            threadID: HiveThreadID("retry-overflow-test"),
            input: "Hello",
            options: HiveRunOptions(maxSteps: 5, checkpointPolicy: .disabled)
        )
        let outcome = try await handle.outcome.value

        guard case .finished(let output, _) = outcome,
              case .fullStore(let store) = output
        else {
            Issue.record("Expected finished fullStore outcome, got \(outcome)")
            return
        }

        #expect(try store.get(ChatGraph.Schema.finalAnswerKey) == "success")
    }

    @Test("No retry policy means immediate failure")
    func modelNode_noRetry_failsImmediately() async throws {
        let script = RetryModelScript(failCount: 1, successChunks: [
            .final(HiveChatResponse(message: retryAssistantMsg(id: "m1", content: "success")))
        ])

        let context = RuntimeContext(
            modelName: "test-model",
            toolApprovalPolicy: .never
            // No retryPolicy — defaults to nil
        )

        let graph = try ChatGraph.makeToolUsingChatAgent()
        let environment = HiveEnvironment<ChatGraph.Schema>(
            context: context,
            clock: RetryTestClock(),
            logger: RetryTestLogger(),
            model: AnyHiveModelClient(RetryScriptedModelClient(script: script)),
            modelRouter: nil,
            tools: AnyHiveToolRegistry(RetryStubToolRegistry(resultContent: "ok")),
            checkpointStore: nil
        )

        let runtime = try HiveRuntime(graph: graph, environment: environment)
        let handle = await runtime.run(
            threadID: HiveThreadID("no-retry-test"),
            input: "Hello",
            options: HiveRunOptions(maxSteps: 5, checkpointPolicy: .disabled)
        )

        await #expect(throws: (any Error).self) {
            _ = try await handle.outcome.value
        }
    }
}

// MARK: - Test Doubles

/// Model script actor that fails a configurable number of times before succeeding.
private actor RetryModelScript {
    private var failsRemaining: Int
    private let successChunks: [HiveChatStreamChunk]

    init(failCount: Int, successChunks: [HiveChatStreamChunk]) {
        self.failsRemaining = failCount
        self.successChunks = successChunks
    }

    func nextChunks() throws -> [HiveChatStreamChunk] {
        if failsRemaining > 0 {
            failsRemaining -= 1
            throw SwarmRuntimeError.modelStreamInvalid("transient failure")
        }
        return successChunks
    }
}

private struct RetryScriptedModelClient: HiveModelClient {
    let script: RetryModelScript

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        let chunks = try await script.nextChunks()
        for chunk in chunks {
            if case let .final(response) = chunk { return response }
        }
        throw SwarmRuntimeError.modelStreamInvalid("Missing final chunk.")
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let chunks = try await script.nextChunks()
                    for chunk in chunks { continuation.yield(chunk) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private struct RetryStubToolRegistry: HiveToolRegistry, Sendable {
    let resultContent: String
    func listTools() -> [HiveToolDefinition] { [] }
    func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        HiveToolResult(toolCallID: call.id, content: resultContent)
    }
}

private struct RetryTestClock: HiveClock {
    func nowNanoseconds() -> UInt64 { 0 }
    func sleep(nanoseconds: UInt64) async throws {
        // Use very short sleep for test speed.
        try await Task.sleep(nanoseconds: min(nanoseconds, 1_000))
    }
}

private struct RetryTestLogger: HiveLogger {
    func debug(_ message: String, metadata: [String: String]) {}
    func info(_ message: String, metadata: [String: String]) {}
    func error(_ message: String, metadata: [String: String]) {}
}

private func retryAssistantMsg(id: String, content: String) -> HiveChatMessage {
    HiveChatMessage(id: id, role: .assistant, content: content, toolCalls: [], op: nil)
}
#endif
