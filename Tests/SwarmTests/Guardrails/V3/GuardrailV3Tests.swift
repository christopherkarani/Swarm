// GuardrailV3Tests.swift
// Tests for the unified V3 Guardrail enum.

import Testing
@testable import Swarm

@Suite("V3 Guardrail enum")
struct GuardrailV3Tests {
    @Test("maxInput factory holds correct limit")
    func maxInput() {
        let g: GuardrailV3 = .maxInput(500)
        if case .maxInput(let limit) = g {
            #expect(limit == 500)
        } else {
            Issue.record("Expected .maxInput")
        }
    }

    @Test("maxOutput factory holds correct limit")
    func maxOutput() {
        let g: GuardrailV3 = .maxOutput(5000)
        if case .maxOutput(let limit) = g {
            #expect(limit == 5000)
        } else {
            Issue.record("Expected .maxOutput")
        }
    }

    @Test("inputNotEmpty case")
    func inputNotEmpty() {
        let g: GuardrailV3 = .inputNotEmpty
        if case .inputNotEmpty = g { /* pass */ }
        else { Issue.record("Expected .inputNotEmpty") }
    }

    @Test("inputCustom holds name and handler")
    func inputCustom() async throws {
        let g: GuardrailV3 = .inputCustom("PII filter") { input in
            input.contains("SSN") ? .tripwire(message: "PII detected") : .passed()
        }
        if case .inputCustom(let name, _) = g {
            #expect(name == "PII filter")
        } else {
            Issue.record("Expected .inputCustom")
        }
    }

    @Test("outputCustom holds name and handler")
    func outputCustom() async throws {
        let g: GuardrailV3 = .outputCustom("Length check") { output in
            output.count > 100 ? .tripwire(message: "Too long") : .passed()
        }
        if case .outputCustom(let name, _) = g {
            #expect(name == "Length check")
        } else {
            Issue.record("Expected .outputCustom")
        }
    }

    // MARK: - validate() tests

    @Test("validate maxInput passes for short input")
    func validateMaxInputPasses() async throws {
        let g: GuardrailV3 = .maxInput(10)
        let result = try await g.validate("short")
        #expect(!result.tripwireTriggered)
    }

    @Test("validate maxInput trips for long input")
    func validateMaxInputTrips() async throws {
        let g: GuardrailV3 = .maxInput(5)
        let result = try await g.validate("this is too long")
        #expect(result.tripwireTriggered)
    }

    @Test("validate inputNotEmpty trips for empty string")
    func validateInputNotEmptyTrips() async throws {
        let g: GuardrailV3 = .inputNotEmpty
        let result = try await g.validate("   ")
        #expect(result.tripwireTriggered)
    }

    @Test("validate inputNotEmpty passes for non-empty string")
    func validateInputNotEmptyPasses() async throws {
        let g: GuardrailV3 = .inputNotEmpty
        let result = try await g.validate("hello")
        #expect(!result.tripwireTriggered)
    }

    @Test("validate custom input guardrail")
    func validateCustomInput() async throws {
        let g: GuardrailV3 = .inputCustom("SSN check") { input in
            input.contains("SSN") ? .tripwire(message: "PII") : .passed()
        }
        let pass = try await g.validate("hello")
        #expect(!pass.tripwireTriggered)

        let fail = try await g.validate("my SSN is 123")
        #expect(fail.tripwireTriggered)
    }
}
