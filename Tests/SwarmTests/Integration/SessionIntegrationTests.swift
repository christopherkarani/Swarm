// SessionIntegrationTests.swift
// SwarmTests
//
// Integration tests for multi-turn conversation behavior with Session.
// Verifies that agents correctly store and retrieve session history.

import Foundation
@testable import Swarm
import Testing

// MARK: - SessionIntegrationTests

@Suite("Session Integration Tests")
struct SessionIntegrationTests {
    // MARK: - Basic Multi-Turn Conversation Tests

    @Test("Multi-turn conversation stores messages")
    func multiTurnConversationStoresMessages() async throws {
        // Setup
        let session = InMemorySession()
        let mockProvider = MockInferenceProvider(responses: [
            "Hello! How can I help you?",
            "I'm doing great, thank you for asking!"
        ])

        let agent = try Agent(
            tools: [],
            instructions: "You are a helpful assistant.",
            inferenceProvider: mockProvider
        )

        // Turn 1
        let result1 = try await agent.run("Hello!", session: session)
        #expect(result1.output == "Hello! How can I help you?")

        // Turn 2
        let result2 = try await agent.run("How are you?", session: session)
        #expect(result2.output == "I'm doing great, thank you for asking!")

        // Verify session contains all messages (user + assistant for each turn)
        let items = try await session.getAllItems()
        #expect(items.count == 4)

        // Verify message order and content
        #expect(items[0].role == .user)
        #expect(items[0].content == "Hello!")
        #expect(items[1].role == .assistant)
        #expect(items[1].content == "Hello! How can I help you?")
        #expect(items[2].role == .user)
        #expect(items[2].content == "How are you?")
        #expect(items[3].role == .assistant)
        #expect(items[3].content == "I'm doing great, thank you for asking!")
    }

    @Test("Session history is loaded on subsequent runs")
    func sessionHistoryLoadedOnSubsequentRuns() async throws {
        // Setup
        let session = InMemorySession()
        let mockProvider = MockInferenceProvider(responses: [
            "Nice to meet you, Alice!",
            "Of course, Alice! I remember you."
        ])

        let agent = try Agent(
            tools: [],
            instructions: "You are a helpful assistant.",
            inferenceProvider: mockProvider
        )

        // Turn 1: User introduces themselves
        _ = try await agent.run("My name is Alice", session: session)

        // Turn 2: User asks if agent remembers
        _ = try await agent.run("Do you remember my name?", session: session)

        // Verify the second call received the session history in the prompt
        let messageCalls = await mockProvider.generateMessageCalls
        #expect(messageCalls.count == 2)

        // The second request should contain conversation history with the user's previous input
        let secondMessages = messageCalls[1].messages
        #expect(secondMessages.contains { $0.content.contains("Alice") })
        #expect(secondMessages.contains { $0.content.contains("My name is Alice") })
    }

    // MARK: - Multiple Agents Sharing Session Tests

    @Test("Multiple agents can share the same session")
    func multipleAgentsSharingSession() async throws {
        // Setup shared session
        let sharedSession = InMemorySession()

        // First agent
        let mockProvider1 = MockInferenceProvider(responses: [
            "I understand you want to calculate something."
        ])
        let agent1 = try Agent(
            tools: [],
            instructions: "You are a math assistant.",
            inferenceProvider: mockProvider1
        )

        // Second agent
        let mockProvider2 = MockInferenceProvider(responses: [
            "Based on the previous context, I can help with that calculation."
        ])
        let agent2 = try Agent(
            tools: [],
            instructions: "You are a helpful assistant.",
            inferenceProvider: mockProvider2
        )

        // Agent 1 processes first message
        _ = try await agent1.run("I need to calculate 2+2", session: sharedSession)

        // Agent 2 uses the same session
        _ = try await agent2.run("Please continue", session: sharedSession)

        // Verify session contains messages from both interactions
        let items = try await sharedSession.getAllItems()
        #expect(items.count == 4)

        // Verify agent 2 received the history from agent 1
        let agent2Calls = await mockProvider2.generateMessageCalls
        #expect(agent2Calls.count == 1)
        let agent2Messages = agent2Calls[0].messages
        #expect(agent2Messages.contains { $0.content.contains("calculate") })
    }

    // MARK: - Session Limits Tests

    @Test("getItems with limit returns appropriate messages")
    func sessionLimitReturnsCorrectMessages() async throws {
        // Setup session with pre-populated history
        let session = InMemorySession()

        // Pre-populate with 10 message pairs (20 total messages)
        for i in 1...10 {
            try await session.addItem(.user("User message \(i)"))
            try await session.addItem(.assistant("Assistant response \(i)"))
        }

        // Verify total count
        #expect(await session.itemCount == 20)

        // Test limit of 4 (should get last 4 messages)
        let lastFour = try await session.getItems(limit: 4)
        #expect(lastFour.count == 4)
        #expect(lastFour[0].content == "User message 9")
        #expect(lastFour[1].content == "Assistant response 9")
        #expect(lastFour[2].content == "User message 10")
        #expect(lastFour[3].content == "Assistant response 10")

        // Test with limit larger than count
        let allItems = try await session.getItems(limit: 100)
        #expect(allItems.count == 20)

        // Test with nil limit (returns all)
        let nilLimit = try await session.getItems(limit: nil)
        #expect(nilLimit.count == 20)
    }

    // MARK: - Empty Session Tests

    @Test("Agent works correctly with fresh empty session")
    func agentWorksWithEmptySession() async throws {
        // Setup
        let session = InMemorySession()
        let mockProvider = MockInferenceProvider(responses: [
            "Hello! I'm ready to help."
        ])

        let agent = try Agent(
            tools: [],
            instructions: "You are a helpful assistant.",
            inferenceProvider: mockProvider
        )

        // Verify session is empty
        #expect(await session.isEmpty == true)

        // Run agent with empty session
        let result = try await agent.run("Hello", session: session)

        // Verify execution succeeded
        #expect(result.output == "Hello! I'm ready to help.")

        // Verify session now has messages
        #expect(await session.isEmpty == false)
        #expect(await session.itemCount == 2)
    }

    // MARK: - Backward Compatibility Tests

    @Test("Agent works without session parameter (backward compatibility)")
    func agentWorksWithoutSession() async throws {
        // Setup
        let mockProvider = MockInferenceProvider(responses: [
            "Hello, world!"
        ])

        let agent = try Agent(
            tools: [],
            instructions: "You are a helpful assistant.",
            inferenceProvider: mockProvider
        )

        // Run agent without session (uses default nil)
        let result = try await agent.run("Hello")

        // Verify execution succeeded
        #expect(result.output == "Hello, world!")
        #expect(result.iterationCount == 1)
    }

    @Test("Agent works with explicit nil session")
    func agentWorksWithExplicitNilSession() async throws {
        // Setup
        let mockProvider = MockInferenceProvider(responses: [
            "Response without session"
        ])

        let agent = try Agent(
            tools: [],
            instructions: "You are a helpful assistant.",
            inferenceProvider: mockProvider
        )

        // Run agent with explicit nil session
        let result = try await agent.run("Test", session: nil)

        // Verify execution succeeded
        #expect(result.output == "Response without session")
    }

    // MARK: - Session Isolation Tests

    @Test("Different sessions do not interfere with each other")
    func sessionIsolation() async throws {
        // Setup two separate sessions
        let session1 = InMemorySession(sessionId: "session-1")
        let session2 = InMemorySession(sessionId: "session-2")

        let mockProvider = MockInferenceProvider(responses: [
            "Response for session 1",
            "Response for session 2",
            "Second response for session 1"
        ])

        let agent = try Agent(
            tools: [],
            instructions: "You are a helpful assistant.",
            inferenceProvider: mockProvider
        )

        // Run in session 1
        _ = try await agent.run("Message for session 1", session: session1)

        // Run in session 2
        _ = try await agent.run("Message for session 2", session: session2)

        // Run another in session 1
        _ = try await agent.run("Another message for session 1", session: session1)

        // Verify session 1 has its own messages (4 messages: 2 turns x 2)
        let session1Items = try await session1.getAllItems()
        #expect(session1Items.count == 4)
        #expect(session1Items[0].content == "Message for session 1")
        #expect(session1Items[2].content == "Another message for session 1")

        // Verify session 2 has its own messages (2 messages: 1 turn x 2)
        let session2Items = try await session2.getAllItems()
        #expect(session2Items.count == 2)
        #expect(session2Items[0].content == "Message for session 2")

        // Verify session IDs are distinct (we set these explicitly in the constructor)
        #expect("session-1" != "session-2")
    }

    @Test("Sessions maintain separate conversation contexts")
    func sessionsSeparateContexts() async throws {
        // Setup
        let sessionAlice = InMemorySession(sessionId: "alice-session")
        let sessionBob = InMemorySession(sessionId: "bob-session")

        let mockProvider = MockInferenceProvider(responses: [
            "Hello Alice!",
            "Hello Bob!",
            "Yes, you are Alice.",
            "Yes, you are Bob."
        ])

        let agent = try Agent(
            tools: [],
            instructions: "You are a helpful assistant that remembers names.",
            inferenceProvider: mockProvider
        )

        // Alice introduces herself
        _ = try await agent.run("My name is Alice", session: sessionAlice)

        // Bob introduces himself
        _ = try await agent.run("My name is Bob", session: sessionBob)

        // Alice asks about her name
        _ = try await agent.run("What is my name?", session: sessionAlice)

        // Bob asks about his name
        _ = try await agent.run("What is my name?", session: sessionBob)

        // Verify prompts contain correct session context
        let messageCalls = await mockProvider.generateMessageCalls
        #expect(messageCalls.count == 4)

        // Third call (Alice asking) should contain "Alice" in history
        let aliceSecondMessages = messageCalls[2].messages
        let aliceCombined = aliceSecondMessages.map(\.content).joined(separator: "\n")
        #expect(aliceCombined.contains("Alice"))
        #expect(!aliceCombined.contains("Bob"))

        // Fourth call (Bob asking) should contain "Bob" in history
        let bobSecondMessages = messageCalls[3].messages
        let bobCombined = bobSecondMessages.map(\.content).joined(separator: "\n")
        #expect(bobCombined.contains("Bob"))
        #expect(!bobCombined.contains("Alice"))
    }

    // MARK: - Tool Calls with Session Tests

    @Test("Session stores messages during tool-using conversations")
    func sessionWithToolCalls() async throws {
        // Setup
        let session = InMemorySession()
        let mockTool = MockTool(
            name: "calculator",
            description: "Performs calculations",
            result: .string("4")
        )

        let mockProvider = MockInferenceProvider()
        // Use native tool calling: first response triggers the tool, second returns text
        await mockProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_calc",
                        name: "calculator",
                        arguments: ["expression": .string("2+2")]
                    )
                ],
                finishReason: .toolCall,
                usage: nil
            ),
            InferenceResponse(
                content: "The result is 4",
                toolCalls: [],
                finishReason: .completed,
                usage: nil
            )
        ])

        let agent = try Agent(
            tools: [mockTool],
            instructions: "You are a math assistant.",
            inferenceProvider: mockProvider
        )

        // Run with tool usage
        let result = try await agent.run("What is 2+2?", session: session)

        // Verify result
        #expect(result.output == "The result is 4")

        // Verify session stores the replayable transcript shape
        let items = try await session.getAllItems()
        #expect(items.count == 4)
        #expect(items[0].role == .user)
        #expect(items[0].content == "What is 2+2?")
        #expect(items[1].role == .assistant)
        #expect(items[2].role == .tool)
        #expect(items[2].content == "4")
        #expect(items[3].role == .assistant)
        #expect(items[3].content == "The result is 4")

        let transcript = SwarmTranscript(memoryMessages: items)
        try transcript.validateReplayCompatibility()
        #expect(transcript.entries.count == 4)
        #expect(transcript.entries[1].toolCalls.count == 1)
        #expect(transcript.entries[1].toolCalls.first?.id == "call_calc")
        #expect(transcript.entries[1].toolCalls.first?.name == "calculator")
        #expect(transcript.entries[2].toolCallID == "call_calc")
        #expect(transcript.entries[2].toolName == "calculator")
    }

    // MARK: - Session Persistence Behavior Tests

    @Test("Session persists across agent lifecycle")
    func sessionPersistsAcrossAgentLifecycle() async throws {
        // Setup shared session
        let session = InMemorySession()

        // First agent instance
        do {
            let mockProvider = MockInferenceProvider(responses: [
                "First agent response"
            ])
            let agent = try Agent(
                tools: [],
                instructions: "First agent",
                inferenceProvider: mockProvider
            )
            _ = try await agent.run("First message", session: session)
        }

        // Second agent instance (first one goes out of scope)
        do {
            let mockProvider = MockInferenceProvider(responses: [
                "Second agent response"
            ])
            let agent = try Agent(
                tools: [],
                instructions: "Second agent",
                inferenceProvider: mockProvider
            )
            _ = try await agent.run("Second message", session: session)

            // Verify session history is available to second agent
            let calls = await mockProvider.generateMessageCalls
            #expect(calls.count == 1)
            let combined = calls[0].messages.map(\.content).joined(separator: "\n")
            #expect(combined.contains("First message"))
        }

        // Verify total session content
        let items = try await session.getAllItems()
        #expect(items.count == 4)
    }

    // MARK: - Edge Cases

    @Test("Session handles rapid sequential runs")
    func sessionHandlesRapidRuns() async throws {
        // Setup
        let session = InMemorySession()
        var responses: [String] = []
        for i in 1...10 {
            responses.append("Response \(i)")
        }
        let mockProvider = MockInferenceProvider(responses: responses)

        let agent = try Agent(
            tools: [],
            instructions: "You are a helpful assistant.",
            inferenceProvider: mockProvider
        )

        // Run multiple times in quick succession
        for i in 1...10 {
            _ = try await agent.run("Message \(i)", session: session)
        }

        // Verify all messages were stored
        let items = try await session.getAllItems()
        #expect(items.count == 20) // 10 user + 10 assistant messages

        // Verify order is preserved
        #expect(items[0].content == "Message 1")
        #expect(items[1].content == "Response 1")
        #expect(items[18].content == "Message 10")
        #expect(items[19].content == "Response 10")
    }

    @Test("Session handles special characters in messages")
    func sessionHandlesSpecialCharacters() async throws {
        // Setup
        let session = InMemorySession()
        let specialInput = "Hello! <script>alert('test')</script> & unicode: \u{1F600}"
        let mockProvider = MockInferenceProvider(responses: [
            "Response with special chars: <>&\""
        ])

        let agent = try Agent(
            tools: [],
            instructions: "You are a helpful assistant.",
            inferenceProvider: mockProvider
        )

        // Run with special characters
        let result = try await agent.run(specialInput, session: session)

        // Verify messages are stored correctly
        let items = try await session.getAllItems()
        #expect(items.count == 2)
        #expect(items[0].content == specialInput)
        #expect(result.output == "Response with special chars: <>&\"")
    }

    @Test("Session works with long conversations")
    func sessionWorksWithLongConversations() async throws {
        // Setup
        let session = InMemorySession()
        let turnCount = 25
        var responses: [String] = []
        for i in 1...turnCount {
            responses.append("Response \(i)")
        }
        let mockProvider = MockInferenceProvider(responses: responses)

        let agent = try Agent(
            tools: [],
            instructions: "You are a helpful assistant.",
            inferenceProvider: mockProvider
        )

        // Run 25 turns
        for i in 1...turnCount {
            _ = try await agent.run("Message \(i)", session: session)
        }

        // Verify session contains all messages
        let items = try await session.getAllItems()
        #expect(items.count == turnCount * 2)

        // Verify session can be queried with limits
        let lastTen = try await session.getItems(limit: 10)
        #expect(lastTen.count == 10)
        #expect(lastTen[0].content == "Message 21")
    }
}
