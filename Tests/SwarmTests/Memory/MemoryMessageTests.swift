// MemoryMessageTests.swift
// Swarm Framework

import Foundation
@testable import Swarm
import Testing

@Suite("MemoryMessage Tests")
struct MemoryMessageTests {
    // MARK: - Initialization Tests

    @Test("Creates message with all parameters")
    func fullInitialization() {
        let id = UUID()
        let timestamp = Date()
        let metadata = ["key": "value"]

        let message = MemoryMessage(
            id: id,
            role: .user,
            content: "Hello",
            timestamp: timestamp,
            metadata: metadata
        )

        #expect(message.id == id)
        #expect(message.role == .user)
        #expect(message.content == "Hello")
        #expect(message.timestamp == timestamp)
        #expect(message.metadata == metadata)
    }

    @Test("Creates message with default parameters")
    func defaultInitialization() {
        let message = MemoryMessage(role: .assistant, content: "Hi there")

        #expect(message.role == .assistant)
        #expect(message.content == "Hi there")
        #expect(message.metadata.isEmpty)
        // ID and timestamp should be auto-generated
        #expect(message.id != UUID())
    }

    // MARK: - Factory Methods Tests

    @Test("User factory method creates correct role")
    func userFactory() {
        let message = MemoryMessage.user("Hello world")

        #expect(message.role == .user)
        #expect(message.content == "Hello world")
    }

    @Test("Assistant factory method creates correct role")
    func assistantFactory() {
        let message = MemoryMessage.assistant("I can help")

        #expect(message.role == .assistant)
        #expect(message.content == "I can help")
    }

    @Test("System factory method creates correct role")
    func systemFactory() {
        let message = MemoryMessage.system("You are helpful")

        #expect(message.role == .system)
        #expect(message.content == "You are helpful")
    }

    @Test("Tool factory method creates correct role and metadata")
    func toolFactory() {
        let message = MemoryMessage.tool("Result: 42", toolName: "calculator")

        #expect(message.role == .tool)
        #expect(message.content == "Result: 42")
        #expect(message.metadata["tool_name"] == "calculator")
    }

    @Test("Factory methods accept metadata")
    func factoryWithMetadata() {
        let message = MemoryMessage.user("Hello", metadata: ["source": "test"])

        #expect(message.metadata["source"] == "test")
    }

    // MARK: - Formatted Content Tests

    @Test("Formatted content includes role prefix")
    func testFormattedContent() {
        let userMessage = MemoryMessage.user("Hello")
        let assistantMessage = MemoryMessage.assistant("Hi")

        #expect(userMessage.formattedContent == "[user]: Hello")
        #expect(assistantMessage.formattedContent == "[assistant]: Hi")
    }

    // MARK: - Role Tests

    @Test("All roles are accessible")
    func allRoles() {
        let roles: [MemoryMessage.Role] = [.user, .assistant, .system, .tool]

        #expect(roles.count == 4)
        #expect(MemoryMessage.Role.allCases.count == 4)
    }

    @Test("Role raw values are correct")
    func roleRawValues() {
        #expect(MemoryMessage.Role.user.rawValue == "user")
        #expect(MemoryMessage.Role.assistant.rawValue == "assistant")
        #expect(MemoryMessage.Role.system.rawValue == "system")
        #expect(MemoryMessage.Role.tool.rawValue == "tool")
    }

    // MARK: - Codable Tests

    @Test("Message encodes and decodes correctly")
    func codable() throws {
        let original = MemoryMessage.user("Test message", metadata: ["key": "value"])

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MemoryMessage.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.role == original.role)
        #expect(decoded.content == original.content)
        #expect(decoded.metadata == original.metadata)
    }

    // MARK: - Equatable Tests

    @Test("Messages with same ID are equal")
    func equatable() {
        let id = UUID()
        let timestamp = Date()
        let message1 = MemoryMessage(id: id, role: .user, content: "Hello", timestamp: timestamp)
        let message2 = MemoryMessage(id: id, role: .user, content: "Hello", timestamp: timestamp)

        #expect(message1 == message2)
    }

    @Test("Messages with different IDs are not equal")
    func notEqual() {
        let message1 = MemoryMessage.user("Hello")
        let message2 = MemoryMessage.user("Hello")

        #expect(message1 != message2)
    }

    // MARK: - Hashable Tests

    @Test("Messages can be used in sets")
    func hashable() {
        let message1 = MemoryMessage.user("Hello")
        let message2 = MemoryMessage.user("World")

        var set: Set<MemoryMessage> = []
        set.insert(message1)
        set.insert(message2)
        set.insert(message1) // Duplicate

        #expect(set.count == 2)
    }

    // MARK: - Description Tests

    @Test("Description is human-readable")
    func testDescription() {
        let message = MemoryMessage.user("Hello world")
        let description = message.description

        #expect(description.contains("user"))
        #expect(description.contains("Hello world"))
    }

    @Test("Description truncates long content")
    func descriptionTruncation() {
        let longContent = String(repeating: "a", count: 100)
        let message = MemoryMessage.user(longContent)
        let description = message.description

        #expect(description.contains("..."))
        #expect(description.count < 100)
    }

    // MARK: - Context Formatting Tests

    @Test("Context formatting skips oversized newest message")
    func contextFormattingSkipsOversizedNewestMessage() {
        let estimator = CharacterBasedTokenEstimator(charactersPerToken: 1)
        let messages = [
            MemoryMessage.user("first-fit"),
            MemoryMessage.assistant("second-fit"),
            MemoryMessage.user(String(repeating: "x", count: 120))
        ]

        let context = MemoryMessage.formatContext(
            messages,
            tokenLimit: 60,
            tokenEstimator: estimator
        )

        #expect(context.contains("[user]: first-fit"))
        #expect(context.contains("[assistant]: second-fit"))
        #expect(!context.contains(String(repeating: "x", count: 120)))
    }

    @Test("Context formatting with custom separator skips oversized newest message")
    func contextFormattingWithCustomSeparatorSkipsOversizedNewestMessage() {
        let estimator = CharacterBasedTokenEstimator(charactersPerToken: 1)
        let messages = [
            MemoryMessage.user("first-fit"),
            MemoryMessage.assistant("second-fit"),
            MemoryMessage.user(String(repeating: "x", count: 120))
        ]

        let context = MemoryMessage.formatContext(
            messages,
            tokenLimit: 64,
            separator: "\n---\n",
            tokenEstimator: estimator
        )

        #expect(context == "[user]: first-fit\n---\n[assistant]: second-fit")
    }

    @Test("Context formatting skips oversized middle message")
    func contextFormattingSkipsOversizedMiddleMessage() {
        let estimator = CharacterBasedTokenEstimator(charactersPerToken: 1)
        let oversized = String(repeating: "x", count: 120)
        let messages = [
            MemoryMessage.user("older-fit"),
            MemoryMessage.user(oversized),
            MemoryMessage.assistant("newer-fit")
        ]

        let context = MemoryMessage.formatContext(
            messages,
            tokenLimit: 64,
            tokenEstimator: estimator
        )

        #expect(context.contains("[user]: older-fit"))
        #expect(context.contains("[assistant]: newer-fit"))
        #expect(!context.contains(oversized))
    }

    @Test("Context formatting stops at non-oversized message that exhausts remaining budget")
    func contextFormattingStopsAtNonOversizedBudgetExhaustion() {
        let estimator = CharacterBasedTokenEstimator(charactersPerToken: 1)
        let fittingButTooLargeAfterNewest = String(repeating: "m", count: 40)
        let messages = [
            MemoryMessage.user("older-fit"),
            MemoryMessage.user(fittingButTooLargeAfterNewest),
            MemoryMessage.assistant("new")
        ]

        let context = MemoryMessage.formatContext(
            messages,
            tokenLimit: 48,
            tokenEstimator: estimator
        )

        #expect(context == "[assistant]: new")
    }

    @Test("Context formatting with custom separator stops at non-oversized budget exhaustion")
    func contextFormattingWithCustomSeparatorStopsAtNonOversizedBudgetExhaustion() {
        let estimator = CharacterBasedTokenEstimator(charactersPerToken: 1)
        let fittingButTooLargeAfterNewest = String(repeating: "m", count: 40)
        let messages = [
            MemoryMessage.user("older-fit"),
            MemoryMessage.user(fittingButTooLargeAfterNewest),
            MemoryMessage.assistant("new")
        ]

        let context = MemoryMessage.formatContext(
            messages,
            tokenLimit: 48,
            separator: "\n---\n",
            tokenEstimator: estimator
        )

        #expect(context == "[assistant]: new")
    }

    @Test("Context formatting returns empty when token limit is zero")
    func contextFormattingReturnsEmptyWhenTokenLimitIsZero() {
        let estimator = CharacterBasedTokenEstimator(charactersPerToken: 1)
        let messages = [
            MemoryMessage.user("first"),
            MemoryMessage.assistant("second")
        ]

        let context = MemoryMessage.formatContext(
            messages,
            tokenLimit: 0,
            tokenEstimator: estimator
        )

        #expect(context.isEmpty)
    }

    @Test("Context formatting returns empty when all messages are oversized")
    func contextFormattingReturnsEmptyWhenAllMessagesAreOversized() {
        let estimator = CharacterBasedTokenEstimator(charactersPerToken: 1)
        let messages = [
            MemoryMessage.user(String(repeating: "x", count: 120)),
            MemoryMessage.assistant(String(repeating: "y", count: 200))
        ]

        let context = MemoryMessage.formatContext(
            messages,
            tokenLimit: 60,
            tokenEstimator: estimator
        )

        #expect(context.isEmpty)
    }

    @Test("Context formatting with custom separator returns empty when token limit is zero")
    func contextFormattingWithSeparatorReturnsEmptyWhenTokenLimitIsZero() {
        let estimator = CharacterBasedTokenEstimator(charactersPerToken: 1)
        let messages = [
            MemoryMessage.user("first"),
            MemoryMessage.assistant("second")
        ]

        let context = MemoryMessage.formatContext(
            messages,
            tokenLimit: 0,
            separator: "\n---\n",
            tokenEstimator: estimator
        )

        #expect(context.isEmpty)
    }

    @Test("Context formatting with custom separator returns empty when all messages are oversized")
    func contextFormattingWithSeparatorReturnsEmptyWhenAllMessagesAreOversized() {
        let estimator = CharacterBasedTokenEstimator(charactersPerToken: 1)
        let messages = [
            MemoryMessage.user(String(repeating: "x", count: 120)),
            MemoryMessage.assistant(String(repeating: "y", count: 200))
        ]

        let context = MemoryMessage.formatContext(
            messages,
            tokenLimit: 60,
            separator: "\n---\n",
            tokenEstimator: estimator
        )

        #expect(context.isEmpty)
    }
}
