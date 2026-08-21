import Foundation
@testable import Swarm
import Testing

@Suite("Memory Hooks")
struct MemoryHooksTests {
    @Test("Memory requirements fill hooks without marker conformances")
    func memoryWithoutLifecycleResolvesToProtocolDefaults() async {
        let memory = ConversationMemory()
        let hooks = MemoryHooks.resolved(from: memory)

        #expect(hooks.beginMemorySession != nil)
        #expect(hooks.endMemorySession != nil)
        #expect(hooks.contextForQuery != nil)
        #expect(hooks.memoryPromptTitle == "Relevant Context from Memory")
        #expect(hooks.memoryPromptGuidance == nil)
        #expect(hooks.memoryPriority == .primary)
        #expect(hooks.trackedSessionMemory == nil)
        #expect(hooks.allowsAutomaticSessionSeeding)
        #expect(hooks.shouldImportSessionHistory != nil)
        #expect(hooks.importSessionHistory != nil)
    }

    @Test("Public marker protocols still fill hooks through the shim")
    func publicMarkerProtocolsFillHooks() async throws {
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

private actor RecordingLifecycleMemory: Memory, MemorySessionLifecycle, MemoryPromptDescriptor, MemoryRetrievalPolicyAware {
    nonisolated let memoryPromptTitle = "Recording Title"
    nonisolated let memoryPromptGuidance: String? = "Use recorded context."
    nonisolated let memoryPriority: MemoryPriorityHint = .primary

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
