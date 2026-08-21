// AgentTurnKernel.swift
// Swarm Framework
//
// Pure turn decisions for the Agent tool loop. Effects stay in Agent.

import Foundation

/// Closed decisions for one Agent iteration.
///
/// The kernel does not call providers, tools, observers, or clocks. `Agent`
/// snapshots booleans from the run, asks for a decision, then executes I/O.
enum AgentTurnKernel: Sendable {
    /// How this iteration should invoke the inference provider.
    enum InferenceKind: Sendable, Equatable {
        /// Empty host-loop tool list: generate text only, then finish.
        case withoutTools
        /// Host or owned tool loop: `generateWithTools` / streaming variant.
        case withTools(streaming: Bool)
    }

    /// What to do with a completed `InferenceResponse`.
    enum AfterInference: Sendable, Equatable {
        case finishAssistant(content: String)
        case processHostToolCalls
        case failMissingContent
    }

    /// Chooses text-only vs tool-calling inference for this iteration.
    ///
    /// An owned-loop provider still uses the tool-calling path when schemas are
    /// empty so the adapter can run an empty inner loop.
    static func inferenceKind(
        toolSchemasEmpty: Bool,
        useProviderOwnedToolLoop: Bool,
        streamingToolCalls: Bool
    ) -> InferenceKind {
        if toolSchemasEmpty, !useProviderOwnedToolLoop {
            return .withoutTools
        }
        return .withTools(streaming: streamingToolCalls)
    }

    /// Owned-loop tool execution is not retry-safe; empty owned loops may retry.
    static func ownedLoopInferenceRetryPolicy(
        useProviderOwnedToolLoop: Bool,
        hasToolSchemas: Bool
    ) -> RetryPolicy? {
        if useProviderOwnedToolLoop, hasToolSchemas {
            return .noRetry
        }
        return nil
    }

    /// Owned-loop execution requires the timeout gate created by `runInternal`.
    static func requireOwnedLoopGate(
        useProviderOwnedToolLoop: Bool,
        hasExecutionGate: Bool
    ) throws {
        if useProviderOwnedToolLoop, !hasExecutionGate {
            throw AgentError.internalError(
                reason: "Provider-owned tool loop missing execution gate"
            )
        }
    }

    /// Interprets a finished model response for host vs owned-loop control flow.
    static func afterInference(
        useProviderOwnedToolLoop: Bool,
        response: InferenceResponse
    ) -> AfterInference {
        if useProviderOwnedToolLoop {
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

    /// Maps a classified kind plus handle snapshots onto the arm Agent should run.
    ///
    /// Missing handoff configuration or a missing Membrane adapter becomes
    /// `.regular`. Handoff never becomes `.membraneInternal`, even when an
    /// adapter is present.
    static func resolvedHostToolCallKind(
        _ kind: HostToolCallKind,
        hasHandoffConfiguration: Bool,
        hasMembraneAdapter: Bool
    ) -> HostToolCallKind {
        switch kind {
        case .handoff:
            return hasHandoffConfiguration ? .handoff : .regular
        case .membraneInternal:
            return hasMembraneAdapter ? .membraneInternal : .regular
        case .regular:
            return .regular
        }
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
