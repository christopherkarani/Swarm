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

    @Test("asResult reuses ToolCallRecord callId across repeated conversions")
    func reusesStableToolCallIDs() throws {
        let knownID = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
        let record = ToolCallRecord.success(
            callId: knownID,
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
        #expect(firstID == knownID)
        #expect(secondID == knownID)
        #expect(firstID == secondID)
        #expect(first.toolResults.first?.callId == knownID)
        #expect(second.toolResults.first?.callId == knownID)
        #expect(first.toolCalls.first?.arguments["q"] == .string("hi"))
        #expect(first.toolResults.first?.output == .string("hi"))
        #expect(first == second)
    }

    @Test("asResult is equal across conversions when callId was defaulted")
    func defaultedCallIdsStayStable() {
        let record = ToolCallRecord.success(
            toolName: "echo",
            result: .string("hi"),
            duration: .milliseconds(2),
            timestamp: Date(timeIntervalSince1970: 3)
        )
        let response = AgentResponse(
            output: "done",
            agentName: "Echo",
            timestamp: Date(timeIntervalSince1970: 3),
            toolCalls: [record]
        )

        #expect(response.asResult == response.asResult)
        #expect(response.asResult.toolCalls.first?.id == record.callId)
    }

    @Test("ToolInvocation shares identity by construction and rejects mismatches")
    func invocationIdentityByConstruction() {
        let callID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
        let call = ToolCall(id: callID, toolName: "calc", arguments: ["n": .int(2)])
        let mismatched = ToolResult.success(
            callId: UUID(uuidString: "FEDCBA98-7654-3210-FEDC-BA9876543210")!,
            output: .int(4),
            duration: .milliseconds(1)
        )
        #expect(ToolInvocation(call: call, result: mismatched) == nil)

        let constructed = ToolInvocation(
            call: call,
            duration: .milliseconds(1),
            outcome: .success(.int(4))
        )
        #expect(constructed.call.id == callID)
        #expect(constructed.result.callId == callID)
        #expect(ToolInvocation(call: call, result: constructed.result) != nil)
    }

    @Test("AgentResult pairing drops tool results with no matching call")
    func dropsOrphanToolResults() {
        let callID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let orphanID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let call = ToolCall(id: callID, toolName: "a", arguments: [:])
        let matched = ToolResult.success(callId: callID, output: .string("ok"), duration: .zero)
        let orphan = ToolResult.failure(callId: orphanID, error: "lost", duration: .zero)

        let result = AgentResult(
            output: "done",
            toolCalls: [call],
            toolResults: [orphan, matched]
        )

        #expect(result.invocations.count == 1)
        #expect(result.toolCalls.count == 1)
        #expect(result.toolResults.count == 1)
        #expect(result.toolCalls[0].id == callID)
        #expect(result.toolResults[0].callId == callID)
    }

    @Test("AgentResult pairing omits calls with no matching result")
    func dropsUnmatchedCalls() {
        let pairedID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let unmatchedID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
        let pairedCall = ToolCall(id: pairedID, toolName: "kept", arguments: [:])
        let unmatchedCall = ToolCall(id: unmatchedID, toolName: "lost", arguments: [:])
        let matched = ToolResult.success(callId: pairedID, output: .string("ok"), duration: .zero)

        let result = AgentResult(
            output: "done",
            toolCalls: [unmatchedCall, pairedCall],
            toolResults: [matched]
        )

        #expect(result.invocations.count == 1)
        #expect(result.toolCalls.map(\.id) == [pairedID])
        #expect(result.toolResults.map(\.callId) == [pairedID])
    }

    @Test("WorkflowResultSnapshot decodes pre-invocation paired checkpoint payloads")
    func snapshotDecodesLegacyPairedArrays() throws {
        let callID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        let call = ToolCall(
            id: callID,
            toolName: "calc",
            arguments: ["n": .int(2)],
            timestamp: Date(timeIntervalSince1970: 10)
        )
        let toolResult = ToolResult.success(callId: callID, output: .int(4), duration: .milliseconds(5))
        let payload = LegacyWorkflowResultSnapshotPayload(
            output: "4",
            toolCalls: [call],
            toolResults: [toolResult],
            iterationCount: 2,
            durationSeconds: 1,
            durationAttoseconds: 0,
            tokenUsage: TokenUsage(inputTokens: 3, outputTokens: 1),
            metadata: ["source": .string("checkpoint")]
        )

        let decoded = try JSONDecoder().decode(
            WorkflowResultSnapshot.self,
            from: try JSONEncoder().encode(payload)
        )
        let restored = decoded.agentResult

        #expect(decoded.output == "4")
        #expect(restored.invocations.count == 1)
        #expect(restored.toolCalls.map(\.id) == [callID])
        #expect(restored.toolResults.map(\.callId) == [callID])
        #expect(restored.toolResults.first?.output == .int(4))
        #expect(restored.iterationCount == 2)
        #expect(restored.tokenUsage == TokenUsage(inputTokens: 3, outputTokens: 1))
        #expect(restored.metadata["source"] == .string("checkpoint"))
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

/// Checkpoint JSON shape from before `AgentResult` stored `invocations`.
private struct LegacyWorkflowResultSnapshotPayload: Encodable {
    let output: String
    let toolCalls: [ToolCall]
    let toolResults: [ToolResult]
    let iterationCount: Int
    let durationSeconds: Int64
    let durationAttoseconds: Int64
    let tokenUsage: TokenUsage?
    let metadata: [String: SendableValue]
}
