// HandoffPreparationTests.swift
// SwarmTests
//
// Pure handoff request construction shared by the tool loop and coordinator.

import Foundation
@testable import Swarm
import Testing

struct HandoffPreparationTests {
    @Test("Last user text is the last user message in the conversation")
    func lastUserTextUsesLastUserMessage() {
        let conversation: [AgentTurnTranscript.Message] = [
            .system("router"),
            .user("first"),
            .assistant("ack"),
            .user("please route this"),
        ]

        #expect(HandoffPreparation.lastUserText(from: conversation) == "please route this")
    }

    @Test("Last user text is nil when the conversation has no user turn")
    func lastUserTextNilWithoutUser() {
        let conversation: [AgentTurnTranscript.Message] = [
            .system("router"),
            .assistant("waiting"),
        ]

        #expect(HandoffPreparation.lastUserText(from: conversation) == nil)
    }

    @Test("makeRequest prefers transformed input over the kernel fallback")
    func makeRequestPrefersTransformedInput() {
        let request = HandoffPreparation.makeRequest(
            sourceAgentName: "source-agent",
            targetAgentName: "target-agent",
            lastUserText: "please route this",
            reason: "needs specialist",
            transformed: HandoffInputData(
                sourceAgentName: "source-agent",
                targetAgentName: "target-agent",
                input: "transformed: please route this",
                context: ["ticket": .string("t-1")],
                metadata: ["transformed": .bool(true)]
            )
        )

        #expect(request.sourceAgentName == "source-agent")
        #expect(request.targetAgentName == "target-agent")
        #expect(request.input == "transformed: please route this")
        #expect(request.reason == "needs specialist")
        #expect(request.context["ticket"] == .string("t-1"))
        #expect(request.context["transformed"] == .bool(true))
    }

    @Test("makeRequest uses AgentTurnKernel.handoffInput when transformed input is empty")
    func makeRequestFallsBackToKernelInputPolicy() {
        let withUser = HandoffPreparation.makeRequest(
            sourceAgentName: "source",
            targetAgentName: "target",
            lastUserText: "summarize this",
            reason: "writer",
            transformed: HandoffInputData(
                sourceAgentName: "source",
                targetAgentName: "target",
                input: ""
            )
        )
        let withReason = HandoffPreparation.makeRequest(
            sourceAgentName: "source",
            targetAgentName: "target",
            lastUserText: nil,
            reason: "need writer",
            transformed: HandoffInputData(
                sourceAgentName: "source",
                targetAgentName: "target",
                input: ""
            )
        )
        let fallback = HandoffPreparation.makeRequest(
            sourceAgentName: "source",
            targetAgentName: "target",
            lastUserText: nil,
            reason: "",
            transformed: HandoffInputData(
                sourceAgentName: "source",
                targetAgentName: "target",
                input: ""
            )
        )

        #expect(withUser.input == AgentTurnKernel.handoffInput(lastUserText: "summarize this", reason: "writer"))
        #expect(withReason.input == AgentTurnKernel.handoffInput(lastUserText: nil, reason: "need writer"))
        #expect(fallback.input == AgentTurnKernel.handoffInput(lastUserText: nil, reason: ""))
        #expect(fallback.reason == nil)
    }

    @Test("makeRequest metadata overwrites colliding context keys")
    func makeRequestMetadataWinsOnCollision() {
        let request = HandoffPreparation.makeRequest(
            sourceAgentName: "source",
            targetAgentName: "target",
            lastUserText: "hi",
            reason: "go",
            transformed: HandoffInputData(
                sourceAgentName: "source",
                targetAgentName: "target",
                input: "hi",
                context: ["mode": .string("context")],
                metadata: ["mode": .string("metadata")]
            )
        )

        #expect(request.context["mode"] == .string("metadata"))
        #expect(request.reason == "go")
    }

    @Test("prepare applies summarized metadata and filters reserved context keys")
    func prepareAnnotatesSummarizedHistoryAndFiltersContext() {
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
        ]
        let prepared = HandoffPreparation.prepare(
            sourceAgentName: "source-agent",
            targetAgentName: "target-agent",
            lastUserText: "please route this",
            reason: "delegate",
            transformed: HandoffInputData(
                sourceAgentName: "source-agent",
                targetAgentName: "target-agent",
                input: "please route this",
                context: [
                    "ticket": .string("t-1"),
                    "user_id": .string("secret"),
                ],
                metadata: ["transformed": .bool(true)]
            ),
            history: .summarized(maxTokens: 80),
            conversation: conversation,
            skippingToolCallID: "call_handoff"
        )

        #expect(prepared.request.input == "please route this")
        #expect(prepared.request.reason == "delegate")
        #expect(prepared.request.context["ticket"] == .string("t-1"))
        #expect(prepared.request.context["transformed"] == .bool(true))
        #expect(prepared.request.context["swarm.handoff.history.mode"] == .string("summarized"))
        #expect(prepared.request.context["swarm.handoff.history.maxTokens"] == .int(80))
        #expect(prepared.allowedContext["ticket"] == .string("t-1"))
        #expect(prepared.allowedContext["user_id"] == nil)
        #expect(prepared.allowedContext["swarm.handoff.history.mode"] == .string("summarized"))
        #expect(prepared.historyProjection.messages == [.user("please route this")])
        #expect(prepared.nestsSession == true)
    }

    @Test("prepare with .none does not nest a session or project messages")
    func prepareNoneDoesNotNest() {
        let prepared = HandoffPreparation.prepare(
            sourceAgentName: "source",
            targetAgentName: "target",
            lastUserText: "hi",
            reason: "",
            transformed: HandoffInputData(
                sourceAgentName: "source",
                targetAgentName: "target",
                input: "hi"
            ),
            history: .none,
            conversation: [.user("hi"), .assistant("ack")],
            skippingToolCallID: nil
        )

        #expect(prepared.historyProjection.messages.isEmpty)
        #expect(prepared.nestsSession == false)
        #expect(prepared.request.reason == nil)
    }
}
