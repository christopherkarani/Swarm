// ObservabilityTests+Metrics.swift
// Swarm Framework
//
// MetricsCollector and JSONMetricsReporter tests.

import Foundation
@testable import Swarm
import Testing

// MARK: - MetricsCollectorTests

@Suite("MetricsCollector Tests")
struct MetricsCollectorTests {
    // MARK: - Execution Tracking Tests

    @Test("MetricsCollector tracks agent start")
    func metricsCollectorTracksAgentStart() async {
        let collector = MetricsCollector()
        let traceId = UUID()

        await collector.trace(.agentStart(traceId: traceId, agentName: "TestAgent"))

        let total = await collector.getTotalExecutions()
        #expect(total == 1)
    }

    @Test("MetricsCollector tracks successful execution")
    func metricsCollectorTracksSuccess() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        let spanId = UUID()

        await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "TestAgent"))
        await collector.trace(.agentComplete(traceId: traceId, spanId: spanId, agentName: "TestAgent", duration: 1.5))

        let successful = await collector.getSuccessfulExecutions()
        #expect(successful == 1)
    }

    @Test("MetricsCollector tracks provider-reported token usage")
    func metricsCollectorTracksTokenUsage() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        let spanId = UUID()

        await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "TestAgent"))
        await collector.trace(TraceEvent(
            traceId: traceId,
            spanId: spanId,
            kind: .agentComplete,
            message: "done",
            metadata: [
                "input_tokens": .int(11),
                "output_tokens": .int(7)
            ],
            agentName: "TestAgent"
        ))

        let snapshot = await collector.snapshot()
        #expect(snapshot.inputTokens == 11)
        #expect(snapshot.outputTokens == 7)
        #expect(snapshot.totalTokens == 18)
    }

    @Test("MetricsCollector tracks failed execution")
    func metricsCollectorTracksError() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        let spanId = UUID()

        await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "TestAgent"))
        await collector.trace(.agentError(traceId: traceId, spanId: spanId, agentName: "TestAgent", error: NSError(domain: "test", code: 1)))

        let failed = await collector.getFailedExecutions()
        #expect(failed == 1)
    }

    @Test("MetricsCollector tracks cancelled execution")
    func metricsCollectorTracksCancelled() async {
        let collector = MetricsCollector()
        let traceId = UUID()

        let event = TraceEvent.Builder(traceId: traceId, kind: .agentCancelled, message: "Cancelled")
            .agent("TestAgent")
            .build()

        await collector.trace(event)

        let cancelled = await collector.getCancelledExecutions()
        #expect(cancelled == 1)
    }

    // MARK: - Tool Tracking Tests

    @Test("MetricsCollector tracks tool calls")
    func metricsCollectorTracksToolCalls() async {
        let collector = MetricsCollector()
        let traceId = UUID()

        await collector.trace(.toolCall(traceId: traceId, parentSpanId: UUID(), toolName: "web_search"))
        await collector.trace(.toolCall(traceId: traceId, parentSpanId: UUID(), toolName: "web_search"))
        await collector.trace(.toolCall(traceId: traceId, parentSpanId: UUID(), toolName: "calculator"))

        let toolCalls = await collector.getToolCalls()
        #expect(toolCalls["web_search"] == 2)
        #expect(toolCalls["calculator"] == 1)
    }

    @Test("MetricsCollector tracks tool results with duration")
    func metricsCollectorTracksToolResults() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        let spanId = UUID()

        await collector.trace(.toolCall(traceId: traceId, spanId: spanId, parentSpanId: UUID(), toolName: "web_search"))
        await collector.trace(.toolResult(traceId: traceId, spanId: spanId, toolName: "web_search", duration: 1.2))

        let toolDurations = await collector.getToolDurations()
        #expect(toolDurations["web_search"]?.count == 1)
        #expect(toolDurations["web_search"]?.first == 1.2)
    }

    @Test("MetricsCollector tracks tool errors")
    func metricsCollectorTracksToolErrors() async {
        let collector = MetricsCollector()
        let traceId = UUID()

        let event = TraceEvent.Builder(traceId: traceId, kind: .toolError, message: "Tool failed")
            .tool("web_search")
            .build()

        await collector.trace(event)
        await collector.trace(event)

        let toolErrors = await collector.getToolErrors()
        #expect(toolErrors["web_search"] == 2)
    }

    // MARK: - Snapshot Tests

    @Test("MetricsSnapshot computes success rate correctly")
    func snapshotComputesSuccessRate() async {
        let collector = MetricsCollector()
        let traceId = UUID()

        // 3 successful, 1 failed = 75% success rate
        for _ in 1...3 {
            let spanId = UUID()
            await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "Agent"))
            await collector.trace(.agentComplete(traceId: traceId, spanId: spanId, agentName: "Agent", duration: 1.0))
        }

        let failSpanId = UUID()
        await collector.trace(.agentStart(traceId: traceId, spanId: failSpanId, agentName: "Agent"))
        await collector.trace(.agentError(traceId: traceId, spanId: failSpanId, agentName: "Agent", error: NSError(domain: "test", code: 1)))

        let snapshot = await collector.snapshot()
        #expect(snapshot.totalExecutions == 4)
        #expect(snapshot.successfulExecutions == 3)
        #expect(snapshot.failedExecutions == 1)
        #expect(snapshot.successRate == 75.0)
    }

    @Test("MetricsSnapshot computes error rate correctly")
    func snapshotComputesErrorRate() async {
        let collector = MetricsCollector()
        let traceId = UUID()

        // 1 successful, 3 failed = 75% error rate
        let successSpanId = UUID()
        await collector.trace(.agentStart(traceId: traceId, spanId: successSpanId, agentName: "Agent"))
        await collector.trace(.agentComplete(traceId: traceId, spanId: successSpanId, agentName: "Agent", duration: 1.0))

        for _ in 1...3 {
            let spanId = UUID()
            await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "Agent"))
            await collector.trace(.agentError(traceId: traceId, spanId: spanId, agentName: "Agent", error: NSError(domain: "test", code: 1)))
        }

        let snapshot = await collector.snapshot()
        #expect(snapshot.errorRate == 75.0)
    }

    @Test("MetricsSnapshot handles zero executions")
    func snapshotHandlesZeroExecutions() async {
        let collector = MetricsCollector()
        let snapshot = await collector.snapshot()

        #expect(snapshot.successRate == 0.0)
        #expect(snapshot.errorRate == 0.0)
        #expect(snapshot.averageExecutionDuration == 0.0)
        #expect(snapshot.minimumExecutionDuration == nil)
        #expect(snapshot.maximumExecutionDuration == nil)
    }

    @Test("MetricsSnapshot computes average duration")
    func snapshotComputesAverageDuration() async {
        let collector = MetricsCollector()
        let traceId = UUID()

        let durations: [TimeInterval] = [1.0, 2.0, 3.0]
        for duration in durations {
            let spanId = UUID()
            await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "Agent"))
            await collector.trace(.agentComplete(traceId: traceId, spanId: spanId, agentName: "Agent", duration: duration))
        }

        let snapshot = await collector.snapshot()
        #expect(snapshot.averageExecutionDuration == 2.0)
    }

    @Test("MetricsSnapshot computes min/max durations")
    func snapshotComputesMinMaxDurations() async {
        let collector = MetricsCollector()
        let traceId = UUID()

        let durations: [TimeInterval] = [1.5, 0.5, 3.0, 2.0]
        for duration in durations {
            let spanId = UUID()
            await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "Agent"))
            await collector.trace(.agentComplete(traceId: traceId, spanId: spanId, agentName: "Agent", duration: duration))
        }

        let snapshot = await collector.snapshot()
        #expect(snapshot.minimumExecutionDuration == 0.5)
        #expect(snapshot.maximumExecutionDuration == 3.0)
    }

    @Test("MetricsSnapshot computes median duration")
    func snapshotComputesMedianDuration() async {
        let collector = MetricsCollector()
        let traceId = UUID()

        // Odd number of durations: [1, 2, 3] -> median = 2
        let durations: [TimeInterval] = [1.0, 3.0, 2.0]
        for duration in durations {
            let spanId = UUID()
            await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "Agent"))
            await collector.trace(.agentComplete(traceId: traceId, spanId: spanId, agentName: "Agent", duration: duration))
        }

        let snapshot = await collector.snapshot()
        #expect(snapshot.medianExecutionDuration == 2.0)
    }

    @Test("MetricsSnapshot computes percentiles")
    func snapshotComputesPercentiles() async {
        let collector = MetricsCollector()
        let traceId = UUID()

        // Add 100 durations from 0.1 to 10.0
        for i in 1...100 {
            let spanId = UUID()
            let duration = Double(i) * 0.1
            await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "Agent"))
            await collector.trace(.agentComplete(traceId: traceId, spanId: spanId, agentName: "Agent", duration: duration))
        }

        let snapshot = await collector.snapshot()

        // P95 should be around 9.5 (95th element out of 100)
        // P99 should be around 9.9 (99th element out of 100)
        #expect(snapshot.p95ExecutionDuration != nil)
        #expect(snapshot.p99ExecutionDuration != nil)

        if let p95 = snapshot.p95ExecutionDuration, let p99 = snapshot.p99ExecutionDuration {
            #expect(p95 >= 9.0)
            #expect(p99 >= 9.5)
        }
    }

    @Test("MetricsSnapshot computes total tool calls and errors")
    func snapshotComputesTotalToolMetrics() async {
        let collector = MetricsCollector()
        let traceId = UUID()

        // Add tool calls
        await collector.trace(.toolCall(traceId: traceId, parentSpanId: UUID(), toolName: "tool1"))
        await collector.trace(.toolCall(traceId: traceId, parentSpanId: UUID(), toolName: "tool2"))
        await collector.trace(.toolCall(traceId: traceId, parentSpanId: UUID(), toolName: "tool1"))

        // Add tool errors
        let errorEvent = TraceEvent.Builder(traceId: traceId, kind: .toolError, message: "Error")
            .tool("tool1")
            .build()
        await collector.trace(errorEvent)

        let snapshot = await collector.snapshot()
        #expect(snapshot.totalToolCalls == 3)
        #expect(snapshot.totalToolErrors == 1)
    }

    // MARK: - Reset Tests

    @Test("MetricsCollector reset clears all metrics")
    func resetClearsAllMetrics() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        let spanId = UUID()

        // Add some metrics
        await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "Agent"))
        await collector.trace(.agentComplete(traceId: traceId, spanId: spanId, agentName: "Agent", duration: 1.0))
        await collector.trace(.toolCall(traceId: traceId, parentSpanId: UUID(), toolName: "tool"))

        // Verify metrics exist
        var snapshot = await collector.snapshot()
        #expect(snapshot.totalExecutions > 0)

        // Reset
        await collector.reset()

        // Verify all metrics are cleared
        snapshot = await collector.snapshot()
        #expect(snapshot.totalExecutions == 0)
        #expect(snapshot.successfulExecutions == 0)
        #expect(snapshot.failedExecutions == 0)
        #expect(snapshot.cancelledExecutions == 0)
        #expect(snapshot.executionDurations.isEmpty)
        #expect(snapshot.toolCalls.isEmpty)
        #expect(snapshot.toolErrors.isEmpty)
        #expect(snapshot.toolDurations.isEmpty)
    }

    @Test("MetricsCollector tracks after reset")
    func tracksAfterReset() async {
        let collector = MetricsCollector()
        let traceId = UUID()
        let spanId = UUID()

        // Add metric, reset, add another
        await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "Agent"))
        await collector.reset()
        await collector.trace(.agentStart(traceId: traceId, spanId: spanId, agentName: "Agent"))

        let total = await collector.getTotalExecutions()
        #expect(total == 1) // Only the metric after reset
    }
}

// MARK: - JSONMetricsReporterTests

@Suite("JSONMetricsReporter Tests")
struct JSONMetricsReporterTests {
    @Test("JSONMetricsReporter encodes snapshot to JSON")
    func jsonReporterEncodesSnapshot() throws {
        let snapshot = MetricsSnapshot(
            totalExecutions: 10,
            successfulExecutions: 8,
            failedExecutions: 2,
            cancelledExecutions: 0,
            executionDurations: [1.0, 2.0, 3.0],
            toolCalls: ["tool1": 5],
            toolErrors: ["tool1": 1],
            toolDurations: ["tool1": [1.0, 2.0]],
            timestamp: Date()
        )

        let reporter = JSONMetricsReporter(prettyPrint: true)
        let jsonString = try reporter.jsonString(from: snapshot)

        #expect(jsonString.contains("totalExecutions"))
        #expect(jsonString.contains("successfulExecutions"))
    }

    @Test("JSONMetricsReporter produces valid JSON data")
    func jsonReporterProducesValidData() throws {
        let snapshot = MetricsSnapshot(
            totalExecutions: 5,
            successfulExecutions: 5,
            failedExecutions: 0,
            cancelledExecutions: 0,
            executionDurations: [1.0],
            toolCalls: [:],
            toolErrors: [:],
            toolDurations: [:],
            timestamp: Date()
        )

        let reporter = JSONMetricsReporter(prettyPrint: false)
        let data = try reporter.jsonData(from: snapshot)

        // Verify it can be decoded back
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MetricsSnapshot.self, from: data)

        #expect(decoded.totalExecutions == 5)
        #expect(decoded.successfulExecutions == 5)
    }
}
