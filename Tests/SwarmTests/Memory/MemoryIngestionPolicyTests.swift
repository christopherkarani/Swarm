import Testing
@testable import Swarm

@Suite("Memory Ingestion Policy")
struct MemoryIngestionPolicyTests {
    @Test("Agent stores tool results in memory")
    func agentStoresToolResults() async throws {
        let tool = MockTool(name: "mock_tool", result: .string("ok"))

        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                toolCalls: [.init(id: "1", name: "mock_tool", arguments: [:])],
                finishReason: .toolCall
            ),
            InferenceResponse(content: "done", finishReason: .completed)
        ])

        let memory = MockAgentMemory()
        let agent = try Agent(
            tools: [tool],
            configuration: .default.maxIterations(3),
            memory: memory,
            inferenceProvider: provider
        )

        let result = try await agent.run("hi")
        #expect(result.output == "done")

        let added = await memory.addCalls
        #expect(added.contains(where: { message in
            message.role == .tool
                && message.metadata["tool_name"] == "mock_tool"
                && message.content.contains("ok")
        }))
    }

    @Test("No-session runs do not store transcript turns in explicit memory")
    func noSessionRunDoesNotStoreTranscriptTurnsInExplicitMemory() async throws {
        let provider = MockInferenceProvider(responses: ["Final Answer: ok"])
        let memory = MockAgentMemory()

        let agent = try Agent(
            memory: memory,
            inferenceProvider: provider
        )

        _ = try await agent.run("hi")

        let added = await memory.addCalls
        #expect(!added.contains(where: { $0.role == .user || $0.role == .assistant }))
    }

    @Test("Session history is seeded only when memory is empty")
    func sessionHistorySeedsOnce() async throws {
        let session = InMemorySession(sessionId: "test")
        try await session.addItems([
            .user("seed-user"),
            .assistant("seed-assistant")
        ])

        let provider = MockInferenceProvider(responses: ["Final Answer: ok"])
        let memory = MockAgentMemory()

        let agent = try Agent(
            memory: memory,
            inferenceProvider: provider
        )

        _ = try await agent.run("turn-1", session: session)
        _ = try await agent.run("turn-2", session: session)

        let added = await memory.addCalls
        let seededUserCount = added.filter { $0.content == "seed-user" }.count
        let seededAssistantCount = added.filter { $0.content == "seed-assistant" }.count

        #expect(seededUserCount == 1)
        #expect(seededAssistantCount == 1)
    }

    @Test("Composite memory seeds only eligible child memories")
    func compositeMemoryRespectsChildImportPolicy() async throws {
        let session = InMemorySession(sessionId: "composite-policy")
        try await session.addItems([
            .user("composite-seed-user"),
            .assistant("composite-seed-assistant")
        ])

        let seedable = MockAgentMemory()
        let optOut = OptOutMemory()
        let composite = CompositeMemory([seedable, optOut])

        let provider = MockInferenceProvider(responses: ["ok"])
        let agent = try Agent(
            memory: composite,
            inferenceProvider: provider
        )

        _ = try await agent.run("turn", session: session)

        let seedableMessages = await seedable.addCalls.map(\.content)
        let optOutMessages = await optOut.addCalls.map(\.content)

        #expect(seedableMessages.contains("composite-seed-user"))
        #expect(seedableMessages.contains("composite-seed-assistant"))
        #expect(optOutMessages.isEmpty)
    }

    @Test("Composite memory gives a sole matching layer the full token budget")
    func compositeMemoryDoesNotReserveBudgetForNoHitLayers() async throws {
        let matching = RecordingContextMemory(context: "primary context includes the obsidian-tail marker.")
        let noHit = RecordingContextMemory(context: "", isEmpty: false)
        let composite = CompositeMemory([matching, noHit])

        let context = await composite.context(for: "obsidian", tokenLimit: 120)

        #expect(context.contains("obsidian-tail marker"))
        #expect(await matching.observedTokenLimits == [120])
        #expect(await noHit.observedTokenLimits == [120])
    }
}

private actor OptOutMemory: Memory, MemorySessionImportPolicy {
    nonisolated let allowsAutomaticSessionSeeding = false
    private(set) var addCalls: [MemoryMessage] = []

    var count: Int { get async { addCalls.count } }
    var isEmpty: Bool { get async { addCalls.isEmpty } }

    func add(_ message: MemoryMessage) async {
        addCalls.append(message)
    }

    func context(for query: String, tokenLimit: Int) async -> String {
        _ = query
        _ = tokenLimit
        return addCalls.map(\.formattedContent).joined(separator: "\n")
    }

    func allMessages() async -> [MemoryMessage] {
        addCalls
    }

    func clear() async {
        addCalls.removeAll()
    }
}

private actor RecordingContextMemory: Memory {
    private let contextText: String
    private let empty: Bool
    private(set) var observedTokenLimits: [Int] = []

    init(context: String, isEmpty: Bool = true) {
        self.contextText = context
        self.empty = isEmpty
    }

    var count: Int { get async { empty ? 0 : 1 } }
    var isEmpty: Bool { get async { empty } }

    func add(_ message: MemoryMessage) async {
        _ = message
    }

    func context(for query: String, tokenLimit: Int) async -> String {
        _ = query
        observedTokenLimits.append(tokenLimit)
        return contextText
    }

    func allMessages() async -> [MemoryMessage] {
        []
    }

    func clear() async {
        observedTokenLimits.removeAll()
    }
}
