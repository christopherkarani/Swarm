import Foundation
@testable import Swarm
import Testing

/// Regression coverage for capability-witness dispatch on ``Memory``.
///
/// Every capability below is implemented WITHOUT declaring any of the
/// deprecated marker protocols (`MemorySessionLifecycle`,
/// `MemorySessionReplayAware`, `MemoryRetrievalPolicyAware`,
/// `MemorySessionImportPolicy`, `MemoryPromptDescriptor`). Under the former
/// marker-probe discovery these implementations were silently ignored; they
/// must now be dispatched through defaulted `Memory` requirements.
@Suite("Memory Capability Witness")
struct MemoryCapabilityWitnessTests {
    @Test("Implementing lifecycle methods without marker conformance fires through resolved hooks")
    func implementWithoutDeclareFiresThroughResolvedHooks() async throws {
        let memory = WitnessOnlyMemory(contextText: "witness-context")
        let hooks = MemoryHooks.resolved(from: memory)

        let begin = try #require(hooks.beginMemorySession)
        let end = try #require(hooks.endMemorySession)
        await begin()
        await end()

        #expect(await memory.beginCount == 1)
        #expect(await memory.endCount == 1)

        // Prompt metadata also resolves without any marker conformance.
        #expect(hooks.memoryPromptTitle == "Witness Title")
        #expect(hooks.memoryPriority == .primary)
    }

    @Test("Implementing lifecycle methods without marker conformance fires during an Agent run")
    func implementWithoutDeclareFiresDuringAgentRun() async throws {
        let memory = WitnessOnlyMemory(contextText: "witness-context")
        let provider = MockInferenceProvider(responses: ["ok"])
        let agent = try Agent(
            "You are helpful.",
            configuration: AgentConfiguration(name: "capability-witness", defaultTracingEnabled: false),
            memory: memory,
            inferenceProvider: provider
        )

        _ = try await agent.run("hello")

        #expect(await memory.beginCount == 1)
        #expect(await memory.endCount == 1)
    }

    @Test("Implementing retrieval policy without marker conformance routes item-aware queries")
    func implementWithoutDeclareRetrievalPolicyRoutesQueries() async throws {
        let memory = WitnessOnlyMemory(contextText: "witness-context")
        let hooks = MemoryHooks.resolved(from: memory)
        let contextForQuery = try #require(hooks.contextForQuery)

        let query = MemoryQuery(text: "obsidian", tokenLimit: 90, maxItems: 3, maxItemTokens: 30)
        let context = await contextForQuery(query)

        #expect(context == "witness-context")
        let observedQueries = await memory.queries
        #expect(observedQueries.count == 1)
        #expect(observedQueries.first?.maxItems == 3)
    }

    @Test("Implementing seeding opt-out without marker conformance is respected")
    func implementWithoutDeclareSeedingOptOutIsRespected() async throws {
        let memory = WitnessOnlyMemory(contextText: "", allowsAutomaticSessionSeeding: false)

        await memory.seedSessionHistoryIfNeeded([.user("should-not-import")])

        #expect(await memory.importedBatches.isEmpty)
    }
}

private actor WitnessOnlyMemory: Memory {
    let contextText: String
    nonisolated let allowsAutomaticSessionSeeding: Bool

    private(set) var beginCount = 0
    private(set) var endCount = 0
    private(set) var queries: [MemoryQuery] = []
    private(set) var importedBatches: [[MemoryMessage]] = []

    init(contextText: String, allowsAutomaticSessionSeeding: Bool = true) {
        self.contextText = contextText
        self.allowsAutomaticSessionSeeding = allowsAutomaticSessionSeeding
    }

    nonisolated var memoryPromptMetadata: MemoryPromptMetadata? {
        MemoryPromptMetadata(title: "Witness Title", guidance: nil, priority: .primary)
    }

    var count: Int { get async { 0 } }
    var isEmpty: Bool { get async { true } }

    func add(_ message: MemoryMessage) async {
        _ = message
    }

    func context(for query: String, tokenLimit: Int) async -> String {
        _ = query
        _ = tokenLimit
        return contextText
    }

    func context(for query: MemoryQuery) async -> String {
        queries.append(query)
        return contextText
    }

    func allMessages() async -> [MemoryMessage] { [] }
    func clear() async {}

    func beginMemorySession() async {
        beginCount += 1
    }

    func endMemorySession() async {
        endCount += 1
    }

    func importSessionHistory(_ messages: [MemoryMessage]) async {
        importedBatches.append(messages)
    }
}
