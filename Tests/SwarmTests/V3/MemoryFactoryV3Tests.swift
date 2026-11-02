// MemoryFactoryV3Tests.swift
// SwarmTests
//
// Tests for Memory protocol factory extensions (V3 dot-syntax API).
// These factories allow: agent.withMemory(.conversation()), .slidingWindow(), etc.

import Testing
@testable import Swarm

// MARK: - Memory Factory V3 Tests

@Suite("Memory Factory Extensions (V3)")
struct MemoryFactoryV3Tests {

    // MARK: - ConversationMemory Factory

    @Test(".conversation() creates a ConversationMemory")
    func conversationFactory() async {
        let memory: ConversationMemory = .conversation()
        let count = await memory.count
        #expect(count == 0)
        #expect(await memory.isEmpty)
    }

    @Test(".conversation(maxMessages:) respects the cap")
    func conversationFactoryMaxMessages() async {
        let memory: ConversationMemory = .conversation(maxMessages: 5)
        #expect(await memory.maxMessages == 5)
    }

    @Test(".conversation() default maxMessages is 100")
    func conversationFactoryDefaultMaxMessages() async {
        let memory: ConversationMemory = .conversation()
        #expect(await memory.maxMessages == 100)
    }

    // MARK: - SlidingWindowMemory Factory

    @Test(".slidingWindow() creates a SlidingWindowMemory")
    func slidingWindowFactory() async {
        let memory: SlidingWindowMemory = .slidingWindow()
        let count = await memory.count
        #expect(count == 0)
        #expect(await memory.isEmpty)
    }

    @Test(".slidingWindow(maxTokens:) respects the limit")
    func slidingWindowFactoryMaxTokens() async {
        let memory: SlidingWindowMemory = .slidingWindow(maxTokens: 2000)
        #expect(await memory.maxTokens == 2000)
    }

    @Test(".slidingWindow() default maxTokens is 4000")
    func slidingWindowFactoryDefaultMaxTokens() async {
        let memory: SlidingWindowMemory = .slidingWindow()
        #expect(await memory.maxTokens == 4000)
    }

    // MARK: - PersistentMemory Factory

    @Test(".persistent(backend:) creates a PersistentMemory with InMemoryBackend")
    func persistentFactory() async {
        let memory: PersistentMemory = .persistent(backend: InMemoryBackend())
        let count = await memory.count
        #expect(count == 0)
        #expect(await memory.isEmpty)
    }

    @Test(".persistent(backend:) accepts a custom backend")
    func persistentFactoryCustomBackend() async {
        let backend = InMemoryBackend()
        let memory: PersistentMemory = .persistent(backend: backend)
        let count = await memory.count
        #expect(count == 0)
    }

    @Test(".persistent(backend:conversationId:) preserves the provided ID")
    func persistentFactoryConversationId() async {
        let id = "test-session-42"
        let memory: PersistentMemory = .persistent(backend: InMemoryBackend(), conversationId: id)
        #expect(await memory.conversationId == id)
    }

    @Test(".persistent(backend:maxMessages:) stores the limit")
    func persistentFactoryMaxMessages() async {
        let memory: PersistentMemory = .persistent(backend: InMemoryBackend(), maxMessages: 10)
        #expect(await memory.maxMessages == 10)
    }

    // MARK: - HybridMemory Factory

    @Test(".hybrid() creates a HybridMemory with default config")
    func hybridFactory() async {
        let memory: HybridMemory = .hybrid()
        let count = await memory.count
        #expect(count == 0)
        #expect(await memory.isEmpty)
    }

    @Test(".hybrid(configuration:) uses provided config")
    func hybridFactoryWithConfiguration() async {
        let config = HybridMemory.Configuration(
            shortTermMaxMessages: 15,
            longTermSummaryTokens: 500,
            summaryTokenRatio: 0.2,
            summarizationThreshold: 30
        )
        let memory: HybridMemory = .hybrid(configuration: config)
        #expect(await memory.configuration.shortTermMaxMessages == 15)
    }

    // MARK: - SummaryMemory Factory

    @Test(".summary() creates a SummaryMemory with default config")
    func summaryFactory() async {
        let memory: SummaryMemory = .summary()
        let count = await memory.count
        #expect(count == 0)
        #expect(await memory.isEmpty)
    }

    @Test(".summary(configuration:) uses provided config")
    func summaryFactoryWithConfiguration() async {
        let config = SummaryMemory.Configuration(
            recentMessageCount: 10,
            summarizationThreshold: 25,
            summaryTokenTarget: 300
        )
        let memory: SummaryMemory = .summary(configuration: config)
        #expect(await memory.configuration.recentMessageCount == 10)
    }

    // MARK: - VectorMemory Factory

    @Test(".vector(embeddingProvider:) creates a VectorMemory")
    func vectorFactory() async {
        let provider = MockEmbeddingProvider()
        let memory: VectorMemory = .vector(embeddingProvider: provider)
        let count = await memory.count
        #expect(count == 0)
        #expect(await memory.isEmpty)
    }

    @Test(".vector(embeddingProvider:similarityThreshold:) respects threshold")
    func vectorFactoryWithThreshold() async {
        let provider = MockEmbeddingProvider()
        let memory: VectorMemory = .vector(embeddingProvider: provider, similarityThreshold: 0.85)
        #expect(await memory.similarityThreshold == 0.85)
    }

    @Test(".vector(embeddingProvider:maxResults:) respects maxResults")
    func vectorFactoryWithMaxResults() async {
        let provider = MockEmbeddingProvider()
        let memory: VectorMemory = .vector(embeddingProvider: provider, maxResults: 5)
        #expect(await memory.maxResults == 5)
    }

    // MARK: - Dot-Syntax in Agent Modifier

    @Test("dot-syntax .conversation() works in withMemory modifier")
    func dotSyntaxConversationInAgentModifier() throws {
        let agent = try Agent("test agent")
            .withMemory(.conversation())
        #expect(agent.memory != nil)
    }

    @Test("dot-syntax .slidingWindow() works in withMemory modifier")
    func dotSyntaxSlidingWindowInAgentModifier() throws {
        let agent = try Agent("test agent")
            .withMemory(.slidingWindow(maxTokens: 2000))
        #expect(agent.memory != nil)
    }

    @Test("dot-syntax .persistent(backend:) works in withMemory modifier")
    func dotSyntaxPersistentInAgentModifier() throws {
        let agent = try Agent("test agent")
            .withMemory(.persistent(backend: InMemoryBackend()))
        #expect(agent.memory != nil)
    }

    @Test("dot-syntax .hybrid() works in withMemory modifier")
    func dotSyntaxHybridInAgentModifier() throws {
        let agent = try Agent("test agent")
            .withMemory(.hybrid())
        #expect(agent.memory != nil)
    }

    @Test("dot-syntax .summary() works in withMemory modifier")
    func dotSyntaxSummaryInAgentModifier() throws {
        let agent = try Agent("test agent")
            .withMemory(.summary())
        #expect(agent.memory != nil)
    }

    // MARK: - some Memory Parameter Acceptance

    @Test("factory result satisfies some Memory parameter")
    func someMemoryParameterConversation() {
        func acceptsMemory(_ memory: some Memory) -> Bool { true }
        let memory: ConversationMemory = .conversation()
        #expect(acceptsMemory(memory))
    }

    @Test("SlidingWindowMemory factory result satisfies some Memory parameter")
    func someMemoryParameterSlidingWindow() {
        func acceptsMemory(_ memory: some Memory) -> Bool { true }
        let memory: SlidingWindowMemory = .slidingWindow()
        #expect(acceptsMemory(memory))
    }

    @Test("PersistentMemory factory result satisfies some Memory parameter")
    func someMemoryParameterPersistent() {
        func acceptsMemory(_ memory: some Memory) -> Bool { true }
        let memory: PersistentMemory = .persistent(backend: InMemoryBackend())
        #expect(acceptsMemory(memory))
    }

    // MARK: - Store and retrieve round-trip

    @Test(".conversation() memory stores and retrieves messages")
    func conversationStoreAndRetrieve() async {
        let memory: ConversationMemory = .conversation(maxMessages: 10)
        await memory.add(.user("hello"))
        await memory.add(.assistant("hi there"))
        let messages = await memory.allMessages()
        #expect(messages.count == 2)
        #expect(messages[0].content == "hello")
        #expect(messages[1].content == "hi there")
    }

    @Test(".slidingWindow() memory stores messages within budget")
    func slidingWindowStoreAndRetrieve() async {
        let memory: SlidingWindowMemory = .slidingWindow(maxTokens: 4000)
        await memory.add(.user("a short message"))
        let messages = await memory.allMessages()
        #expect(messages.count == 1)
    }
}
