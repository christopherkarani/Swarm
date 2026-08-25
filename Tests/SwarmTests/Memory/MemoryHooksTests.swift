import Foundation
@testable import Swarm
import Testing

@Suite("Memory Hooks")
struct MemoryHooksTests {
    @Test("Memory without capability implementations resolves defaulted hooks")
    func memoryWithoutCapabilitiesResolvesDefaultedHooks() async throws {
        let memory = ConversationMemory()
        let hooks = MemoryHooks.resolved(from: memory)

        // Capability closures always wrap witnesses, defaulted ones included.
        let begin = try #require(hooks.beginMemorySession)
        let end = try #require(hooks.endMemorySession)
        await begin()
        await end()

        let contextForQuery = try #require(hooks.contextForQuery)
        let context = await contextForQuery(
            MemoryQuery(text: "query", tokenLimit: 10, maxItems: 1, maxItemTokens: 10)
        )
        #expect(context == "")

        // Prompt metadata defaults to nil for memories without descriptor data.
        #expect(hooks.memoryPromptTitle == nil)
        #expect(hooks.memoryPromptGuidance == nil)
        #expect(hooks.memoryPriority == nil)
        #expect(hooks.trackedSessionMemory == nil)
        #expect(hooks.allowsAutomaticSessionSeeding)

        // Default seed gate mirrors isEmpty; default replay appends via add(_:).
        let shouldImport = try #require(hooks.shouldImportSessionHistory)
        #expect(await shouldImport())

        let importHistory = try #require(hooks.importSessionHistory)
        await importHistory([.user("seeded")])
        #expect(await memory.count == 1)
    }

    @Test("Implemented capabilities fill hooks through witness dispatch")
    func implementedCapabilitiesFillHooks() async throws {
        let memory = RecordingLifecycleMemory()
        let hooks = MemoryHooks.resolved(from: memory)

        let begin = try #require(hooks.beginMemorySession)
        let end = try #require(hooks.endMemorySession)
        await begin()
        await end()

        #expect(await memory.beginCount == 1)
        #expect(await memory.endCount == 1)
        #expect(hooks.memoryPromptTitle == "Recording Title")
        #expect(hooks.memoryPriority == .primary)
        #expect(hooks.contextForQuery != nil)
    }

    @Test("Default and composite tracked session identity use ObjectIdentifier")
    func defaultVersusCompositeTrackedSessionIdentity() throws {
        let defaultMemory = ConversationMemory()
        let defaultTracked = try #require(
            resolvedTrackedSessionMemory(from: defaultMemory, defaultMemory: defaultMemory)
        )
        #expect(memoriesAreSameInstance(defaultMemory, defaultTracked))
        #expect(resolvedTrackedSessionMemory(from: ConversationMemory(), defaultMemory: defaultMemory) == nil)

        let tracked = ConversationMemory()
        let staticLayer = ConversationMemory()
        let composite = CompositeMemory([staticLayer, tracked], trackedSessionMemory: tracked)
        let resolvedTracked = try #require(
            resolvedTrackedSessionMemory(from: composite, defaultMemory: nil)
        )

        #expect(memoriesAreSameInstance(resolvedTracked, tracked))
        #expect(!memoriesAreSameInstance(resolvedTracked, composite))
        #expect(memoryObjectIdentifier(composite) != memoryObjectIdentifier(tracked))
        #expect(
            MemoryHooks.resolved(from: composite).trackedSessionMemory.map(memoryObjectIdentifier)
                == memoryObjectIdentifier(tracked)
        )
    }
}

private actor RecordingLifecycleMemory: Memory {
    nonisolated let memoryPromptTitle = "Recording Title"
    nonisolated let memoryPromptGuidance: String? = "Use recorded context."
    nonisolated let memoryPriority: MemoryPriorityHint = .primary

    nonisolated var memoryPromptMetadata: MemoryPromptMetadata? {
        MemoryPromptMetadata(
            title: memoryPromptTitle,
            guidance: memoryPromptGuidance,
            priority: memoryPriority
        )
    }

    private(set) var beginCount = 0
    private(set) var endCount = 0
    private(set) var lastQuery: MemoryQuery?

    var count: Int { get async { 0 } }
    var isEmpty: Bool { get async { true } }

    func add(_ message: MemoryMessage) async {
        _ = message
    }

    func context(for query: String, tokenLimit: Int) async -> String {
        _ = query
        _ = tokenLimit
        return "string-context"
    }

    func context(for query: MemoryQuery) async -> String {
        lastQuery = query
        return "query-context"
    }

    func allMessages() async -> [MemoryMessage] { [] }
    func clear() async {}

    func beginMemorySession() async {
        beginCount += 1
    }

    func endMemorySession() async {
        endCount += 1
    }
}
