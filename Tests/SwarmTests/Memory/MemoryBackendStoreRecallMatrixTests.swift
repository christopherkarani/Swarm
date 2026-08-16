// MemoryBackendStoreRecallMatrixTests.swift
// SwarmTests
//
// Store → recall matrix for every shipped memory backend.

import Foundation
@testable import Swarm
import Testing

@Suite("Memory backend store→recall matrix")
struct MemoryBackendStoreRecallMatrixTests {
    @Test("conversation stores N messages, recalls in order, respects maxMessages")
    func conversationStoreRecall() async {
        let memory: ConversationMemory = .conversation(maxMessages: 3)
        let seed = numberedMessages(5, prefix: "conv")
        for message in seed {
            await memory.add(message)
        }

        let recalled = await memory.allMessages()
        #expect(recalled.map(\.content) == ["conv-3", "conv-4", "conv-5"])
        #expect(recalled.map(\.role) == [.user, .user, .user])
        #expect(await memory.count == 3)
    }

    @Test("slidingWindow stores messages in order and drops oldest when over token budget")
    func slidingWindowStoreRecall() async {
        let estimator = CharacterBasedTokenEstimator(charactersPerToken: 1)
        let memory = SlidingWindowMemory(maxTokens: 40, tokenEstimator: estimator)

        await memory.add(MemoryMessage.user("short-a"))
        await memory.add(MemoryMessage.user("short-b"))
        let withinBudget = await memory.allMessages()
        #expect(withinBudget.map(\.content) == ["short-a", "short-b"])

        await memory.add(MemoryMessage.user(String(repeating: "z", count: 80)))
        let afterOverflow = await memory.allMessages()
        #expect(afterOverflow.count == 1)
        #expect(afterOverflow[0].content.contains("z"))
        #expect(!afterOverflow.map(\.content).contains("short-a"))
    }

    @Test("summary keeps recent messages and truncates older content at threshold")
    func summaryStoreRecallDocumentedTruncation() async {
        let memory: SummaryMemory = .summary(
            configuration: .init(
                recentMessageCount: 5,
                summarizationThreshold: 15,
                summaryTokenTarget: 200
            )
        )
        let seed = numberedMessages(20, prefix: "sum")
        for message in seed {
            await memory.add(message)
        }

        let recent = await memory.allMessages()
        // Threshold 15 keeps 5, then 5 more arrive before the next trigger.
        #expect(recent.map(\.content) == (11...20).map { "sum-\($0)" })
        #expect(await memory.hasSummary)
        let summary = await memory.currentSummary
        #expect(summary.contains("sum-") || summary.contains("[user]"))
    }

    @Test("hybrid keeps recent short-term messages and summarizes older ones")
    func hybridStoreRecallDocumentedLayering() async {
        let memory: HybridMemory = .hybrid(
            configuration: .init(
                shortTermMaxMessages: 10,
                longTermSummaryTokens: 200,
                summarizationThreshold: 20
            )
        )
        let seed = numberedMessages(20, prefix: "hyb")
        for message in seed {
            await memory.add(message)
        }

        let recent = await memory.allMessages()
        #expect(recent.map(\.content) == (11...20).map { "hyb-\($0)" })
        #expect(await memory.hasSummary)
        let summary = await memory.summary
        #expect(summary.contains("hyb-") || summary.contains("[user]"))
    }

    @Test("persistent InMemoryBackend store→recall fidelity and maxMessages")
    func persistentInMemoryStoreRecall() async {
        let unlimited: PersistentMemory = .persistent(
            backend: InMemoryBackend(),
            conversationId: "matrix-inmemory"
        )
        let seed = numberedMessages(4, prefix: "pin")
        for message in seed {
            await unlimited.add(message)
        }
        let recalled = await unlimited.allMessages()
        #expect(recalled.map(\.content) == ["pin-1", "pin-2", "pin-3", "pin-4"])
        #expect(recalled.map(\.role) == [.user, .user, .user, .user])

        let capped: PersistentMemory = .persistent(
            backend: InMemoryBackend(),
            conversationId: "matrix-inmemory-cap",
            maxMessages: 2
        )
        for message in numberedMessages(4, prefix: "cap") {
            await capped.add(message)
        }
        #expect(await capped.allMessages().map(\.content) == ["cap-3", "cap-4"])
    }

    @Test("vector mock embedder store→recall preserves insertion order")
    func vectorStoreRecall() async {
        let memory: VectorMemory = .vector(
            embeddingProvider: MockEmbeddingProvider(),
            similarityThreshold: 0.0,
            maxResults: 10
        )
        let seed = numberedMessages(3, prefix: "vec")
        for message in seed {
            await memory.add(message)
        }

        let recalled = await memory.allMessages()
        #expect(recalled.map(\.content) == ["vec-1", "vec-2", "vec-3"])

        let context = await memory.context(for: "vec-2", tokenLimit: 4000)
        #expect(context.contains("vec-2"))
    }
}

#if canImport(SwiftData)
    @Suite("Memory backend store→recall matrix (SwiftData)")
    struct SwiftDataBackendStoreRecallMatrixTests {
        @Test("persistent SwiftDataBackend store→recall fidelity and maxMessages")
        func persistentSwiftDataStoreRecall() async throws {
            if !SwiftDataTestGate.canRun { return }

            let backend = try SwiftDataBackend.inMemory()
            let memory: PersistentMemory = .persistent(
                backend: backend,
                conversationId: "matrix-swiftdata",
                maxMessages: 3
            )
            let seed = numberedMessages(5, prefix: "psd")
            for message in seed {
                await memory.add(message)
            }

            let recalled = await memory.allMessages()
            #expect(recalled.map(\.content) == ["psd-3", "psd-4", "psd-5"])
        }
    }
#endif

#if SWARM_INTEGRATIONS && canImport(ContextCore)
    @Suite("Memory backend store→recall matrix (DefaultAgentMemory)")
    struct DefaultAgentMemoryStoreRecallMatrixTests {
        @Test("DefaultAgentMemory store→recall preserves content")
        func defaultAgentMemoryStoreRecall() async throws {
            let url = try makeTemporaryWaxURL()
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

            let memory = try DefaultAgentMemory(
                configuration: .init(waxStoreURL: url)
            )
            let seed = numberedMessages(3, prefix: "def")
            for message in seed {
                await memory.add(message)
            }

            let recalled = await memory.allMessages()
            #expect(recalled.map(\.content) == ["def-1", "def-2", "def-3"])
        }
    }

    private func makeTemporaryWaxURL() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swarm-matrix-default-memory-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("wax-memory-\(UUID().uuidString).mv2s")
    }
#endif

private func numberedMessages(_ count: Int, prefix: String) -> [MemoryMessage] {
    (1...count).map { index in
        MemoryMessage(
            role: .user,
            content: "\(prefix)-\(index)",
            timestamp: Date(timeIntervalSince1970: TimeInterval(index))
        )
    }
}
