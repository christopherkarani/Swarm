import Foundation
@testable import Swarm
import Testing

@Suite("Foundation Models transcript seed")
struct FoundationModelsTranscriptSeedTests {
    @Test("user, assistant, and tool messages round-trip through the mapper")
    func userAssistantToolRoundTrip() {
        let messages: [InferenceMessage] = [
            .user("what is the weather?"),
            .assistant("I'll check."),
            .tool(name: "weather", content: "72F", toolCallID: "call-1"),
            .assistant("It is 72F."),
        ]
        let mapped = FoundationModelsTranscriptSeed.mapEntries(
            messages: messages,
            instructions: nil
        )
        #expect(mapped.canRehydrate == false)
        #expect(mapped.entries == [
            .prompt(text: "what is the weather?", images: []),
            .response("I'll check."),
            .toolOutput(name: "weather", content: "72F", toolCallID: "call-1"),
            .response("It is 72F."),
        ])
        #expect(FoundationModelsTranscriptSeed.messages(from: mapped.entries) == messages)
    }

    @Test("seed keeps prior roles and splits the pending user prompt")
    func seedSplitsPendingUserPrompt() {
        let seed = FoundationModelsTranscriptSeed.seed(
            messages: [
                .system("Be brief."),
                .user("u1"),
                .assistant("a1"),
                .user("u2"),
            ],
            instructions: "Be brief."
        )
        #expect(seed.canRehydrate)
        #expect(seed.pendingPrompt == "u2")
        #expect(seed.seedEntries == [
            .instructions("Be brief."),
            .prompt(text: "u1", images: []),
            .response("a1"),
        ])
        #expect(
            FoundationModelsTranscriptSeed.messages(from: seed.seedEntries)
                == [.user("u1"), .assistant("a1")]
        )
    }

    @Test("history that does not end with a user turn cannot rehydrate")
    func historyNotEndingWithUserCannotRehydrate() {
        let seed = FoundationModelsTranscriptSeed.seed(
            messages: [
                .user("u1"),
                .assistant("a1"),
            ],
            instructions: nil
        )
        #expect(seed.canRehydrate == false)
    }

    @Test("unpaired tool output cannot rehydrate a Transcript")
    func unpairedToolOutputCannotRehydrate() {
        let seed = FoundationModelsTranscriptSeed.seed(
            messages: [
                .user("what is the weather?"),
                .assistant("I'll check."),
                .tool(name: "weather", content: "72F", toolCallID: "call-1"),
            ],
            instructions: nil
        )
        #expect(seed.canRehydrate == false)
    }

    @Test("rehydrate pending prompt keeps ToolChoice.specific suffix")
    func rehydratePendingPromptKeepsSpecificToolChoice() {
        let seed = FoundationModelsTranscriptSeed.seed(
            messages: [
                .user("u1"),
                .assistant("a1"),
                .user("look up"),
            ],
            instructions: nil
        )
        #expect(seed.canRehydrate)
        let lookup = ToolSchema(name: "lookup", description: "Look up", parameters: [])
        let prompt = FoundationModelsPromptFlattening.appendTurnSuffixes(
            to: seed.pendingPrompt,
            tools: [lookup],
            options: InferenceOptions(toolChoice: .specific(toolName: "lookup"))
        )
        #expect(prompt.contains(#"call "lookup""#))
        #expect(prompt.hasPrefix("look up"))
    }

    @Test("assistant tool-call metadata cannot rehydrate")
    func assistantToolCallsFlatten() {
        let seed = FoundationModelsTranscriptSeed.seed(
            messages: [
                .user("look up"),
                .assistant(
                    "",
                    toolCalls: [.init(id: "1", name: "search", arguments: ["q": .string("x")])]
                ),
                .tool(name: "search", content: "hit", toolCallID: "1"),
            ],
            instructions: nil
        )
        #expect(seed.canRehydrate == false)
    }

    @Test("extra system text cannot rehydrate")
    func extraSystemTextFlattens() {
        let seed = FoundationModelsTranscriptSeed.seed(
            messages: [
                .system("other system"),
                .user("hi"),
            ],
            instructions: "Be brief."
        )
        #expect(seed.canRehydrate == false)
        #expect(FoundationModelsPromptFlattening.flatten(
            messages: [.system("other system"), .user("hi")],
            tools: [],
            options: .default
        ).contains("System: other system"))
    }

    @Test("resolve rehydrates representable history with the pending prompt")
    func resolveRehydratesRepresentableHistory() {
        let resolved = FoundationModelsTranscriptSeed.resolve(
            messages: [
                .system("Be brief."),
                .user("u1"),
                .assistant("a1"),
                .user("u2"),
            ],
            instructions: "Be brief.",
            tools: [],
            options: .default
        )

        #expect(resolved == .rehydrate(
            seedEntries: [
                .instructions("Be brief."),
                .prompt(text: "u1", images: []),
                .response("a1"),
            ],
            prompt: "u2",
            images: []
        ))
    }

    @Test("resolve flattens tool-call history into one prompt")
    func resolveFlattensToolCallHistory() {
        let messages: [InferenceMessage] = [
            .user("look up"),
            .assistant(
                "",
                toolCalls: [.init(id: "1", name: "search", arguments: ["q": .string("x")])]
            ),
            .tool(name: "search", content: "hit", toolCallID: "1"),
        ]
        let resolved = FoundationModelsTranscriptSeed.resolve(
            messages: messages,
            instructions: nil,
            tools: [],
            options: .default
        )

        #expect(resolved == .flatten(
            prompt: [
                "User: look up",
                "Assistant requested tool calls:",
                #"- search({"q":"x"})"#,
                "Tool result (search) [id=1]: hit",
            ].joined(separator: "\n"),
            images: []
        ))
    }

    @Test("resolve sends the pending turn when history is already resident")
    func resolveResidentSendsPendingTurn() {
        let messages: [InferenceMessage] = [
            .user("look up"),
            .assistant(
                "",
                toolCalls: [.init(id: "1", name: "search", arguments: ["q": .string("x")])]
            ),
            .tool(name: "search", content: "hit", toolCallID: "1"),
        ]
        let resolved = FoundationModelsTranscriptSeed.resolve(
            messages: messages,
            instructions: nil,
            tools: [],
            options: .default,
            historyResident: true
        )

        #expect(resolved == .rehydrate(
            seedEntries: [
                .prompt(text: "look up", images: []),
                .toolOutput(name: "search", content: "hit", toolCallID: "1"),
            ],
            prompt: "look up",
            images: []
        ))
    }

    @Test("resolve keeps ToolChoice.specific suffix on the rehydrate branch")
    func resolveRehydrateKeepsSpecificToolChoice() {
        let lookup = ToolSchema(name: "lookup", description: "Look up", parameters: [])
        let resolved = FoundationModelsTranscriptSeed.resolve(
            messages: [.user("look up")],
            instructions: nil,
            tools: [lookup],
            options: InferenceOptions(toolChoice: .specific(toolName: "lookup"))
        )

        #expect(resolved.prompt.hasPrefix("look up"))
        #expect(resolved.prompt.contains(#"call "lookup""#))
        #expect(resolved.images == [])
    }
}

#if canImport(FoundationModels)
import FoundationModels

extension FoundationModelsTranscriptSeedTests {
    @Test("capture turn prompts match the central history resolution")
    func captureTurnMatchesCentralResolution() {
        guard #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) else {
            return
        }
        #if os(tvOS) || os(watchOS)
        return
        #else
        let provider = FoundationModelsInferenceProvider()
        let rehydratable: [InferenceMessage] = [
            .user("u1"),
            .assistant("a1"),
            .user("u2"),
        ]
        let rehydrated = provider.makeCaptureTurn(
            tools: [],
            messages: rehydratable,
            flattenTools: [],
            instructions: nil,
            options: .default
        )
        let resolvedRehydrate = FoundationModelsTranscriptSeed.resolve(
            messages: rehydratable,
            instructions: nil,
            tools: [],
            options: .default
        )
        #expect(rehydrated.prompt == "u2")
        #expect(rehydrated.prompt == resolvedRehydrate.prompt)
        #expect(rehydrated.images == resolvedRehydrate.images)
        #expect(!rehydrated.session.transcript.isEmpty)

        let flattenOnly: [InferenceMessage] = [
            .user("look up"),
            .assistant("", toolCalls: [.init(id: "1", name: "search", arguments: [:])]),
            .tool(name: "search", content: "hit", toolCallID: "1"),
        ]
        let flattened = provider.makeCaptureTurn(
            tools: [],
            messages: flattenOnly,
            flattenTools: [],
            instructions: nil,
            options: .default
        )
        let resolvedFlatten = FoundationModelsTranscriptSeed.resolve(
            messages: flattenOnly,
            instructions: nil,
            tools: [],
            options: .default
        )
        #expect(flattened.prompt == resolvedFlatten.prompt)
        #expect(flattened.images == resolvedFlatten.images)
        #expect(flattened.session.transcript.isEmpty)
        #endif
    }
}
#endif
