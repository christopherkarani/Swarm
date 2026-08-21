// AgentTurnKernel.swift
// Swarm Framework
//
// Pure turn decisions for the Agent tool loop. Effects stay in Agent.

import Foundation

/// Closed decisions for one Agent iteration.
///
/// The kernel does not call providers, tools, observers, or clocks. `Agent`
/// derives a ``TurnMode`` snapshot from the run, feeds ``TurnState`` /
/// ``TurnAction`` values through ``transition(_:_:)``, then executes I/O.
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

    // MARK: - Turn transition (REQ-004)

    /// Pure control state for one tool-calling turn.
    ///
    /// `iteration` counts admitted iterations; `mode` is resolved per iteration
    /// by ``resolveMode(toolSchemasEmpty:providerOwnsToolLoop:streamsToolCalls:hasExecutionGate:)``
    /// and is `nil` between iterations (before the loop's per-iteration effects
    /// have produced tool schemas).
    struct TurnState: Equatable, Sendable {
        /// Iterations admitted so far (0 at turn start).
        var iteration: Int
        /// Configured iteration cap.
        var maxIterations: Int
        /// Mode resolved for the current iteration, if any.
        var mode: TurnMode?
        /// Whether host-visible tool schemas are non-empty this iteration.
        var hasToolSchemas: Bool

        init(
            iteration: Int,
            maxIterations: Int,
            mode: TurnMode? = nil,
            hasToolSchemas: Bool = false
        ) {
            self.iteration = iteration
            self.maxIterations = maxIterations
            self.mode = mode
            self.hasToolSchemas = hasToolSchemas
        }
    }

    /// Facts the shell reports to the kernel after executing an effect.
    enum TurnAction: Equatable, Sendable {
        /// Loop head: request admission of the next iteration.
        case startNextIteration
        /// The provider returned a response for the current iteration.
        case inferenceCompleted(InferenceResponse)
        /// Host tools executed without a handoff; the loop continues.
        case toolsCompleted
        /// Owned-loop inference failed; `AgentError` is the underlying failure.
        case ownedLoopInferenceFailed(AgentError)
    }

    /// The kernel's decision plus the state the shell carries forward.
    enum TurnTransition: Equatable, Sendable {
        /// Iteration admitted; run inference for it.
        case performInference(TurnState)
        /// Host tool calls are pending; execute them, then report
        /// `.toolsCompleted`.
        case executeTools(TurnState)
        /// Owned-loop inference may be retried (empty tool list only; tools
        /// already ran inside inference).
        case retryOwnedLoopInference(TurnState)
        /// The turn finished with assistant content.
        case finish(content: String)
        /// The turn failed.
        case fail(AgentError)
    }

    /// Pure transition over the turn's control state. No effects: `Agent`
    /// executes the effect each case names and feeds the next action back.
    static func transition(_ state: TurnState, _ action: TurnAction) -> TurnTransition {
        switch action {
        case .startNextIteration:
            guard state.iteration < state.maxIterations else {
                return .fail(.maxIterationsExceeded(iterations: state.iteration))
            }
            var admitted = state
            admitted.iteration += 1
            admitted.mode = nil
            return .performInference(admitted)

        case .inferenceCompleted(let response):
            guard let mode = state.mode else {
                return .fail(.internalError(reason: "Turn mode not resolved before inference"))
            }
            switch afterInference(mode: mode, response: response) {
            case .finishAssistant(let content):
                return .finish(content: content)
            case .failMissingContent:
                return .fail(.generationFailed(reason: "Model returned no content or tool calls"))
            case .processHostToolCalls:
                return .executeTools(state)
            }

        case .toolsCompleted:
            // Continuing the loop re-enters at the loop head, where the
            // iteration cap is enforced before any per-iteration effects run.
            return transition(state, .startNextIteration)

        case .ownedLoopInferenceFailed(let error):
            if case .ownedLoopTools = state.mode, !state.hasToolSchemas {
                return .retryOwnedLoopInference(state)
            }
            return .fail(error)
        }
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
