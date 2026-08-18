// FoundationModelsNativeProfileFilterTests.swift
//
// Owned-loop DynamicProfile tool deny — helper-level, no live Apple required.

import Foundation
@testable import Swarm
import Testing

#if canImport(FoundationModels)
@Suite("FoundationModels Native Profile Filter")
struct FoundationModelsNativeProfileFilterTests {
    private let search = ToolSchema(name: "search", description: "s", parameters: [])
    private let calc = ToolSchema(name: "calc", description: "c", parameters: [])
    private let denyMe = ToolSchema(name: "deny_me", description: "d", parameters: [])

    private var allTools: [ToolSchema] { [search, calc, denyMe] }

    @Test("Profile excluding a tool is applied before native session bind")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func profileExcludingDropsDeniedTool() {
        #if os(tvOS) || os(watchOS)
        return
        #else
        let provider = FoundationModelsInferenceProvider(
            profile: StaticDynamicProfile(
                Profile(
                    id: "review",
                    instructions: "Be precise.",
                    toolFilter: .excluding(["deny_me"])
                )
            )
        )
        let bound = provider.nativeExecutingToolSchemas(
            messages: [.user("hi")],
            tools: allTools,
            options: .default
        )
        #expect(bound.map(\.name) == ["search", "calc"])
        #expect(!bound.contains(where: { $0.name == "deny_me" }))
        #endif
    }

    @Test("Profile only-allow list is the executing set")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func profileOnlyKeepsAllowedTool() {
        #if os(tvOS) || os(watchOS)
        return
        #else
        let provider = FoundationModelsInferenceProvider(
            profile: StaticDynamicProfile(
                Profile(
                    id: "calc-only",
                    instructions: "Use calc.",
                    toolFilter: .only(["calc"])
                )
            )
        )
        let bound = provider.nativeExecutingToolSchemas(
            messages: [.user("hi")],
            tools: allTools,
            options: .default
        )
        #expect(bound.map(\.name) == ["calc"])
        #endif
    }

    @Test("Profile toolChoice.none binds no executing tools")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func profileToolChoiceNoneClearsTools() {
        #if os(tvOS) || os(watchOS)
        return
        #else
        let provider = FoundationModelsInferenceProvider(
            profile: StaticDynamicProfile(
                Profile(
                    id: "no-tools",
                    instructions: "Do not call tools.",
                    generation: .init(toolChoice: ToolChoice.none)
                )
            )
        )
        let bound = provider.nativeExecutingToolSchemas(
            messages: [.user("hi")],
            tools: allTools,
            options: InferenceOptions(toolChoice: .required)
        )
        #expect(bound.isEmpty)
        #endif
    }

    @Test("Request toolChoice.none binds no tools when the profile does not override")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func requestToolChoiceNoneClearsTools() {
        #if os(tvOS) || os(watchOS)
        return
        #else
        let provider = FoundationModelsInferenceProvider()
        let bound = provider.nativeExecutingToolSchemas(
            messages: [.user("hi")],
            tools: allTools,
            options: InferenceOptions(toolChoice: ToolChoice.none)
        )
        #expect(bound.isEmpty)
        #endif
    }

    @Test("No profile keeps the request tool list")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func noProfileKeepsRequestTools() {
        #if os(tvOS) || os(watchOS)
        return
        #else
        let provider = FoundationModelsInferenceProvider()
        let bound = provider.nativeExecutingToolSchemas(
            messages: [.user("hi")],
            tools: allTools,
            options: .default
        )
        #expect(bound.map(\.name) == ["search", "calc", "deny_me"])
        #endif
    }

    @Test("executingToolSchemas honors resolved toolChoice.none")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func executingToolSchemasHonorsNone() {
        #if os(tvOS) || os(watchOS)
        return
        #else
        let kept = FoundationModelsInferenceProvider.executingToolSchemas(
            resolvedTools: allTools,
            toolChoice: .auto
        )
        #expect(kept.map(\.name) == ["search", "calc", "deny_me"])

        let cleared = FoundationModelsInferenceProvider.executingToolSchemas(
            resolvedTools: allTools,
            toolChoice: ToolChoice.none
        )
        #expect(cleared.isEmpty)
        #endif
    }

    @Test("Owned-loop bind order is resolveTurn then executingToolSchemas")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func bindOrderMatchesCaptureMode() {
        #if os(tvOS) || os(watchOS)
        return
        #else
        let provider = FoundationModelsInferenceProvider(
            profile: StaticDynamicProfile(
                Profile(
                    id: "review",
                    instructions: "Review.",
                    toolFilter: .excluding(["deny_me"]),
                    generation: .init(toolChoice: .auto)
                )
            )
        )
        let messages = [InferenceMessage.user("hi")]
        let options = InferenceOptions(toolChoice: .required)
        let resolved = provider.resolveTurn(
            messages: messages,
            tools: allTools,
            options: options
        )
        let fromSteps = FoundationModelsInferenceProvider.executingToolSchemas(
            resolvedTools: resolved.tools,
            toolChoice: resolved.options.toolChoice
        )
        let fromHelper = provider.nativeExecutingToolSchemas(
            messages: messages,
            tools: allTools,
            options: options
        )
        #expect(resolved.tools.map(\.name) == ["search", "calc"])
        #expect(fromSteps.map(\.name) == ["search", "calc"])
        #expect(fromHelper.map(\.name) == fromSteps.map(\.name))
        #expect(resolved.options.toolChoice == .auto)
        #endif
    }
}
#endif
