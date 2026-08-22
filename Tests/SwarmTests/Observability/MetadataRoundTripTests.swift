// MetadataRoundTripTests.swift
// SwarmTests
//
// End-to-end typed metadata round trips across TracingHelper, MetricsCollector,
// and Workflow fallback seams.

import Foundation
@testable import Swarm
import Testing

// MARK: - MetadataRoundTripTests

@Suite("Metadata Round-Trip Tests")
struct MetadataRoundTripTests {

    // MARK: - TracingHelper → TraceEvent → MetricsCollector Tests

    @Test("TracingHelper token writes round-trip through raw strings and metrics")
    func tracingHelperTokenWritesRoundTrip() async {
        let spy = SpyTracer()
        let helper = TracingHelper(tracer: spy, agentName: "TypedAgent")
        let result = AgentResult(output: "done")

        await helper.traceComplete(
            result: result,
            tokenUsage: TokenUsage(inputTokens: 11, outputTokens: 7)
        )

        let events = await spy.tracedEvents
        #expect(events.count == 1)
        guard let event = events.first else { return }

        // Typed reads share the producer's key symbols.
        #expect(event.metadata[.inputTokens] == 11)
        #expect(event.metadata[.outputTokens] == 7)
        #expect(event.metadata[.totalTokens] == 18)
        #expect(event.metadata[.legacyTokenCount] == 18)

        // Serialized form keeps the stable string names and .int payloads.
        #expect(event.metadata["input_tokens"] == .int(11))
        #expect(event.metadata["output_tokens"] == .int(7))
        #expect(event.metadata["total_tokens"] == .int(18))
        #expect(event.metadata["tokenCount"] == .int(18))

        // The typed duration key observes the helper's duration_ms write.
        #expect(event.metadata[.durationMs] == event.metadata["duration_ms"]?.doubleValue)

        // The same event feeds MetricsCollector through the typed keys.
        let collector = MetricsCollector()
        let spanId = event.spanId
        let traceId = event.traceId
        await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "TypedAgent"))
        await collector.trace(event)

        let snapshot = await collector.snapshot()
        #expect(snapshot.inputTokens == 11)
        #expect(snapshot.outputTokens == 7)
        #expect(snapshot.totalTokens == 18)
    }

    @Test("TracingHelper omits token keys when usage is absent")
    func tracingHelperOmitsTokenKeysWithoutUsage() async {
        let spy = SpyTracer()
        let helper = TracingHelper(tracer: spy, agentName: "TypedAgent")

        await helper.traceComplete(result: AgentResult(output: "done"), tokenUsage: nil)

        let events = await spy.tracedEvents
        guard let event = events.first else { return }

        #expect(event.metadata[.inputTokens] == nil)
        #expect(event.metadata[.outputTokens] == nil)
        #expect(event.metadata[.totalTokens] == nil)
        #expect(event.metadata[.legacyTokenCount] == nil)
    }

    // MARK: - Workflow Fallback Tests

    @Test("workflow fallback writes typed metadata readable through raw strings")
    func workflowFallbackMetadataRoundTrip() async throws {
        let result = try await Workflow()
            .durable
            .fallback(primary: AlwaysFailingAgent(), to: MockAgentRuntime(response: "backup"), retries: 1)
            .run("input")

        #expect(result.output == "backup")

        // Typed reads share the writer's key symbols.
        #expect(result.metadata[.fallbackUsed] == true)
        #expect(result.metadata[.fallbackError]?.isEmpty == false)

        // Serialized form stays identical to the pre-typed format.
        #expect(result.metadata["workflow.fallback.used"] == .bool(true))
        #expect(result.metadata["workflow.fallback.error"]?.stringValue?.isEmpty == false)
    }
}

// MARK: - Fixtures

/// Agent runtime that always fails so workflows exercise their fallback path.
private actor AlwaysFailingAgent: AgentRuntime {
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions: String = "AlwaysFailingAgent"
    nonisolated let configuration = AgentConfiguration(name: "AlwaysFailingAgent")
    nonisolated let handoffs: [AnyHandoffConfiguration] = []

    func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult {
        throw AgentError.internalError(reason: "forced failure")
    }

    nonisolated func stream(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: AgentError.internalError(reason: "forced failure")) }
    }

    func cancel() async {}
}
