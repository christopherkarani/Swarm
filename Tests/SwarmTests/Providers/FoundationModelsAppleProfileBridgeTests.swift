import Foundation
@testable import Swarm
import Testing

@Suite("Foundation Models Apple profile bridge")
struct FoundationModelsAppleProfileBridgeTests {
    private let search = ToolSchema(name: "search", description: "s", parameters: [])
    private let calc = ToolSchema(name: "calc", description: "c", parameters: [])

    private var toolHeavyHistory: [InferenceMessage] {
        [
            .system("sys"),
            .user("look it up"),
            .assistant(
                "thinking",
                toolCalls: [.init(id: "1", name: "search", arguments: ["q": .string("x")])]
            ),
            .tool(name: "search", content: "result", toolCallID: "1"),
            .user("thanks"),
            .assistant("final"),
        ]
    }

    @Test("dropToolTranscript maps onto text-only transcript entries")
    func dropToolTranscriptMapsToTextOnlyEntries() {
        let profile = Profile(
            id: "review",
            instructions: "Be precise.",
            toolFilter: .excluding(["search"]),
            history: .dropToolTranscript
        )
        let plan = FoundationModelsAppleProfileBridge.plan(
            profile: profile,
            messages: toolHeavyHistory,
            tools: [search, calc],
            options: .default,
            baseInstructions: nil
        )

        #expect(plan.instructions == "Be precise.")
        #expect(plan.tools.map(\.name) == ["calc"])
        #expect(plan.messages.contains(where: { $0.role == .tool }) == false)
        #expect(plan.messages.contains(where: { !$0.toolCalls.isEmpty }) == false)
        #expect(plan.canRehydrateTranscript)
        #expect(plan.entries.contains { if case .toolOutput = $0 { true } else { false } } == false)
        #expect(plan.entries.contains(.instructions("Be precise.")))
        #expect(plan.entries.contains(.prompt("look it up")))
        #expect(plan.entries.contains(.response("thinking")))
        #expect(plan.entries.contains(.prompt("thanks")))
        #expect(plan.entries.contains(.response("final")))
    }

    @Test("keepAll with tool calls cannot rehydrate a Transcript")
    func keepAllWithToolsCannotRehydrate() {
        let profile = Profile(id: "keep", instructions: "Keep tools.", history: .keepAll)
        let plan = FoundationModelsAppleProfileBridge.plan(
            profile: profile,
            messages: toolHeavyHistory,
            tools: [search],
            options: .default,
            baseInstructions: nil
        )
        #expect(plan.canRehydrateTranscript == false)
        #expect(plan.entries.contains { if case .toolOutput = $0 { true } else { false } })
    }

    @Test("seed drops the pending user prompt from transcript entries")
    func seedDropsPendingUserPrompt() {
        let seed = FoundationModelsAppleProfileBridge.seed(
            messages: [
                .system("Be precise."),
                .user("u1"),
                .assistant("a1"),
                .user("u2"),
            ],
            instructions: "Be precise."
        )
        #expect(seed.canRehydrateTranscript)
        #expect(seed.pendingPrompt == "u2")
        #expect(seed.seedEntries == [
            .instructions("Be precise."),
            .prompt("u1"),
            .response("a1"),
        ])
    }

    @Test("does not alias Swarm Profile onto Apple DynamicProfile")
    func swarmTypesStaySwarmTypes() {
        let profile = Profile(id: "review", instructions: "Be precise.", history: .dropToolTranscript)
        let resolved = StaticDynamicProfile(profile).resolve()
        #expect(resolved.id == "review")
        #expect(resolved.history == .dropToolTranscript)
    }
}
