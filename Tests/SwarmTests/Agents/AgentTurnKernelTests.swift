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

    // MARK: - Transition (REQ-004)

    private let toolCallResponse = InferenceResponse(
        content: nil,
        toolCalls: [
            InferenceResponse.ParsedToolCall(id: "1", name: "search", arguments: [:]),
        ],
        finishReason: .toolCall
    )

    private func state(
        iteration: Int = 0,
        maxIterations: Int = 3,
        mode: AgentTurnKernel.TurnMode? = nil,
        hasToolSchemas: Bool = true
    ) -> AgentTurnKernel.TurnState {
        AgentTurnKernel.TurnState(
            iteration: iteration,
            maxIterations: maxIterations,
            mode: mode,
            hasToolSchemas: hasToolSchemas
        )
    }

    @Test("Admission increments the iteration and clears the per-iteration mode")
    func admissionIncrementsIteration() {
        let result = AgentTurnKernel.transition(
            state(iteration: 1, maxIterations: 3, mode: .hostTools(streaming: false)),
            .startNextIteration
        )
        #expect(result == .performInference(state(iteration: 2, maxIterations: 3, mode: nil)))
    }

    @Test("Admission at the cap fails with maxIterationsExceeded")
    func admissionAtCapFails() {
        let result = AgentTurnKernel.transition(
            state(iteration: 3, maxIterations: 3),
            .startNextIteration
        )
        #expect(result == .fail(.maxIterationsExceeded(iterations: 3)))
    }

    @Test("Inference completion with pending host tool calls executes tools")
    func inferenceCompletionExecutesTools() {
        let current = state(iteration: 1, mode: .hostTools(streaming: false))
        let result = AgentTurnKernel.transition(current, .inferenceCompleted(toolCallResponse))
        #expect(result == .executeTools(current))
    }

    @Test("Inference completion with assistant content finishes")
    func inferenceCompletionFinishes() {
        let response = InferenceResponse(content: "42", finishReason: .completed)
        let result = AgentTurnKernel.transition(
            state(iteration: 1, mode: .hostTools(streaming: false)),
            .inferenceCompleted(response)
        )
        #expect(result == .finish(content: "42"))
    }

    @Test("Owned-loop inference completion finishes even with tool calls")
    func ownedLoopInferenceCompletionFinishes() {
        let response = InferenceResponse(
            content: "done",
            toolCalls: [
                InferenceResponse.ParsedToolCall(id: "1", name: "search", arguments: [:]),
            ],
            finishReason: .toolCall
        )
        let result = AgentTurnKernel.transition(
            state(iteration: 1, mode: .ownedLoopTools(streaming: false)),
            .inferenceCompleted(response)
        )
        #expect(result == .finish(content: "done"))
    }

    @Test("Inference completion without content fails like the loop did")
    func inferenceCompletionWithoutContentFails() {
        let empty = InferenceResponse(content: nil, toolCalls: [], finishReason: .completed)
        let result = AgentTurnKernel.transition(
            state(iteration: 1, mode: .hostTools(streaming: false)),
            .inferenceCompleted(empty)
        )
        #expect(result == .fail(.generationFailed(reason: "Model returned no content or tool calls")))
    }

    @Test("Inference completion before mode resolution fails closed")
    func inferenceCompletionWithoutModeFails() {
        let result = AgentTurnKernel.transition(
            state(iteration: 1, mode: nil),
            .inferenceCompleted(toolCallResponse)
        )
        #expect(result == .fail(.internalError(reason: "Turn mode not resolved before inference")))
    }

    @Test("Completed tools continue to the next admission, respecting the cap")
    func toolsCompletedContinuesLoop() {
        let continuing = AgentTurnKernel.transition(
            state(iteration: 1, mode: .hostTools(streaming: false)),
            .toolsCompleted
        )
        #expect(continuing == .performInference(state(iteration: 2, maxIterations: 3, mode: nil)))

        let capped = AgentTurnKernel.transition(
            state(iteration: 3, maxIterations: 3, mode: .hostTools(streaming: false)),
            .toolsCompleted
        )
        #expect(capped == .fail(.maxIterationsExceeded(iterations: 3)))
    }

    @Test("toolsCompleted already admits, so a second startNextIteration would skip a slot")
    func toolsCompletedMustNotBeFollowedByStartNextIteration() {
        let afterHostTools = state(iteration: 1, mode: .hostTools(streaming: false))
        let continued = AgentTurnKernel.transition(afterHostTools, .toolsCompleted)
        guard case let .performInference(admitted) = continued else {
            Issue.record("Expected toolsCompleted to admit the next iteration")
            return
        }
        #expect(admitted.iteration == 2)

        let doubled = AgentTurnKernel.transition(admitted, .startNextIteration)
        #expect(doubled == .performInference(state(iteration: 3, maxIterations: 3, mode: nil)))
    }

    @Test("Owned-loop inference failure retries only with an empty tool list")
    func ownedLoopInferenceFailureRetryDecision() {
        let transient = AgentError.generationFailed(reason: "transient 503")

        let emptySchemasState = state(iteration: 1, mode: .ownedLoopTools(streaming: false), hasToolSchemas: false)
        let emptySchemas = AgentTurnKernel.transition(
            emptySchemasState,
            .ownedLoopInferenceFailed(transient)
        )
        #expect(emptySchemas == .retryOwnedLoopInference(emptySchemasState))
        guard case let .retryOwnedLoopInference(retryState) = emptySchemas else {
            return
        }
        #expect(retryState.iteration == emptySchemasState.iteration)

        let withSchemas = AgentTurnKernel.transition(
            state(iteration: 1, mode: .ownedLoopTools(streaming: false), hasToolSchemas: true),
            .ownedLoopInferenceFailed(transient)
        )
        #expect(withSchemas == .fail(transient))

        let hostLoop = AgentTurnKernel.transition(
            state(iteration: 1, mode: .hostTools(streaming: false), hasToolSchemas: true),
            .ownedLoopInferenceFailed(transient)
        )
        #expect(hostLoop == .fail(transient))
    }

    @Test("Max iterations reached while tool calls are pending fails identically to the loop")
    func maxIterationsWithPendingToolCalls() {
        // Edge from the spec: the cap wins even though tool calls are pending;
        // the failing admission happens at the next loop head.
        let afterTools = AgentTurnKernel.transition(
            state(iteration: 2, maxIterations: 3, mode: .hostTools(streaming: false)),
            .toolsCompleted
        )
        guard case .performInference = afterTools else {
            Issue.record("Expected the loop to continue under the cap")
            return
        }
        let nextAdmission = AgentTurnKernel.transition(
            state(iteration: 3, maxIterations: 3, mode: .hostTools(streaming: false)),
            .startNextIteration
        )
        #expect(nextAdmission == .fail(.maxIterationsExceeded(iterations: 3)))
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
