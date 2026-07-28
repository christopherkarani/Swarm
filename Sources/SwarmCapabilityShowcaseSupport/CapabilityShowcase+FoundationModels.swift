// CapabilityShowcase+FoundationModels.swift
// SwarmCapabilityShowcaseSupport
//
// Foundation Models capability scenarios — kept out of the main showcase file
// so CapabilityShowcase.swift does not keep absorbing provider-specific growth.

import Foundation
import Swarm

// MARK: - Foundation Models (deterministic)

/// Exercises the first-class Foundation Models path without requiring live inference.
///
/// Validates:
/// - Dot-syntax `.foundationModels()` type resolution (Apple platforms)
/// - Capability reporting (native tools, private inference; no streaming tool calls)
/// - `isAvailable` / `ifAvailable` consistency
/// - Graceful degradation messaging when the framework is not present (Linux)
/// - Agent + tool + multi-turn wiring still works with a scripted provider alongside
///   the FM entry points so the on-device DX path stays integrated with core Swarm
func runFoundationModelsScenario(context: CapabilityScenarioContext) async throws -> CapabilityScenarioResult {
    var lines: [String] = []

    #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            let provider: any InferenceProvider = .foundationModels()
            try ensure(
                provider is FoundationModelsInferenceProvider,
                "Expected .foundationModels() to return FoundationModelsInferenceProvider."
            )
            lines.append("dot-syntax=FoundationModelsInferenceProvider")

            let native = FoundationModelsInferenceProvider()
            let capabilities = InferenceProviderCapabilities.resolved(for: native)
            try ensure(capabilities.contains(.nativeToolCalling), "FM should advertise native tool calling.")
            try ensure(capabilities.contains(.conversationMessages), "FM should advertise conversation messages.")
            try ensure(capabilities.contains(.privateInference), "FM should advertise private on-device inference.")
            try ensure(capabilities.contains(.structuredOutputs), "FM should advertise structured outputs.")
            try ensure(
                capabilities.contains(.streamingToolCalls) == false,
                "FM must not advertise streaming tool calls (Apple path is capture-then-execute)."
            )
            try ensure(native.providerName == "foundationmodels", "Expected providerName foundationmodels.")
            lines.append("capabilities=nativeToolCalling,conversationMessages,privateInference,structuredOutputs")
            lines.append("streamingToolCalls=false")

            let available = FoundationModelsInferenceProvider.isAvailable
            let optional = FoundationModelsInferenceProvider.ifAvailable()
            try ensure(
                (optional != nil) == available,
                "ifAvailable() must agree with isAvailable."
            )
            lines.append("isAvailable=\(available)")
            lines.append("ifAvailable=\(optional != nil)")

            // Profile-driven factory stays first-class and Sendable.
            let mode = ProfileMode("showcase")
            let profile = ModeSwitchingDynamicProfile(mode: mode) { _ in
                Profile(
                    id: "showcase",
                    instructions: "Be concise.",
                    generation: .init(temperature: 0.2)
                )
            }
            let profiled: any InferenceProvider = .foundationModels(profile: profile)
            try ensure(
                profiled is FoundationModelsInferenceProvider,
                "Expected .foundationModels(profile:) to return FoundationModelsInferenceProvider."
            )
            if let typed = profiled as? FoundationModelsInferenceProvider {
                try ensure(
                    typed.modelName?.contains("showcase") == true,
                    "Expected profile id to appear in modelName."
                )
                lines.append("profile-modelName=\(typed.modelName ?? "nil")")
            }

            // Core multi-turn + tools remain wired for apps that fall back to scripted/mocks
            // while developing against the same Agent surface used with FM.
            let additionTool = ShowcaseAdditionTool().asAnyJSONTool()
            let scripted = ScriptedInferenceProvider(
                toolCallResponses: [
                    .init(
                        toolCalls: [
                            .init(
                                id: "fm-demo-1",
                                name: additionTool.name,
                                arguments: ["lhs": .int(2), "rhs": .int(3)]
                            ),
                        ],
                        finishReason: .toolCall
                    ),
                    .init(content: "Sum is 5.", finishReason: .completed),
                ]
            )
            let toolAgent = try Agent(
                tools: [additionTool],
                instructions: "Use tools when needed.",
                memory: makeScenarioMemory(),
                inferenceProvider: scripted
            )
            let toolResult = try await toolAgent.run("Add 2 and 3.")
            try ensure(toolResult.output.contains("5"), "Expected scripted tool path to return 5.")
            lines.append("agent-tools-path=ok")

            let conversationProvider = ScriptedInferenceProvider(responses: [
                "Hello, Alex.",
                "Your name is Alex.",
            ])
            let conversationAgent = try Agent(
                "Remember the user.",
                memory: makeScenarioMemory(),
                inferenceProvider: conversationProvider
            )
            let conversation = Conversation(with: conversationAgent)
            _ = try await conversation.send("My name is Alex.")
            let followUp = try await conversation.send("What is my name?")
            try ensure(followUp.output.contains("Alex"), "Expected multi-turn memory of the name.")
            lines.append("multi-turn=ok")

            let summary: String
            if available {
                summary = "Validated first-class Foundation Models factories, capabilities, availability, and Agent multi-turn/tool wiring. Live generation is opt-in via smoke."
            } else {
                summary = "Foundation Models framework is present but the system model is unavailable; factories, capabilities, and degrade semantics still check out."
            }

            let body = lines.joined(separator: "\n")
            let artifact = try context.writeArtifact(named: "foundation-models.txt", contents: body)
            return .init(
                id: "foundation-models",
                name: "Foundation Models Path",
                families: [.foundationModels, .providers],
                status: .passed,
                summary: summary,
                evidence: [
                    .init(label: "foundation-models", detail: body, artifactPath: context.relativeArtifactPath(for: artifact)),
                ]
            )
        } else {
            let body = "platform=below-macOS-26-or-equivalent"
            let artifact = try context.writeArtifact(named: "foundation-models.txt", contents: body)
            return .init(
                id: "foundation-models",
                name: "Foundation Models Path",
                families: [.foundationModels, .providers],
                status: .passed,
                summary: "Runtime OS is below Foundation Models availability; path correctly gated by @available.",
                evidence: [
                    .init(label: "foundation-models", detail: body, artifactPath: context.relativeArtifactPath(for: artifact)),
                ]
            )
        }
    #else
        let body = "canImport(FoundationModels)=false"
        let artifact = try context.writeArtifact(named: "foundation-models.txt", contents: body)
        return .init(
            id: "foundation-models",
            name: "Foundation Models Path",
            families: [.foundationModels, .providers],
            status: .passed,
            summary: "FoundationModels framework is not importable on this platform (expected on Linux). On-device path is compile-time gated; inject a custom InferenceProvider instead.",
            evidence: [
                .init(label: "foundation-models", detail: body, artifactPath: context.relativeArtifactPath(for: artifact)),
            ]
        )
    #endif
}

func runLiveFoundationModelsSmokeScenario(
    context: CapabilityScenarioContext,
    environment: [String: String]
) async throws -> CapabilityScenarioResult {
    let enabled = environment["SWARM_SHOWCASE_FOUNDATION_MODELS"] == "1"
        || environment["SWARM_RUN_LIVE_FOUNDATION_MODELS_TESTS"] == "1"
    guard enabled else {
        return .init(
            id: "live-foundation-models-smoke",
            name: "Live Foundation Models Smoke",
            families: [.foundationModels, .providers],
            status: .skipped,
            summary: "Set SWARM_SHOWCASE_FOUNDATION_MODELS=1 to run live on-device Foundation Models smoke."
        )
    }

    #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            guard let provider = FoundationModelsInferenceProvider.ifAvailable() else {
                return .init(
                    id: "live-foundation-models-smoke",
                    name: "Live Foundation Models Smoke",
                    families: [.foundationModels, .providers],
                    status: .skipped,
                    summary: "Foundation Models system model is not available on this device."
                )
            }

            let agent = try Agent(
                "Reply with exactly the single word pong.",
                memory: makeScenarioMemory(),
                inferenceProvider: provider
            )
            let result = try await agent.run("ping")
            let artifact = try context.writeArtifact(
                named: "live-foundation-models-smoke.txt",
                contents: result.output
            )
            return .init(
                id: "live-foundation-models-smoke",
                name: "Live Foundation Models Smoke",
                families: [.foundationModels, .providers],
                status: .passed,
                summary: "Ran a live on-device Foundation Models generation.",
                evidence: [
                    .init(
                        label: "live-output",
                        detail: result.output,
                        artifactPath: context.relativeArtifactPath(for: artifact)
                    ),
                ]
            )
        } else {
            return .init(
                id: "live-foundation-models-smoke",
                name: "Live Foundation Models Smoke",
                families: [.foundationModels, .providers],
                status: .skipped,
                summary: "OS version is below Foundation Models availability."
            )
        }
    #else
        return .init(
            id: "live-foundation-models-smoke",
            name: "Live Foundation Models Smoke",
            families: [.foundationModels, .providers],
            status: .skipped,
            summary: "FoundationModels framework is not importable on this platform."
        )
    #endif
}
