// AgentTurnKernelTests.swift
// SwarmTests
//
// Pure turn-kernel decisions for the Agent tool loop.

import Foundation
@testable import Swarm
import Testing

struct AgentTurnKernelTests {
    @Test(
        "Mode resolution collapses the flag snapshot into one closed mode",
        arguments: [
            (true, false, false, true, AgentTurnKernel.TurnMode.textOnly),
            (true, false, true, true, AgentTurnKernel.TurnMode.textOnly),
            (false, false, false, false, AgentTurnKernel.TurnMode.hostTools(streaming: false)),
            (false, false, true, false, AgentTurnKernel.TurnMode.hostTools(streaming: true)),
            (true, true, false, true, AgentTurnKernel.TurnMode.ownedLoopTools(streaming: false)),
            (true, true, true, true, AgentTurnKernel.TurnMode.ownedLoopTools(streaming: true)),
            (false, true, true, true, AgentTurnKernel.TurnMode.ownedLoopTools(streaming: true)),
        ]
    )
    func resolveMode(
        toolSchemasEmpty: Bool,
        providerOwnsToolLoop: Bool,
        streamsToolCalls: Bool,
        hasExecutionGate: Bool,
        expected: AgentTurnKernel.TurnMode
    ) throws {
        let mode = try AgentTurnKernel.resolveMode(
            toolSchemasEmpty: toolSchemasEmpty,
            providerOwnsToolLoop: providerOwnsToolLoop,
            streamsToolCalls: streamsToolCalls,
            hasExecutionGate: hasExecutionGate
        )
        #expect(mode == expected)
        #expect(mode.streamsToolCalls == streamsToolCalls || mode == .textOnly)
    }

    @Test("Owned loop without an execution gate fails mode resolution")
    func ownedLoopRequiresGate() {
        #expect(throws: AgentError.internalError(
            reason: "Provider-owned tool loop missing execution gate"
        )) {
            _ = try AgentTurnKernel.resolveMode(
                toolSchemasEmpty: false,
                providerOwnsToolLoop: true,
                streamsToolCalls: false,
                hasExecutionGate: false
            )
        }
    }

    @Test("Owned-loop inference retries only when tool schemas are empty")
    func ownedLoopRetryPolicy() {
        #expect(
            AgentTurnKernel.ownedLoopInferenceRetryPolicy(
                mode: .ownedLoopTools(streaming: false),
                hasToolSchemas: true
            ) == .noRetry
        )
        #expect(
            AgentTurnKernel.ownedLoopInferenceRetryPolicy(
                mode: .ownedLoopTools(streaming: false),
                hasToolSchemas: false
            ) == nil
        )
        #expect(
            AgentTurnKernel.ownedLoopInferenceRetryPolicy(
                mode: .hostTools(streaming: false),
                hasToolSchemas: true
            ) == nil
        )
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
            mode: .ownedLoopTools(streaming: false),
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
            mode: .hostTools(streaming: false),
            response: response
        )
        #expect(decision == .processHostToolCalls)
    }

    @Test("Missing assistant content fails closed")
    func missingContentFails() {
        let empty = InferenceResponse(content: nil, toolCalls: [], finishReason: .completed)
        #expect(
            AgentTurnKernel.afterInference(mode: .hostTools(streaming: false), response: empty)
                == .failMissingContent
        )
        #expect(
            AgentTurnKernel.afterInference(mode: .ownedLoopTools(streaming: false), response: empty)
                == .failMissingContent
        )
    }

    @Test("Host loop finishes on assistant text")
    func hostLoopFinishesOnText() {
        let response = InferenceResponse(content: "42", finishReason: .completed)
        #expect(
            AgentTurnKernel.afterInference(mode: .hostTools(streaming: false), response: response)
                == .finishAssistant(content: "42")
        )
    }

    // MARK: - Steps (REQ-004 boundary)

    private let toolCallResponse = InferenceResponse(
        content: nil,
        toolCalls: [
            InferenceResponse.ParsedToolCall(id: "1", name: "search", arguments: [:]),
        ],
        finishReason: .toolCall
    )

    @Test("Admission under the cap admits the next iteration")
    func admissionAdmitsNextIteration() {
        #expect(
            AgentTurnKernel.admissionStep(iteration: 1, maxIterations: 3)
                == .admitted(iteration: 2)
        )
    }

    @Test("Admission at the cap rejects with maxIterationsExceeded")
    func admissionAtCapRejects() {
        #expect(
            AgentTurnKernel.admissionStep(iteration: 3, maxIterations: 3)
                == .rejected(.maxIterationsExceeded(iterations: 3))
        )
        #expect(
            AgentTurnKernel.admissionStep(iteration: 5, maxIterations: 3)
                == .rejected(.maxIterationsExceeded(iterations: 5))
        )
    }

    @Test("The cap wins at the next loop head even though tool calls are pending")
    func admissionAfterToolsRespectsCap() {
        // Edge from the spec: the failing admission happens at the next loop
        // head. Every head admits exactly once, including after host tools.
        #expect(
            AgentTurnKernel.admissionStep(iteration: 2, maxIterations: 3)
                == .admitted(iteration: 3)
        )
        #expect(
            AgentTurnKernel.admissionStep(iteration: 3, maxIterations: 3)
                == .rejected(.maxIterationsExceeded(iterations: 3))
        )
    }

    @Test("Inference step with pending host tool calls executes tools")
    func inferenceStepExecutesTools() {
        #expect(
            AgentTurnKernel.inferenceStep(
                mode: .hostTools(streaming: false),
                response: toolCallResponse
            ) == .executeTools
        )
    }

    @Test("Inference step with assistant content finishes")
    func inferenceStepFinishes() {
        let response = InferenceResponse(content: "42", finishReason: .completed)
        #expect(
            AgentTurnKernel.inferenceStep(
                mode: .hostTools(streaming: false),
                response: response
            ) == .finish(content: "42")
        )
    }

    @Test("Owned-loop inference step finishes even with tool calls")
    func ownedLoopInferenceStepFinishes() {
        let response = InferenceResponse(
            content: "done",
            toolCalls: [
                InferenceResponse.ParsedToolCall(id: "1", name: "search", arguments: [:]),
            ],
            finishReason: .toolCall
        )
        #expect(
            AgentTurnKernel.inferenceStep(
                mode: .ownedLoopTools(streaming: false),
                response: response
            ) == .finish(content: "done")
        )
    }

    @Test("Inference step without content fails like the loop did")
    func inferenceStepWithoutContentFails() {
        let empty = InferenceResponse(content: nil, toolCalls: [], finishReason: .completed)
        #expect(
            AgentTurnKernel.inferenceStep(
                mode: .hostTools(streaming: false),
                response: empty
            ) == .fail(.generationFailed(reason: "Model returned no content or tool calls"))
        )
    }

    @Test("Inference step before mode resolution fails closed")
    func inferenceStepWithoutModeFails() {
        #expect(
            AgentTurnKernel.inferenceStep(mode: nil, response: toolCallResponse)
                == .fail(.internalError(reason: "Turn mode not resolved before inference"))
        )
    }

    @Test("Owned-loop inference failure retries only with an empty tool list")
    func ownedLoopInferenceFailureRetryDecision() {
        let transient = AgentError.generationFailed(reason: "transient 503")

        #expect(
            AgentTurnKernel.ownedLoopFailureStep(
                mode: .ownedLoopTools(streaming: false),
                hasToolSchemas: false,
                error: transient
            ) == .retryInference
        )
        #expect(
            AgentTurnKernel.ownedLoopFailureStep(
                mode: .ownedLoopTools(streaming: false),
                hasToolSchemas: true,
                error: transient
            ) == .fail(transient)
        )
        #expect(
            AgentTurnKernel.ownedLoopFailureStep(
                mode: .hostTools(streaming: false),
                hasToolSchemas: true,
                error: transient
            ) == .fail(transient)
        )
    }

    @Test("Owned-loop failure before mode resolution fails closed")
    func ownedLoopInferenceFailureWithoutModeFails() {
        let transient = AgentError.generationFailed(reason: "transient 503")
        #expect(
            AgentTurnKernel.ownedLoopFailureStep(
                mode: nil,
                hasToolSchemas: false,
                error: transient
            ) == .fail(transient)
        )
    }

    @Test("Owned-loop cancellation and timeout fail closed even with empty schemas")
    func ownedLoopInferenceFailureDoesNotRetryCancellationOrTimeout() {
        #expect(
            AgentTurnKernel.ownedLoopFailureStep(
                mode: .ownedLoopTools(streaming: false),
                hasToolSchemas: false,
                error: .cancelled
            ) == .fail(.cancelled)
        )
        #expect(
            AgentTurnKernel.ownedLoopFailureStep(
                mode: .ownedLoopTools(streaming: false),
                hasToolSchemas: false,
                error: .timeout(duration: .seconds(15))
            ) == .fail(.timeout(duration: .seconds(15)))
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
