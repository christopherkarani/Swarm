// HybridMemoryTests.swift
// Swarm Framework

import Foundation
@testable import Swarm
import Testing

@Suite("HybridMemory Tests")
struct HybridMemoryTests {
    // MARK: - Initialization Tests

    @Test("Creates with default configuration")
    func defaultInit() async {
        let memory = HybridMemory()

        let config = await memory.configuration
        #expect(config.shortTermMaxMessages == 30)
        #expect(config.longTermSummaryTokens == 1000)
        #expect(config.summaryTokenRatio == 0.3)
    }

    @Test("Creates with custom configuration")
    func customConfiguration() async {
        let config = HybridMemory.Configuration(
            shortTermMaxMessages: 20,
            longTermSummaryTokens: 500,
            summaryTokenRatio: 0.4,
            summarizationThreshold: 40
        )
        let memory = HybridMemory(configuration: config)

        let memoryConfig = await memory.configuration
        #expect(memoryConfig.shortTermMaxMessages == 20)
        #expect(memoryConfig.summaryTokenRatio == 0.4)
    }

    @Test("Configuration enforces bounds")
    func configurationBounds() async {
        let config = HybridMemory.Configuration(
            shortTermMaxMessages: 5,
            longTermSummaryTokens: 50,
            summaryTokenRatio: 0.8, // Should be capped to 0.5
            summarizationThreshold: 10
        )

        #expect(config.shortTermMaxMessages >= 10)
        #expect(config.longTermSummaryTokens >= 200)
        #expect(config.summaryTokenRatio <= 0.5)
    }

    // MARK: - Add Tests

    @Test("Adds messages to short-term memory")
    func addToShortTerm() async {
        let memory = HybridMemory()

        await memory.add(.user("Hello"))
        await memory.add(.assistant("Hi there"))

        #expect(await memory.count == 2)
    }

    @Test("Tracks total messages")
    func testTotalMessages() async {
        let memory = HybridMemory()

        await memory.add(.user("1"))
        await memory.add(.user("2"))
        await memory.add(.user("3"))

        #expect(await memory.totalMessages == 3)
    }

    // MARK: - Summarization Tests

    @Test("Triggers summarization at threshold")
    func summarizationTrigger() async {
        let mockSummarizer = MockSummarizer()
        await mockSummarizer.stub(result: "Hybrid summary")

        let config = HybridMemory.Configuration(
            shortTermMaxMessages: 10,
            summarizationThreshold: 20
        )
        let memory = HybridMemory(
            configuration: config,
            summarizer: mockSummarizer
        )

        for i in 1...20 {
            await memory.add(.user("Message \(i)"))
        }

        let callCount = await mockSummarizer.callCount
        #expect(callCount >= 1)
    }

    @Test("Creates long-term summary")
    func createsLongTermSummary() async {
        let mockSummarizer = MockSummarizer()
        await mockSummarizer.stub(result: "Long-term summary content")

        let config = HybridMemory.Configuration(
            shortTermMaxMessages: 10,
            summarizationThreshold: 20
        )
        let memory = HybridMemory(
            configuration: config,
            summarizer: mockSummarizer
        )

        for i in 1...20 {
            await memory.add(.user("Message \(i)"))
        }

        #expect(await memory.hasSummary == true)
        #expect(await memory.summary == "Long-term summary content")
    }

    @Test("Does not lose pending messages when summarizer is unavailable")
    func preservesPendingMessagesWhenSummarizerUnavailable() async {
        let mockSummarizer = MockSummarizer(isAvailable: false)

        let config = HybridMemory.Configuration(
            shortTermMaxMessages: 10,
            summarizationThreshold: 20
        )
        let memory = HybridMemory(
            configuration: config,
            summarizer: mockSummarizer
        )

        for i in 1...20 {
            await memory.add(.user("Unavailable message \(i)"))
        }

        let diagnostics = await memory.diagnostics()
        #expect(diagnostics.pendingMessages > 0 || diagnostics.hasSummary)

        if !diagnostics.hasSummary {
            await mockSummarizer.stub(available: true)
            await mockSummarizer.stub(result: "Recovered summary")
            await memory.forceSummarize()
            #expect(await memory.summary == "Recovered summary")
        }
    }

    // MARK: - Context Retrieval Tests

    @Test("Context includes recent messages without summary")
    func contextWithoutSummary() async {
        let memory = HybridMemory()

        await memory.add(.user("Hello"))
        await memory.add(.assistant("Hi"))

        let context = await memory.context(for: "test", tokenLimit: 1000)

        #expect(context.contains("[user]: Hello"))
        #expect(context.contains("[assistant]: Hi"))
    }

    @Test("Context includes both summary and recent messages")
    func contextWithSummaryAndRecent() async {
        let mockSummarizer = MockSummarizer()
        await mockSummarizer.stub(result: "Summary of history")

        // Note: With shortTermMaxMessages=10, minimum threshold is 20 (10*2)
        let config = HybridMemory.Configuration(
            shortTermMaxMessages: 10,
            summarizationThreshold: 20
        )
        let memory = HybridMemory(
            configuration: config,
            summarizer: mockSummarizer
        )

        for i in 1...20 {
            await memory.add(.user("Message \(i)"))
        }

        let context = await memory.context(for: "test", tokenLimit: 2000)

        #expect(context.contains("summary"))
        #expect(context.contains("Recent conversation"))
    }

    @Test("Context respects token budget allocation")
    func tokenBudgetAllocation() async {
        let memory = HybridMemory(
            configuration: .init(summaryTokenRatio: 0.3)
        )

        await memory.add(.user("Test message"))

        // Request small token limit
        let context = await memory.context(for: "test", tokenLimit: 100)

        // Should still return something
        #expect(!context.isEmpty)
    }

    // MARK: - Clear Tests

    @Test("Clear removes all data")
    func testClear() async {
        let mockSummarizer = MockSummarizer()
        await mockSummarizer.stub(result: "Test summary")

        // Note: With shortTermMaxMessages=10, minimum threshold is 20 (10*2)
        let config = HybridMemory.Configuration(
            shortTermMaxMessages: 10,
            summarizationThreshold: 20
        )
        let memory = HybridMemory(
            configuration: config,
            summarizer: mockSummarizer
        )

        for i in 1...20 {
            await memory.add(.user("Message \(i)"))
        }

        await memory.clear()

        #expect(await memory.isEmpty)
        #expect(await memory.hasSummary == false)
        #expect(await memory.totalMessages == 0)
    }

    // MARK: - Manual Operations Tests

    @Test("Force summarize works")
    func testForceSummarize() async {
        let mockSummarizer = MockSummarizer()
        await mockSummarizer.stub(result: "Forced summary")

        let config = HybridMemory.Configuration(
            shortTermMaxMessages: 10,
            summarizationThreshold: 100
        )
        let memory = HybridMemory(
            configuration: config,
            summarizer: mockSummarizer
        )

        // 15 messages through a 10-message window: 5 are evicted and summarizable.
        for i in 1...15 {
            await memory.add(.user("Message \(i)"))
        }

        await memory.forceSummarize()

        #expect(await memory.hasSummary == true)
    }

    @Test("Set custom summary")
    func testSetSummary() async {
        let memory = HybridMemory()

        await memory.setSummary("Custom long-term summary")

        #expect(await memory.summary == "Custom long-term summary")
    }

    @Test("Clear summary keeps short-term messages")
    func testClearSummary() async {
        let mockSummarizer = MockSummarizer()
        await mockSummarizer.stub(result: "Test summary")

        // Note: With shortTermMaxMessages=10, minimum threshold is 20 (10*2)
        let config = HybridMemory.Configuration(
            shortTermMaxMessages: 10,
            summarizationThreshold: 20
        )
        let memory = HybridMemory(
            configuration: config,
            summarizer: mockSummarizer
        )

        for i in 1...20 {
            await memory.add(.user("Message \(i)"))
        }

        await memory.clearSummary()

        #expect(await memory.hasSummary == false)
        #expect(await memory.isEmpty == false) // Short-term messages kept
    }

    // MARK: - Diagnostics Tests

    @Test("Provides accurate diagnostics")
    func testDiagnostics() async {
        let mockSummarizer = MockSummarizer()
        await mockSummarizer.stub(result: "Summary")

        // Note: With shortTermMaxMessages=10, minimum threshold is 20 (10*2)
        let config = HybridMemory.Configuration(
            shortTermMaxMessages: 10,
            summarizationThreshold: 20
        )
        let memory = HybridMemory(
            configuration: config,
            summarizer: mockSummarizer
        )

        for i in 1...20 {
            await memory.add(.user("Message \(i)"))
        }

        let diagnostics = await memory.diagnostics()

        #expect(diagnostics.shortTermMaxMessages == 10)
        #expect(diagnostics.totalMessagesProcessed == 20)
        #expect(diagnostics.hasSummary == true)
        #expect(diagnostics.summarizationCount >= 1)
    }
    // MARK: - Double-Context Regression Tests

    @Test("Summary input only contains messages evicted from the short-term window")
    func summarizesOnlyEvictedMessages() async throws {
        let mockSummarizer = MockSummarizer()
        await mockSummarizer.stub(result: "Evicted summary")

        let memory = HybridMemory(
            configuration: .init(shortTermMaxMessages: 10, summarizationThreshold: 20),
            summarizer: mockSummarizer
        )

        for i in 1...20 {
            await memory.add(.user("Message #\(i)#"))
        }

        let call = try #require(await mockSummarizer.lastCall)
        for i in 1...10 {
            #expect(call.text.contains("Message #\(i)#"), "evicted message \(i) should be summarized")
        }
        for i in 11...20 {
            #expect(!call.text.contains("Message #\(i)#"), "in-window message \(i) must not be summarized")
        }
    }

    @Test("Context never sends a message both in the summary and the recent window")
    func contextHasNoDuplicatedMessages() async {
        let memory = HybridMemory(
            configuration: .init(shortTermMaxMessages: 10, summarizationThreshold: 20),
            summarizer: TruncatingSummarizer.shared
        )

        for i in 1...20 {
            await memory.add(.user("Message #\(i)#"))
        }

        let context = await memory.context(for: "q", tokenLimit: 100_000)
        for i in 1...20 {
            let occurrences = context.components(separatedBy: "Message #\(i)#").count - 1
            #expect(occurrences <= 1, "message \(i) appears \(occurrences) times")
        }
        #expect(await memory.diagnostics().pendingMessages == 0)
    }

    @Test("Force summarize leaves in-window messages alone")
    func forceSummarizeSkipsWindow() async {
        let mockSummarizer = MockSummarizer()
        await mockSummarizer.stub(result: "Forced summary")

        let memory = HybridMemory(
            configuration: .init(shortTermMaxMessages: 10, summarizationThreshold: 100),
            summarizer: mockSummarizer
        )
        for i in 1...5 {
            await memory.add(.user("Message \(i)"))
        }

        await memory.forceSummarize()

        #expect(await mockSummarizer.callCount == 0)
        #expect(await memory.hasSummary == false)
    }

    @Test("Threshold clamp uses the clamped short-term size")
    func thresholdClampUsesClampedWindow() {
        let config = HybridMemory.Configuration(
            shortTermMaxMessages: 5, // clamped to 10
            summarizationThreshold: 15
        )

        #expect(config.shortTermMaxMessages == 10)
        #expect(config.summarizationThreshold == 20)
    }
}
