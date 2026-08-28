// InputGuardrailTests.swift
// SwarmTests
//
// TDD tests for InputGuardrail protocol and implementations
// These tests define the contract before implementation

import Foundation
@testable import Swarm
import Testing

// MARK: - InputGuardrailTests

@Suite("InputGuardrail Tests")
struct InputGuardrailTests {
    // MARK: - Protocol Conformance Tests

    @Test("InputGuardrail protocol requires name property")
    func inputGuardrailProtocolNameRequirement() async throws {
        // Given
        struct TestGuardrail: InputGuardrail {
            let name: String
            func validate(_: String, context _: AgentContext?) async throws -> GuardrailResult {
                .passed()
            }
        }

        // When
        let guardrail = TestGuardrail(name: "TestGuardrail")

        // Then
        #expect(guardrail.name == "TestGuardrail")
    }

    @Test("InputGuardrail protocol requires validate method")
    func inputGuardrailProtocolValidateRequirement() async throws {
        // Given
        struct TestGuardrail: InputGuardrail {
            let name: String
            func validate(_: String, context _: AgentContext?) async throws -> GuardrailResult {
                .passed(message: "Validation passed")
            }
        }

        // When
        let guardrail = TestGuardrail(name: "Test")
        let result = try await guardrail.validate("test input", context: nil)

        // Then
        #expect(result.tripwireTriggered == false)
        #expect(result.message == "Validation passed")
    }

    @Test("InputGuardrail is Sendable across async boundaries")
    func inputGuardrailSendableConformance() async throws {
        // Given
        struct SendableTestGuardrail: InputGuardrail {
            let name: String
            func validate(_: String, context _: AgentContext?) async throws -> GuardrailResult {
                .passed()
            }
        }

        let guardrail = SendableTestGuardrail(name: "Sendable")

        // When - pass across async boundary
        let result = try await Task {
            try await guardrail.validate("test", context: nil)
        }.value

        // Then
        #expect(result.tripwireTriggered == false)
    }

    // MARK: - InputGuard Tests

    @Test("InputGuard initializes with name and handler")
    func inputGuardInitialization() {
        // When
        let guardrail = InputGuard("TestGuardrail") { _, _ in
            .passed()
        }

        // Then
        #expect(guardrail.name == "TestGuardrail")
    }

    @Test("InputGuard validates with passed result")
    func inputGuardPassedResult() async throws {
        // Given
        let guardrail = InputGuard("PassGuardrail") { _, _ in
            .passed(message: "Input is valid")
        }

        // When
        let result = try await guardrail.validate("test input", context: nil)

        // Then
        #expect(result.tripwireTriggered == false)
        #expect(result.message == "Input is valid")
    }

    @Test("InputGuard validates with tripwire result")
    func inputGuardTripwireResult() async throws {
        // Given
        let guardrail = InputGuard("TripwireGuardrail") { _, _ in
            .tripwire(message: "Sensitive data detected")
        }

        // When
        let result = try await guardrail.validate("SSN: 123-45-6789", context: nil)

        // Then
        #expect(result.tripwireTriggered == true)
        #expect(result.message == "Sensitive data detected")
    }

    @Test("InputGuard handler receives input")
    func inputGuardReceivesInput() async throws {
        // Given
        actor InputCapture {
            var value: String?
            func set(_ newValue: String) { value = newValue }
            func get() -> String? { value }
        }

        let capture = InputCapture()
        let guardrail = InputGuard("CaptureGuardrail") { input, _ in
            await capture.set(input)
            return .passed()
        }

        // When
        _ = try await guardrail.validate("test input", context: nil)

        // Then
        let capturedInput = await capture.get()
        #expect(capturedInput == "test input")
    }

    @Test("InputGuard handler receives context")
    func inputGuardReceivesContext() async throws {
        // Given
        let testContext = AgentContext(input: "test")
        await testContext.set("customKey", value: .string("original"))

        actor ContextCapture {
            var value: AgentContext?
            func set(_ newValue: AgentContext?) { value = newValue }
            func get() -> AgentContext? { value }
        }

        let capture = ContextCapture()
        let guardrail = InputGuard("ContextGuardrail") { _, context in
            await capture.set(context)
            return .passed()
        }

        // When
        _ = try await guardrail.validate("test", context: testContext)

        // Then
        let capturedContext = await capture.get()
        #expect(capturedContext != nil)
        let customValue = await capturedContext?.get("customKey")
        #expect(customValue?.stringValue == "original")
    }

    @Test("InputGuard works with nil context")
    func inputGuardWithNilContext() async throws {
        // Given
        actor ContextCapture {
            var value: AgentContext?
            var wasSet = false
            func set(_ newValue: AgentContext?) {
                value = newValue
                wasSet = true
            }

            func get() -> AgentContext? { value }
            func didSet() -> Bool { wasSet }
        }

        let capture = ContextCapture()
        let guardrail = InputGuard("NilContextGuardrail") { _, context in
            await capture.set(context)
            return .passed()
        }

        // When
        let result = try await guardrail.validate("test", context: nil)

        // Then
        let receivedContext = await capture.get()
        #expect(receivedContext == nil)
        #expect(result.tripwireTriggered == false)
    }

    @Test("InputGuard propagates errors from handler")
    func inputGuardThrowsError() async {
        // Given
        struct TestError: Error {}
        let guardrail = InputGuard("ErrorGuardrail") { _, _ in
            throw TestError()
        }

        // When/Then
        await #expect(throws: TestError.self) {
            _ = try await guardrail.validate("test", context: nil)
        }
    }

    @Test("InputGuard name property is accessible")
    func inputGuardNameProperty() {
        // Given
        let guardrail = InputGuard("NamedGuardrail") { _, _ in
            .passed()
        }

        // When
        let name = guardrail.name

        // Then
        #expect(name == "NamedGuardrail")
    }

    @Test("InputGuard supports concurrent validations")
    func inputGuardConcurrentExecution() async throws {
        // Given
        actor ValidationCounter {
            private var count = 0
            func increment() { count += 1 }
            func getCount() -> Int { count }
        }

        let counter = ValidationCounter()
        let guardrail = InputGuard("ConcurrentGuardrail") { _, _ in
            await counter.increment()
            return .passed()
        }

        // When - execute 10 concurrent validations
        try await withThrowingTaskGroup(of: GuardrailResult.self) { group in
            for i in 0..<10 {
                group.addTask {
                    try await guardrail.validate("input \(i)", context: nil)
                }
            }

            for try await _ in group {}
        }

        // Then
        let finalCount = await counter.getCount()
        #expect(finalCount == 10)
    }

    @Test("InputGuard returns outputInfo from handler")
    func inputGuardWithOutputInfo() async throws {
        // Given
        let outputInfo: SendableValue = .dictionary([
            "tokensChecked": .int(42),
            "category": .string("safe")
        ])

        let guardrail = InputGuard("InfoGuardrail") { _, _ in
            .passed(outputInfo: outputInfo)
        }

        // When
        let result = try await guardrail.validate("test", context: nil)

        // Then
        #expect(result.outputInfo == outputInfo)
    }

    @Test("InputGuard returns metadata from handler")
    func inputGuardWithMetadata() async throws {
        // Given
        let metadata: [String: SendableValue] = [
            "duration": .double(0.123),
            "version": .string("1.0")
        ]

        let guardrail = InputGuard("MetadataGuardrail") { _, _ in
            .passed(metadata: metadata)
        }

        // When
        let result = try await guardrail.validate("test", context: nil)

        // Then
        #expect(result.metadata == metadata)
    }

    // MARK: - InputGuard Direct Construction Tests

    @Test("InputGuard direct construction with name and handler")
    func inputGuardDirectConstructionBasic() throws {
        // When
        let guardrail = InputGuard("TestGuardrail") { _, _ in
            .passed()
        }

        // Then
        #expect(guardrail.name == "TestGuardrail")
    }

    @Test("InputGuard creates correct type")
    func inputGuardCreatesCorrectType() throws {
        // When
        let guardrail = InputGuard("TypeTest") { _, _ in .passed() }

        // Then
        let erased: any InputGuardrail = guardrail
        _ = erased
    }

    @Test("InputGuard preserves name")
    func inputGuardPreservesName() throws {
        // Given
        let expectedName = "PreservedName"

        // When
        let guardrail = InputGuard(expectedName) { _, _ in .passed() }

        // Then
        #expect(guardrail.name == expectedName)
    }

    @Test("InputGuard preserves handler")
    func inputGuardPreservesHandler() async throws {
        // Given
        let expectedMessage = "Handler preserved"

        // When
        let guardrail = InputGuard("Test") { _, _ in
            .passed(message: expectedMessage)
        }

        let result = try await guardrail.validate("test", context: nil)

        // Then
        #expect(result.message == expectedMessage)
    }

    // MARK: - Integration Tests

    @Test("Multiple guardrails execute sequentially")
    func multipleGuardrailsSequential() async throws {
        // Given
        actor ExecutionOrder {
            private var order: [String] = []
            func append(_ name: String) { order.append(name) }
            func getOrder() -> [String] { order }
        }

        let executionOrder = ExecutionOrder()

        let guardrail1 = InputGuard("First") { _, _ in
            await executionOrder.append("First")
            return .passed()
        }

        let guardrail2 = InputGuard("Second") { _, _ in
            await executionOrder.append("Second")
            return .passed()
        }

        let guardrail3 = InputGuard("Third") { _, _ in
            await executionOrder.append("Third")
            return .passed()
        }

        // When
        _ = try await guardrail1.validate("test", context: nil)
        _ = try await guardrail2.validate("test", context: nil)
        _ = try await guardrail3.validate("test", context: nil)

        // Then
        let order = await executionOrder.getOrder()
        #expect(order == ["First", "Second", "Third"])
    }

    @Test("Guardrail works with actor-isolated AgentContext")
    func guardrailWithActorContext() async throws {
        // Given
        let context = AgentContext(input: "test input")

        let guardrail = InputGuard("ContextGuardrail") { _, context in
            guard let ctx = context else {
                return .tripwire(message: "No context provided")
            }

            let originalInput: String? = await ctx.get(.originalInput)
            if originalInput == "test input" {
                return .passed(message: "Context verified")
            }

            return .tripwire(message: "Context mismatch")
        }

        // When
        let result = try await guardrail.validate("input", context: context)

        // Then
        #expect(result.tripwireTriggered == false)
        #expect(result.message == "Context verified")
    }

    @Test("Guardrail is Sendable in TaskGroup")
    func guardrailSendableInTaskGroup() async throws {
        // Given
        let guardrail = InputGuard("TaskGroupGuardrail") { input, _ in
            .passed(message: "Validated: \(input)")
        }

        // When
        let results = try await withThrowingTaskGroup(of: GuardrailResult.self) { group in
            for i in 0..<5 {
                group.addTask {
                    try await guardrail.validate("input-\(i)", context: nil)
                }
            }

            var collected: [GuardrailResult] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }

        // Then
        #expect(results.count == 5)
        #expect(results.allSatisfy { !$0.tripwireTriggered })
    }

    @Test("Guardrail can be stored in actor")
    func guardrailStoredInActor() async throws {
        // Given
        actor GuardrailStore {
            private var guardrails: [any InputGuardrail] = []

            func add(_ guardrail: any InputGuardrail) {
                guardrails.append(guardrail)
            }

            func execute(_ input: String, context: AgentContext?) async throws -> [GuardrailResult] {
                var results: [GuardrailResult] = []
                for guardrail in guardrails {
                    let result = try await guardrail.validate(input, context: context)
                    results.append(result)
                }
                return results
            }
        }

        let store = GuardrailStore()

        let guardrail1 = InputGuard("Guard1") { _, _ in
            .passed()
        }
        let guardrail2 = InputGuard("Guard2") { _, _ in
            .passed()
        }

        // When
        await store.add(guardrail1)
        await store.add(guardrail2)
        let results = try await store.execute("test", context: nil)

        // Then
        #expect(results.count == 2)
        #expect(results.allSatisfy { !$0.tripwireTriggered })
    }

    // MARK: - Edge Cases

    @Test("InputGuard handles empty input")
    func inputGuardEmptyInput() async throws {
        // Given
        actor InputCapture {
            var value: String?
            func set(_ newValue: String) { value = newValue }
            func get() -> String? { value }
        }

        let capture = InputCapture()
        let guardrail = InputGuard("EmptyInputGuardrail") { input, _ in
            await capture.set(input)
            return input.isEmpty ? .tripwire(message: "Empty input") : .passed()
        }

        // When
        let result = try await guardrail.validate("", context: nil)

        // Then
        let capturedInput = await capture.get()
        #expect(capturedInput?.isEmpty == true)
        #expect(result.tripwireTriggered == true)
        #expect(result.message == "Empty input")
    }

    @Test("InputGuard handles very long input")
    func inputGuardLongInput() async throws {
        // Given
        let longInput = String(repeating: "a", count: 10000)
        let guardrail = InputGuard("LongInputGuardrail") { input, _ in
            .passed(message: "Length: \(input.count)")
        }

        // When
        let result = try await guardrail.validate(longInput, context: nil)

        // Then
        #expect(result.tripwireTriggered == false)
        #expect(result.message == "Length: 10000")
    }

    @Test("InputGuard handles special characters in input")
    func inputGuardSpecialCharacters() async throws {
        // Given
        let specialInput = "Test with émojis 🎉 and symbols !@#$%^&*()"

        actor InputCapture {
            var value: String?
            func set(_ newValue: String) { value = newValue }
            func get() -> String? { value }
        }

        let capture = InputCapture()
        let guardrail = InputGuard("SpecialCharGuardrail") { input, _ in
            await capture.set(input)
            return .passed()
        }

        // When
        _ = try await guardrail.validate(specialInput, context: nil)

        // Then
        let capturedInput = await capture.get()
        #expect(capturedInput == specialInput)
    }
}
