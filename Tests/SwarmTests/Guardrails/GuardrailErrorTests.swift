// GuardrailErrorTests.swift
// SwarmTests
//
// TDD tests for GuardrailError - Sprint 1 of Guardrails system
// These tests define the contract for GuardrailError before implementation

import Foundation
@testable import Swarm
import Testing

// MARK: - GuardrailErrorTests

@Suite("GuardrailError Tests")
struct GuardrailErrorTests {
    // MARK: - Input Tripwire Tests

    @Test("Input tripwire error contains correct values")
    func testInputTripwireTriggered() {
        // Given
        let guardrailName = "PIIDetector"
        let message = "Personal information detected in input"
        let outputInfo: SendableValue = .dictionary([
            "detected": .array([.string("email"), .string("phone")])
        ])

        // When
        let error = GuardrailError.inputTripwireTriggered(
            guardrailName: guardrailName,
            message: message,
            outputInfo: outputInfo
        )

        // Then
        if case let .inputTripwireTriggered(name, msg, info) = error {
            #expect(name == guardrailName)
            #expect(msg == message)
            #expect(info == outputInfo)
        } else {
            Issue.record("Expected inputTripwireTriggered case")
        }
    }

    @Test("Input tripwire error with nil outputInfo")
    func inputTripwireWithNilOutputInfo() {
        // Given
        let guardrailName = "ContentFilter"
        let message = "Inappropriate content detected"

        // When
        let error = GuardrailError.inputTripwireTriggered(
            guardrailName: guardrailName,
            message: message,
            outputInfo: nil
        )

        // Then
        if case let .inputTripwireTriggered(name, msg, info) = error {
            #expect(name == guardrailName)
            #expect(msg == message)
            #expect(info == nil)
        } else {
            Issue.record("Expected inputTripwireTriggered case")
        }
    }

    @Test("Input tripwire error always includes a message")
    func inputTripwireMessageIsRequired() {
        let error = GuardrailError.inputTripwireTriggered(
            guardrailName: "Validator",
            message: "blocked",
            outputInfo: nil
        )

        if case let .inputTripwireTriggered(name, msg, _) = error {
            #expect(name == "Validator")
            #expect(msg == "blocked")
        } else {
            Issue.record("Expected inputTripwireTriggered case")
        }
    }

    // MARK: - Output Tripwire Tests

    @Test("Output tripwire error contains all associated values")
    func testOutputTripwireTriggered() {
        // Given
        let guardrailName = "ToxicityFilter"
        let agentName = "ChatAgent"
        let message = "Toxic content in agent output"
        let outputInfo: SendableValue = .dictionary([
            "toxicityScore": .double(0.92),
            "category": .string("hate_speech")
        ])

        // When
        let error = GuardrailError.outputTripwireTriggered(
            guardrailName: guardrailName,
            agentName: agentName,
            message: message,
            outputInfo: outputInfo
        )

        // Then
        if case let .outputTripwireTriggered(gName, aName, msg, info) = error {
            #expect(gName == guardrailName)
            #expect(aName == agentName)
            #expect(msg == message)
            #expect(info == outputInfo)
        } else {
            Issue.record("Expected outputTripwireTriggered case")
        }
    }

    @Test("Output tripwire error with nil outputInfo")
    func outputTripwireWithNilOutputInfo() {
        // Given
        let guardrailName = "OutputValidator"
        let agentName = "DataAgent"
        let message = "Validation failed"

        // When
        let error = GuardrailError.outputTripwireTriggered(
            guardrailName: guardrailName,
            agentName: agentName,
            message: message,
            outputInfo: nil
        )

        // Then
        if case let .outputTripwireTriggered(_, _, _, info) = error {
            #expect(info == nil)
        } else {
            Issue.record("Expected outputTripwireTriggered case")
        }
    }

    // MARK: - Tool Input Tripwire Tests

    @Test("Tool input tripwire error contains guardrailName and toolName")
    func testToolInputTripwireTriggered() {
        // Given
        let guardrailName = "ToolInputValidator"
        let toolName = "DatabaseQuery"
        let message = "SQL injection attempt detected"
        let outputInfo: SendableValue = .dictionary([
            "pattern": .string("DROP TABLE"),
            "severity": .string("critical")
        ])

        // When
        let error = GuardrailError.toolInputTripwireTriggered(
            guardrailName: guardrailName,
            toolName: toolName,
            message: message,
            outputInfo: outputInfo
        )

        // Then
        if case let .toolInputTripwireTriggered(gName, tName, msg, info) = error {
            #expect(gName == guardrailName)
            #expect(tName == toolName)
            #expect(msg == message)
            #expect(info == outputInfo)
        } else {
            Issue.record("Expected toolInputTripwireTriggered case")
        }
    }

    @Test("Tool input tripwire error with nil outputInfo")
    func toolInputTripwireWithNilOutputInfo() {
        // Given
        let guardrailName = "ToolGuard"
        let toolName = "FileSystem"
        let message = "Unauthorized file access"

        // When
        let error = GuardrailError.toolInputTripwireTriggered(
            guardrailName: guardrailName,
            toolName: toolName,
            message: message,
            outputInfo: nil
        )

        // Then
        if case let .toolInputTripwireTriggered(_, _, _, info) = error {
            #expect(info == nil)
        } else {
            Issue.record("Expected toolInputTripwireTriggered case")
        }
    }

    // MARK: - Tool Output Tripwire Tests

    @Test("Tool output tripwire error contains all values")
    func testToolOutputTripwireTriggered() {
        // Given
        let guardrailName = "ToolOutputFilter"
        let toolName = "WebSearch"
        let message = "Malicious URL in search results"
        let outputInfo: SendableValue = .dictionary([
            "blockedUrls": .array([
                .string("http://malicious.example.com")
            ]),
            "reason": .string("phishing_detected")
        ])

        // When
        let error = GuardrailError.toolOutputTripwireTriggered(
            guardrailName: guardrailName,
            toolName: toolName,
            message: message,
            outputInfo: outputInfo
        )

        // Then
        if case let .toolOutputTripwireTriggered(gName, tName, msg, info) = error {
            #expect(gName == guardrailName)
            #expect(tName == toolName)
            #expect(msg == message)
            #expect(info == outputInfo)
        } else {
            Issue.record("Expected toolOutputTripwireTriggered case")
        }
    }

    @Test("Tool output tripwire error with nil outputInfo")
    func toolOutputTripwireWithNilOutputInfo() {
        // Given
        let guardrailName = "OutputGuard"
        let toolName = "Calculator"
        let message = "Invalid output format"

        // When
        let error = GuardrailError.toolOutputTripwireTriggered(
            guardrailName: guardrailName,
            toolName: toolName,
            message: message,
            outputInfo: nil
        )

        // Then
        if case let .toolOutputTripwireTriggered(_, _, _, info) = error {
            #expect(info == nil)
        } else {
            Issue.record("Expected toolOutputTripwireTriggered case")
        }
    }

    // MARK: - Execution Failed Tests

    @Test("Execution failed error contains guardrailName and error message")
    func testExecutionFailed() {
        // Given
        let guardrailName = "AsyncGuardrail"
        let errorMessage = "Network timeout occurred"

        // When
        let error = GuardrailError.executionFailed(
            guardrailName: guardrailName,
            underlyingError: errorMessage
        )

        // Then
        if case let .executionFailed(name, message) = error {
            #expect(name == guardrailName)
            #expect(message == errorMessage)
        } else {
            Issue.record("Expected executionFailed case")
        }
    }

    @Test("Execution failed error with detailed error description")
    func executionFailedWithDetailedError() {
        // Given
        let guardrailName = "ValidatorGuardrail"
        let errorMessage = "Failed to connect to validation service: Connection refused (errno: 61)"

        // When
        let error = GuardrailError.executionFailed(
            guardrailName: guardrailName,
            underlyingError: errorMessage
        )

        // Then
        if case let .executionFailed(name, message) = error {
            #expect(name == guardrailName)
            #expect(message.contains("Connection refused"))
        } else {
            Issue.record("Expected executionFailed case")
        }
    }

    // MARK: - LocalizedError Conformance Tests

    @Test("Input tripwire error has descriptive errorDescription")
    func inputTripwireErrorDescription() {
        // Given
        let error = GuardrailError.inputTripwireTriggered(
            guardrailName: "TestGuard",
            message: "Input blocked",
            outputInfo: nil
        )

        // When
        let description = error.errorDescription

        // Then
        #expect(description != nil)
        #expect(description!.contains("TestGuard"))
        #expect(description!.contains("Input blocked"))
    }

    @Test("Input tripwire error description interpolates the required message")
    func inputTripwireErrorDescriptionIncludesMessage() {
        let error = GuardrailError.inputTripwireTriggered(
            guardrailName: "TestGuard",
            message: "blocked",
            outputInfo: nil
        )

        let description = error.errorDescription
        #expect(description != nil)
        #expect(description!.contains("TestGuard"))
        #expect(description!.contains("blocked"))
        #expect(!(description!.contains("No message")))
    }

    @Test("Output tripwire error has descriptive errorDescription")
    func outputTripwireErrorDescription() {
        // Given
        let error = GuardrailError.outputTripwireTriggered(
            guardrailName: "OutputGuard",
            agentName: "MyAgent",
            message: "Output blocked",
            outputInfo: nil
        )

        // When
        let description = error.errorDescription

        // Then
        #expect(description != nil)
        #expect(description!.contains("OutputGuard"))
        #expect(description!.contains("MyAgent"))
        #expect(description!.contains("Output blocked"))
    }

    @Test("Tool input tripwire error has descriptive errorDescription")
    func toolInputTripwireErrorDescription() {
        // Given
        let error = GuardrailError.toolInputTripwireTriggered(
            guardrailName: "ToolGuard",
            toolName: "SearchTool",
            message: "Tool input blocked",
            outputInfo: nil
        )

        // When
        let description = error.errorDescription

        // Then
        #expect(description != nil)
        #expect(description!.contains("ToolGuard"))
        #expect(description!.contains("SearchTool"))
        #expect(description!.contains("Tool input blocked"))
    }

    @Test("Tool output tripwire error has descriptive errorDescription")
    func toolOutputTripwireErrorDescription() {
        // Given
        let error = GuardrailError.toolOutputTripwireTriggered(
            guardrailName: "OutputFilter",
            toolName: "WebTool",
            message: "Tool output blocked",
            outputInfo: nil
        )

        // When
        let description = error.errorDescription

        // Then
        #expect(description != nil)
        #expect(description!.contains("OutputFilter"))
        #expect(description!.contains("WebTool"))
        #expect(description!.contains("Tool output blocked"))
    }

    @Test("Execution failed error has descriptive errorDescription")
    func executionFailedErrorDescription() {
        // Given
        let errorMessage = "Test failure occurred"
        let error = GuardrailError.executionFailed(
            guardrailName: "AsyncGuard",
            underlyingError: errorMessage
        )

        // When
        let description = error.errorDescription

        // Then
        #expect(description != nil)
        #expect(description!.contains("AsyncGuard"))
        #expect(description!.contains("Test failure"))
    }
}

// MARK: - GuardrailErrorTests Sendable and Edge Cases

extension GuardrailErrorTests {
    // MARK: - Sendable Conformance Tests

    @Test("GuardrailError is Sendable across async boundaries")
    func sendableInAsyncContext() async {
        // Given
        let error = GuardrailError.inputTripwireTriggered(
            guardrailName: "TestGuard",
            message: "Test error",
            outputInfo: .string("info")
        )

        // When - pass error across async boundary
        let receivedError = await withCheckedContinuation { continuation in
            Task {
                continuation.resume(returning: error)
            }
        }

        // Then
        if case let .inputTripwireTriggered(name1, msg1, info1) = error,
           case let .inputTripwireTriggered(name2, msg2, info2) = receivedError {
            #expect(name1 == name2)
            #expect(msg1 == msg2)
            #expect(info1 == info2)
        } else {
            Issue.record("Error cases don't match")
        }
    }

    @Test("GuardrailError can be thrown across async boundaries")
    func sendableErrorThrown() async {
        // Given
        func throwingFunction() async throws -> String {
            throw GuardrailError.inputTripwireTriggered(
                guardrailName: "Guard",
                message: "Blocked",
                outputInfo: nil
            )
        }

        // When/Then
        do {
            _ = try await throwingFunction()
            Issue.record("Should have thrown error")
        } catch let error as GuardrailError {
            if case let .inputTripwireTriggered(name, msg, _) = error {
                #expect(name == "Guard")
                #expect(msg == "Blocked")
            } else {
                Issue.record("Wrong error case")
            }
        } catch {
            Issue.record("Wrong error type")
        }
    }

    @Test("GuardrailError can be stored in actor")
    func sendableWithActor() async {
        // Given
        actor ErrorStore {
            private var storedError: GuardrailError?

            func store(_ error: GuardrailError) {
                storedError = error
            }

            func retrieve() -> GuardrailError? {
                storedError
            }
        }

        let store = ErrorStore()
        let error = GuardrailError.outputTripwireTriggered(
            guardrailName: "Guard",
            agentName: "Agent",
            message: "Error",
            outputInfo: nil
        )

        // When
        await store.store(error)
        let retrieved = await store.retrieve()

        // Then
        #expect(retrieved != nil)
        if case let .outputTripwireTriggered(gName1, aName1, msg1, _) = error,
           case let .outputTripwireTriggered(gName2, aName2, msg2, _) = retrieved! {
            #expect(gName1 == gName2)
            #expect(aName1 == aName2)
            #expect(msg1 == msg2)
        } else {
            Issue.record("Error cases don't match")
        }
    }

    // MARK: - Edge Cases

    @Test("Error with empty message string")
    func errorWithEmptyMessage() {
        // Given
        let error = GuardrailError.inputTripwireTriggered(
            guardrailName: "Guard",
            message: "",
            outputInfo: nil
        )

        // Then
        if case let .inputTripwireTriggered(_, msg, _) = error {
            #expect(msg.isEmpty)
        } else {
            Issue.record("Expected inputTripwireTriggered case")
        }
    }

    @Test("Error with complex nested outputInfo")
    func errorWithComplexOutputInfo() {
        // Given
        let complexInfo: SendableValue = .dictionary([
            "violations": .array([
                .dictionary([
                    "type": .string("PII"),
                    "location": .int(42)
                ]),
                .dictionary([
                    "type": .string("TOXIC"),
                    "score": .double(0.95)
                ])
            ])
        ])

        // When
        let error = GuardrailError.inputTripwireTriggered(
            guardrailName: "MultiCheck",
            message: "Multiple violations",
            outputInfo: complexInfo
        )

        // Then
        if case let .inputTripwireTriggered(_, _, info) = error {
            #expect(info == complexInfo)
        } else {
            Issue.record("Expected inputTripwireTriggered case")
        }
    }

    @Test("All error cases have unique patterns")
    func allErrorCasesUnique() {
        // Given
        let errors: [GuardrailError] = [
            .inputTripwireTriggered(guardrailName: "G1", message: "M1", outputInfo: nil),
            .outputTripwireTriggered(guardrailName: "G2", agentName: "A1", message: "M2", outputInfo: nil),
            .toolInputTripwireTriggered(guardrailName: "G3", toolName: "T1", message: "M3", outputInfo: nil),
            .toolOutputTripwireTriggered(guardrailName: "G4", toolName: "T2", message: "M4", outputInfo: nil),
            .executionFailed(guardrailName: "G5", underlyingError: "Test error")
        ]

        // Then - each should have a unique error description
        let descriptions = errors.compactMap(\.errorDescription)
        #expect(descriptions.count == 5)

        // Verify we can distinguish between cases
        var caseNames: Set<String> = []
        for error in errors {
            switch error {
            case .inputTripwireTriggered: caseNames.insert("input")
            case .outputTripwireTriggered: caseNames.insert("output")
            case .toolInputTripwireTriggered: caseNames.insert("toolInput")
            case .toolOutputTripwireTriggered: caseNames.insert("toolOutput")
            case .executionFailed: caseNames.insert("executionFailed")
            }
        }
        #expect(caseNames.count == 5)
    }
}
