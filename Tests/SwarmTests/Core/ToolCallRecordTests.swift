// ToolCallRecordTests.swift
// SwarmTests
//
// Tests for ToolCallRecord closed outcome and Codable compatibility.

import Foundation
@testable import Swarm
import Testing

@Suite("ToolCallRecord Tests")
struct ToolCallRecordTests {
    @Test("ToolCallRecord.success factory")
    func successFactory() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let record = ToolCallRecord.success(
            toolName: "calculator",
            arguments: ["a": .int(1)],
            result: .int(8),
            duration: .seconds(1),
            timestamp: timestamp
        )

        #expect(record.toolName == "calculator")
        #expect(record.isSuccess)
        #expect(record.result == .int(8))
        #expect(record.errorMessage == nil)
        #expect(record.duration == .seconds(1))
        #expect(record.timestamp == timestamp)
        guard case let .success(value) = record.outcome else {
            Issue.record("expected success outcome")
            return
        }
        #expect(value == .int(8))
    }

    @Test("ToolCallRecord.failure factory")
    func failureFactory() {
        let record = ToolCallRecord.failure(
            toolName: "calculator",
            arguments: ["a": .int(1)],
            error: "Division by zero",
            duration: .milliseconds(4)
        )

        #expect(!record.isSuccess)
        #expect(record.result == .null)
        #expect(record.errorMessage == "Division by zero")
        guard case let .failure(message) = record.outcome else {
            Issue.record("expected failure outcome")
            return
        }
        #expect(message == "Division by zero")
    }

    @Test("ToolCallRecord Codable round-trip preserves outcome")
    func codableRoundTrip() throws {
        let original = ToolCallRecord.failure(
            toolName: "search",
            arguments: ["q": .string("swift")],
            error: "timeout",
            duration: .seconds(2),
            timestamp: Date(timeIntervalSince1970: 50)
        )
        let decoded = try JSONDecoder().decode(
            ToolCallRecord.self,
            from: try JSONEncoder().encode(original)
        )
        #expect(decoded == original)
        #expect(!decoded.isSuccess)
        #expect(decoded.errorMessage == "timeout")
    }

    private struct LegacyToolCallRecordPayload: Encodable {
        let toolName: String
        let arguments: [String: SendableValue]
        let result: SendableValue
        let duration: Duration
        let timestamp: Date
        let isSuccess: Bool
        let errorMessage: String?
    }

    @Test("ToolCallRecord decodes historical boolean+optional JSON")
    func decodesLegacyJSON() throws {
        let timestamp = Date(timeIntervalSince1970: 99)
        let data = try JSONEncoder().encode(
            LegacyToolCallRecordPayload(
                toolName: "lookup",
                arguments: ["id": .int(3)],
                result: .string("stale"),
                duration: .milliseconds(12),
                timestamp: timestamp,
                isSuccess: false,
                errorMessage: "missing"
            )
        )
        let decoded = try JSONDecoder().decode(ToolCallRecord.self, from: data)
        #expect(decoded.toolName == "lookup")
        #expect(!decoded.isSuccess)
        #expect(decoded.result == .null)
        #expect(decoded.errorMessage == "missing")
        #expect(decoded.timestamp == timestamp)
    }

    @Test("ToolCallRecord encodes existing keys derived from outcome")
    func encodesLegacyKeysFromOutcome() throws {
        let record = ToolCallRecord.success(
            toolName: "echo",
            result: .string("hi"),
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let data = try JSONEncoder().encode(record)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            Issue.record("expected JSON object")
            return
        }
        #expect(dictionary["isSuccess"] as? Bool == true)
        #expect(dictionary["result"] as? String == "hi")
        #expect(dictionary["errorMessage"] == nil)
        #expect(dictionary["outcome"] == nil)
    }

    @Test("AgentResponse.asResult maps a failed record to a failed ToolResult")
    func asResultMapsFailureOutcome() throws {
        let record = ToolCallRecord.failure(
            toolName: "broken",
            error: "nope",
            duration: .seconds(1),
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let response = AgentResponse(
            output: "done",
            agentName: "tester",
            timestamp: Date(timeIntervalSince1970: 1),
            toolCalls: [record]
        )
        let toolResult = try #require(response.asResult.toolResults.first)
        #expect(!toolResult.isSuccess)
        #expect(toolResult.output == .null)
        #expect(toolResult.errorMessage == "nope")
        guard case .failure = toolResult.outcome else {
            Issue.record("expected failure outcome")
            return
        }
    }
}
