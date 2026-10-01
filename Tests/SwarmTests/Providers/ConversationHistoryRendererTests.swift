// ConversationHistoryRendererTests.swift
// SwarmTests
//
// Both flatten sites delegate to ConversationHistoryRenderer.

@testable import Swarm
import Testing

@Suite("Conversation History Renderer")
struct ConversationHistoryRendererTests {
    private var mixedHistory: [InferenceMessage] {
        [
            .system("Be brief."),
            .system(""),
            .user("look up"),
            .assistant(
                "",
                toolCalls: [.init(id: "1", name: "search", arguments: ["q": .string("x")])]
            ),
            .assistant("done", toolCalls: [.init(name: "other", arguments: [:])]),
            .tool(name: "search", content: "hit", toolCallID: "1"),
            .tool(name: "other", content: "ok"),
        ]
    }

    @Test("bracketed render pins every role shape")
    func bracketedRenderPinsRoleShapes() {
        let rendered = ConversationHistoryRenderer.render(mixedHistory, style: .bracketed)

        #expect(rendered == [
            "[System]: Be brief.",
            "[System]: ",
            "[User]: look up",
            "[Assistant]: Calling tool: search",
            "[Assistant]: done\n[Assistant Tool Calls]: Calling tool: other",
            "[Tool Result - search]: hit",
            "[Tool Result - other]: ok",
        ].joined(separator: "\n\n"))
    }

    @Test("plain render skips empty turns and keeps call ids")
    func plainRenderSkipsEmptyTurns() {
        let rendered = ConversationHistoryRenderer.render(mixedHistory, style: .plain)

        #expect(rendered == [
            "System: Be brief.",
            "User: look up",
            "Assistant requested tool calls:",
            #"- search({"q":"x"})"#,
            "Assistant requested tool calls:",
            "- other({})",
            "Assistant: done",
            "Tool result (search) [id=1]: hit",
            "Tool result (other): ok",
        ].joined(separator: "\n"))
    }

    @Test("flattenPrompt delegates to the bracketed renderer")
    func flattenPromptDelegatesToRenderer() {
        #expect(InferenceMessage.flattenPrompt(mixedHistory) ==
            ConversationHistoryRenderer.render(mixedHistory, style: .bracketed))
        for message in mixedHistory {
            #expect(message.flattenedPromptLine ==
                ConversationHistoryRenderer.lines(for: message, style: .bracketed).joined(separator: "\n"))
        }
    }

    @Test("Foundation Models flatten delegates to the plain renderer")
    func foundationModelsFlattenDelegatesToRenderer() {
        let flattened = FoundationModelsPromptFlattening.flatten(
            messages: mixedHistory,
            tools: [],
            options: .default
        )
        let expected = FoundationModelsPromptFlattening.appendTurnSuffixes(
            to: ConversationHistoryRenderer.render(mixedHistory, style: .plain),
            tools: [],
            options: .default
        )

        #expect(flattened == expected)
    }

    @Test("both styles keep attachments off the text")
    func bothStylesIgnoreAttachments() {
        let attachment = InferenceMessage.Attachment(
            id: "utt-1",
            kind: .audio,
            mimeType: "audio/wav",
            data: Data([0x01, 0x02, 0x03, 0x04])
        )
        let messages = [InferenceMessage.user("hi", attachments: [attachment])]

        for style in [ConversationHistoryRenderer.Style.bracketed, .plain] {
            let rendered = ConversationHistoryRenderer.render(messages, style: style)
            #expect(rendered.contains("hi"))
            #expect(!rendered.contains("AQIDBA=="))
        }
    }
}
