// AgentResponseConversionTests.swift
// SwarmTests
//
// AgentResponse.asResult is a lossy compatibility projection.

import Foundation
@testable import Swarm
import Testing

@Suite("AgentResponse asResult Conversion")
struct AgentResponseConversionTests {
    @Test("asResult preserves output, metadata, usage, and iteration count")
    func preservesMappedFields() {
        let metadata: [String: SendableValue] = [
            "confidence": .double(0.9),
            "source": .string("unit-test"),
        ]
        let usage = TokenUsage(inputTokens: 11, outputTokens: 7)
        let response = AgentResponse(
            responseId: "resp-keep",
            output: "hello",
            agentName: "Greeter",
            timestamp: Date(timeIntervalSince1970: 42),
            metadata: metadata,
            usage: usage,
            iterationCount: 4
        )

        let result = response.asResult
        #expect(result.output == "hello")
        #expect(result.metadata == metadata)
        #expect(result.tokenUsage == usage)
        #expect(result.iterationCount == 4)
        #expect(result.toolCalls.isEmpty)
        #expect(result.toolResults.isEmpty)
        #expect(result.duration == .zero)
    }

    @Test("asResult drops responseId, agentName, and response timestamp")
    func dropsResponseIdentity() {
        let response = AgentResponse(
            responseId: "resp-lost",
            output: "done",
            agentName: "NamedAgent",
            timestamp: Date(timeIntervalSince1970: 99),
            metadata: ["keep": .bool(true)]
        )

        let result = response.asResult
        let encoded = String(describing: result)
        #expect(!encoded.contains("resp-lost"))
        #expect(!encoded.contains("NamedAgent"))
        #expect(result.metadata["keep"] == .bool(true))
        #expect(result.output == "done")
    }

    @Test("asResult duration is the sum of tool-call durations, not wall-clock time")
    func durationSumsToolCallsOnly() {
        let records = [
            ToolCallRecord.success(
                toolName: "a",
                result: .string("one"),
                duration: .milliseconds(250),
                timestamp: Date(timeIntervalSince1970: 1)
            ),
            ToolCallRecord.failure(
                toolName: "b",
                error: "nope",
                duration: .milliseconds(750),
                timestamp: Date(timeIntervalSince1970: 2)
            ),
        ]
        let response = AgentResponse(
            responseId: "resp-duration",
            output: "mixed",
            agentName: "Timer",
            timestamp: Date(timeIntervalSince1970: 10),
            toolCalls: records,
            iterationCount: 3
        )

        let result = response.asResult
        #expect(result.duration == .milliseconds(1_000))
        #expect(result.toolCalls.count == 2)
        #expect(result.toolResults.count == 2)
        #expect(result.toolCalls[0].toolName == "a")
        #expect(result.toolCalls[1].toolName == "b")
        #expect(result.toolResults[0].isSuccess)
        #expect(!result.toolResults[1].isSuccess)
        #expect(result.toolResults[0].callId == result.toolCalls[0].id)
        #expect(result.toolResults[1].callId == result.toolCalls[1].id)
        #expect(result.toolCalls[0].id != result.toolCalls[1].id)
    }

    @Test("asResult mints new tool-call IDs on every conversion")
    func mintsNewToolCallIDs() throws {
        let record = ToolCallRecord.success(
            toolName: "echo",
            arguments: ["q": .string("hi")],
            result: .string("hi"),
            duration: .seconds(1),
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let response = AgentResponse(
            output: "done",
            agentName: "Echo",
            timestamp: Date(timeIntervalSince1970: 1),
            toolCalls: [record]
        )

        let first = response.asResult
        let second = response.asResult
        let firstID = try #require(first.toolCalls.first?.id)
        let secondID = try #require(second.toolCalls.first?.id)
        #expect(firstID != secondID)
        #expect(first.toolResults.first?.callId == firstID)
        #expect(second.toolResults.first?.callId == secondID)
        #expect(first.toolCalls.first?.arguments["q"] == .string("hi"))
        #expect(first.toolResults.first?.output == .string("hi"))
    }

    @Test("empty tool list converts to zero duration and empty arrays")
    func emptyToolsStayEmpty() {
        let response = AgentResponse(
            output: "none",
            agentName: "Empty",
            timestamp: Date(timeIntervalSince1970: 1),
            toolCalls: [],
            iterationCount: 1
        )
        let result = response.asResult
        #expect(result.toolCalls.isEmpty)
        #expect(result.toolResults.isEmpty)
        #expect(result.duration == .zero)
    }
}
