// AgentTurnKernelTests.swift
// SwarmTests
//
// Pure turn-kernel decisions for the Agent tool loop.

import Foundation
@testable import Swarm
import Testing

struct AgentTurnKernelTests {
    @Test(
        "Inference kind matches empty-schema and owned-loop combinations",
        arguments: [
            (true, false, false, AgentTurnKernel.InferenceKind.withoutTools),
            (true, false, true, AgentTurnKernel.InferenceKind.withoutTools),
            (true, true, false, AgentTurnKernel.InferenceKind.withTools(streaming: false)),
            (true, true, true, AgentTurnKernel.InferenceKind.withTools(streaming: true)),
            (false, false, false, AgentTurnKernel.InferenceKind.withTools(streaming: false)),
            (false, false, true, AgentTurnKernel.InferenceKind.withTools(streaming: true)),
            (false, true, true, AgentTurnKernel.InferenceKind.withTools(streaming: true)),
        ]
    )
    func inferenceKind(
        toolSchemasEmpty: Bool,
        useProviderOwnedToolLoop: Bool,
        streamingToolCalls: Bool,
        expected: AgentTurnKernel.InferenceKind
    ) {
        let kind = AgentTurnKernel.inferenceKind(
            toolSchemasEmpty: toolSchemasEmpty,
            useProviderOwnedToolLoop: useProviderOwnedToolLoop,
            streamingToolCalls: streamingToolCalls
        )
        #expect(kind == expected)
    }

    @Test("Owned-loop inference retries only when tool schemas are empty")
    func ownedLoopRetryPolicy() {
        #expect(
            AgentTurnKernel.ownedLoopInferenceRetryPolicy(
                useProviderOwnedToolLoop: true,
                hasToolSchemas: true
            ) == .noRetry
        )
        #expect(
            AgentTurnKernel.ownedLoopInferenceRetryPolicy(
                useProviderOwnedToolLoop: true,
                hasToolSchemas: false
            ) == nil
        )
        #expect(
            AgentTurnKernel.ownedLoopInferenceRetryPolicy(
                useProviderOwnedToolLoop: false,
                hasToolSchemas: true
            ) == nil
        )
    }

    @Test("Owned loop requires an execution gate")
    func ownedLoopRequiresGate() throws {
        try AgentTurnKernel.requireOwnedLoopGate(
            useProviderOwnedToolLoop: true,
            hasExecutionGate: true
        )
        try AgentTurnKernel.requireOwnedLoopGate(
            useProviderOwnedToolLoop: false,
            hasExecutionGate: false
        )

        #expect(throws: AgentError.internalError(
            reason: "Provider-owned tool loop missing execution gate"
        )) {
            try AgentTurnKernel.requireOwnedLoopGate(
                useProviderOwnedToolLoop: true,
                hasExecutionGate: false
            )
        }
    }

    @Test("Owned-loop responses finish even when the model also listed tool calls")
    func ownedLoopFinishesFromResponse() {
        let response = InferenceResponse(
            content: "done",
            toolCalls: [
                InferenceResponse.ParsedToolCall(id: "1", name: "search", arguments: [:]),
            ],
            finishReason: .toolCall
        )
        let decision = AgentTurnKernel.afterInference(
            useProviderOwnedToolLoop: true,
            response: response
        )
        #expect(decision == .finishAssistant(content: "done"))
    }

    @Test("Host loop processes tool calls before finishing")
    func hostLoopProcessesToolCalls() {
        let response = InferenceResponse(
            content: nil,
            toolCalls: [
                InferenceResponse.ParsedToolCall(id: "1", name: "search", arguments: [:]),
            ],
            finishReason: .toolCall
        )
        let decision = AgentTurnKernel.afterInference(
            useProviderOwnedToolLoop: false,
            response: response
        )
        #expect(decision == .processHostToolCalls)
    }

    @Test("Missing assistant content fails closed")
    func missingContentFails() {
        let empty = InferenceResponse(content: nil, toolCalls: [], finishReason: .completed)
        #expect(
            AgentTurnKernel.afterInference(useProviderOwnedToolLoop: false, response: empty)
                == .failMissingContent
        )
        #expect(
            AgentTurnKernel.afterInference(useProviderOwnedToolLoop: true, response: empty)
                == .failMissingContent
        )
    }

    @Test("Host loop finishes on assistant text")
    func hostLoopFinishesOnText() {
        let response = InferenceResponse(content: "42", finishReason: .completed)
        #expect(
            AgentTurnKernel.afterInference(useProviderOwnedToolLoop: false, response: response)
                == .finishAssistant(content: "42")
        )
    }

    @Test("Assistant tool-turn content prefers model text, then a call summary")
    func assistantContentForToolTurn() {
        let withText = InferenceResponse(
            content: "I'll search",
            toolCalls: [
                InferenceResponse.ParsedToolCall(id: "1", name: "search", arguments: [:]),
            ],
            finishReason: .toolCall
        )
        #expect(AgentTurnKernel.assistantContent(for: withText) == "I'll search")

        let callsOnly = InferenceResponse(
            content: nil,
            toolCalls: [
                InferenceResponse.ParsedToolCall(id: "1", name: "search", arguments: [:]),
                InferenceResponse.ParsedToolCall(id: "2", name: "lookup", arguments: [:]),
            ],
            finishReason: .toolCall
        )
        #expect(
            AgentTurnKernel.assistantContent(for: callsOnly)
                == "Calling tool: search, Calling tool: lookup"
        )
    }

    @Test(
        "Host tool-call kind is exhaustive for Agent dispatch",
        arguments: [
            (true, true, AgentTurnKernel.HostToolCallKind.handoff),
            (true, false, AgentTurnKernel.HostToolCallKind.handoff),
            (false, true, AgentTurnKernel.HostToolCallKind.membraneInternal),
            (false, false, AgentTurnKernel.HostToolCallKind.regular),
        ]
    )
    func hostToolCallKind(
        isHandoffTool: Bool,
        isMembraneInternal: Bool,
        expected: AgentTurnKernel.HostToolCallKind
    ) {
        #expect(
            AgentTurnKernel.hostToolCallKind(
                isHandoffTool: isHandoffTool,
                isMembraneInternal: isMembraneInternal
            ) == expected
        )
    }

    @Test("Handoff input uses the last user message, then reason, then a default")
    func handoffInput() {
        #expect(AgentTurnKernel.handoffInput(lastUserText: "summarize this", reason: "writer") == "summarize this")
        #expect(AgentTurnKernel.handoffInput(lastUserText: nil, reason: "need writer") == "need writer")
        #expect(AgentTurnKernel.handoffInput(lastUserText: nil, reason: "") == "Continue the conversation")
    }

    @Test("Tool failure text for the model and for memory stay distinct")
    func toolFailureText() {
        #expect(
            AgentTurnKernel.toolFailureConversationText(message: "boom")
                == "[TOOL ERROR] Execution failed: boom. Please try a different approach or tool."
        )
        #expect(AgentTurnKernel.memoryToolErrorText(message: "boom") == "Error - boom")
    }
}
