// GuardrailResultTests.swift
// SwarmTests
//
// TDD tests for GuardrailResult - Sprint 1 of Guardrails system
// These tests define the contract for GuardrailResult before implementation

import Foundation
@testable import Swarm
import Testing

// MARK: - GuardrailResultTests

@Suite("GuardrailResult Tests")
struct GuardrailResultTests {
    // MARK: - Passed Result Tests

    @Test("Passed result has tripwireTriggered set to false")
    func passedResultDefaults() {
        // When
        let result = GuardrailResult.passed()

        // Then
        #expect(result.tripwireTriggered == false)
        #expect(result.message == nil)
        #expect(result.outputInfo == nil)
        #expect(result.metadata.isEmpty)
    }

    @Test("Passed result preserves custom message")
    func passedResultWithMessage() {
        // Given
        let message = "Input validation successful"

        // When
        let result = GuardrailResult.passed(message: message)

        // Then
        #expect(result.tripwireTriggered == false)
        #expect(result.message == message)
        #expect(result.outputInfo == nil)
        #expect(result.metadata.isEmpty)
    }

    @Test("Passed result preserves outputInfo")
    func passedResultWithOutputInfo() {
        // Given
        let outputInfo: SendableValue = .dictionary([
            "tokensChecked": .int(42),
            "passed": .bool(true)
        ])

        // When
        let result = GuardrailResult.passed(outputInfo: outputInfo)

        // Then
        #expect(result.tripwireTriggered == false)
        #expect(result.outputInfo == outputInfo)
        #expect(result.message == nil)
        #expect(result.metadata.isEmpty)
    }

    @Test("Passed result preserves metadata")
    func passedResultWithMetadata() {
        // Given
        let metadata: [String: SendableValue] = [
            "checkDuration": .double(0.123),
            "version": .string("1.0")
        ]

        // When
        let result = GuardrailResult.passed(metadata: metadata)

        // Then
        #expect(result.tripwireTriggered == false)
        #expect(result.metadata == metadata)
        #expect(result.message == nil)
        #expect(result.outputInfo == nil)
    }

    @Test("Passed result with all parameters")
    func passedResultWithAllParameters() {
        // Given
        let message = "All checks passed"
        let outputInfo: SendableValue = .dictionary(["status": .string("ok")])
        let metadata: [String: SendableValue] = ["timestamp": .int(1_234_567_890)]

        // When
        let result = GuardrailResult.passed(
            message: message,
            outputInfo: outputInfo,
            metadata: metadata
        )

        // Then
        #expect(result.tripwireTriggered == false)
        #expect(result.message == message)
        #expect(result.outputInfo == outputInfo)
        #expect(result.metadata == metadata)
    }

    // MARK: - Tripwire Result Tests

    @Test("Tripwire result has tripwireTriggered set to true")
    func tripwireResult() {
        // Given
        let message = "Sensitive data detected"

        // When
        let result = GuardrailResult.tripwire(message: message)

        // Then
        #expect(result.tripwireTriggered == true)
        #expect(result.message == message)
        #expect(result.outputInfo == nil)
        #expect(result.metadata.isEmpty)
    }

    @Test("Tripwire result preserves outputInfo")
    func tripwireResultWithOutputInfo() {
        // Given
        let message = "Policy violation"
        let outputInfo: SendableValue = .dictionary([
            "violationType": .string("PII_DETECTED"),
            "detectedPatterns": .array([.string("SSN"), .string("CREDIT_CARD")])
        ])

        // When
        let result = GuardrailResult.tripwire(message: message, outputInfo: outputInfo)

        // Then
        #expect(result.tripwireTriggered == true)
        #expect(result.message == message)
        #expect(result.outputInfo == outputInfo)
        #expect(result.metadata.isEmpty)
    }

    @Test("Tripwire result with all parameters")
    func tripwireResultWithAllParameters() {
        // Given
        let message = "Content filter triggered"
        let outputInfo: SendableValue = .string("Inappropriate content found")
        let metadata: [String: SendableValue] = [
            "severity": .string("high"),
            "category": .string("profanity")
        ]

        // When
        let result = GuardrailResult.tripwire(
            message: message,
            outputInfo: outputInfo,
            metadata: metadata
        )

        // Then
        #expect(result.tripwireTriggered == true)
        #expect(result.message == message)
        #expect(result.outputInfo == outputInfo)
        #expect(result.metadata == metadata)
    }

    // MARK: - Equatable Conformance Tests

    @Test("Two passed results with same values are equal")
    func equatablePassedResults() {
        // Given
        let result1 = GuardrailResult.passed(message: "test")
        let result2 = GuardrailResult.passed(message: "test")

        // Then
        #expect(result1 == result2)
    }

    @Test("Two tripwire results with same values are equal")
    func equatableTripwireResults() {
        // Given
        let outputInfo: SendableValue = .dictionary(["key": .string("value")])
        let result1 = GuardrailResult.tripwire(message: "error", outputInfo: outputInfo)
        let result2 = GuardrailResult.tripwire(message: "error", outputInfo: outputInfo)

        // Then
        #expect(result1 == result2)
    }

    @Test("Passed and tripwire results with same message are not equal")
    func equatableDifferentTripwireState() {
        // Given
        let message = "test message"
        let passed = GuardrailResult.passed(message: message)
        let tripwire = GuardrailResult.tripwire(message: message)

        // Then
        #expect(passed != tripwire)
    }

    @Test("Results with different messages are not equal")
    func equatableDifferentMessages() {
        // Given
        let result1 = GuardrailResult.passed(message: "message1")
        let result2 = GuardrailResult.passed(message: "message2")

        // Then
        #expect(result1 != result2)
    }

    @Test("Results with different outputInfo are not equal")
    func equatableDifferentOutputInfo() {
        // Given
        let result1 = GuardrailResult.passed(outputInfo: .string("info1"))
        let result2 = GuardrailResult.passed(outputInfo: .string("info2"))

        // Then
        #expect(result1 != result2)
    }

    @Test("Results with different metadata are not equal")
    func equatableDifferentMetadata() {
        // Given
        let metadata1: [String: SendableValue] = ["key": .string("value1")]
        let metadata2: [String: SendableValue] = ["key": .string("value2")]
        let result1 = GuardrailResult.passed(metadata: metadata1)
        let result2 = GuardrailResult.passed(metadata: metadata2)

        // Then
        #expect(result1 != result2)
    }

    // MARK: - Sendable Conformance Tests

    @Test("GuardrailResult is Sendable across async boundaries")
    func sendableInAsyncContext() async {
        // Given
        let result = GuardrailResult.passed(message: "test")

        // When - pass result across async boundary
        let receivedResult = await withCheckedContinuation { continuation in
            Task {
                continuation.resume(returning: result)
            }
        }

        // Then
        #expect(receivedResult == result)
        #expect(receivedResult.tripwireTriggered == false)
        #expect(receivedResult.message == "test")
    }

    @Test("GuardrailResult can be used in Task context")
    func sendableInTaskContext() async {
        // Given
        let outputInfo: SendableValue = .dictionary(["status": .string("checked")])
        let result = GuardrailResult.tripwire(message: "blocked", outputInfo: outputInfo)

        // When - use in Task
        let taskResult = await Task {
            result
        }.value

        // Then
        #expect(taskResult == result)
        #expect(taskResult.tripwireTriggered == true)
        #expect(taskResult.message == "blocked")
        #expect(taskResult.outputInfo == outputInfo)
    }

    @Test("GuardrailResult can be stored in actor")
    func sendableWithActor() async {
        // Given
        actor ResultStore {
            private var storedResult: GuardrailResult?

            func store(_ result: GuardrailResult) {
                storedResult = result
            }

            func retrieve() -> GuardrailResult? {
                storedResult
            }
        }

        let store = ResultStore()
        let result = GuardrailResult.passed(message: "stored")

        // When
        await store.store(result)
        let retrieved = await store.retrieve()

        // Then
        #expect(retrieved == result)
    }

    // MARK: - Edge Cases

    @Test("Result with nil message and nil outputInfo")
    func resultWithAllNils() {
        // When
        let result = GuardrailResult.passed(message: nil, outputInfo: nil)

        // Then
        #expect(result.tripwireTriggered == false)
        #expect(result.message == nil)
        #expect(result.outputInfo == nil)
        #expect(result.metadata.isEmpty)
    }

    @Test("Result with empty metadata dictionary")
    func resultWithEmptyMetadata() {
        // Given
        let emptyMetadata: [String: SendableValue] = [:]

        // When
        let result = GuardrailResult.passed(metadata: emptyMetadata)

        // Then
        #expect(result.metadata.isEmpty)
    }

    @Test("Result with complex nested outputInfo")
    func resultWithComplexOutputInfo() {
        // Given
        let complexInfo: SendableValue = .dictionary([
            "analysis": .dictionary([
                "score": .double(0.85),
                "flags": .array([.string("warning1"), .string("warning2")]),
                "metadata": .dictionary([
                    "model": .string("gpt-4"),
                    "version": .int(2)
                ])
            ]),
            "timestamp": .int(1_703_548_800)
        ])

        // When
        let result = GuardrailResult.tripwire(message: "Complex check", outputInfo: complexInfo)

        // Then
        #expect(result.outputInfo == complexInfo)
        #expect(result.tripwireTriggered == true)
    }

    @Test("Tripwire case always carries a message on the enum")
    func tripwireCaseMessageIsRequired() {
        let result = GuardrailResult.tripwire(message: "blocked")
        guard case let .tripwire(message, _, _) = result else {
            Issue.record("expected tripwire case")
            return
        }
        #expect(message == "blocked")
        #expect(result.message == "blocked")
    }

    @Test("Deprecated tripwire initializer fills a default message when nil")
    func deprecatedInitNilTripwireMessage() {
        let tripwire = GuardrailResult(tripwireTriggered: true)
        let passed = GuardrailResult(tripwireTriggered: false)
        #expect(tripwire.message == "Tripwire triggered")
        #expect(tripwire.tripwireTriggered)
        #expect(passed.message == nil)
        #expect(!passed.tripwireTriggered)
    }

    @Test("Passed and tripwire are distinct enum cases")
    func enumCasesAreExhaustivePair() {
        let passed = GuardrailResult.passed()
        let tripwire = GuardrailResult.tripwire(message: "blocked")
        var sawPassed = false
        var sawTripwire = false
        for result in [passed, tripwire] {
            switch result {
            case .passed:
                sawPassed = true
            case .tripwire:
                sawTripwire = true
            }
        }
        #expect(sawPassed)
        #expect(sawTripwire)
    }
}
