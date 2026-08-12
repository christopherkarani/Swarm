import Foundation
import Swarm
import Testing
@testable import WaxChatCore

@Suite("Wax memory store/recall")
struct WaxMemoryIntegrationTests {
    @Test("WaxMemory store then recall returns stored content via factory path")
    func storeThenRecallViaFactoryWaxMemory() async throws {
        let configuration = ChatAgentConfiguration.temporary(demoMode: true)
        defer { try? FileManager.default.removeItem(at: configuration.waxStoreURL.deletingLastPathComponent()) }

        let unique = "waxchat-recall-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let content = "\(unique) favorite city is \(DemoMarkers.favoriteCity)"

        // Drive the shipped factory helper — not a reimplementation.
        // Scope the first handle so the store file is not locked when reopening.
        do {
            let memory = try await ChatAgentFactory.makeWaxMemory(url: configuration.waxStoreURL)
            await memory.add(.user(content))

            let context = await memory.context(for: unique, tokenLimit: 4_000)
            #expect(context.contains(unique))
            #expect(context.lowercased().contains(DemoMarkers.favoriteCity.lowercased()))
            #expect(await memory.count == 1)
        }

        // Re-open the same store URL to prove durability beyond the first instance.
        let reopened = try await ChatAgentFactory.makeWaxMemory(url: configuration.waxStoreURL)
        let reopenedContext = await reopened.context(for: unique, tokenLimit: 4_000)
        #expect(reopenedContext.contains(unique))
        #expect(await reopened.count >= 1)
    }
}
