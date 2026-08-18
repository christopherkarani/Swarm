// InferenceTypesTests.swift
// SwarmTests
//
// Comprehensive tests for InferenceOptions, InferenceResponse, ParsedToolCall, and FinishReason

import Foundation
@testable import Swarm
import Testing

// MARK: - InferenceOptionsTests

@Suite("InferenceOptions Tests")
struct InferenceOptionsTests {
    @Test("Default initialization")
    func defaultInitialization() {
        let options = InferenceOptions()

        #expect(options.temperature == 1.0)
        #expect(options.maxTokens == nil)
        #expect(options.stopSequences.isEmpty)
    }

    @Test("Default static constant")
    func defaultStaticConstant() {
        let options = InferenceOptions.default

        #expect(options.temperature == 1.0)
        #expect(options.maxTokens == nil)
        #expect(options.stopSequences.isEmpty)
    }

    @Test("Custom initialization with all parameters")
    func customInitialization() {
        let options = InferenceOptions(
            temperature: 0.7,
            maxTokens: 1000,
            stopSequences: ["STOP", "END"]
        )

        #expect(options.temperature == 0.7)
        #expect(options.maxTokens == 1000)
        #expect(options.stopSequences == ["STOP", "END"])
    }

    @Test("Partial custom initialization")
    func partialCustomInitialization() {
        let options = InferenceOptions(temperature: 0.5)

        #expect(options.temperature == 0.5)
        #expect(options.maxTokens == nil)
        #expect(options.stopSequences.isEmpty)
    }

    @Test("Edge case: minimum temperature")
    func minimumTemperature() {
        let options = InferenceOptions(temperature: 0.0)

        #expect(options.temperature == 0.0)
    }

    @Test("Edge case: maximum temperature")
    func maximumTemperature() {
        let options = InferenceOptions(temperature: 2.0)

        #expect(options.temperature == 2.0)
    }

    @Test("Equatable conformance: equal instances")
    func equatableEqual() {
        let options1 = InferenceOptions(
            temperature: 0.7,
            maxTokens: 500,
            stopSequences: ["STOP"]
        )
        let options2 = InferenceOptions(
            temperature: 0.7,
            maxTokens: 500,
            stopSequences: ["STOP"]
        )

        #expect(options1 == options2)
    }

    @Test("Equatable conformance: different temperature")
    func equatableDifferentTemperature() {
        let options1 = InferenceOptions(temperature: 0.7)
        let options2 = InferenceOptions(temperature: 0.8)

        #expect(options1 != options2)
    }

    @Test("Equatable conformance: different maxTokens")
    func equatableDifferentMaxTokens() {
        let options1 = InferenceOptions(maxTokens: 500)
        let options2 = InferenceOptions(maxTokens: 1000)

        #expect(options1 != options2)
    }

    @Test("Equatable conformance: different stopSequences")
    func equatableDifferentStopSequences() {
        let options1 = InferenceOptions(stopSequences: ["STOP"])
        let options2 = InferenceOptions(stopSequences: ["END"])

        #expect(options1 != options2)
    }

    @Test("Mutable properties can be changed")
    func mutableProperties() {
        var options = InferenceOptions()

        options.temperature = 0.5
        options.maxTokens = 2000
        options.stopSequences = ["HALT"]

        #expect(options.temperature == 0.5)
        #expect(options.maxTokens == 2000)
        #expect(options.stopSequences == ["HALT"])
    }
}

// MARK: - ParsedToolCallTests

@Suite("ParsedToolCall Tests")
struct ParsedToolCallTests {
    @Test("Basic initialization")
    func basicInitialization() {
        let toolCall = InferenceResponse.ParsedToolCall(
            name: "search",
            arguments: ["query": .string("Swift agents")]
        )

        #expect(toolCall.name == "search")
        #expect(toolCall.arguments["query"] == .string("Swift agents"))
    }

    @Test("Empty arguments")
    func emptyArguments() {
        let toolCall = InferenceResponse.ParsedToolCall(
            name: "getCurrentTime",
            arguments: [:]
        )

        #expect(toolCall.name == "getCurrentTime")
        #expect(toolCall.arguments.isEmpty)
    }

    @Test("Complex nested SendableValue arguments")
    func complexNestedArguments() {
        let toolCall = InferenceResponse.ParsedToolCall(
            name: "complexTool",
            arguments: [
                "string": .string("value"),
                "number": .int(42),
                "bool": .bool(true),
                "array": .array([.string("a"), .string("b")]),
                "dict": .dictionary(["nested": .string("value")])
            ]
        )

        #expect(toolCall.arguments["string"] == .string("value"))
        #expect(toolCall.arguments["number"] == .int(42))
        #expect(toolCall.arguments["bool"] == .bool(true))
        #expect(toolCall.arguments["array"] == .array([.string("a"), .string("b")]))
        #expect(toolCall.arguments["dict"] == .dictionary(["nested": .string("value")]))
    }

    @Test("Equatable conformance: equal instances")
    func equatableEqual() {
        let toolCall1 = InferenceResponse.ParsedToolCall(
            name: "search",
            arguments: ["query": .string("test")]
        )
        let toolCall2 = InferenceResponse.ParsedToolCall(
            name: "search",
            arguments: ["query": .string("test")]
        )

        #expect(toolCall1 == toolCall2)
    }

    @Test("Equatable conformance: different name")
    func equatableDifferentName() {
        let toolCall1 = InferenceResponse.ParsedToolCall(
            name: "search",
            arguments: ["query": .string("test")]
        )
        let toolCall2 = InferenceResponse.ParsedToolCall(
            name: "calculate",
            arguments: ["query": .string("test")]
        )

        #expect(toolCall1 != toolCall2)
    }

    @Test("Equatable conformance: different arguments")
    func equatableDifferentArguments() {
        let toolCall1 = InferenceResponse.ParsedToolCall(
            name: "search",
            arguments: ["query": .string("test1")]
        )
        let toolCall2 = InferenceResponse.ParsedToolCall(
            name: "search",
            arguments: ["query": .string("test2")]
        )

        #expect(toolCall1 != toolCall2)
    }
}

// MARK: - FinishReasonTests

@Suite("FinishReason Tests")
struct FinishReasonTests {
    @Test("All cases exist")
    func allCasesExist() {
        let completed = InferenceResponse.FinishReason.completed
        let toolCall = InferenceResponse.FinishReason.toolCall
        let maxTokens = InferenceResponse.FinishReason.maxTokens
        let contentFilter = InferenceResponse.FinishReason.contentFilter
        let cancelled = InferenceResponse.FinishReason.cancelled

        #expect(completed == .completed)
        #expect(toolCall == .toolCall)
        #expect(maxTokens == .maxTokens)
        #expect(contentFilter == .contentFilter)
        #expect(cancelled == .cancelled)
    }

    @Test("Raw values are correct")
    func rawValuesCorrect() {
        #expect(InferenceResponse.FinishReason.completed.rawValue == "completed")
        #expect(InferenceResponse.FinishReason.toolCall.rawValue == "toolCall")
        #expect(InferenceResponse.FinishReason.maxTokens.rawValue == "maxTokens")
        #expect(InferenceResponse.FinishReason.contentFilter.rawValue == "contentFilter")
        #expect(InferenceResponse.FinishReason.cancelled.rawValue == "cancelled")
    }

    @Test("Codable: encode and decode completed")
    func codableCompleted() throws {
        let original = InferenceResponse.FinishReason.completed
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InferenceResponse.FinishReason.self, from: encoded)

        #expect(decoded == original)
    }

    @Test("Codable: encode and decode toolCall")
    func codableToolCall() throws {
        let original = InferenceResponse.FinishReason.toolCall
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InferenceResponse.FinishReason.self, from: encoded)

        #expect(decoded == original)
    }

    @Test("Codable: encode and decode maxTokens")
    func codableMaxTokens() throws {
        let original = InferenceResponse.FinishReason.maxTokens
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InferenceResponse.FinishReason.self, from: encoded)

        #expect(decoded == original)
    }

    @Test("Codable: encode and decode contentFilter")
    func codableContentFilter() throws {
        let original = InferenceResponse.FinishReason.contentFilter
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InferenceResponse.FinishReason.self, from: encoded)

        #expect(decoded == original)
    }

    @Test("Codable: encode and decode cancelled")
    func codableCancelled() throws {
        let original = InferenceResponse.FinishReason.cancelled
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InferenceResponse.FinishReason.self, from: encoded)

        #expect(decoded == original)
    }

    @Test("Equatable conformance")
    func equatableConformance() {
        #expect(InferenceResponse.FinishReason.completed == .completed)
        #expect(InferenceResponse.FinishReason.completed != .toolCall)
        #expect(InferenceResponse.FinishReason.toolCall != .maxTokens)
    }
}

// MARK: - InferenceResponseTests

@Suite("InferenceResponse Tests")
struct InferenceResponseTests {
    @Test("Default initialization")
    func defaultInitialization() {
        let response = InferenceResponse()

        #expect(response.content == nil)
        #expect(response.toolCalls.isEmpty)
        #expect(response.finishReason == .completed)
        #expect(response.hasToolCalls == false)
        #expect(response.transcriptMessages.isEmpty)
    }

    @Test("Initialization with content only")
    func contentOnlyInitialization() {
        let response = InferenceResponse(content: "Hello, world!")

        #expect(response.content == "Hello, world!")
        #expect(response.toolCalls.isEmpty)
        #expect(response.finishReason == .completed)
        #expect(response.hasToolCalls == false)
    }

    @Test("Initialization with tool calls only")
    func toolCallsOnlyInitialization() {
        let toolCall = InferenceResponse.ParsedToolCall(
            name: "search",
            arguments: ["query": .string("test")]
        )
        let response = InferenceResponse(toolCalls: [toolCall])

        #expect(response.content == nil)
        #expect(response.toolCalls.count == 1)
        #expect(response.toolCalls.first?.name == "search")
        #expect(response.finishReason == .completed)
        #expect(response.hasToolCalls == true)
    }

    @Test("Initialization with custom finish reason")
    func customFinishReasonInitialization() {
        let response = InferenceResponse(
            content: "Partial response",
            finishReason: .maxTokens
        )

        #expect(response.content == "Partial response")
        #expect(response.finishReason == .maxTokens)
    }

    @Test("hasToolCalls: true when tool calls present")
    func hasToolCallsTrue() {
        let toolCall = InferenceResponse.ParsedToolCall(
            name: "calculate",
            arguments: ["expression": .string("2+2")]
        )
        let response = InferenceResponse(toolCalls: [toolCall])

        #expect(response.hasToolCalls == true)
    }

    @Test("hasToolCalls: false when no tool calls")
    func hasToolCallsFalse() {
        let response = InferenceResponse(content: "No tools needed")

        #expect(response.hasToolCalls == false)
    }

    @Test("Multiple tool calls")
    func multipleToolCalls() {
        let toolCall1 = InferenceResponse.ParsedToolCall(
            name: "search",
            arguments: ["query": .string("Swift")]
        )
        let toolCall2 = InferenceResponse.ParsedToolCall(
            name: "calculate",
            arguments: ["expression": .string("10*5")]
        )
        let response = InferenceResponse(toolCalls: [toolCall1, toolCall2])

        #expect(response.toolCalls.count == 2)
        #expect(response.hasToolCalls == true)
        #expect(response.toolCalls[0].name == "search")
        #expect(response.toolCalls[1].name == "calculate")
    }

    @Test("Content with tool calls and custom finish reason")
    func fullInitialization() {
        let toolCall = InferenceResponse.ParsedToolCall(
            name: "search",
            arguments: ["query": .string("test")]
        )
        let response = InferenceResponse(
            content: "Here are the results:",
            toolCalls: [toolCall],
            finishReason: .toolCall
        )

        #expect(response.content == "Here are the results:")
        #expect(response.toolCalls.count == 1)
        #expect(response.finishReason == .toolCall)
        #expect(response.hasToolCalls == true)
    }

    @Test("Equatable conformance: equal instances")
    func equatableEqual() {
        let toolCall = InferenceResponse.ParsedToolCall(
            name: "test",
            arguments: ["key": .string("value")]
        )
        let response1 = InferenceResponse(
            content: "test",
            toolCalls: [toolCall],
            finishReason: .completed
        )
        let response2 = InferenceResponse(
            content: "test",
            toolCalls: [toolCall],
            finishReason: .completed
        )

        #expect(response1 == response2)
    }

    @Test("Equatable conformance: different content")
    func equatableDifferentContent() {
        let response1 = InferenceResponse(content: "test1")
        let response2 = InferenceResponse(content: "test2")

        #expect(response1 != response2)
    }

    @Test("Equatable conformance: different tool calls")
    func equatableDifferentToolCalls() {
        let toolCall1 = InferenceResponse.ParsedToolCall(
            name: "tool1",
            arguments: [:]
        )
        let toolCall2 = InferenceResponse.ParsedToolCall(
            name: "tool2",
            arguments: [:]
        )
        let response1 = InferenceResponse(toolCalls: [toolCall1])
        let response2 = InferenceResponse(toolCalls: [toolCall2])

        #expect(response1 != response2)
    }

    @Test("Equatable conformance: different finish reason")
    func equatableDifferentFinishReason() {
        let response1 = InferenceResponse(
            content: "test",
            finishReason: .completed
        )
        let response2 = InferenceResponse(
            content: "test",
            finishReason: .maxTokens
        )

        #expect(response1 != response2)
    }

    @Test("Edge case: empty content string")
    func emptyContentString() {
        let response = InferenceResponse(content: "")

        #expect(response.content?.isEmpty == true)
        #expect(response.hasToolCalls == false)
    }

    @Test("Edge case: cancelled finish reason")
    func cancelledFinishReason() {
        let response = InferenceResponse(
            content: "Incomplete...",
            finishReason: .cancelled
        )

        #expect(response.finishReason == .cancelled)
    }

    @Test("Edge case: content filter finish reason")
    func contentFilterFinishReason() {
        let response = InferenceResponse(
            content: nil,
            finishReason: .contentFilter
        )

        #expect(response.content == nil)
        #expect(response.finishReason == .contentFilter)
    }

    // MARK: - ReasoningConfig Tests (PR #83)

    @Test("InferenceOptions initialization with reasoning")
    func initializationWithReasoning() {
        let reasoning = ReasoningConfig(effort: .low, maxTokens: 4096, exclude: true)
        let options = InferenceOptions(reasoning: reasoning)

        #expect(options.reasoning?.effort == .low)
        #expect(options.reasoning?.maxTokens == 4096)
        #expect(options.reasoning?.exclude == true)
    }

    @Test("InferenceOptions default reasoning is nil")
    func defaultReasoningIsNil() {
        let options = InferenceOptions.default
        #expect(options.reasoning == nil)
    }

    @Test("InferenceOptions equality with reasoning")
    func equatableWithReasoning() {
        let options1 = InferenceOptions(reasoning: ReasoningConfig(effort: .high))
        let options2 = InferenceOptions(reasoning: ReasoningConfig(effort: .high))
        let options3 = InferenceOptions(reasoning: ReasoningConfig(effort: .low))

        #expect(options1 == options2)
        #expect(options1 != options3)
    }

    @Test("InferenceOptions with reasoning preserves values")
    func preservesReasoningValues() {
        let original = InferenceOptions(
            temperature: 0.7,
            maxTokens: 1000,
            reasoning: ReasoningConfig(effort: .medium, maxTokens: 2048)
        )

        #expect(original.reasoning?.effort == .medium)
        #expect(original.reasoning?.maxTokens == 2048)
    }
}
