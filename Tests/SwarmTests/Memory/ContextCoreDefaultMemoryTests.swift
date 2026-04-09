import Foundation
import Testing
@testable import Swarm

@Suite("Default Composite Memory")
struct ContextCoreDefaultMemoryTests {
    @Test("Agent uses the default composite memory stack on subsequent turns")
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
        #expect(systemMessage?.content.contains("Remember me") == true)
        #expect(systemMessage?.content.contains("First reply") == true)
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

    @Test("DefaultAgentMemory honors item-aware retrieval limits")
    func defaultCompositeMemoryHonorsItemAwareRetrievalLimits() async throws {
        let url = try makeTemporaryWaxURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let memory = try DefaultAgentMemory(
            configuration: .init(
                waxStoreURL: url
            )
        )

        for index in 0 ..< 6 {
            let payload = String(repeating: "needle-\(index) ", count: 40)
            await memory.add(.user("item-\(index): \(payload)"))
        }

        let context = await memory.context(
            for: MemoryQuery(
                text: "needle",
                tokenLimit: 400,
                maxItems: 2,
                maxItemTokens: 60
            )
        )

        let itemMentions = (0 ..< 6).filter { context.contains("item-\($0):") }
        #expect(itemMentions.count <= 2)
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

    @Test("DefaultAgentMemory recalls structured websearch evidence for follow-up queries")
    func defaultCompositeMemoryRecallsWebEvidence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swarm-web-evidence-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let memory = try DefaultAgentMemory(
            configuration: .init(
                waxStoreURL: root.appendingPathComponent("memory.mv2s"),
                webEvidenceStoreURL: root.appendingPathComponent("web-evidence", isDirectory: true)
            )
        )

        let record = WebSearchEvidenceRecord(
            query: "Apple Foundation Models prompt engineering",
            mode: "search",
            summary: "Apple's prompting guide covers on-device prompting constraints.",
            semanticCore: "Prompting guidance for on-device foundation models.",
            primaryHit: .init(
                title: "Prompting an on-device foundation model - Apple Developer",
                url: "https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model",
                snippet: "Prompting techniques for on-device foundation models.",
                domain: "developer.apple.com",
                score: 0.88
            )
        )

        await memory.addWebSearchResult(
            rawPayload: "raw-websearch-payload",
            evidence: record
        )

        let context = await memory.context(
            for: MemoryQuery(
                text: "What did the Apple Foundation Models prompting guide say?",
                tokenLimit: 500,
                maxItems: 3,
                maxItemTokens: 120
            )
        )

        #expect(context.contains("Web Search Evidence (curated)"))
        #expect(context.contains("Prompting an on-device foundation model - Apple Developer"))
        #expect(context.contains("developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model"))
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
