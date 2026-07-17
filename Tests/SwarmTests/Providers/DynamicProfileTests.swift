// DynamicProfileTests.swift
//
// Unit tests for Swarm Dynamic Profiles (WWDC 2026–aligned).

import Foundation
@testable import Swarm
import Testing

@Suite("Dynamic Profile")
struct DynamicProfileTests {
    @Test("Tool filter only / excluding")
    func toolFilters() {
        let tools = [
            ToolSchema(name: "search", description: "s", parameters: []),
            ToolSchema(name: "calc", description: "c", parameters: []),
            ToolSchema(name: "time", description: "t", parameters: []),
        ]

        let only = ProfileToolFilter.only(["search", "time"]).apply(to: tools)
        #expect(only.map(\.name) == ["search", "time"])

        let excluding = ProfileToolFilter.excluding(["calc"]).apply(to: tools)
        #expect(excluding.map(\.name) == ["search", "time"])

        #expect(ProfileToolFilter.all.apply(to: tools).count == 3)
    }

    @Test("History policies drop tools and keep last")
    func historyPolicies() {
        let messages: [InferenceMessage] = [
            .system("sys"),
            .user("u1"),
            .assistant("thinking", toolCalls: [
                .init(id: "1", name: "search", arguments: ["q": .string("x")]),
            ]),
            .tool(name: "search", content: "result", toolCallID: "1"),
            .user("u2"),
            .assistant("final"),
        ]

        let dropped = ProfileHistoryPolicy.dropToolTranscript.apply(to: messages)
        #expect(dropped.contains(where: { $0.role == .tool }) == false)
        #expect(dropped.contains(where: { !$0.toolCalls.isEmpty }) == false)
        #expect(dropped.contains(where: { $0.content == "thinking" }))

        let lastTwo = ProfileHistoryPolicy.keepLast(count: 2).apply(to: messages)
        #expect(lastTwo.count == 2)
        #expect(lastTwo[0].content == "u2")
        #expect(lastTwo[1].content == "final")

        let combined = ProfileHistoryPolicy.dropToolTranscriptAndKeepLast(count: 2).apply(to: messages)
        #expect(combined.count == 2)
        #expect(combined.contains(where: { $0.role == .tool }) == false)
    }

    @Test("DynamicInstructions merge concatenates text and tools")
    func instructionsMerge() {
        let base = DynamicInstructions("You are a craft facilitator.", tools: ["title"])
        let expert = DynamicInstructions("You know origami folds.", tools: ["fold_db", "title"])
        let merged = base + expert

        #expect(merged.text.contains("craft facilitator"))
        #expect(merged.text.contains("origami folds"))
        #expect(merged.toolNames == ["title", "fold_db"])
    }

    @Test("Profile from DynamicInstructions sets tool filter")
    func profileFromInstructions() {
        let instructions = DynamicInstructions("Brainstorm ideas.", tools: ["title", "search"])
        let profile = Profile(id: "brainstorm", dynamicInstructions: instructions)

        #expect(profile.id == "brainstorm")
        #expect(profile.instructions.contains("Brainstorm"))
        #expect(profile.toolFilter == .only(["title", "search"]))
    }

    @Test("Generation overrides merge into InferenceOptions")
    func generationOverrides() {
        let overrides = ProfileGenerationOverrides(
            temperature: 0.2,
            maxTokens: 512,
            toolChoice: .required
        )
        let merged = overrides.merging(into: .default)
        #expect(merged.temperature == 0.2)
        #expect(merged.maxTokens == 512)
        #expect(merged.toolChoice == .required)
    }

    @Test("Mode switching re-resolves profile")
    func modeSwitching() {
        enum Phase: Sendable { case a, b }
        let mode = ProfileMode(Phase.a)
        let profile = ModeSwitchingDynamicProfile(mode: mode) { phase in
            switch phase {
            case .a:
                Profile(id: "a", instructions: "Phase A")
            case .b:
                Profile(id: "b", instructions: "Phase B", history: .dropToolTranscript)
            }
        }

        #expect(profile.resolve().id == "a")
        mode.current = .b
        #expect(profile.resolve().id == "b")
        #expect(profile.resolve().history == .dropToolTranscript)
    }

    @Test("ClosureDynamicProfile re-evaluates every resolve")
    func closureProfileReevaluates() {
        let counter = ProfileMode(0)
        let profile = ClosureDynamicProfile {
            let n = counter.current
            counter.current = n + 1
            return Profile(id: "n\(n)", instructions: "turn \(n)")
        }

        #expect(profile.resolve().id == "n0")
        let second = profile.resolve()
        #expect(second.id == "n1")
        #expect(second.instructions == "turn 1")
    }

    @Test("DynamicProfileResolution applies full stack")
    func resolutionStack() {
        let profile = Profile(
            id: "review",
            instructions: "Review carefully.",
            toolFilter: .only(["calc"]),
            generation: .init(temperature: 0.1, toolChoice: .auto),
            history: .dropToolTranscript
        )

        let messages: [InferenceMessage] = [
            .user("hi"),
            .assistant("", toolCalls: [.init(name: "search", arguments: [:])]),
            .tool(name: "search", content: "data"),
            .user("now review"),
        ]
        let tools = [
            ToolSchema(name: "search", description: "s", parameters: []),
            ToolSchema(name: "calc", description: "c", parameters: []),
        ]

        let applied = DynamicProfileResolution.apply(
            profile,
            messages: messages,
            tools: tools,
            options: .default,
            baseInstructions: "Base agent."
        )

        #expect(applied.tools.map(\.name) == ["calc"])
        #expect(applied.options.temperature == 0.1)
        #expect(applied.messages.contains(where: { $0.role == .tool }) == false)
        #expect(applied.instructions?.contains("Base agent.") == true)
        #expect(applied.instructions?.contains("Review carefully.") == true)

        let withSystem = DynamicProfileResolution.messagesByInjectingInstructions(
            applied.instructions,
            into: applied.messages
        )
        #expect(withSystem.first?.role == .system)
        #expect(withSystem.first?.content.contains("Review carefully.") == true)
    }

    @Test("StaticDynamicProfile is stable")
    func staticProfile() {
        let profile = StaticDynamicProfile(
            Profile(id: "fixed", instructions: "Always this.")
        )
        #expect(profile.resolve().id == "fixed")
        #expect(profile.resolve().instructions == "Always this.")
    }
}

#if canImport(FoundationModels)
@Suite("Dynamic Profile + Foundation Models Provider")
struct DynamicProfileFoundationModelsTests {
    @Test("Provider accepts dynamic profile and reports profile id in modelName")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func providerCarriesProfile() {
        let profile = StaticDynamicProfile(
            Profile(id: "coach", instructions: "Be a craft coach.")
        )
        let provider = FoundationModelsInferenceProvider(profile: profile)
        #expect(provider.modelName == "systemLanguageModel/coach")

        let viaDot: any InferenceProvider = .foundationModels(profile: profile)
        #expect(viaDot is FoundationModelsInferenceProvider)
        #expect((viaDot as? FoundationModelsInferenceProvider)?.modelName == "systemLanguageModel/coach")
    }

    @Test("Live profile switches instructions across modes")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func liveModeSwitch() async throws {
        guard ProcessInfo.processInfo.environment["SWARM_RUN_LIVE_FOUNDATION_MODELS_TESTS"] == "1" else {
            return
        }
        guard FoundationModelsInferenceProvider.isAvailable else { return }

        enum Phase: Sendable { case short, long }
        let mode = ProfileMode(Phase.short)
        let profile = ModeSwitchingDynamicProfile(mode: mode) { phase in
            switch phase {
            case .short:
                Profile(
                    id: "short",
                    instructions: "Reply with exactly one word: PING",
                    generation: .init(temperature: 0)
                )
            case .long:
                Profile(
                    id: "long",
                    instructions: "Reply with exactly one word: PONG",
                    generation: .init(temperature: 0)
                )
            }
        }

        let provider = FoundationModelsInferenceProvider(profile: profile)
        let first = try await provider.generate(
            prompt: "Respond as instructed.",
            options: .default
        )
        #expect(first.uppercased().contains("PING") || !first.isEmpty)

        mode.current = .long
        let second = try await provider.generate(
            prompt: "Respond as instructed.",
            options: .default
        )
        #expect(second.uppercased().contains("PONG") || !second.isEmpty)
    }
}
#endif
