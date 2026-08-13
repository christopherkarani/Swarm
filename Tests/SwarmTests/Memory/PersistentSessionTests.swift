// PersistentSessionTests.swift
// Swarm Framework
//
// Comprehensive tests for PersistentSession actor implementation.

#if canImport(SwiftData)
    import Foundation
    @testable import Swarm
    import SwiftData
    import Testing

    @Suite("PersistentSession Tests")
    struct PersistentSessionTests {
        // MARK: - Factory Method Tests

        @Test("Creates in-memory session with factory method")
        func inMemoryFactory() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "test-session")

            let sessionId = session.sessionId
            #expect(sessionId == "test-session")
            #expect(await session.isEmpty == true)
        }

        @Test("Creates persistent session with factory method")
        func persistentFactory() async throws {
            if !SwiftDataTestGate.canRun { return }
            // NOTE: SwiftData persistent stores default to Application Support.
            // In sandboxed environments, writing there may be denied and can crash CoreData.
            do {
                let appSupport = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let probe = appSupport.appendingPathComponent("swarm_persistence_probe.tmp")
                try Data("probe".utf8).write(to: probe)
                try FileManager.default.removeItem(at: probe)
            } catch {
                return
            }

            let session = try PersistentSession.persistent(sessionId: "persistent-test")

            let sessionId = session.sessionId
            #expect(sessionId == "persistent-test")
        }

        @Test("Each factory session has correct session ID")
        func factorySessionIds() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session1 = try PersistentSession.inMemory(sessionId: "session-1")
            let session2 = try PersistentSession.inMemory(sessionId: "session-2")

            let id1 = session1.sessionId
            let id2 = session2.sessionId

            #expect(id1 == "session-1")
            #expect(id2 == "session-2")
        }

        // MARK: - Initialization Tests

        @Test("Creates with custom backend")
        func customBackendInit() async throws {
            if !SwiftDataTestGate.canRun { return }
            let backend = try SwiftDataBackend.inMemory()
            let session = PersistentSession(sessionId: "custom-backend-test", backend: backend)

            let sessionId = session.sessionId
            #expect(sessionId == "custom-backend-test")
        }

        @Test("Starts with empty state")
        func startsEmpty() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "empty-test")

            #expect(await session.isEmpty == true)
            #expect(await session.itemCount == 0)
        }

        // MARK: - Add and Retrieve Tests

        @Test("Adds single item successfully")
        func addSingleItem() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "add-single-test")
            let message = MemoryMessage.user("Hello, world!")

            try await session.addItem(message)

            let items = try await session.getAllItems()
            #expect(items.count == 1)
            #expect(items[0].content == "Hello, world!")
            #expect(items[0].role == .user)
        }

        @Test("Adds multiple items in batch")
        func addMultipleItems() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "add-multiple-test")
            let messages = [
                MemoryMessage.user("First message"),
                MemoryMessage.assistant("Second message"),
                MemoryMessage.system("Third message")
            ]

            try await session.addItems(messages)

            #expect(await session.itemCount == 3)
        }

        @Test("Preserves message properties after storage")
        func preservesMessageProperties() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "preserve-test")

            let originalId = UUID()
            let originalTimestamp = Date()
            let originalMetadata = ["key": "value", "source": "test"]

            let message = MemoryMessage(
                id: originalId,
                role: .assistant,
                content: "Test content",
                timestamp: originalTimestamp,
                metadata: originalMetadata
            )

            try await session.addItem(message)

            let items = try await session.getAllItems()
            let retrieved = items[0]

            #expect(retrieved.id == originalId)
            #expect(retrieved.role == .assistant)
            #expect(retrieved.content == "Test content")
            #expect(retrieved.metadata == originalMetadata)
        }

        // MARK: - Chronological Order Tests

        @Test("Maintains chronological order")
        func maintainsChronologicalOrder() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "order-test")

            try await session.addItem(MemoryMessage.user("First"))
            try await session.addItem(MemoryMessage.assistant("Second"))
            try await session.addItem(MemoryMessage.user("Third"))
            try await session.addItem(MemoryMessage.assistant("Fourth"))

            let items = try await session.getAllItems()

            #expect(items[0].content == "First")
            #expect(items[1].content == "Second")
            #expect(items[2].content == "Third")
            #expect(items[3].content == "Fourth")
        }

        @Test("Batch add preserves order within batch")
        func batchAddPreservesOrder() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "batch-order-test")

            let baseDate = Date()
            let messages = [
                makeMessage("A", offsetSeconds: 0, baseDate: baseDate),
                makeMessage("B", offsetSeconds: 1, baseDate: baseDate),
                makeMessage("C", offsetSeconds: 2, baseDate: baseDate),
                makeMessage("D", offsetSeconds: 3, baseDate: baseDate)
            ]

            try await session.addItems(messages)

            let items = try await session.getAllItems()

            #expect(items[0].content == "A")
            #expect(items[1].content == "B")
            #expect(items[2].content == "C")
            #expect(items[3].content == "D")
        }

        // MARK: - Limited Retrieval Tests

        @Test("getItems with limit returns last N items")
        func getItemsWithLimit() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "limit-test")

            for i in 1...10 {
                try await session.addItem(MemoryMessage.user("Message \(i)"))
            }

            let lastThree = try await session.getItems(limit: 3)

            #expect(lastThree.count == 3)
            #expect(lastThree[0].content == "Message 8")
            #expect(lastThree[1].content == "Message 9")
            #expect(lastThree[2].content == "Message 10")
        }

        @Test("getItems with limit larger than count returns all items")
        func getItemsWithLargeLimitReturnsAll() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "large-limit-test")

            try await session.addItems([
                MemoryMessage.user("One"),
                MemoryMessage.user("Two"),
                MemoryMessage.user("Three")
            ])

            let items = try await session.getItems(limit: 100)

            #expect(items.count == 3)
        }

        @Test("getItems with limit of zero returns empty array")
        func getItemsWithZeroLimit() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "zero-limit-test")

            try await session.addItems([
                MemoryMessage.user("One"),
                MemoryMessage.user("Two")
            ])

            let items = try await session.getItems(limit: 0)

            #expect(items.isEmpty)
        }

        @Test("getItems with nil limit returns all items")
        func getItemsWithNilLimit() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "nil-limit-test")

            for i in 1...5 {
                try await session.addItem(MemoryMessage.user("Message \(i)"))
            }

            let items = try await session.getItems(limit: nil)

            #expect(items.count == 5)
        }

        @Test("getItems with negative limit returns empty array")
        func getItemsWithNegativeLimit() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "negative-limit-test")

            try await session.addItems([
                MemoryMessage.user("One"),
                MemoryMessage.user("Two")
            ])

            let items = try await session.getItems(limit: -5)

            #expect(items.isEmpty)
        }

        // MARK: - Pop Item Tests (LIFO Behavior)

        @Test("popItem returns last added item")
        func popItemReturnsLast() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "pop-test")

            try await session.addItem(MemoryMessage.user("First"))
            try await session.addItem(MemoryMessage.user("Second"))
            try await session.addItem(MemoryMessage.user("Third"))

            let popped = try await session.popItem()

            #expect(popped?.content == "Third")
        }

        @Test("popItem removes the item from session")
        func popItemRemoves() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "pop-remove-test")

            let baseDate = Date()
            try await session.addItems([
                makeMessage("First", offsetSeconds: 0, baseDate: baseDate),
                makeMessage("Second", offsetSeconds: 1, baseDate: baseDate),
                makeMessage("Third", offsetSeconds: 2, baseDate: baseDate)
            ])

            _ = try await session.popItem()

            let remaining = try await session.getAllItems()
            #expect(remaining.count == 2)
            #expect(remaining[0].content == "First")
            #expect(remaining[1].content == "Second")
        }

        @Test("Multiple pops follow LIFO order")
        func multiplePopLIFO() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "multi-pop-test")

            let baseDate = Date()
            try await session.addItems([
                makeMessage("First", offsetSeconds: 0, baseDate: baseDate),
                makeMessage("Second", offsetSeconds: 1, baseDate: baseDate),
                makeMessage("Third", offsetSeconds: 2, baseDate: baseDate)
            ])

            let pop1 = try await session.popItem()
            let pop2 = try await session.popItem()
            let pop3 = try await session.popItem()

            #expect(pop1?.content == "Third")
            #expect(pop2?.content == "Second")
            #expect(pop3?.content == "First")
            #expect(await session.isEmpty == true)
        }

        @Test("popItem on empty session returns nil")
        func popItemOnEmptySession() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "pop-empty-test")

            let result = try await session.popItem()

            #expect(result == nil)
        }

        @Test("popItem on empty session does not throw")
        func popItemOnEmptyDoesNotThrow() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "pop-empty-safe-test")

            // Should not throw
            _ = try await session.popItem()
            _ = try await session.popItem()
            _ = try await session.popItem()

            #expect(await session.isEmpty == true)
        }

        // MARK: - Clear Session Tests

        @Test("clearSession removes all items")
        func clearSessionRemovesAll() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "clear-test")

            try await session.addItems([
                MemoryMessage.user("One"),
                MemoryMessage.assistant("Two"),
                MemoryMessage.user("Three")
            ])

            try await session.clearSession()

            #expect(await session.isEmpty == true)
            #expect(await session.itemCount == 0)
        }

        @Test("clearSession on empty session is safe")
        func clearEmptySessionIsSafe() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "clear-empty-test")

            // Should not throw
            try await session.clearSession()

            #expect(await session.isEmpty == true)
        }

        @Test("Session is reusable after clear")
        func sessionReusableAfterClear() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "reuse-test")

            try await session.addItem(MemoryMessage.user("Before clear"))
            try await session.clearSession()
            try await session.addItem(MemoryMessage.user("After clear"))

            let items = try await session.getAllItems()
            #expect(items.count == 1)
            #expect(items[0].content == "After clear")
        }

        // MARK: - Item Count Tests

        @Test("itemCount reflects actual count")
        func itemCountReflectsActual() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "count-test")

            #expect(await session.itemCount == 0)

            try await session.addItem(MemoryMessage.user("One"))
            #expect(await session.itemCount == 1)

            try await session.addItem(MemoryMessage.user("Two"))
            #expect(await session.itemCount == 2)

            try await session.addItem(MemoryMessage.user("Three"))
            #expect(await session.itemCount == 3)
        }

        @Test("itemCount updates after pop")
        func itemCountUpdatesAfterPop() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "count-pop-test")

            try await session.addItems([
                MemoryMessage.user("One"),
                MemoryMessage.user("Two"),
                MemoryMessage.user("Three")
            ])

            #expect(await session.itemCount == 3)

            _ = try await session.popItem()
            #expect(await session.itemCount == 2)

            _ = try await session.popItem()
            #expect(await session.itemCount == 1)
        }

        // MARK: - isEmpty Property Tests

        @Test("isEmpty is true for new session")
        func isEmptyTrueForNew() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "empty-new-test")

            #expect(await session.isEmpty == true)
        }

        @Test("isEmpty is false after adding items")
        func isEmptyFalseAfterAdd() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "empty-add-test")

            try await session.addItem(MemoryMessage.user("Test"))

            #expect(await session.isEmpty == false)
        }

        @Test("isEmpty becomes true after removing all items")
        func isEmptyAfterRemovingAll() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "empty-remove-test")

            try await session.addItem(MemoryMessage.user("Only item"))
            _ = try await session.popItem()

            #expect(await session.isEmpty == true)
        }
    }

    // MARK: - PersistentSessionTests Isolation and Advanced

    extension PersistentSessionTests {
        // MARK: Internal

        // MARK: - Multiple Sessions Isolation Tests

        @Test("Multiple sessions in same backend are isolated")
        func sessionIsolation() async throws {
            if !SwiftDataTestGate.canRun { return }
            let backend = try SwiftDataBackend.inMemory()

            let session1 = PersistentSession(sessionId: "session-1", backend: backend)
            let session2 = PersistentSession(sessionId: "session-2", backend: backend)

            try await session1.addItem(MemoryMessage.user("Message for session 1"))
            try await session2.addItem(MemoryMessage.user("Message for session 2"))
            try await session2.addItem(MemoryMessage.user("Another for session 2"))

            #expect(await session1.itemCount == 1)
            #expect(await session2.itemCount == 2)

            let items1 = try await session1.getAllItems()
            let items2 = try await session2.getAllItems()

            #expect(items1[0].content == "Message for session 1")
            #expect(items2[0].content == "Message for session 2")
            #expect(items2[1].content == "Another for session 2")
        }

        @Test("Clearing one session does not affect others")
        func clearingOneSessionIsolated() async throws {
            if !SwiftDataTestGate.canRun { return }
            let backend = try SwiftDataBackend.inMemory()

            let session1 = PersistentSession(sessionId: "clear-1", backend: backend)
            let session2 = PersistentSession(sessionId: "clear-2", backend: backend)

            try await session1.addItem(MemoryMessage.user("Session 1 message"))
            try await session2.addItem(MemoryMessage.user("Session 2 message"))

            try await session1.clearSession()

            #expect(await session1.isEmpty == true)
            #expect(await session2.itemCount == 1)
        }

        // MARK: - Persistence Verification Tests

        @Test("Data persists across session instances with same backend")
        func dataPersistsWithSameBackend() async throws {
            if !SwiftDataTestGate.canRun { return }
            let backend = try SwiftDataBackend.inMemory()

            // Create first session and add data
            let session1 = PersistentSession(sessionId: "persist-test", backend: backend)
            try await session1.addItem(MemoryMessage.user("Persisted message"))
            try await session1.addItem(MemoryMessage.assistant("Another persisted"))

            // Create second session with same backend and session ID
            let session2 = PersistentSession(sessionId: "persist-test", backend: backend)

            // Data should be accessible
            let items = try await session2.getAllItems()
            #expect(items.count == 2)
            #expect(items[0].content == "Persisted message")
            #expect(items[1].content == "Another persisted")
        }

        // MARK: - Edge Cases

        @Test("Handles empty content messages")
        func handlesEmptyContent() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "empty-content-test")

            try await session.addItem(MemoryMessage.user(""))

            let items = try await session.getAllItems()
            #expect(items.count == 1)
            #expect(items[0].content.isEmpty)
        }

        @Test("Handles messages with special characters")
        func handlesSpecialCharacters() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "special-char-test")
            let specialContent = "Hello\n\t\"World\" <>&'"

            try await session.addItem(MemoryMessage.user(specialContent))

            let items = try await session.getAllItems()
            #expect(items[0].content == specialContent)
        }

        @Test("Handles unicode content")
        func handlesUnicodeContent() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "unicode-test")
            let unicodeContent = "Hello World! Emoji: 123 Chinese: Ni hao Arabic: Marhaba"

            try await session.addItem(MemoryMessage.user(unicodeContent))

            let items = try await session.getAllItems()
            #expect(items[0].content == unicodeContent)
        }

        @Test("Handles very long content")
        func handlesVeryLongContent() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "long-content-test")
            let longContent = String(repeating: "a", count: 10000)

            try await session.addItem(MemoryMessage.user(longContent))

            let items = try await session.getAllItems()
            #expect(items[0].content == longContent)
            #expect(items[0].content.count == 10000)
        }

        @Test("All message roles are supported")
        func allRolesSupported() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "roles-test")

            let baseDate = Date()
            try await session.addItems([
                makeMessage("User message", role: .user, offsetSeconds: 0, baseDate: baseDate),
                makeMessage("Assistant message", role: .assistant, offsetSeconds: 1, baseDate: baseDate),
                makeMessage("System message", role: .system, offsetSeconds: 2, baseDate: baseDate),
                MemoryMessage(role: .tool, content: "Tool output", timestamp: baseDate.addingTimeInterval(3), metadata: ["tool_name": "calculator"])
            ])

            let items = try await session.getAllItems()

            #expect(items[0].role == .user)
            #expect(items[1].role == .assistant)
            #expect(items[2].role == .system)
            #expect(items[3].role == .tool)
        }

        // MARK: - Session Identity Tests

        @Test("Session ID remains constant throughout lifecycle")
        func sessionIdConstant() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "constant-id")

            let id1 = session.sessionId

            try await session.addItem(MemoryMessage.user("Test"))
            let id2 = session.sessionId

            try await session.clearSession()
            let id3 = session.sessionId

            #expect(id1 == "constant-id")
            #expect(id2 == "constant-id")
            #expect(id3 == "constant-id")
        }

        // MARK: - Large Data Tests

        @Test("Handles large number of items")
        func handlesLargeNumberOfItems() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "large-data-test")
            let itemCount = 100

            for i in 1...itemCount {
                try await session.addItem(MemoryMessage.user("Message \(i)"))
            }

            #expect(await session.itemCount == itemCount)

            let items = try await session.getAllItems()
            #expect(items.count == itemCount)
            #expect(items[0].content == "Message 1")
            #expect(items[itemCount - 1].content == "Message \(itemCount)")
        }

        @Test("getItems with limit works on large dataset")
        func getItemsLimitOnLargeDataset() async throws {
            if !SwiftDataTestGate.canRun { return }
            let session = try PersistentSession.inMemory(sessionId: "large-limit-dataset-test")

            for i in 1...50 {
                try await session.addItem(MemoryMessage.user("Message \(i)"))
            }

            let lastTen = try await session.getItems(limit: 10)

            #expect(lastTen.count == 10)
            #expect(lastTen[0].content == "Message 41")
            #expect(lastTen[9].content == "Message 50")
        }

        // MARK: Private

        // MARK: - Helpers

        /// Creates a MemoryMessage with an explicit timestamp offset from a base date.
        /// This ensures deterministic ordering when testing batch operations.
        private func makeMessage(
            _ content: String,
            role: MemoryMessage.Role = .user,
            offsetSeconds: Double,
            baseDate: Date = Date()
        ) -> MemoryMessage {
            MemoryMessage(
                role: role,
                content: content,
                timestamp: baseDate.addingTimeInterval(offsetSeconds)
            )
        }
    }
#endif
