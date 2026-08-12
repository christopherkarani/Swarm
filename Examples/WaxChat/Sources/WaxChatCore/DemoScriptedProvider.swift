// DemoScriptedProvider.swift
// Deterministic inference provider for CI / machines without Apple Intelligence.

import Foundation
import Swarm

/// Scripted provider that exercises websearch tool calling and multi-turn memory recall.
///
/// Turn sequence for a typical demo run:
/// 1. First tool-capable turn → request `websearch`
/// 2. After tool result → finalize with a primary answer containing demo markers
/// 3. Conversation turn 1 → acknowledge a stored fact
/// 4. Conversation turn 2 → recall that fact **only if** the prompt already contains it
///    (injected from Wax memory context / session history). Hardcoding Kyoto without
///    prompt evidence is intentionally avoided so demo memory checks are not fake.
public actor DemoScriptedProvider: InferenceProvider {
    private var toolPhase = 0
    private var chatTurn = 0

    public init() {}

    public func generate(prompt: String, options: InferenceOptions) async throws -> String {
        "ok"
    }

    public nonisolated func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for token in DemoMarkers.primaryStreamTokens {
                continuation.yield(token)
            }
            continuation.finish()
        }
    }

    public func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        let hasWebSearch = tools.contains { $0.name.lowercased() == "websearch" }
        let lowerPrompt = prompt.lowercased()

        // Primary agent.stream / run path: request websearch, then answer.
        if toolPhase == 0, hasWebSearch {
            toolPhase = 1
            return InferenceResponse(
                toolCalls: [
                    .init(
                        id: "demo-websearch",
                        name: "websearch",
                        arguments: [
                            "mode": .string("search"),
                            "query": .string(DemoMarkers.searchQuery),
                            "maxResults": .int(3),
                        ]
                    ),
                ],
                finishReason: .toolCall
            )
        }

        if toolPhase == 1 {
            toolPhase = 2
            return InferenceResponse(
                content: DemoMarkers.primaryAnswer,
                finishReason: .completed
            )
        }

        // Multi-turn Conversation path.
        // Session history (and/or Wax-injected memory context) must carry the fact
        // for turn 2 — we do not invent Kyoto without prompt evidence.
        chatTurn += 1
        if chatTurn == 1 {
            return InferenceResponse(
                content: DemoMarkers.turn1Answer,
                finishReason: .completed
            )
        }

        if lowerPrompt.contains(DemoMarkers.favoriteCity.lowercased()) {
            return InferenceResponse(
                content: DemoMarkers.turn2Answer,
                finishReason: .completed
            )
        }

        return InferenceResponse(
            content: "I do not remember any favorite city from prior turns.",
            finishReason: .completed
        )
    }
}

/// Fixed content markers asserted by demo mode and unit tests.
public enum DemoMarkers: Sendable {
    public static let searchQuery = "Swift Swarm on-device agents"
    public static let primaryAnswer =
        "Based on websearch for Swift Swarm on-device agents: Swarm runs agents with Foundation Models on device."
    public static let primaryStreamTokens = [
        "Based ", "on ", "websearch ", "for ", "Swift ", "Swarm ",
        "on-device ", "agents: ", "Swarm ", "runs ", "agents ",
        "with ", "Foundation ", "Models ", "on ", "device.",
    ]
    public static let favoriteCity = "Kyoto"
    public static let turn1Answer = "Got it — favorite city Kyoto saved to Wax memory."
    public static let turn2Answer = "Your favorite city is Kyoto."
    public static let turn1UserPrompt = "My favorite city is Kyoto."
    public static let turn2UserPrompt = "What is my favorite city?"
    /// Query used when probing Wax for the multi-turn fact.
    public static let waxRecallQuery = "favorite city"

    public static var defaultPrimaryPrompt: String {
        "Search the web for Swift Swarm on-device agents and summarize in one short sentence."
    }
}
