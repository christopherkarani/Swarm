import Foundation
import Swarm
import Testing
@testable import WaxChatCore

@Suite("ChatSession demo orchestration")
struct ChatSessionDemoTests {
    @Test("Demo session invokes websearch, persists turn1 to Wax, and recalls multi-turn fact")
    func demoSessionPersistsAndRecallsViaWax() async throws {
        let configuration = ChatAgentConfiguration.temporary(demoMode: true)
        defer { try? FileManager.default.removeItem(at: configuration.waxStoreURL.deletingLastPathComponent()) }

        // Real entry orchestration used by the executable.
        let result = try await ChatSession.run(
            prompt: DemoMarkers.defaultPrimaryPrompt,
            configuration: configuration,
            printStream: false
        )

        #expect(result.isDemoMode)
        #expect(result.usesWebSearch)
        #expect(result.usesWaxMemory)
        #expect(result.demoChecksPassed)

        #expect(result.invokedToolNames.map { $0.lowercased() }.contains("websearch"))
        #expect(result.toolNames.map { $0.lowercased() }.contains("websearch"))

        let primary = result.primaryOutput.lowercased()
        #expect(primary.contains("websearch") || primary.contains("swarm"))
        #expect(result.turn2Output.lowercased().contains(DemoMarkers.favoriteCity.lowercased()))
        #expect(!result.primaryOutput.isEmpty)

        // Criterion 4: multi-turn fact is in the Wax store (not only scripted turn2 text).
        #expect(result.waxRecalledFavoriteCity)
        #expect(result.waxRecallContext.lowercased().contains(DemoMarkers.favoriteCity.lowercased()))
    }

    @Test("After ChatSession run, reopening WaxMemory at store URL still contains the turn1 fact")
    func reopenedWaxStoreContainsTurn1Fact() async throws {
        let configuration = ChatAgentConfiguration.temporary(demoMode: true)
        let storeRoot = configuration.waxStoreURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        let result = try await ChatSession.run(
            prompt: DemoMarkers.defaultPrimaryPrompt,
            configuration: configuration,
            printStream: false
        )
        #expect(result.waxRecalledFavoriteCity)

        // Fresh handle after the run (agent/Wax actor from the run are not retained).
        let reopened = try await ChatAgentFactory.makeWaxMemory(url: result.waxStoreURL)
        let context = await reopened.context(for: DemoMarkers.waxRecallQuery, tokenLimit: 4_000)
        #expect(context.lowercased().contains(DemoMarkers.favoriteCity.lowercased()))

        let messages = await reopened.allMessages()
        let joined = messages.map(\.content).joined(separator: "\n").lowercased()
        #expect(joined.contains(DemoMarkers.favoriteCity.lowercased()))
        #expect(messages.contains { $0.role == .user && $0.content.contains(DemoMarkers.favoriteCity) })
    }

    @Test("syncSessionTurnsToWax writes session user/assistant turns into WaxMemory")
    func syncSessionTurnsToWaxWritesUserAndAssistant() async throws {
        let configuration = ChatAgentConfiguration.temporary(demoMode: true)
        defer { try? FileManager.default.removeItem(at: configuration.waxStoreURL.deletingLastPathComponent()) }

        let wax = try await ChatAgentFactory.makeWaxMemory(url: configuration.waxStoreURL)
        let session = InMemorySession(sessionId: "sync-test")
        try await session.addItems([
            .user("My favorite city is Kyoto."),
            .assistant("Saved Kyoto."),
        ])

        try await ChatSession.syncSessionTurnsToWax(session: session, waxMemory: wax)

        #expect(await wax.count == 2)
        let context = await wax.context(for: "favorite city", tokenLimit: 4_000)
        #expect(context.lowercased().contains("kyoto"))
    }

    @Test("Non-demo session runs only the user prompt (no Kyoto demo turns)")
    func liveSessionSkipsDemoMemoryTurns() async throws {
        let configuration = ChatAgentConfiguration.temporary(demoMode: false)
        defer { try? FileManager.default.removeItem(at: configuration.waxStoreURL.deletingLastPathComponent()) }

        // Scripted provider keeps the test offline; demoMode:false must skip Kyoto turns.
        let bundle = try await ChatAgentFactory.makeAgent(
            configuration: configuration,
            provider: DemoScriptedProvider(),
            modeLabel: "test-non-demo"
        )
        #expect(!bundle.isDemoMode)

        let result = try await ChatSession.run(
            prompt: "Say hello once.",
            bundle: bundle,
            printStream: false
        )

        #expect(!result.isDemoMode)
        #expect(result.turn1Output.isEmpty)
        #expect(result.turn2Output.isEmpty)
        #expect(!result.waxRecalledFavoriteCity)
        #expect(result.waxRecallContext.isEmpty)
        #expect(result.demoChecksPassed)
    }

    @Test("evaluateDemoChecks requires websearch, primary content, and Wax store recall")
    func evaluateDemoChecksCriteria() {
        #expect(
            ChatSession.evaluateDemoChecks(
                isDemoMode: true,
                primaryOutput: DemoMarkers.primaryAnswer,
                invokedToolNames: ["websearch"],
                turn2Output: DemoMarkers.turn2Answer,
                waxRecalledFavoriteCity: true,
                waxRecallContext: "favorite city is Kyoto"
            )
        )

        #expect(
            !ChatSession.evaluateDemoChecks(
                isDemoMode: true,
                primaryOutput: DemoMarkers.primaryAnswer,
                invokedToolNames: [],
                turn2Output: DemoMarkers.turn2Answer,
                waxRecalledFavoriteCity: true,
                waxRecallContext: "favorite city is Kyoto"
            )
        )

        // Scripted turn2 alone is not enough without Wax proof.
        #expect(
            !ChatSession.evaluateDemoChecks(
                isDemoMode: true,
                primaryOutput: DemoMarkers.primaryAnswer,
                invokedToolNames: ["websearch"],
                turn2Output: DemoMarkers.turn2Answer,
                waxRecalledFavoriteCity: false,
                waxRecallContext: ""
            )
        )
    }
}
