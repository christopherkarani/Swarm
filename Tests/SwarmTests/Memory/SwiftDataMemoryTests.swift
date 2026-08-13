// SwiftDataMemoryTests.swift
// Swarm Framework

#if canImport(SwiftData)
    import Foundation
    @testable import Swarm
    import SwiftData
    import Testing

    @Suite("SwiftDataMemory Tests")
    struct SwiftDataMemoryTests {
        // MARK: - Helper

        func makeInMemoryMemory(
            conversationId: String = "test",
            maxMessages: Int = 0
        ) throws -> SwiftDataMemory {
            try SwiftDataMemory.inMemory(
                conversationId: conversationId,
                maxMessages: maxMessages
            )
        }

        // MARK: - Initialization Tests

        @Test("Creates with in-memory container")
        func inMemoryInit() async throws {
            if !SwiftDataTestGate.canRun { return }
            let memory = try makeInMemoryMemory()

            #expect(await memory.conversationId == "test")
            #expect(await memory.maxMessages == 0)
            #expect(await memory.isEmpty)
        }

        @Test("Creates with custom conversation ID")
        func customConversationId() async throws {
            if !SwiftDataTestGate.canRun { return }
            let memory = try makeInMemoryMemory(conversationId: "chat-123")

            #expect(await memory.conversationId == "chat-123")
        }

        @Test("Creates with max messages limit")
        func maxMessagesLimit() async throws {
            if !SwiftDataTestGate.canRun { return }
            let memory = try makeInMemoryMemory(maxMessages: 50)

            #expect(await memory.maxMessages == 50)
        }

        // MARK: - Add Tests

        @Test("Adds single message")
        func addSingleMessage() async throws {
            if !SwiftDataTestGate.canRun { return }
            let memory = try makeInMemoryMemory()

            await memory.add(.user("Hello"))

            #expect(await memory.count == 1)
        }

        @Test("Adds multiple messages")
        func addMultipleMessages() async throws {
            if !SwiftDataTestGate.canRun { return }
            let memory = try makeInMemoryMemory()

            await memory.add(.user("Hello"))
            await memory.add(.assistant("Hi there"))
            await memory.add(.user("How are you?"))

            #expect(await memory.count == 3)
        }

        @Test("Persists message content correctly")
        func messagePersistence() async throws {
            if !SwiftDataTestGate.canRun { return }
            let memory = try makeInMemoryMemory()

            let message = MemoryMessage.user("Test content", metadata: ["key": "value"])
            await memory.add(message)

            let messages = await memory.allMessages()

            #expect(messages.count == 1)
            #expect(messages[0].content == "Test content")
            #expect(messages[0].role == .user)
            #expect(messages[0].metadata["key"] == "value")
        }

        // MARK: - Message Limit Tests

        @Test("Trims to max messages")
        func trimsToMaxMessages() async throws {
            if !SwiftDataTestGate.canRun { return }
            let memory = try makeInMemoryMemory(maxMessages: 5)

            for i in 1...10 {
                await memory.add(.user("Message \(i)"))
            }

            #expect(await memory.count == 5)

            // Should have kept the most recent
            let messages = await memory.allMessages()
            #expect(messages.first?.content == "Message 6")
            #expect(messages.last?.content == "Message 10")
        }

        @Test("Unlimited messages when maxMessages is 0")
        func unlimitedMessages() async throws {
            if !SwiftDataTestGate.canRun { return }
            let memory = try makeInMemoryMemory(maxMessages: 0)

            for i in 1...100 {
                await memory.add(.user("Message \(i)"))
            }

            #expect(await memory.count == 100)
        }

        // MARK: - Context Retrieval Tests

        @Test("Gets context within token limit")
        func getContext() async throws {
            if !SwiftDataTestGate.canRun { return }
            let memory = try makeInMemoryMemory()

            await memory.add(.user("Hello"))
            await memory.add(.assistant("Hi there"))

            let context = await memory.context(for: "test", tokenLimit: 1000)

            #expect(context.contains("[user]: Hello"))
            #expect(context.contains("[assistant]: Hi there"))
        }

        // MARK: - Clear Tests

        @Test("Clear removes all messages")
        func testClear() async throws {
            if !SwiftDataTestGate.canRun { return }
            let memory = try makeInMemoryMemory()

            await memory.add(.user("Hello"))
            await memory.add(.assistant("Hi"))

            #expect(await memory.count == 2)

            await memory.clear()

            #expect(await memory.isEmpty)
        }

        // MARK: - Batch Operations Tests

        @Test("Adds all messages in batch")
        func testAddAll() async throws {
            if !SwiftDataTestGate.canRun { return }
            let memory = try makeInMemoryMemory()

            let messages = [
                MemoryMessage.user("1"),
                MemoryMessage.user("2"),
                MemoryMessage.user("3")
            ]

            await memory.addAll(messages)

            #expect(await memory.count == 3)
        }

        @Test("Gets recent messages")
        func testGetRecentMessages() async throws {
            if !SwiftDataTestGate.canRun { return }
            let memory = try makeInMemoryMemory()

            for i in 1...10 {
                await memory.add(.user("Message \(i)"))
            }

            let recent = await memory.getRecentMessages(3)

            #expect(recent.count == 3)
            #expect(recent[0].content == "Message 8")
            #expect(recent[2].content == "Message 10")
        }

        // MARK: - Conversation Isolation Tests

        @Test("Isolates messages by conversation ID")
        func conversationIsolation() async throws {
            if !SwiftDataTestGate.canRun { return }
            let container = try PersistedMessage.makeContainer(inMemory: true)

            let memory1 = SwiftDataMemory(modelContainer: container, conversationId: "chat-1")
            let memory2 = SwiftDataMemory(modelContainer: container, conversationId: "chat-2")

            await memory1.add(.user("Message for chat 1"))
            await memory2.add(.user("Message for chat 2"))
            await memory2.add(.user("Another for chat 2"))

            #expect(await memory1.count == 1)
            #expect(await memory2.count == 2)
        }

        // MARK: - Conversation Management Tests

        @Test("Lists all conversation IDs")
        func testAllConversationIds() async throws {
            if !SwiftDataTestGate.canRun { return }
            let container = try PersistedMessage.makeContainer(inMemory: true)

            let memory1 = SwiftDataMemory(modelContainer: container, conversationId: "alpha")
            let memory2 = SwiftDataMemory(modelContainer: container, conversationId: "beta")

            await memory1.add(.user("Test 1"))
            await memory2.add(.user("Test 2"))

            let ids = await memory1.allConversationIds()

            #expect(ids.contains("alpha"))
            #expect(ids.contains("beta"))
        }

        @Test("Deletes specific conversation")
        func testDeleteConversation() async throws {
            if !SwiftDataTestGate.canRun { return }
            let container = try PersistedMessage.makeContainer(inMemory: true)

            let memory = SwiftDataMemory(modelContainer: container, conversationId: "to-delete")
            await memory.add(.user("Test message"))

            #expect(await memory.count == 1)

            await memory.deleteConversation("to-delete")

            #expect(await memory.isEmpty)
        }

        @Test("Gets message count for conversation")
        func messageCountForConversation() async throws {
            if !SwiftDataTestGate.canRun { return }
            let container = try PersistedMessage.makeContainer(inMemory: true)

            let memory = SwiftDataMemory(modelContainer: container, conversationId: "test")
            await memory.add(.user("1"))
            await memory.add(.user("2"))

            let count = await memory.messageCount(forConversation: "test")

            #expect(count == 2)
        }

        // MARK: - Diagnostics Tests

        @Test("Provides accurate diagnostics")
        func testDiagnostics() async throws {
            if !SwiftDataTestGate.canRun { return }
            let memory = try makeInMemoryMemory(conversationId: "diag-test", maxMessages: 100)

            await memory.add(.user("Hello"))
            await memory.add(.assistant("Hi"))

            let diagnostics = await memory.diagnostics()

            #expect(diagnostics.conversationId == "diag-test")
            #expect(diagnostics.messageCount == 2)
            #expect(diagnostics.maxMessages == 100)
            #expect(diagnostics.isUnlimited == false)
        }

        @Test("Diagnostics show unlimited correctly")
        func diagnosticsUnlimited() async throws {
            if !SwiftDataTestGate.canRun { return }
            let memory = try makeInMemoryMemory(maxMessages: 0)

            let diagnostics = await memory.diagnostics()

            #expect(diagnostics.isUnlimited == true)
        }

        // MARK: - Factory Methods Tests

        @Test("In-memory factory creates correct instance")
        func inMemoryFactory() async throws {
            if !SwiftDataTestGate.canRun { return }
            let memory = try SwiftDataMemory.inMemory(
                conversationId: "factory-test",
                maxMessages: 25
            )

            #expect(await memory.conversationId == "factory-test")
            #expect(await memory.maxMessages == 25)
        }
    }
#endif
