// AgentEventTests+ToolResult.swift
// SwarmTests
//
// Tests for ToolResult type

import Foundation
@testable import Swarm
import Testing

// MARK: - ToolResult Tests

@Suite("ToolResult Tests")
struct ToolResultTests {
    // MARK: - Success Factory Method

    @Test("ToolResult.success factory")
    func successFactory() {
        let callId = UUID()
        let output: SendableValue = .string("Success result")
        let duration = Duration.seconds(2)

        let result = ToolResult.success(
            callId: callId,
            output: output,
            duration: duration
        )

        #expect(result.callId == callId)
        #expect(result.isSuccess == true)
        #expect(result.output == output)
        #expect(result.duration == duration)
        #expect(result.errorMessage == nil)
    }

    @Test("ToolResult.success with different output types")
    func successDifferentOutputTypes() {
        let callId = UUID()

        // String output
        let stringResult = ToolResult.success(
            callId: callId,
            output: .string("text"),
            duration: .milliseconds(100)
        )
        #expect(stringResult.output == .string("text"))

        // Int output
        let intResult = ToolResult.success(
            callId: callId,
            output: .int(42),
            duration: .milliseconds(100)
        )
        #expect(intResult.output == .int(42))

        // Dictionary output
        let dictResult = ToolResult.success(
            callId: callId,
            output: .dictionary(["key": .string("value")]),
            duration: .milliseconds(100)
        )
        #expect(dictResult.output["key"] == .string("value"))

        // Array output
        let arrayResult = ToolResult.success(
            callId: callId,
            output: .array([.int(1), .int(2)]),
            duration: .milliseconds(100)
        )
        #expect(arrayResult.output[0] == .int(1))
    }

    // MARK: - Failure Factory Method

    @Test("ToolResult.failure factory")
    func failureFactory() {
        let callId = UUID()
        let error = "Connection timeout"
        let duration = Duration.seconds(5)

        let result = ToolResult.failure(
            callId: callId,
            error: error,
            duration: duration
        )

        #expect(result.callId == callId)
        #expect(result.isSuccess == false)
        #expect(result.output == .null)
        #expect(result.duration == duration)
        #expect(result.errorMessage == error)
    }

    @Test("ToolResult.failure with different error messages")
    func failureDifferentErrors() {
        let callId = UUID()

        let errors = [
            "Network error",
            "Invalid input",
            "Permission denied",
            "Resource not found"
        ]

        for errorMessage in errors {
            let result = ToolResult.failure(
                callId: callId,
                error: errorMessage,
                duration: .milliseconds(50)
            )

            #expect(result.isSuccess == false)
            #expect(result.errorMessage == errorMessage)
            #expect(result.output == .null)
        }
    }

    // MARK: - Direct Outcome Initialization

    @Test("ToolResult outcome initialization - success")
    func directInitializationSuccess() {
        let callId = UUID()
        let result = ToolResult(
            callId: callId,
            duration: .seconds(1),
            outcome: .success(.int(100))
        )

        #expect(result.callId == callId)
        #expect(result.isSuccess == true)
        #expect(result.output == .int(100))
        #expect(result.duration == .seconds(1))
        #expect(result.errorMessage == nil)
    }

    @Test("ToolResult outcome initialization - failure")
    func directInitializationFailure() {
        let callId = UUID()
        let result = ToolResult(
            callId: callId,
            duration: .milliseconds(500),
            outcome: .failure(message: "Failed")
        )

        #expect(result.callId == callId)
        #expect(result.isSuccess == false)
        #expect(result.output == .null)
        #expect(result.duration == .milliseconds(500))
        #expect(result.errorMessage == "Failed")
    }

    // MARK: - Equatable Conformance

    @Test("ToolResult Equatable - same values")
    func equatableSameValues() {
        let callId = UUID()
        let duration = Duration.seconds(1)

        let result1 = ToolResult.success(
            callId: callId,
            output: .string("test"),
            duration: duration
        )

        let result2 = ToolResult.success(
            callId: callId,
            output: .string("test"),
            duration: duration
        )

        #expect(result1 == result2)
    }

    @Test("ToolResult Equatable - different callIds")
    func equatableDifferentCallIds() {
        let result1 = ToolResult.success(
            callId: UUID(),
            output: .string("test"),
            duration: .seconds(1)
        )

        let result2 = ToolResult.success(
            callId: UUID(),
            output: .string("test"),
            duration: .seconds(1)
        )

        #expect(result1 != result2)
    }

    @Test("ToolResult Equatable - different success states")
    func equatableDifferentSuccessStates() {
        let callId = UUID()

        let success = ToolResult.success(
            callId: callId,
            output: .string("test"),
            duration: .seconds(1)
        )

        let failure = ToolResult.failure(
            callId: callId,
            error: "error",
            duration: .seconds(1)
        )

        #expect(success != failure)
    }

    @Test("ToolResult Equatable - different outputs")
    func equatableDifferentOutputs() {
        let callId = UUID()

        let result1 = ToolResult.success(
            callId: callId,
            output: .string("output1"),
            duration: .seconds(1)
        )

        let result2 = ToolResult.success(
            callId: callId,
            output: .string("output2"),
            duration: .seconds(1)
        )

        #expect(result1 != result2)
    }

    @Test("ToolResult Equatable - different durations")
    func equatableDifferentDurations() {
        let callId = UUID()

        let result1 = ToolResult.success(
            callId: callId,
            output: .string("test"),
            duration: .seconds(1)
        )

        let result2 = ToolResult.success(
            callId: callId,
            output: .string("test"),
            duration: .seconds(2)
        )

        #expect(result1 != result2)
    }

    @Test("ToolResult Equatable - different error messages")
    func equatableDifferentErrorMessages() {
        let callId = UUID()

        let result1 = ToolResult.failure(
            callId: callId,
            error: "error1",
            duration: .seconds(1)
        )

        let result2 = ToolResult.failure(
            callId: callId,
            error: "error2",
            duration: .seconds(1)
        )

        #expect(result1 != result2)
    }

    // MARK: - Codable Conformance

    @Test("ToolResult Codable round-trip - success")
    func codableRoundTripSuccess() throws {
        let original = ToolResult.success(
            callId: UUID(uuidString: "12345678-1234-1234-1234-123456789012")!,
            output: .dictionary([
                "result": .int(42),
                "message": .string("Success")
            ]),
            duration: .seconds(3)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ToolResult.self, from: data)

        #expect(decoded == original)
        #expect(decoded.isSuccess == true)
        #expect(decoded.output["result"] == .int(42))
        #expect(decoded.errorMessage == nil)
    }

    @Test("ToolResult Codable round-trip - failure")
    func codableRoundTripFailure() throws {
        let original = ToolResult.failure(
            callId: UUID(uuidString: "12345678-1234-1234-1234-123456789012")!,
            error: "Something went wrong",
            duration: .milliseconds(250)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ToolResult.self, from: data)

        #expect(decoded == original)
        #expect(decoded.isSuccess == false)
        #expect(decoded.output == .null)
        #expect(decoded.errorMessage == "Something went wrong")
    }

    @Test("ToolResult Codable with null output")
    func codableNullOutput() throws {
        let original = ToolResult.success(
            callId: UUID(),
            output: .null,
            duration: .seconds(1)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ToolResult.self, from: data)

        #expect(decoded.output == .null)
        #expect(decoded.isSuccess == true)
    }

    // MARK: - CustomStringConvertible

    @Test("ToolResult description - success")
    func customStringConvertibleSuccess() {
        let result = ToolResult.success(
            callId: UUID(),
            output: .string("result"),
            duration: .seconds(1)
        )

        let description = result.description

        #expect(description.contains("ToolResult"))
        #expect(description.contains("success"))
        #expect(description.contains("duration"))
    }

    @Test("ToolResult description - failure")
    func customStringConvertibleFailure() {
        let result = ToolResult.failure(
            callId: UUID(),
            error: "Test error",
            duration: .seconds(2)
        )

        let description = result.description

        #expect(description.contains("ToolResult"))
        #expect(description.contains("failure"))
        #expect(description.contains("duration"))
    }

    // MARK: - Edge Cases

    @Test("ToolResult with zero duration")
    func zeroDuration() {
        let result = ToolResult.success(
            callId: UUID(),
            output: .string("instant"),
            duration: .zero
        )

        #expect(result.duration == .zero)
    }

    @Test("ToolResult with very long duration")
    func longDuration() {
        let result = ToolResult.success(
            callId: UUID(),
            output: .string("slow"),
            duration: .seconds(3600) // 1 hour
        )

        #expect(result.duration == .seconds(3600))
    }

    @Test("ToolResult with empty error message")
    func emptyErrorMessage() {
        let result = ToolResult.failure(
            callId: UUID(),
            error: "",
            duration: .milliseconds(100)
        )

        #expect(result.errorMessage?.isEmpty == true)
        #expect(result.isSuccess == false)
    }

    @Test("ToolResult with complex nested output")
    func complexNestedOutput() {
        let output: SendableValue = .dictionary([
            "data": .array([
                .dictionary([
                    "id": .int(1),
                    "name": .string("Item 1"),
                    "tags": .array([.string("tag1"), .string("tag2")])
                ]),
                .dictionary([
                    "id": .int(2),
                    "name": .string("Item 2"),
                    "tags": .array([.string("tag3")])
                ])
            ]),
            "metadata": .dictionary([
                "count": .int(2),
                "cached": .bool(true)
            ])
        ])

        let result = ToolResult.success(
            callId: UUID(),
            output: output,
            duration: .milliseconds(500)
        )

        #expect(result.isSuccess == true)
        #expect(result.output["data"]?[0]?["name"] == .string("Item 1"))
        #expect(result.output["metadata"]?["count"] == .int(2))
    }

    // MARK: - Closed Outcome

    @Test("ToolResult success and failure are distinct outcome cases")
    func outcomeCasesAreExhaustivePair() {
        let callId = UUID()
        let success = ToolResult.success(callId: callId, output: .string("ok"), duration: .zero)
        let failure = ToolResult.failure(callId: callId, error: "nope", duration: .zero)
        var sawSuccess = false
        var sawFailure = false
        for result in [success, failure] {
            switch result.outcome {
            case .success:
                sawSuccess = true
            case .failure:
                sawFailure = true
            }
        }
        #expect(sawSuccess)
        #expect(sawFailure)
        #expect(success.errorMessage == nil)
        #expect(failure.output == .null)
    }

    @Test("Deprecated ToolResult initializer cannot store success-with-error")
    func deprecatedInitDropsErrorOnSuccess() {
        let result = ToolResult(
            callId: UUID(),
            isSuccess: true,
            output: .string("ok"),
            duration: .zero,
            errorMessage: "ignored"
        )
        #expect(result.isSuccess)
        #expect(result.errorMessage == nil)
        guard case let .success(value) = result.outcome else {
            Issue.record("expected success outcome")
            return
        }
        #expect(value == .string("ok"))
    }

    @Test("Deprecated ToolResult initializer cannot store failure-with-success-output")
    func deprecatedInitDropsOutputOnFailure() {
        let result = ToolResult(
            callId: UUID(),
            isSuccess: false,
            output: .string("should not be kept"),
            duration: .milliseconds(10),
            errorMessage: "boom"
        )
        #expect(result.isSuccess == false)
        #expect(result.output == .null)
        #expect(result.errorMessage == "boom")
        guard case let .failure(message) = result.outcome else {
            Issue.record("expected failure outcome")
            return
        }
        #expect(message == "boom")
    }

    @Test("Deprecated ToolResult failure initializer fills a default message when nil")
    func deprecatedInitNilFailureMessage() {
        let result = ToolResult(
            callId: UUID(),
            isSuccess: false,
            output: .null,
            duration: .zero
        )
        #expect(result.isSuccess == false)
        #expect(result.errorMessage == "Tool execution failed")
    }

    // MARK: - Legacy Codable

    private struct LegacyToolResultPayload: Encodable {
        let callId: UUID
        let isSuccess: Bool
        let output: SendableValue
        let duration: Duration
        let errorMessage: String?
    }

    @Test("ToolResult decodes historical success JSON")
    func decodesLegacySuccessJSON() throws {
        let callId = UUID(uuidString: "12345678-1234-1234-1234-123456789012")!
        let data = try JSONEncoder().encode(
            LegacyToolResultPayload(
                callId: callId,
                isSuccess: true,
                output: .string("hello"),
                duration: .seconds(3),
                errorMessage: nil
            )
        )
        let decoded = try JSONDecoder().decode(ToolResult.self, from: data)
        #expect(decoded.callId == callId)
        #expect(decoded.isSuccess)
        #expect(decoded.output == .string("hello"))
        #expect(decoded.errorMessage == nil)
        #expect(decoded.duration == .seconds(3))
        guard case .success = decoded.outcome else {
            Issue.record("expected success outcome")
            return
        }
    }

    @Test("ToolResult decodes historical failure JSON and ignores success output")
    func decodesLegacyFailureJSON() throws {
        let callId = UUID(uuidString: "12345678-1234-1234-1234-123456789012")!
        let data = try JSONEncoder().encode(
            LegacyToolResultPayload(
                callId: callId,
                isSuccess: false,
                output: .string("stale output"),
                duration: .milliseconds(250),
                errorMessage: "Something went wrong"
            )
        )
        let decoded = try JSONDecoder().decode(ToolResult.self, from: data)
        #expect(decoded.callId == callId)
        #expect(!decoded.isSuccess)
        #expect(decoded.output == .null)
        #expect(decoded.errorMessage == "Something went wrong")
        guard case let .failure(message) = decoded.outcome else {
            Issue.record("expected failure outcome")
            return
        }
        #expect(message == "Something went wrong")
    }

    @Test("ToolResult encodes existing boolean and optional keys derived from outcome")
    func encodesLegacyKeysFromOutcome() throws {
        let success = ToolResult.success(
            callId: UUID(uuidString: "12345678-1234-1234-1234-123456789012")!,
            output: .int(7),
            duration: .zero
        )
        let failure = ToolResult.failure(
            callId: UUID(uuidString: "12345678-1234-1234-1234-123456789012")!,
            error: "nope",
            duration: .zero
        )

        let successObject = try jsonObject(from: success)
        #expect(successObject["isSuccess"] as? Bool == true)
        #expect(successObject["output"] as? Int == 7)
        #expect(successObject["errorMessage"] == nil)
        #expect(successObject["outcome"] == nil)

        let failureObject = try jsonObject(from: failure)
        #expect(failureObject["isSuccess"] as? Bool == false)
        #expect(failureObject["errorMessage"] as? String == "nope")
        #expect(failureObject["outcome"] == nil)
    }

    @Test("EventStreamObserver treats ToolResult failure as a tool error")
    func eventStreamTreatsFailureAsToolError() async throws {
        let (stream, continuation) = AsyncThrowingStream<AgentEvent, any Error>.makeStream()
        let observer = EventStreamObserver(continuation: continuation)
        let agent = MockAgentForToolResultEvents()
        let callId = UUID()
        let call = ToolCall(id: callId, toolName: "calculator", arguments: [:])

        await observer.onToolStart(context: nil, agent: agent, call: call)
        await observer.onToolEnd(
            context: nil,
            agent: agent,
            result: ToolResult.failure(callId: callId, error: "Division by zero", duration: .milliseconds(5))
        )
        continuation.finish()

        var events: [AgentEvent] = []
        for try await event in stream {
            events.append(event)
        }

        #expect(events.count == 3)
        guard case let .tool(.started(call: startedCall)) = events[0] else {
            Issue.record("expected started event")
            return
        }
        #expect(startedCall.id == callId)
        guard case let .tool(.completed(call: _, result: result)) = events[1] else {
            Issue.record("expected completed event")
            return
        }
        #expect(!result.isSuccess)
        #expect(result.errorMessage == "Division by zero")
        guard case let .tool(.failed(call: failedCall, error: error)) = events[2] else {
            Issue.record("expected failed event")
            return
        }
        #expect(failedCall.id == callId)
        guard case let .toolFailure(toolName: toolName, message: message, cause: cause) = error else {
            Issue.record("expected toolFailure")
            return
        }
        #expect(toolName == "calculator")
        #expect(message == "Division by zero")
        #expect(cause == nil)
    }

    private func jsonObject(from result: ToolResult) throws -> [String: Any] {
        let data = try JSONEncoder().encode(result)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            Issue.record("expected JSON object")
            return [:]
        }
        return dictionary
    }
}

private struct MockAgentForToolResultEvents: AgentRuntime {
    let tools: [any AnyJSONTool] = []
    let instructions: String = "Mock agent"
    let configuration: AgentConfiguration = AgentConfiguration(name: "mock")

    func run(_ input: String, session _: (any Session)? = nil, observer _: (any AgentObserver)? = nil) async throws -> AgentResult {
        AgentResult(output: input)
    }

    nonisolated func stream(
        _ input: String,
        session _: (any Session)? = nil,
        observer _: (any AgentObserver)? = nil
    ) -> AsyncThrowingStream<AgentEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.lifecycle(.started(input: input)))
            continuation.finish()
        }
    }

    func cancel() async {}
}
