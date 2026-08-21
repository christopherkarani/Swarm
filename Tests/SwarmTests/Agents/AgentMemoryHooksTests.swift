import Foundation
@testable import Swarm
import Testing

@Suite("Agent Memory Hooks")
struct AgentMemoryHooksTests {
    @Test("Session run with Memory-only store is a lifecycle no-op")
    func memoryWithoutLifecycleIsSessionNoOp() async throws {
        let memory = ConversationMemory()
        let provider = MockInferenceProvider(responses: ["ok"])
        let session = InMemorySession(sessionId: "memory-only-noop")
        let agent = try Agent(
            "You are helpful.",
            configuration: AgentConfiguration(name: "memory-only", defaultTracingEnabled: false),
            memory: memory,
            inferenceProvider: provider
        )

        let result = try await agent.run("hello", session: session)

        #expect(result.output == "ok")
        #expect(MemoryHooks.resolved(from: memory).beginMemorySession != nil)
        #expect(MemoryHooks.resolved(from: memory).endMemorySession != nil)
    }

    @Test("Agent still invokes lifecycle through resolved hooks")
    func agentInvokesLifecycleThroughHooks() async throws {
        let memory = SessionLifecycleProbeMemory()
        let provider = MockInferenceProvider(responses: ["ok"])
        let agent = try Agent(
            "You are helpful.",
            configuration: AgentConfiguration(name: "lifecycle-shim", defaultTracingEnabled: false),
            memory: memory,
            inferenceProvider: provider
        )

        _ = try await agent.run("hello", session: InMemorySession(sessionId: "lifecycle-shim"))

        #expect(await memory.beginCount == 1)
        #expect(await memory.endCount == 1)
    }

    @Test("Default memory session identity clears prior session context")
    func defaultMemorySessionIdentityClearsOnSessionSwitch() async throws {
        let provider = MockInferenceProvider(responses: ["first", "second"])
        let agent = try Agent(
            "You are helpful.",
            configuration: AgentConfiguration(name: "default-identity", defaultTracingEnabled: false),
            inferenceProvider: provider
        )

        let sessionA = InMemorySession(sessionId: "default-session-a")
        try await sessionA.addItems([.user("alpha-session-marker")])
        _ = try await agent.run("turn-a", session: sessionA)

        let sessionB = InMemorySession(sessionId: "default-session-b")
        try await sessionB.addItems([.user("beta-session-marker")])
        _ = try await agent.run("turn-b", session: sessionB)

        let calls = await provider.generateMessageCalls
        #expect(calls.count == 2)
        let secondSystem = try #require(calls[1].messages.first(where: { $0.role == .system })?.content)
        #expect(!secondSystem.contains("alpha-session-marker"))
        #expect(secondSystem.contains("beta-session-marker"))
    }

    @Test("Composite tracked session identity clears only the tracked layer")
    func compositeTrackedSessionIdentityClearsTrackedLayerOnly() async throws {
        let tracked = ConversationMemory()
        let staticLayer = ConversationMemory()
        await staticLayer.add(.user("static-layer-marker"))
        let composite = CompositeMemory([staticLayer, tracked], trackedSessionMemory: tracked)

        #expect(
            memoriesAreSameInstance(
                try #require(resolvedTrackedSessionMemory(from: composite, defaultMemory: nil)),
                tracked
            )
        )

        let provider = MockInferenceProvider(responses: ["first", "second"])
        let agent = try Agent(
            "You are helpful.",
            configuration: AgentConfiguration(name: "composite-identity", defaultTracingEnabled: false),
            memory: composite,
            inferenceProvider: provider
        )

        let sessionA = InMemorySession(sessionId: "composite-session-a")
        try await sessionA.addItems([.user("alpha-session-marker")])
        _ = try await agent.run("turn-a", session: sessionA)

        let sessionB = InMemorySession(sessionId: "composite-session-b")
        try await sessionB.addItems([.user("beta-session-marker")])
        _ = try await agent.run("turn-b", session: sessionB)

        let trackedContents = await tracked.allMessages().map(\.content)
        let staticContents = await staticLayer.allMessages().map(\.content)

        #expect(!trackedContents.contains(where: { $0.contains("alpha-session-marker") }))
        #expect(trackedContents.contains(where: { $0.contains("beta-session-marker") }))
        #expect(staticContents.contains(where: { $0.contains("static-layer-marker") }))
        #expect(!staticContents.contains(where: { $0.contains("alpha-session-marker") }))
    }

    @Test("Agent uses prompt descriptor fields from resolved hooks")
    func agentUsesPromptDescriptorFromHooks() async throws {
        let memory = TitledMemory(context: "titled-context-marker")
        let provider = MockInferenceProvider(responses: ["ok"])
        let agent = try Agent(
            "You are helpful.",
            configuration: AgentConfiguration(name: "prompt-hooks", defaultTracingEnabled: false),
            memory: memory,
            inferenceProvider: provider
        )

        _ = try await agent.run("hello")

        let system = try #require(
            await provider.generateMessageCalls.last?.messages.first(where: { $0.role == .system })?.content
        )
        #expect(system.contains("Custom Hook Title"))
        #expect(system.contains("Treat hooks as primary."))
        #expect(system.contains("titled-context-marker"))
    }
}

private actor SessionLifecycleProbeMemory: Memory, MemorySessionLifecycle {
    private(set) var beginCount = 0
    private(set) var endCount = 0

    var count: Int { get async { 0 } }
    var isEmpty: Bool { get async { true } }

    func add(_ message: MemoryMessage) async {
        _ = message
    }

    func context(for query: String, tokenLimit: Int) async -> String {
        _ = query
        _ = tokenLimit
        return ""
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

private actor TitledMemory: Memory, MemoryPromptDescriptor {
    nonisolated let memoryPromptTitle = "Custom Hook Title"
    nonisolated let memoryPromptGuidance: String? = "Treat hooks as primary."
    nonisolated let memoryPriority: MemoryPriorityHint = .primary

    private let contextText: String

    init(context: String) {
        self.contextText = context
    }

    var count: Int { get async { 1 } }
    var isEmpty: Bool { get async { false } }

    func add(_ message: MemoryMessage) async {
        _ = message
    }

    func context(for query: String, tokenLimit: Int) async -> String {
        _ = query
        _ = tokenLimit
        return contextText
    }

    func allMessages() async -> [MemoryMessage] { [] }
    func clear() async {}
}
