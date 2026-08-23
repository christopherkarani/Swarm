// BuiltinGuardPredicateTests.swift
// SwarmTests
//
// Exercises the built-in guards (notEmpty, maxLength, custom) as pure
// predicates at the protocol level, without constructing any AgentRuntime.

import Foundation
@testable import Swarm
import Testing

@Suite("Built-in Guard Predicates")
struct BuiltinGuardPredicateTests {
    // MARK: - InputGuard.notEmpty

    @Test("InputGuard.notEmpty trips empty and whitespace-only input")
    func notEmptyTripsOnBlankInput() async throws {
        let guardrail = InputGuard.notEmpty()

        #expect(guardrail.name == "NotEmptyGuardrail")

        for blank in ["", "   ", "\n\t "] {
            let result = try await guardrail.validate(blank, context: nil)
            #expect(result.tripwireTriggered)
            #expect(result.message == "Input cannot be empty")
        }
    }

    @Test("InputGuard.notEmpty passes input containing non-whitespace characters")
    func notEmptyPassesRealInput() async throws {
        let result = try await InputGuard.notEmpty().validate("  hello \n", context: nil)
        #expect(!result.tripwireTriggered)
    }

    // MARK: - InputGuard.maxLength

    @Test("InputGuard.maxLength passes at the limit and trips past it with metadata")
    func maxLengthBoundaryAndPayload() async throws {
        let guardrail = InputGuard.maxLength(5)

        #expect(guardrail.name == "MaxLengthGuardrail")

        let atLimit = try await guardrail.validate("12345", context: nil)
        #expect(!atLimit.tripwireTriggered)

        let overLimit = try await guardrail.validate("123456", context: nil)
        #expect(overLimit.tripwireTriggered)
        #expect(overLimit.message == "Input exceeds maximum length of 5")
        #expect(overLimit.metadata["length"]?.intValue == 6)
        #expect(overLimit.metadata["limit"]?.intValue == 5)
    }

    @Test("InputGuard.maxLength honors a custom name")
    func maxLengthCustomName() async throws {
        #expect(InputGuard.maxLength(10, name: "TweetLimit").name == "TweetLimit")
    }

    // MARK: - InputGuard.custom

    @Test("InputGuard.custom evaluates the provided closure")
    func customClosureEvaluation() async throws {
        let guardrail = InputGuard.custom("no_secrets") { input in
            input.contains("hunter2")
                ? .tripwire(message: "secret detected", outputInfo: .string(input))
                : .passed()
        }

        let clean = try await guardrail.validate("all good", context: nil)
        #expect(!clean.tripwireTriggered)

        let dirty = try await guardrail.validate("password is hunter2", context: nil)
        #expect(dirty.tripwireTriggered)
        #expect(dirty.message == "secret detected")
        #expect(dirty.outputInfo == .string("password is hunter2"))
    }

    // MARK: - OutputGuard.maxLength

    @Test("OutputGuard.maxLength passes within the limit and trips past it with metadata")
    func outputMaxLengthBoundaryAndPayload() async throws {
        let guardrail = OutputGuard.maxLength(4)

        #expect(guardrail.name == "MaxOutputLengthGuardrail")

        let atLimit = try await guardrail.evaluate("abcd")
        #expect(!atLimit.tripwireTriggered)

        let overLimit = try await guardrail.evaluate("abcde")
        #expect(overLimit.tripwireTriggered)
        #expect(overLimit.message == "Output exceeds maximum length of 4")
        #expect(overLimit.metadata["length"]?.intValue == 5)
        #expect(overLimit.metadata["limit"]?.intValue == 4)
    }

    @Test("OutputGuard.maxLength honors a custom name")
    func outputMaxLengthCustomName() async throws {
        #expect(OutputGuard.maxLength(280, name: "TwitterLimit").name == "TwitterLimit")
    }

    // MARK: - OutputGuard.custom

    @Test("OutputGuard.custom evaluates the provided closure")
    func outputCustomClosureEvaluation() async throws {
        let guardrail = OutputGuard.custom("no_phone_numbers") { output in
            output.hasPrefix("+") ? .tripwire(message: "phone number detected") : .passed()
        }

        let text = try await guardrail.evaluate("just words")
        #expect(!text.tripwireTriggered)

        let phone = try await guardrail.evaluate("+15551234567")
        #expect(phone.tripwireTriggered)
        #expect(phone.message == "phone number detected")
    }

    // MARK: - Protocol Extension Factories

    @Test("Protocol extension factories build heterogeneous guardrail arrays")
    func protocolExtensionFactories() {
        let inputs: [any InputGuardrail] = [.maxLength(10), .notEmpty()]
        #expect(inputs.map(\.name) == ["MaxLengthGuardrail", "NotEmptyGuardrail"])

        let outputs: [any OutputGuardrail] = [.maxLength(100)]
        #expect(outputs.map(\.name) == ["MaxOutputLengthGuardrail"])
    }
}
