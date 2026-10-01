// AgentTurnKernel.swift
// Swarm Framework
//
// Pure turn decisions for the Agent tool loop. Effects stay in Agent.

import Foundation

/// Closed decisions for one Agent iteration.
///
/// The kernel does not call providers, tools, observers, or clocks. The
/// runner owns its loop-carried progress, reports explicit step inputs
/// (counters, mode, response), and executes the effect each returned step
/// names.
enum AgentTurnKernel: Sendable {
    /// How a turn executes the tool loop (REQ-003).
    ///
    /// Replaces the parallel boolean snapshots (`toolSchemasEmpty`,
    /// `useProviderOwnedToolLoop`, `streamingToolCalls`, `hasExecutionGate`)
    /// with one closed enum, so contradictory flag combinations are
    /// unrepresentable.
    enum TurnMode: Equatable, Sendable {
        /// No host tool schemas and the provider does not own the loop:
        /// one text-only generation, then the turn finishes.
        case textOnly
        /// The Agent owns the tool loop; tools execute between inference calls.
        case hostTools(streaming: Bool)
        /// The provider owns the tool loop; tools execute inside inference and
        /// require the execution gate created by `runInternal`.
        case ownedLoopTools(streaming: Bool)

        /// Whether this mode consumes the streaming tool-call seam.
        var streamsToolCalls: Bool {
            switch self {
            case .textOnly: return false
            case .hostTools(streaming: let streaming), .ownedLoopTools(streaming: let streaming):
                return streaming
            }
        }
    }

    /// Derives the turn mode from the run's flags. Single derivation point
    /// (REQ-003): `Agent` must not reconstruct the mode from booleans.
    ///
    /// An owned-loop provider still uses the tool-calling path when schemas are
    /// empty so the adapter can run an empty inner loop. Owned-loop execution
    /// requires the timeout gate created by `runInternal`.
    static func resolveMode(
        toolSchemasEmpty: Bool,
        providerOwnsToolLoop: Bool,
        streamsToolCalls: Bool,
        hasExecutionGate: Bool
    ) throws -> TurnMode {
        if providerOwnsToolLoop {
            guard hasExecutionGate else {
                throw AgentError.internalError(
                    reason: "Provider-owned tool loop missing execution gate"
                )
            }
            return .ownedLoopTools(streaming: streamsToolCalls)
        }
        if toolSchemasEmpty {
            return .textOnly
        }
        return .hostTools(streaming: streamsToolCalls)
    }

    /// What to do with a completed `InferenceResponse`.
    enum AfterInference: Sendable, Equatable {
        case finishAssistant(content: String)
        case processHostToolCalls
        case failMissingContent
    }

    /// Owned-loop tool execution is not retry-safe; empty owned loops may retry.
    static func ownedLoopInferenceRetryPolicy(
        mode: TurnMode,
        hasToolSchemas: Bool
    ) -> RetryPolicy? {
        if case .ownedLoopTools = mode, hasToolSchemas {
            return .noRetry
        }
        return nil
    }

    /// Interprets a finished model response for host vs owned-loop control flow.
    static func afterInference(
        mode: TurnMode,
        response: InferenceResponse
    ) -> AfterInference {
        if case .ownedLoopTools = mode {
            guard let content = response.content else {
                return .failMissingContent
            }
            return .finishAssistant(content: content)
        }

        if response.hasToolCalls {
            return .processHostToolCalls
        }

        guard let content = response.content else {
            return .failMissingContent
        }
        return .finishAssistant(content: content)
    }

    // MARK: - Turn steps (REQ-004 boundary)

    /// Admission decision for one loop head. The runner passes its own
    /// counters; the kernel admits the next iteration or rejects at the cap.
    /// An explicit step value: no shared mutable state crosses the boundary.
    enum AdmissionStep: Equatable, Sendable {
        /// Iteration admitted; run inference for it.
        case admitted(iteration: Int)
        /// The cap was reached; the turn fails with this error.
        case rejected(AgentError)
    }

    /// Post-inference decision for the current iteration.
    enum InferenceStep: Equatable, Sendable {
        /// The turn finished with assistant content.
        case finish(content: String)
        /// Host tool calls are pending; execute them, then admit the next
        /// iteration at the loop head.
        case executeTools
        /// The turn failed.
        case fail(AgentError)
    }

    /// Owned-loop inference-failure decision. Empty schemas may retry
    /// transient failures (``ownedLoopInferenceRetryPolicy(mode:hasToolSchemas:)``
    /// still governs retry timing inside `executeProviderInference`);
    /// cancellation, timeout, and tools that already ran inside inference
    /// fail closed.
    enum OwnedLoopFailureStep: Equatable, Sendable {
        /// Owned-loop inference may be retried (empty retryable failures only).
        case retryInference
        /// The turn failed.
        case fail(AgentError)
    }

    /// Admits the next iteration. Pure: the runner owns the counters and
    /// applies the admitted iteration to its own progress.
    static func admissionStep(iteration: Int, maxIterations: Int) -> AdmissionStep {
        guard iteration < maxIterations else {
            return .rejected(.maxIterationsExceeded(iterations: iteration))
        }
        return .admitted(iteration: iteration + 1)
    }

    /// Interprets a finished model response for host vs owned-loop control
    /// flow. A missing mode fails closed: the runner resolves the mode through
    /// ``resolveMode(toolSchemasEmpty:providerOwnsToolLoop:streamsToolCalls:hasExecutionGate:)``
    /// before reporting inference.
    static func inferenceStep(mode: TurnMode?, response: InferenceResponse) -> InferenceStep {
        guard let mode else {
            return .fail(.internalError(reason: "Turn mode not resolved before inference"))
        }
        switch afterInference(mode: mode, response: response) {
        case .finishAssistant(let content):
            return .finish(content: content)
        case .failMissingContent:
            return .fail(.generationFailed(reason: "Model returned no content or tool calls"))
        case .processHostToolCalls:
            return .executeTools
        }
    }

    /// Classifies an owned-loop inference failure. Empty schemas are
    /// retry-safe (no host tools to replay), but only transient inference
    /// failures may retry.
    static func ownedLoopFailureStep(
        mode: TurnMode?,
        hasToolSchemas: Bool,
        error: AgentError
    ) -> OwnedLoopFailureStep {
        // Cancellation and timeout fail closed so they cannot be classified
        // as generationFailed.
        if case .ownedLoopTools = mode, !hasToolSchemas, error.isRetryable {
            return .retryInference
        }
        return .fail(error)
    }

    /// How the host loop should treat one tool name.
    enum HostToolCallKind: Sendable, Equatable {
        case handoff
        case membraneInternal
        case regular
    }

    /// Assistant text recorded for a tool-calling turn.
    static func assistantContent(for response: InferenceResponse) -> String {
        if let content = response.content {
            return content
        }
        return response.toolCalls.map { "Calling tool: \($0.name)" }.joined(separator: ", ")
    }

    /// Handoff names win so transfer tools are never treated as Membrane internals.
    ///
    /// Pass `isHandoffTool` only when a handoff configuration exists for the
    /// name, and `isMembraneInternal` only when an adapter is present and the
    /// name is a Membrane internal. Agent then switches this result exhaustively;
    /// a missing handle is a `.regular` execution arm, never a remapped kind.
    static func hostToolCallKind(
        isHandoffTool: Bool,
        isMembraneInternal: Bool
    ) -> HostToolCallKind {
        if isHandoffTool {
            return .handoff
        }
        if isMembraneInternal {
            return .membraneInternal
        }
        return .regular
    }

    /// Input passed to the target agent when a handoff tool fires.
    static func handoffInput(lastUserText: String?, reason: String) -> String {
        if let lastUserText {
            return lastUserText
        }
        return reason.isEmpty ? "Continue the conversation" : reason
    }

    /// Tool-error text the model sees on the next turn.
    static func toolFailureConversationText(message: String) -> String {
        "[TOOL ERROR] Execution failed: \(message). Please try a different approach or tool."
    }

    /// Shorter tool-error text stored in memory.
    static func memoryToolErrorText(message: String) -> String {
        "Error - \(message)"
    }
}
