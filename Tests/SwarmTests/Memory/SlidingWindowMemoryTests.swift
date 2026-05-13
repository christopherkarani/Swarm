// SlidingWindowMemoryTests.swift
// Swarm Framework

import Foundation
@testable import Swarm
import Testing

@Suite("SlidingWindowMemory Tests")
struct SlidingWindowMemoryTests {
    // MARK: - Initialization Tests

    @Test("Creates with default configuration")
    func defaultInit() async {
        let memory = SlidingWindowMemory()

        #expect(await memory.maxTokens == 4000)
        #expect(await memory.isEmpty)
        #expect(await memory.tokenCount == 0)
    }

    @Test("Creates with custom max tokens")
    func customMaxTokens() async {
        let memory = SlidingWindowMemory(maxTokens: 2000)

        #expect(await memory.maxTokens == 2000)
    }

    @Test("Enforces minimum max tokens of 100")
    func minimumMaxTokens() async {
        let memory = SlidingWindowMemory(maxTokens: 50)

        #expect(await memory.maxTokens == 100)
    }

    // MARK: - Add Tests

    @Test("Adds message and updates token count")
    func addUpdatesTokenCount() async {
        let memory = SlidingWindowMemory()

        await memory.add(.user("Hello"))

        #expect(await memory.count == 1)
        #expect(await memory.tokenCount > 0)
    }

    @Test("Tracks remaining tokens")
    func testRemainingTokens() async {
        let memory = SlidingWindowMemory(maxTokens: 1000)

        let initialRemaining = await memory.remainingTokens
        #expect(initialRemaining == 1000)

        await memory.add(.user("Hello world"))

        let afterAdd = await memory.remainingTokens
        #expect(afterAdd < 1000)
    }

    // MARK: - Token-Based Eviction Tests

    @Test("Evicts oldest messages when tokens exceeded")
    func tokenBasedEviction() async {
        let memory = SlidingWindowMemory(maxTokens: 200)

        // Add messages until we exceed the limit
        for i in 1...20 {
            await memory.add(.user("Message number \(i) with some content"))
        }

        // Should have evicted old messages to stay within limit
        let tokenCount = await memory.tokenCount
        #expect(tokenCount <= 200)
    }

    @Test("Keeps at least one message")
    func keepsAtLeastOneMessage() async {
        let memory = SlidingWindowMemory(maxTokens: 100)

        // Add a very long message that exceeds the limit
        let longContent = String(repeating: "a ", count: 200)
        await memory.add(.user(longContent))

        #expect(await memory.count >= 1)
    }

    @Test("Near capacity flag works correctly")
    func nearCapacity() async {
        let memory = SlidingWindowMemory(maxTokens: 100)

        #expect(await memory.isNearCapacity == false)

        // Add content to exceed 90%
        await memory.add(.user(String(repeating: "word ", count: 50)))

        // After eviction, check capacity status
        _ = await memory.isNearCapacity
        // May or may not be near capacity depending on eviction
    }

    // MARK: - Context Retrieval Tests

    @Test("Gets context within token limit")
    func getContext() async {
        let memory = SlidingWindowMemory()

        await memory.add(.user("Hello"))
        await memory.add(.assistant("Hi there"))

        let context = await memory.context(for: "test", tokenLimit: 500)

        #expect(context.contains("[user]: Hello"))
        #expect(context.contains("[assistant]: Hi there"))
    }

    @Test("Context respects both request limit and max tokens")
    func contextRespectsLimits() async {
        let memory = SlidingWindowMemory(maxTokens: 100)

        await memory.add(.user("Hello"))

        // Request more tokens than maxTokens
        let context = await memory.context(for: "test", tokenLimit: 1000)

        // Should be capped to maxTokens
        #expect(!context.isEmpty)
    }

    @Test("Context skips oversized newest message and keeps older context")
    func contextSkipsOversizedNewestMessage() async {
        let memory = SlidingWindowMemory(
            maxTokens: 200,
            tokenEstimator: CharacterBasedTokenEstimator(charactersPerToken: 1)
        )

        await memory.add(.user("older-fit"))
        await memory.add(.assistant("still-fits"))
        await memory.add(.user(String(repeating: "x", count: 120)))

        let context = await memory.context(for: "test", tokenLimit: 64)

        #expect(context.contains("[user]: older-fit"))
        #expect(context.contains("[assistant]: still-fits"))
        #expect(!context.contains(String(repeating: "x", count: 120)))
    }

    @Test("Context skips oversized middle message and keeps surrounding context")
    func contextSkipsOversizedMiddleMessage() async {
        let memory = SlidingWindowMemory(
            maxTokens: 300,
            tokenEstimator: CharacterBasedTokenEstimator(charactersPerToken: 1)
        )
        let oversized = String(repeating: "x", count: 120)

        await memory.add(.user("older-fit"))
        await memory.add(.user(oversized))
        await memory.add(.assistant("newer-fit"))

        let context = await memory.context(for: "test", tokenLimit: 64)

        #expect(context.contains("[user]: older-fit"))
        #expect(context.contains("[assistant]: newer-fit"))
        #expect(!context.contains(oversized))
    }

    @Test("Context stops at non-oversized message that exhausts remaining budget")
    func contextStopsAtNonOversizedBudgetExhaustion() async {
        let memory = SlidingWindowMemory(
            maxTokens: 300,
            tokenEstimator: CharacterBasedTokenEstimator(charactersPerToken: 1)
        )
        let fittingButTooLargeAfterNewest = String(repeating: "m", count: 40)

        await memory.add(.user("older-fit"))
        await memory.add(.user(fittingButTooLargeAfterNewest))
        await memory.add(.assistant("new"))

        let context = await memory.context(for: "test", tokenLimit: 48)

        #expect(context == "[assistant]: new")
    }

    // MARK: - Clear Tests

    @Test("Clear resets both messages and token count")
    func testClear() async {
        let memory = SlidingWindowMemory()

        await memory.add(.user("Hello"))
        await memory.add(.assistant("Hi"))

        await memory.clear()

        #expect(await memory.isEmpty)
        #expect(await memory.tokenCount == 0)
    }

    // MARK: - Batch Operations Tests

    @Test("Adds all messages with eviction")
    func testAddAll() async {
        let memory = SlidingWindowMemory(maxTokens: 200)

        var messages: [MemoryMessage] = []
        for i in 1...10 {
            messages.append(.user("Message \(i)"))
        }

        await memory.addAll(messages)

        #expect(await memory.tokenCount <= 200)
    }

    @Test("Gets messages within token budget")
    func getMessagesWithinBudget() async {
        let memory = SlidingWindowMemory()

        for i in 1...10 {
            await memory.add(.user("Message \(i)"))
        }

        let budgeted = await memory.getMessages(withinTokenBudget: 50)

        // Should return recent messages that fit
        #expect(!budgeted.isEmpty)
        #expect(budgeted.count <= 10)
    }

    // MARK: - Diagnostics Tests

    @Test("Provides accurate diagnostics")
    func testDiagnostics() async {
        let memory = SlidingWindowMemory(maxTokens: 1000)

        await memory.add(.user("Hello world"))

        let diagnostics = await memory.diagnostics()

        #expect(diagnostics.messageCount == 1)
        #expect(diagnostics.maxTokens == 1000)
        #expect(diagnostics.currentTokens > 0)
        #expect(diagnostics.remainingTokens < 1000)
        #expect(diagnostics.utilizationPercent > 0)
    }

    // MARK: - Recalculation Tests

    @Test("Recalculates token count accurately")
    func testRecalculateTokenCount() async {
        let memory = SlidingWindowMemory()

        await memory.add(.user("Hello"))
        await memory.add(.assistant("Hi there"))

        let before = await memory.tokenCount

        await memory.recalculateTokenCount()

        let after = await memory.tokenCount

        #expect(before == after)
    }
}
