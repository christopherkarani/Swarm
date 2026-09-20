// HandoffHistoryApplicationTests.swift
// SwarmTests
//
// Pure history projection: none / nested / summarized (nest + annotate).

import Foundation
@testable import Swarm
import Testing

struct HandoffHistoryApplicationTests {
    private let conversation: [AgentTurnTranscript.Message] = [
        .system("You are a router."),
        .user("please route this"),
        .assistant(
            "handing off",
            toolCalls: [
                InferenceResponse.ParsedToolCall(
                    id: "call_handoff",
                    name: "handoff_to_target",
                    arguments: ["reason": .string("delegate")]
                ),
                InferenceResponse.ParsedToolCall(
                    id: "call_other",
                    name: "lookup",
                    arguments: [:]
                ),
            ]
        ),
        .toolResult(toolName: "handoff_to_target", result: "transfer", toolCallID: "call_handoff"),
        .toolResult(toolName: "lookup", result: "ok", toolCallID: "call_other"),
    ]

    @Test("None yields no messages and no summary metadata")
    func noneYieldsEmptyProjection() {
        let projection = HandoffHistoryApplication.apply(
            .none,
            conversation: conversation,
            skippingToolCallID: "call_handoff"
        )

        #expect(projection.messages.isEmpty, "`.none` must not carry source transcript")
        #expect(projection.metadata.isEmpty, "`.none` must not annotate summary metadata")
    }

    @Test("Nested skips the triggering tool-call and keeps the rest")
    func nestedSkipsTriggeringToolCall() throws {
        let projection = HandoffHistoryApplication.apply(
            .nested,
            conversation: conversation,
            skippingToolCallID: "call_handoff"
        )

        #expect(projection.messages.count == 4)
        #expect(projection.messages[0] == .system("You are a router."))
        #expect(projection.messages[1] == .user("please route this"))

        guard case let .assistant(content, toolCalls) = projection.messages[2] else {
            Issue.record("Expected a filtered assistant message")
            return
        }
        #expect(content == "handing off")
        #expect(toolCalls.count == 1)
        #expect(toolCalls[0].id == "call_other")
        #expect(toolCalls[0].name == "lookup")

        #expect(
            projection.messages[3] == .toolResult(toolName: "lookup", result: "ok", toolCallID: "call_other")
        )
        #expect(projection.metadata.isEmpty, "`.nested` must not add summary metadata")
    }

    @Test("Assistant that only contains the triggering tool-call is dropped")
    func assistantWithOnlyTriggeringToolCallIsDropped() {
        let conversation: [AgentTurnTranscript.Message] = [
            .user("please route this"),
            .assistant(
                "",
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_handoff",
                        name: "handoff_to_target",
                        arguments: [:]
                    ),
                ]
            ),
            .toolResult(toolName: "handoff_to_target", result: "gone", toolCallID: "call_handoff"),
        ]

        let projection = HandoffHistoryApplication.apply(
            .nested,
            conversation: conversation,
            skippingToolCallID: "call_handoff"
        )

        #expect(projection.messages == [.user("please route this")])
    }

    @Test(
        "Summarized messages match nested and annotate mode plus maxTokens",
        arguments: [80, 600, 1]
    )
    func summarizedMatchesNestedMessagesAndAnnotatesMetadata(maxTokens: Int) {
        let nested = HandoffHistoryApplication.apply(
            .nested,
            conversation: conversation,
            skippingToolCallID: "call_handoff"
        )
        let summarized = HandoffHistoryApplication.apply(
            .summarized(maxTokens: maxTokens),
            conversation: conversation,
            skippingToolCallID: "call_handoff"
        )

        #expect(summarized.messages == nested.messages, "summarized is nest + annotate, not a real summary")
        #expect(summarized.metadata["swarm.handoff.history.mode"] == .string("summarized"))
        #expect(summarized.metadata["swarm.handoff.history.maxTokens"] == .int(maxTokens))
    }

    @Test("Summarized on empty conversation still annotates metadata")
    func summarizedEmptyConversationAnnotatesMetadata() {
        let projection = HandoffHistoryApplication.apply(
            .summarized(maxTokens: 80),
            conversation: [],
            skippingToolCallID: nil
        )

        #expect(projection.messages.isEmpty)
        #expect(projection.metadata["swarm.handoff.history.mode"] == .string("summarized"))
        #expect(projection.metadata["swarm.handoff.history.maxTokens"] == .int(80))
    }
}
