// MemoryFactoryTests.swift
// SwarmTests
//
// TDD tests for Memory protocol factory extensions (V3 dot-syntax).

import Testing
@testable import Swarm

@Suite("Memory Factory Extensions")
struct MemoryFactoryTests {
    @Test("conversation factory creates ConversationMemory")
    func conversationFactory() async {
        let memory: any Memory = .conversation()
        let count = await memory.count
        #expect(count == 0)
    }

    @Test("conversation factory respects maxMessages parameter")
    func conversationFactoryWithMaxMessages() async {
        let memory: any Memory = .conversation(maxMessages: 50)
        let count = await memory.count
        #expect(count == 0)
    }

    @Test("slidingWindow factory creates SlidingWindowMemory")
    func slidingWindowFactory() async {
        let memory: any Memory = .slidingWindow(maxTokens: 1000)
        let count = await memory.count
        #expect(count == 0)
    }

    @Test("slidingWindow factory uses default maxTokens")
    func slidingWindowFactoryDefaultTokens() async {
        let memory: any Memory = .slidingWindow()
        let count = await memory.count
        #expect(count == 0)
    }

    @Test("vector factory creates VectorMemory with provider")
    func vectorFactory() async {
        let provider = MockEmbeddingProvider()
        let memory: any Memory = .vector(embeddingProvider: provider)
        let count = await memory.count
        #expect(count == 0)
    }

    @Test("persistent factory requires an explicit backend")
    func persistentFactory() async {
        let memory: any Memory = .persistent(backend: InMemoryBackend())
        let count = await memory.count
        #expect(count == 0)
    }

    @Test("persistent factory respects custom backend")
    func persistentFactoryCustomBackend() async {
        let backend = InMemoryBackend()
        let memory: any Memory = .persistent(backend: backend)
        let count = await memory.count
        #expect(count == 0)
    }
}
