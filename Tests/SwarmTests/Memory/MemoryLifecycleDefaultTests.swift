import Foundation
@testable import Swarm
import Testing

@Suite("Memory defaulted requirements")
struct MemoryLifecycleDefaultTests {
    @Test("CompositeMemory begins every layer without satellite downcasts")
    func compositeBeginsEveryLayer() async {
        let bare = SessionCountingMemory()
        let waxLike = SessionCountingMemory()
        await waxLike.markAsLifecycleOverride()
        let composite = CompositeMemory([bare, waxLike])

        await composite.beginMemorySession()
        await composite.endMemorySession()

        #expect(await bare.beginCount == 1)
        #expect(await bare.endCount == 1)
        #expect(await waxLike.beginCount == 1)
        #expect(await waxLike.endCount == 1)
    }
}

private actor SessionCountingMemory: Memory {
    private var messages: [MemoryMessage] = []
    private(set) var beginCount = 0
    private(set) var endCount = 0
    private var overridesLifecycle = false

    func markAsLifecycleOverride() {
        overridesLifecycle = true
    }

    var count: Int { messages.count }
    var isEmpty: Bool { messages.isEmpty }

    func add(_ message: MemoryMessage) async {
        messages.append(message)
    }

    func context(for query: String, tokenLimit _: Int) async -> String {
        query
    }

    func allMessages() async -> [MemoryMessage] {
        messages
    }

    func clear() async {
        messages.removeAll()
    }

    func beginMemorySession() async {
        beginCount += 1
        _ = overridesLifecycle
    }

    func endMemorySession() async {
        endCount += 1
    }
}
