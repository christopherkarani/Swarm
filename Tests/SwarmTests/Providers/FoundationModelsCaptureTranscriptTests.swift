import Foundation
@testable import Swarm
import Testing

@Suite("Foundation Models capture transcript")
struct FoundationModelsCaptureTranscriptTests {
    @Test("user, assistant, and tool messages round-trip through the mapper")
    func userAssistantToolRoundTrip() {
        let messages: [InferenceMessage] = [
            .user("what is the weather?"),
            .assistant("I'll check."),
            .tool(name: "weather", content: "72F", toolCallID: "call-1"),
            .assistant("It is 72F."),
        ]
        let mapped = FoundationModelsCaptureTranscript.mapEntries(
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
        #expect(FoundationModelsCaptureTranscript.messages(from: mapped.entries) == messages)
    }

    @Test("seed keeps prior roles and splits the pending user prompt")
    func seedSplitsPendingUserPrompt() {
        let seed = FoundationModelsCaptureTranscript.seed(
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
            FoundationModelsCaptureTranscript.messages(from: seed.seedEntries)
                == [.user("u1"), .assistant("a1")]
        )
    }

    @Test("history that does not end with a user turn cannot rehydrate")
    func historyNotEndingWithUserCannotRehydrate() {
        let seed = FoundationModelsCaptureTranscript.seed(
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
        let seed = FoundationModelsCaptureTranscript.seed(
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
        let seed = FoundationModelsCaptureTranscript.seed(
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
        let seed = FoundationModelsCaptureTranscript.seed(
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
        let seed = FoundationModelsCaptureTranscript.seed(
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
}
