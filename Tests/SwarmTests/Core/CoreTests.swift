// CoreTests.swift
// SwarmTests
//
// Tests for core types: SendableValue, AgentConfiguration, and AgentError
// NOTE: Full tests pending Phase 1 completion

import Foundation
@testable import Swarm
import Testing

// MARK: - SendableValueTests

@Suite("SendableValue Tests")
struct SendableValueTests {
    @Test("Literal initialization")
    func literalInitialization() {
        let nullValue: SendableValue = nil
        let boolValue: SendableValue = true
        let intValue: SendableValue = 42
        let doubleValue: SendableValue = 3.14
        let stringValue: SendableValue = "hello"

        #expect(nullValue == .null)
        #expect(boolValue == .bool(true))
        #expect(intValue == .int(42))
        #expect(doubleValue == .double(3.14))
        #expect(stringValue == .string("hello"))
    }

    @Test("Type-safe accessors")
    func typeSafeAccessors() {
        let intVal: SendableValue = .int(42)
        let doubleVal: SendableValue = .double(3.14)
        let stringVal: SendableValue = .string("hello")
        let boolVal: SendableValue = .bool(true)

        #expect(intVal.intValue == 42)
        #expect(doubleVal.doubleValue == 3.14)
        #expect(stringVal.stringValue == "hello")
        #expect(boolVal.boolValue == true)
    }

    @Test("Codable conformance")
    func codableConformance() throws {
        let original: SendableValue = [
            "string": "hello",
            "number": 42,
            "bool": true
        ]

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(SendableValue.self, from: data)

        #expect(decoded == original)
    }

    // MARK: - New Tests: Subscript Access

    @Test("Subscript dictionary access")
    func subscriptDictionaryAccess() {
        let dict: SendableValue = [
            "name": "Alice",
            "age": 30,
            "active": true
        ]

        #expect(dict["name"] == .string("Alice"))
        #expect(dict["age"] == .int(30))
        #expect(dict["active"] == .bool(true))
        #expect(dict["missing"] == nil)
    }

    @Test("Subscript array access")
    func subscriptArrayAccess() {
        let array: SendableValue = [.int(1), .int(2), .int(3)]

        // Valid indices
        #expect(array[0] == .int(1))
        #expect(array[1] == .int(2))
        #expect(array[2] == .int(3))

        // Invalid indices
        #expect(array[-1] == nil)
        #expect(array[3] == nil)
        #expect(array[100] == nil)
    }

    @Test("Subscript returns nil for wrong type")
    func subscriptReturnsNilForWrongType() {
        let dict: SendableValue = ["key": "value"]
        let array: SendableValue = [.int(1), .int(2)]
        let string: SendableValue = "hello"

        // Dictionary subscript on non-dictionary
        #expect(array["key"] == nil)
        #expect(string["key"] == nil)

        // Array subscript on non-array
        #expect(dict[0] == nil)
        #expect(string[0] == nil)
    }

    // MARK: - New Tests: Hashable Conformance

    @Test("Hashable conformance")
    func hashableConformance() {
        let value1: SendableValue = .string("hello")
        let value2: SendableValue = .string("hello")
        let value3: SendableValue = .string("world")

        // Can be used in Set
        let set: Set<SendableValue> = [value1, value2, value3]
        #expect(set.count == 2) // value1 and value2 are equal
        #expect(set.contains(value1))
        #expect(set.contains(value3))

        // Can be used as dictionary key
        let dict: [SendableValue: String] = [
            .int(1): "one",
            .int(2): "two",
            .string("key"): "value"
        ]
        #expect(dict[.int(1)] == "one")
        #expect(dict[.string("key")] == "value")
    }
}

// MARK: - AgentConfigurationTests

@Suite("AgentConfiguration Tests")
struct AgentConfigurationTests {
    @Test("Default configuration")
    func defaultConfiguration() {
        let config = AgentConfiguration.default

        #expect(config.maxIterations == 10)
        #expect(config.timeout == .seconds(60))
        #expect(config.temperature == 1.0)
        #expect(config.foundationModelsExecution == .capture)
        #expect(config.resilience == .disabled)
        #expect(config.resilience.retryPolicy == .noRetry)
    }

    @Test("Native session execution is opt-in and does not mutate capture default")
    func nativeSessionExecutionIsOptIn() {
        let original = AgentConfiguration.default
        let native = original.foundationModelsExecution(.nativeSession)

        #expect(original.foundationModelsExecution == .capture)
        #expect(native.foundationModelsExecution == .nativeSession)
        #expect(native.maxIterations == original.maxIterations)
    }

    @Test("Custom initialization")
    func customInitialization() {
        let config = AgentConfiguration(
            maxIterations: 5,
            timeout: .seconds(30),
            temperature: 0.5
        )

        #expect(config.maxIterations == 5)
        #expect(config.timeout == .seconds(30))
        #expect(config.temperature == 0.5)
    }

    // MARK: - New Tests: Fluent Builder Methods

    @Test("Fluent maxIterations")
    func fluentMaxIterations() {
        let config = AgentConfiguration.default.maxIterations(15)

        #expect(config.maxIterations == 15)
        // Other properties unchanged
        #expect(config.timeout == .seconds(60))
        #expect(config.temperature == 1.0)
    }

    @Test("Fluent timeout")
    func fluentTimeout() {
        let config = AgentConfiguration.default.timeout(.seconds(120))

        #expect(config.timeout == .seconds(120))
        // Other properties unchanged
        #expect(config.maxIterations == 10)
        #expect(config.temperature == 1.0)
    }

    @Test("Fluent temperature")
    func fluentTemperature() {
        let config = AgentConfiguration.default.temperature(0.7)

        #expect(config.temperature == 0.7)
        // Other properties unchanged
        #expect(config.maxIterations == 10)
        #expect(config.timeout == .seconds(60))
    }

    @Test("Fluent method chaining")
    func fluentMethodChaining() {
        let config = AgentConfiguration.default
            .maxIterations(20)
            .timeout(.seconds(180))
            .temperature(0.5)
            .maxTokens(1000)
            .stopSequences(["STOP", "END"])
            .enableStreaming(false)
            .includeToolCallDetails(false)
            .stopOnToolError(true)
            .includeReasoning(false)

        #expect(config.maxIterations == 20)
        #expect(config.timeout == .seconds(180))
        #expect(config.temperature == 0.5)
        #expect(config.maxTokens == 1000)
        #expect(config.stopSequences == ["STOP", "END"])
        #expect(config.enableStreaming == false)
        #expect(config.includeToolCallDetails == false)
        #expect(config.stopOnToolError == true)
        #expect(config.includeReasoning == false)
    }

    @Test("Fluent does not mutate original")
    func fluentDoesNotMutateOriginal() {
        let original = AgentConfiguration.default
        let modified = original
            .maxIterations(20)
            .temperature(0.5)

        // Original unchanged (value semantics)
        #expect(original.maxIterations == 10)
        #expect(original.temperature == 1.0)

        // Modified has new values
        #expect(modified.maxIterations == 20)
        #expect(modified.temperature == 0.5)
    }

    @Test("Invalid initializer inputs are coerced to safe defaults")
    func invalidInputsAreCoerced() {
        let config = AgentConfiguration(
            maxIterations: 0,
            timeout: .zero,
            temperature: .infinity
        )

        #expect(config.maxIterations == 1)
        #expect(config.timeout == .seconds(60))
        #expect(config.temperature == 1.0)
    }
}

// MARK: - InferencePolicyTests

@Suite("InferencePolicy Tests")
struct InferencePolicyTests {
    @Test("Invalid token budget is dropped instead of crashing")
    func invalidTokenBudgetIsDropped() {
        let policy = InferencePolicy(tokenBudget: 0)
        #expect(policy.tokenBudget == nil)
    }
}

// MARK: - AgentErrorTests

@Suite("AgentError Tests")
struct AgentErrorTests {
    @Test("Error descriptions exist")
    func errorDescriptions() {
        let errors: [AgentError] = [
            .invalidInput(reason: "empty"),
            .cancelled,
            .maxIterationsExceeded(iterations: 10),
            .toolNotFound(name: "missing_tool"),
        ]

        for error in errors {
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test("Equatable conformance")
    func equatableConformance() {
        let error1 = AgentError.toolNotFound(name: "test")
        let error2 = AgentError.toolNotFound(name: "test")
        let error3 = AgentError.toolNotFound(name: "other")

        #expect(error1 == error2)
        #expect(error1 != error3)
    }

    // MARK: - New Tests: All Error Cases

    @Test("invalidInput error")
    func invalidInputError() {
        let error = AgentError.invalidInput(reason: "empty query")

        #expect(error.localizedDescription.contains("Invalid input"))
        #expect(error.localizedDescription.contains("empty query"))

        // Test equatability with associated value
        let error2 = AgentError.invalidInput(reason: "empty query")
        let error3 = AgentError.invalidInput(reason: "different")
        #expect(error == error2)
        #expect(error != error3)
    }

    @Test("cancelled error")
    func cancelledError() {
        let error = AgentError.cancelled

        #expect(error.localizedDescription.contains("cancelled"))

        // Test equatability (no associated value)
        let error2 = AgentError.cancelled
        #expect(error == error2)
    }

    @Test("maxIterationsExceeded error")
    func maxIterationsExceededError() {
        let error = AgentError.maxIterationsExceeded(iterations: 15)

        #expect(error.localizedDescription.contains("exceeded"))
        #expect(error.localizedDescription.contains("15"))

        // Test equatability with associated value
        let error2 = AgentError.maxIterationsExceeded(iterations: 15)
        let error3 = AgentError.maxIterationsExceeded(iterations: 20)
        #expect(error == error2)
        #expect(error != error3)
    }

    @Test("timeout error")
    func timeoutError() {
        let error = AgentError.timeout(duration: .seconds(120))

        #expect(error.localizedDescription.contains("timed out"))
        #expect(error.localizedDescription.contains("120"))

        // Test equatability with Duration
        let error2 = AgentError.timeout(duration: .seconds(120))
        let error3 = AgentError.timeout(duration: .seconds(60))
        #expect(error == error2)
        #expect(error != error3)
    }

    @Test("toolNotFound error")
    func toolNotFoundError() {
        let error = AgentError.toolNotFound(name: "search_tool")

        #expect(error.localizedDescription.contains("Tool not found"))
        #expect(error.localizedDescription.contains("search_tool"))

        // Test equatability
        let error2 = AgentError.toolNotFound(name: "search_tool")
        let error3 = AgentError.toolNotFound(name: "other_tool")
        #expect(error == error2)
        #expect(error != error3)
    }

    @Test("toolExecutionFailed error")
    func toolExecutionFailedError() {
        let error = AgentError.toolExecutionFailed(
            toolName: "calculator",
            underlyingError: "division by zero"
        )

        #expect(error.localizedDescription.contains("calculator"))
        #expect(error.localizedDescription.contains("failed"))
        #expect(error.localizedDescription.contains("division by zero"))

        // Test equatability with both associated values
        let error2 = AgentError.toolExecutionFailed(
            toolName: "calculator",
            underlyingError: "division by zero"
        )
        let error3 = AgentError.toolExecutionFailed(
            toolName: "calculator",
            underlyingError: "overflow"
        )
        #expect(error == error2)
        #expect(error != error3)
    }

    @Test("invalidToolArguments error")
    func invalidToolArgumentsError() {
        let error = AgentError.invalidToolArguments(
            toolName: "search",
            reason: "missing query parameter"
        )

        #expect(error.localizedDescription.contains("Invalid arguments"))
        #expect(error.localizedDescription.contains("search"))
        #expect(error.localizedDescription.contains("missing query parameter"))

        // Test equatability
        let error2 = AgentError.invalidToolArguments(
            toolName: "search",
            reason: "missing query parameter"
        )
        let error3 = AgentError.invalidToolArguments(
            toolName: "search",
            reason: "invalid type"
        )
        #expect(error == error2)
        #expect(error != error3)
    }

    @Test("inferenceProviderUnavailable error")
    func inferenceProviderUnavailableError() {
        let error = AgentError.inferenceProviderUnavailable(reason: "model not loaded")

        #expect(error.localizedDescription.contains("Inference provider unavailable"))
        #expect(error.localizedDescription.contains("model not loaded"))

        // Test equatability
        let error2 = AgentError.inferenceProviderUnavailable(reason: "model not loaded")
        let error3 = AgentError.inferenceProviderUnavailable(reason: "network error")
        #expect(error == error2)
        #expect(error != error3)
    }

    @Test("contextWindowExceeded error")
    func contextWindowExceededError() {
        let error = AgentError.contextWindowExceeded(tokenCount: 5000, limit: 4096)

        #expect(error.localizedDescription.contains("Context window exceeded"))
        #expect(error.localizedDescription.contains("5000"))
        #expect(error.localizedDescription.contains("4096"))

        // Test equatability with both values
        let error2 = AgentError.contextWindowExceeded(tokenCount: 5000, limit: 4096)
        let error3 = AgentError.contextWindowExceeded(tokenCount: 3000, limit: 4096)
        #expect(error == error2)
        #expect(error != error3)
    }

    @Test("guardrailViolation error")
    func guardrailViolationError() {
        let error = AgentError.guardrailViolation(reason: "harmful content detected")

        #expect(error.localizedDescription.contains("violated content guidelines"))
        #expect(error.localizedDescription.contains("harmful content detected"))

        // Test equatability
        let error2 = AgentError.guardrailViolation(reason: "harmful content detected")
        let error3 = AgentError.guardrailViolation(reason: "different reason")
        #expect(error == error2)
        #expect(error != error3)
    }

    @Test("unsupportedLanguage error")
    func unsupportedLanguageError() {
        let error = AgentError.unsupportedLanguage(language: "Klingon")

        #expect(error.localizedDescription.contains("Language not supported"))
        #expect(error.localizedDescription.contains("Klingon"))

        // Test equatability
        let error2 = AgentError.unsupportedLanguage(language: "Klingon")
        let error3 = AgentError.unsupportedLanguage(language: "Elvish")
        #expect(error == error2)
        #expect(error != error3)
    }

    @Test("generationFailed error")
    func generationFailedError() {
        let error = AgentError.generationFailed(reason: "token limit exceeded")

        #expect(error.localizedDescription.contains("Generation failed"))
        #expect(error.localizedDescription.contains("token limit exceeded"))

        // Test equatability
        let error2 = AgentError.generationFailed(reason: "token limit exceeded")
        let error3 = AgentError.generationFailed(reason: "model crashed")
        #expect(error == error2)
        #expect(error != error3)
    }

    @Test("internalError error")
    func internalErrorError() {
        let error = AgentError.internalError(reason: "unexpected state")

        #expect(error.localizedDescription.contains("Internal error"))
        #expect(error.localizedDescription.contains("unexpected state"))

        // Test equatability
        let error2 = AgentError.internalError(reason: "unexpected state")
        let error3 = AgentError.internalError(reason: "memory corruption")
        #expect(error == error2)
        #expect(error != error3)
    }

    @Test("All error cases have non-empty descriptions")
    func allErrorCasesHaveDescriptions() {
        let allErrors: [AgentError] = [
            .invalidInput(reason: "test"),
            .cancelled,
            .maxIterationsExceeded(iterations: 10),
            .timeout(duration: .seconds(60)),
            .toolNotFound(name: "test"),
            .toolExecutionFailed(toolName: "test", underlyingError: "error"),
            .invalidToolArguments(toolName: "test", reason: "reason"),
            .inferenceProviderUnavailable(reason: "test"),
            .contextWindowExceeded(tokenCount: 1000, limit: 500),
            .guardrailViolation(reason: "test"),
            .contentFiltered(reason: "test"),
            .unsupportedLanguage(language: "test"),
            .generationFailed(reason: "test"),
            .modelNotAvailable(model: "test-model"),
            .rateLimitExceeded(retryAfter: 60.0),
            .rateLimitExceeded(retryAfter: nil),
            .embeddingFailed(reason: "test"),
            .internalError(reason: "test"),
            .toolCallingUnsupported
        ]

        for error in allErrors {
            #expect(!error.localizedDescription.isEmpty)
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test("Different error cases are not equal")
    func differentErrorCasesNotEqual() {
        let error1 = AgentError.cancelled
        let error2 = AgentError.guardrailViolation(reason: "test")
        let error3 = AgentError.invalidInput(reason: "test")
        let error4 = AgentError.toolNotFound(name: "test")

        #expect(error1 != error2)
        #expect(error1 != error3)
        #expect(error1 != error4)
        #expect(error2 != error3)
        #expect(error2 != error4)
        #expect(error3 != error4)
    }

    @Test("contentFiltered error")
    func contentFilteredError() {
        let error = AgentError.contentFiltered(reason: "explicit content")

        #expect(error.localizedDescription.contains("Content filtered"))
        #expect(error.localizedDescription.contains("explicit content"))

        // Test equatability
        let error2 = AgentError.contentFiltered(reason: "explicit content")
        let error3 = AgentError.contentFiltered(reason: "different reason")
        #expect(error == error2)
        #expect(error != error3)
    }

    @Test("rateLimitExceeded error with retry after")
    func rateLimitExceededWithRetryError() {
        let error = AgentError.rateLimitExceeded(retryAfter: 30.0)

        #expect(error.localizedDescription.contains("Rate limit exceeded"))
        #expect(error.localizedDescription.contains("30"))

        // Test equatability
        let error2 = AgentError.rateLimitExceeded(retryAfter: 30.0)
        let error3 = AgentError.rateLimitExceeded(retryAfter: 60.0)
        #expect(error == error2)
        #expect(error != error3)
    }

    @Test("rateLimitExceeded error without retry after")
    func rateLimitExceededWithoutRetryError() {
        let error = AgentError.rateLimitExceeded(retryAfter: nil)

        #expect(error.localizedDescription.contains("Rate limit exceeded"))

        // Test equatability
        let error2 = AgentError.rateLimitExceeded(retryAfter: nil)
        let error3 = AgentError.rateLimitExceeded(retryAfter: 30.0)
        #expect(error == error2)
        #expect(error != error3)
    }

    @Test("modelNotAvailable error")
    func modelNotAvailableError() {
        let error = AgentError.modelNotAvailable(model: "gpt-5-turbo")

        #expect(error.localizedDescription.contains("Model not available"))
        #expect(error.localizedDescription.contains("gpt-5-turbo"))

        // Test equatability
        let error2 = AgentError.modelNotAvailable(model: "gpt-5-turbo")
        let error3 = AgentError.modelNotAvailable(model: "claude-4")
        #expect(error == error2)
        #expect(error != error3)
    }

    @Test("embeddingFailed error")
    func embeddingFailedError() {
        let error = AgentError.embeddingFailed(reason: "invalid vector dimensions")

        #expect(error.localizedDescription.contains("Embedding failed"))
        #expect(error.localizedDescription.contains("invalid vector dimensions"))

        // Test equatability
        let error2 = AgentError.embeddingFailed(reason: "invalid vector dimensions")
        let error3 = AgentError.embeddingFailed(reason: "service unavailable")
        #expect(error == error2)
        #expect(error != error3)
    }
}

// MARK: - CoreTypesPendingTests

@Suite("Core Types - Phase 1")
struct CoreTypesPendingTests {
    @Test("ToolCall and ToolResult")
    func toolCallAndResult() {
        // Test ToolCall creation
        let toolCall = ToolCall(
            toolName: "test_tool",
            arguments: ["key": .string("value")]
        )

        #expect(toolCall.toolName == "test_tool")
        #expect(toolCall.arguments["key"] == .string("value"))
        #expect(toolCall.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)

        // Test ToolResult.success
        let successResult = ToolResult.success(
            callId: toolCall.id,
            output: .string("result"),
            duration: .seconds(1)
        )

        #expect(successResult.isSuccess == true)
        #expect(successResult.output == .string("result"))
        #expect(successResult.callId == toolCall.id)
        #expect(successResult.duration == .seconds(1))
        #expect(successResult.errorMessage == nil)

        // Test ToolResult.failure
        let failureResult = ToolResult.failure(
            callId: toolCall.id,
            error: "error message",
            duration: .seconds(1)
        )

        #expect(failureResult.isSuccess == false)
        #expect(failureResult.errorMessage == "error message")
        #expect(failureResult.callId == toolCall.id)
        #expect(failureResult.duration == .seconds(1))
        #expect(failureResult.output == .null)
    }

    @Test("AgentResult builder")
    func agentResultBuilder() {
        // Create and configure the builder
        let builder = AgentResult.Builder()
        _ = builder.start()
        _ = builder.setOutput("test output")

        // Create and add a tool call
        let toolCall = ToolCall(
            toolName: "test_tool",
            arguments: ["key": .string("value")]
        )
        _ = builder.addToolCall(toolCall)

        // Create and add a tool result
        let toolResult = ToolResult.success(
            callId: toolCall.id,
            output: .string("tool result"),
            duration: .seconds(1)
        )
        _ = builder.addToolResult(toolResult)

        // Increment iteration count twice
        _ = builder.incrementIteration()
        _ = builder.incrementIteration()

        // Build the final result
        let result = builder.build()

        // Verify all properties
        #expect(result.output == "test output")
        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls.first?.toolName == "test_tool")
        #expect(result.toolResults.count == 1)
        #expect(result.toolResults.first?.isSuccess == true)
        #expect(result.iterationCount == 2)
        #expect(result.duration > .zero)
    }

    @Test("TokenUsage")
    func tokenUsage() {
        // Create TokenUsage
        let usage = TokenUsage(inputTokens: 100, outputTokens: 50)

        // Verify properties
        #expect(usage.inputTokens == 100)
        #expect(usage.outputTokens == 50)
        #expect(usage.totalTokens == 150)

        let merged = usage.merging(TokenUsage(inputTokens: 10, outputTokens: 5))
        #expect(merged.inputTokens == 110)
        #expect(merged.outputTokens == 55)
        #expect(merged.totalTokens == 165)
    }
}
