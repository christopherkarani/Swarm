#if SWARM_INTEGRATIONS && canImport(ContextCore)
import Foundation
import Testing
@testable import Swarm

@Suite("Default Composite Memory", .ephemeralDefaultStores)
struct ContextCoreDefaultMemoryTests {

    @Test("Agent uses ContextCore + Wax memory by default on subsequent turns")
    func agentUsesContextCoreMemoryByDefault() async throws {
        let session = InMemorySession()
        let provider = MockInferenceProvider(responses: [
            "First reply",
            "Second reply"
        ])

        let agent = try Agent(
            tools: [],
            instructions: "You are a helpful assistant.",
            inferenceProvider: provider
        )

        _ = try await agent.run("Remember me", session: session)
        _ = try await agent.run("Do you remember what I said?", session: session)

        let messageCalls = await provider.generateMessageCalls
        #expect(messageCalls.count == 2)

        let secondMessages = messageCalls[1].messages
        let systemMessage = secondMessages.first(where: { $0.role == .system })

        #expect(systemMessage != nil)
        #expect(systemMessage?.content.contains("ContextCore Memory Context (primary)") == true)
        #expect(systemMessage?.content.contains("Wax Memory Context (secondary)") == true)
        #expect(systemMessage?.content.contains("Remember me") == true)
        #expect(systemMessage?.content.contains("First reply") == true)
    }

    @Test("No-session agent run persists default memory for subsequent turns")
    func noSessionAgentRunPersistsDefaultMemoryForSubsequentTurns() async throws {
        let provider = MockInferenceProvider(responses: [
            "First no-session reply",
            "Second no-session reply"
        ])

        let agent = try Agent(
            tools: [],
            instructions: "You are a helpful assistant.",
            inferenceProvider: provider
        )

        _ = try await agent.run("Remember this no-session fact")
        _ = try await agent.run("What did I ask you to remember?")

        let messageCalls = await provider.generateMessageCalls
        #expect(messageCalls.count == 2)

        let secondMessages = messageCalls[1].messages
        let systemMessage = secondMessages.first(where: { $0.role == .system })

        #expect(systemMessage != nil)
        #expect(systemMessage?.content.contains("ContextCore Memory Context (primary)") == true)
        #expect(systemMessage?.content.contains("Wax Memory Context (secondary)") == true)
        #expect(systemMessage?.content.contains("Remember this no-session fact") == true)
        #expect(systemMessage?.content.contains("First no-session reply") == true)
    }

    @Test("DefaultAgentMemory seeds replayed history into both layers")
    func defaultCompositeMemorySeedsReplayIntoBothLayers() async throws {
        let url = try makeTemporaryWaxURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let memory = try DefaultAgentMemory(
            configuration: .init(
                waxStoreURL: url
            )
        )

        let replay = [
            MemoryMessage.user("alpha"),
            MemoryMessage.assistant("beta")
        ]

        await memory.importSessionHistory(replay)

        let workingMessages = await memory.workingMessages()
        let durableMessages = await memory.durableMessages()
        let allMessages = await memory.allMessages()

        #expect(await memory.count == 2)
        #expect(await memory.isEmpty == false)
        #expect(allMessages.map(\.content) == ["alpha", "beta"])
        #expect(workingMessages.map(\.content) == ["alpha", "beta"])
        #expect(durableMessages.map(\.content) == ["alpha", "beta"])
    }

    @Test("DefaultAgentMemory reports durable history through the composite view after reopen")
    func defaultCompositeMemoryReportsDurableHistoryAfterReopen() async throws {
        let url = try makeTemporaryWaxURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let replay = [
            MemoryMessage(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, role: .user, content: "alpha", timestamp: Date(timeIntervalSince1970: 1)),
            MemoryMessage(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, role: .assistant, content: "beta", timestamp: Date(timeIntervalSince1970: 2))
        ]

        do {
            let seed = try DefaultAgentMemory(
                configuration: .init(
                    waxStoreURL: url
                )
            )
            await seed.importSessionHistory(replay)
        }

        let reopened = try DefaultAgentMemory(
            configuration: .init(
                waxStoreURL: url
            )
        )

        #expect(await reopened.count == 2)
        #expect(await reopened.isEmpty == false)
        #expect((await reopened.allMessages()).map(\.content) == ["alpha", "beta"])
        #expect((await reopened.workingMessages()).isEmpty)
        #expect((await reopened.durableMessages()).map(\.content) == ["alpha", "beta"])
    }

    @Test("DefaultAgentMemory keeps layered context within the requested token budget")
    func defaultCompositeMemoryHonorsCompositeBudget() async throws {
        let url = try makeTemporaryWaxURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let counter = CountingPromptTokenCounter()
        let memory = try DefaultAgentMemory(
            configuration: .init(
                waxStoreURL: url
            )
        )

        let payload = String(repeating: "layered memory context ", count: 24)
        for index in 0 ..< 6 {
            await memory.add(.user("primary-\(index): \(payload)"))
            await memory.add(.assistant("secondary-\(index): \(payload)"))
        }

        let tokenLimit = 700
        let context = await AgentEnvironmentValues.$current.withValue(
            AgentEnvironment(promptTokenCounter: counter)
        ) {
            await memory.context(for: "layered memory context", tokenLimit: tokenLimit)
        }

        let workingMessages = await memory.workingMessages()
        let durableMessages = await memory.durableMessages()
        let exactCount = try await counter.countTokens(in: context)

        #expect(await counter.callCount > 0)
        #expect(exactCount <= tokenLimit)
        #expect(workingMessages.isEmpty == false)
        #expect(durableMessages.isEmpty == false)
        #expect(context.isEmpty == false)
    }

    @Test("DefaultAgentMemory policy query limits retrieved items")
    func defaultCompositeMemoryPolicyQueryLimitsRetrievedItems() async throws {
        let url = try makeTemporaryWaxURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let counter = CountingPromptTokenCounter()
        let memory = try DefaultAgentMemory(
            configuration: .init(
                waxStoreURL: url
            )
        )

        await memory.add(.user("policytopic policytopic policytopic keep-most-relevant"))
        await memory.add(.assistant("policytopic drop-secondary"))
        await memory.add(.user("policytopic drop-tertiary"))

        let context = await AgentEnvironmentValues.$current.withValue(
            AgentEnvironment(promptTokenCounter: counter)
        ) {
            await memory.context(
                for: MemoryQuery(
                    text: "policytopic",
                    tokenLimit: 1_000,
                    maxItems: 1,
                    maxItemTokens: 300
                )
            )
        }

        #expect(context.contains("keep-most-relevant"))
        #expect(!context.contains("drop-secondary"))
        #expect(!context.contains("drop-tertiary"))
    }

    @Test("DefaultAgentMemory policy query limits tokens per retrieved item")
    func defaultCompositeMemoryPolicyQueryLimitsItemTokens() async throws {
        let url = try makeTemporaryWaxURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let counter = CountingPromptTokenCounter()
        let memory = try DefaultAgentMemory(
            configuration: .init(
                waxStoreURL: url
            )
        )

        await memory.add(.user("policytopic \(String(repeating: "x", count: 180)) tail-not-allowed"))

        let context = await AgentEnvironmentValues.$current.withValue(
            AgentEnvironment(promptTokenCounter: counter)
        ) {
            await memory.context(
                for: MemoryQuery(
                    text: "policytopic",
                    tokenLimit: 800,
                    maxItems: 1,
                    maxItemTokens: 80
                )
            )
        }

        #expect(context.contains("policytopic"))
        #expect(!context.contains("tail-not-allowed"))
    }

    @Test("DefaultAgentMemory policy query preserves bracket-prefixed body lines")
    func defaultCompositeMemoryPolicyQueryPreservesBracketPrefixedBodyLines() async throws {
        let url = try makeTemporaryWaxURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let counter = CountingPromptTokenCounter()
        let memory = try DefaultAgentMemory(
            configuration: .init(
                waxStoreURL: url
            )
        )

        await memory.add(.user("""
        brackettopic
        [dependencies]
        body-kept
        """))
        await memory.add(.assistant("brackettopic drop-secondary"))

        let context = await AgentEnvironmentValues.$current.withValue(
            AgentEnvironment(promptTokenCounter: counter)
        ) {
            await memory.context(
                for: MemoryQuery(
                    text: "brackettopic",
                    tokenLimit: 1_000,
                    maxItems: 1,
                    maxItemTokens: 600
                )
            )
        }

        #expect(context.contains("brackettopic"))
        #expect(context.contains("[dependencies]"))
        #expect(context.contains("body-kept"))
        #expect(!context.contains("drop-secondary"))
    }

    @Test("DefaultAgentMemory policy query trims durable-only oversized items after reopen")
    func defaultCompositeMemoryPolicyQueryTrimsDurableOnlyOversizedItemsAfterReopen() async throws {
        let url = try makeTemporaryWaxURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let counter = CountingPromptTokenCounter()
        let longPayload = String(repeating: "durable body ", count: 120)

        do {
            let seed = try DefaultAgentMemory(
                configuration: .init(
                    waxStoreURL: url
                )
            )
            await seed.add(.user("durable-policytopic \(longPayload) tail-not-allowed"))
        }

        let reopened = try DefaultAgentMemory(
            configuration: .init(
                waxStoreURL: url
            )
        )

        let context = await AgentEnvironmentValues.$current.withValue(
            AgentEnvironment(promptTokenCounter: counter)
        ) {
            await reopened.context(
                for: MemoryQuery(
                    text: "durable-policytopic",
                    tokenLimit: 180,
                    maxItems: 1,
                    maxItemTokens: 80
                )
            )
        }

        #expect((await reopened.workingMessages()).isEmpty)
        #expect(context.contains("durable-policytopic"))
        #expect(!context.contains("tail-not-allowed"))
    }

    @Test("DefaultAgentMemory skips duplicate replay entries against an existing Wax store")
    func defaultCompositeMemorySkipsDuplicateReplayEntries() async throws {
        let url = try makeTemporaryWaxURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let replay = [
            MemoryMessage(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, role: .user, content: "gamma", timestamp: Date(timeIntervalSince1970: 3)),
            MemoryMessage(id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, role: .assistant, content: "delta", timestamp: Date(timeIntervalSince1970: 4))
        ]

        do {
            let first = try DefaultAgentMemory(
                configuration: .init(
                    waxStoreURL: url
                )
            )
            await first.importSessionHistory(replay)
        }

        let reopened = try DefaultAgentMemory(
            configuration: .init(
                waxStoreURL: url
            )
        )
        await reopened.importSessionHistory(replay)

        #expect(await reopened.count == 2)
        #expect((await reopened.allMessages()).map(\.content) == ["gamma", "delta"])
        #expect((await reopened.durableMessages()).map(\.content) == ["gamma", "delta"])
    }
}

private actor CountingPromptTokenCounter: PromptTokenCounter {
    private var callCountStorage = 0

    var callCount: Int {
        callCountStorage
    }

    func countTokens(in text: String) async throws -> Int {
        callCountStorage += 1
        return max(1, text.count)
    }
}

private func makeTemporaryWaxURL() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "swarm-default-memory-tests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appendingPathComponent("wax-memory-\(UUID().uuidString).mv2s")
}
#endif
