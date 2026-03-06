// MemoryOptionTests.swift
// Tests for the V3 MemoryOption enum.

@testable import Swarm
import Testing

@Suite("MemoryOption")
struct MemoryOptionTests {
    @Test("none case")
    func noneCase() {
        let m: MemoryOption = .none
        if case .none = m { /* pass */ }
        else { Issue.record("Expected .none") }
    }

    @Test("conversation with default limit")
    func conversationDefault() {
        let m: MemoryOption = .conversation()
        if case .conversation(let limit) = m {
            #expect(limit == 50)
        } else {
            Issue.record("Expected .conversation")
        }
    }

    @Test("conversation with custom limit")
    func conversationCustom() {
        let m: MemoryOption = .conversation(limit: 100)
        if case .conversation(let limit) = m {
            #expect(limit == 100)
        } else {
            Issue.record("Expected .conversation")
        }
    }

    @Test("slidingWindow with default count")
    func slidingWindowDefault() {
        let m: MemoryOption = .slidingWindow()
        if case .slidingWindow(let count) = m {
            #expect(count == 20)
        } else {
            Issue.record("Expected .slidingWindow")
        }
    }

    @Test("vector with defaults")
    func vectorDefaults() {
        let m: MemoryOption = .vector()
        if case .vector(let dims, let topK) = m {
            #expect(dims == 384)
            #expect(topK == 5)
        } else {
            Issue.record("Expected .vector")
        }
    }

    @Test("summary with default maxTokens")
    func summaryDefault() {
        let m: MemoryOption = .summary()
        if case .summary(let maxTokens) = m {
            #expect(maxTokens == 2000)
        } else {
            Issue.record("Expected .summary")
        }
    }

    @Test("persistent with default store name")
    func persistentDefault() {
        let m: MemoryOption = .persistent()
        if case .persistent(let name) = m {
            #expect(name == "SwarmMemory")
        } else {
            Issue.record("Expected .persistent")
        }
    }

    @Test("hybrid composition")
    func hybrid() {
        let m: MemoryOption = .hybrid([.conversation(limit: 30), .slidingWindow(count: 10)])
        if case .hybrid(let options) = m {
            #expect(options.count == 2)
        } else {
            Issue.record("Expected .hybrid")
        }
    }

    // MARK: - resolve()

    @Test("none resolves to nil")
    func resolveNone() {
        let resolved = MemoryOption.none.resolve()
        #expect(resolved == nil)
    }

    @Test("conversation resolves to ConversationMemory")
    func resolveConversation() {
        let resolved = MemoryOption.conversation(limit: 25).resolve()
        #expect(resolved != nil)
        #expect(resolved is ConversationMemory)
    }

    @Test("slidingWindow resolves to SlidingWindowMemory")
    func resolveSlidingWindow() {
        let resolved = MemoryOption.slidingWindow(count: 15).resolve()
        #expect(resolved != nil)
        #expect(resolved is SlidingWindowMemory)
    }
}
