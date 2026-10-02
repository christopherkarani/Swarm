// ConversationHistoryRendererTests.swift
// SwarmTests
//
// Both flatten sites delegate to ConversationHistoryRenderer.

import Foundation
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

    @Test("empty history renders empty in both styles")
    func emptyHistoryRendersEmpty() {
        for style in [ConversationHistoryRenderer.Style.bracketed, .plain] {
            #expect(ConversationHistoryRenderer.render([], style: style) == "")
            #expect(ConversationHistoryRenderer.lines(for: [], style: style) == [])
        }
    }

    @Test("bracketed render joins multiple tool calls with commas")
    func bracketedRenderJoinsMultipleToolCalls() {
        let calls = [
            InferenceMessage.ToolCall(name: "a", arguments: [:]),
            InferenceMessage.ToolCall(name: "b", arguments: [:]),
        ]
        let silent = InferenceMessage.assistant("", toolCalls: calls)
        let speaking = InferenceMessage.assistant("working", toolCalls: calls)

        #expect(silent.flattenedPromptLine == "[Assistant]: Calling tool: a, Calling tool: b")
        #expect(speaking.flattenedPromptLine ==
            "[Assistant]: working\n[Assistant Tool Calls]: Calling tool: a, Calling tool: b")
        #expect(ConversationHistoryRenderer.render([silent, speaking], style: .bracketed) == [
            "[Assistant]: Calling tool: a, Calling tool: b",
            "[Assistant]: working\n[Assistant Tool Calls]: Calling tool: a, Calling tool: b",
        ].joined(separator: "\n\n"))
    }

    @Test("bracketed render keeps empty user and tool turns as blocks")
    func bracketedRenderKeepsEmptyBlocks() {
        let rendered = ConversationHistoryRenderer.render(
            [.user(""), .tool(name: "search", content: "")],
            style: .bracketed
        )

        #expect(rendered == ["[User]: ", "[Tool Result - search]: "].joined(separator: "\n\n"))
    }

    @Test("plain render skips empty user and content-free assistant turns")
    func plainRenderSkipsEmptyUserAndSilentAssistant() {
        let messages: [InferenceMessage] = [
            .user(""),
            .assistant(""),
            .assistant("", toolCalls: [.init(name: "search", arguments: [:])]),
        ]
        let expected = [
            "Assistant requested tool calls:",
            "- search({})",
        ]

        #expect(ConversationHistoryRenderer.lines(for: messages, style: .plain) == expected)
        #expect(ConversationHistoryRenderer.render(messages, style: .plain) ==
            expected.joined(separator: "\n"))
    }

    @Test("plain tool line omits empty call ids")
    func plainToolLineOmitsEmptyCallID() {
        let message = InferenceMessage.tool(name: "search", content: "hit", toolCallID: "")

        #expect(ConversationHistoryRenderer.lines(for: message, style: .plain) ==
            ["Tool result (search): hit"])
    }

    @Test("plain render keeps empty tool content as a bare result line")
    func plainRenderKeepsEmptyToolContent() {
        let messages: [InferenceMessage] = [
            .user(""),
            .tool(name: "search", content: ""),
        ]

        #expect(ConversationHistoryRenderer.lines(for: messages, style: .plain) ==
            ["Tool result (search): "])
        #expect(ConversationHistoryRenderer.render(messages, style: .plain) ==
            "Tool result (search): ")
    }

    @Test("plain tool arguments encode sorted JSON and fall back when not JSON")
    func plainToolArgumentsEncodeSortedJSON() {
        let sorted = InferenceMessage.assistant(
            "",
            toolCalls: [.init(name: "search", arguments: ["b": .int(2), "a": .string("x")])]
        )
        #expect(ConversationHistoryRenderer.lines(for: sorted, style: .plain) == [
            "Assistant requested tool calls:",
            #"- search({"a":"x","b":2})"#,
        ])

        let unencodable = InferenceMessage.assistant(
            "",
            toolCalls: [.init(name: "search", arguments: ["q": .double(.nan)])]
        )
        #expect(ConversationHistoryRenderer.lines(for: unencodable, style: .plain) == [
            "Assistant requested tool calls:",
            "- search({})",
        ])
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
