// EventStreamObserver.swift
// Swarm Framework
//
// Internal hook implementation that pipes events to a stream continuation.

import Foundation

/// Internal hook implementation that pipes agent events to an `AsyncThrowingStream` continuation.
///
/// This serves as the bridge between the internal hook-based observation system
/// and the external stream-based observation API.
///
/// ## Emission-order invariant (REQ-008)
///
/// Events are yielded in observer-callback order, which pins the observable
/// stream shape: ``AgentEvent/lifecycle(.started)`` first, then per-iteration
/// `.lifecycle(.iterationStarted/.iterationCompleted)` around LLM/tool/output
/// events, and finally `.lifecycle(.completed)` or `.lifecycle(.failed)`.
/// A failed tool emits `.tool(.completed)` (carrying the failure result)
/// *followed immediately by* `.tool(.failed)` from the same `onToolEnd`
/// callback — a deliberate double emission kept for backward compatibility.
/// Changing that order is a future deprecation-cycle decision; the TurnEngine
/// characterization tests pin it element-for-element.
internal struct EventStreamObserver: AgentObserver {
    /// The continuation to yield events to.
    private let continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    private let toolCallStore = ToolCallStore()

    /// Creates a new event stream hook.
    /// - Parameter continuation: The continuation to yield events to.
    init(continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation) {
        self.continuation = continuation
    }

    // MARK: - AgentObserver Implementation

    func onAgentStart(context _: AgentContext?, agent _: any AgentRuntime, input: String) async {
        continuation.yield(.lifecycle(.started(input: input)))
    }

    func onAgentEnd(context _: AgentContext?, agent _: any AgentRuntime, result: AgentResult) async {
        continuation.yield(.lifecycle(.completed(result: result)))
    }

    func onError(context _: AgentContext?, agent _: any AgentRuntime, error: Error) async {
        if let agentError = error as? AgentError {
            continuation.yield(.lifecycle(.failed(error: agentError)))
        } else {
            continuation.yield(.lifecycle(.failed(error: .internalError(reason: error.localizedDescription))))
        }
    }

    func onToolStart(context _: AgentContext?, agent _: any AgentRuntime, call: ToolCall) async {
        await toolCallStore.record(call)
        continuation.yield(.tool(.started(call: call)))
    }

    func onToolCallPartial(context _: AgentContext?, agent _: any AgentRuntime, update: PartialToolCallUpdate) async {
        continuation.yield(.tool(.partial(update: update)))
    }

    /// Yields `.tool(.completed)` for every settled tool call, then — only when
    /// the result is a failure — a second `.tool(.failed)` event for the same
    /// call. The completed-then-failed adjacency is the pinned REQ-008 order;
    /// do not reorder without a deprecation cycle.
    func onToolEnd(context _: AgentContext?, agent _: any AgentRuntime, result: ToolResult) async {
        let call = await toolCallStore.take(id: result.callId)
            ?? ToolCall(id: result.callId, toolName: "unknown", arguments: [:])
        continuation.yield(.tool(.completed(call: call, result: result)))

        if !result.isSuccess {
            let errorMessage = result.errorMessage ?? "Unknown error"
            continuation.yield(.tool(.failed(
                call: call,
                error: .toolFailure(toolName: call.toolName, message: errorMessage, cause: nil)
            )))
        }
    }

    func onThinking(context _: AgentContext?, agent _: any AgentRuntime, thought: String) async {
        continuation.yield(.output(.thinking(thought: thought)))
    }

    func onThinkingPartial(context _: AgentContext?, agent _: any AgentRuntime, partialThought: String) async {
        continuation.yield(.output(.thinkingPartial(partialThought)))
    }

    func onOutputToken(context _: AgentContext?, agent _: any AgentRuntime, token: String) async {
        continuation.yield(.output(.token(token)))
    }

    func onIterationStart(context _: AgentContext?, agent _: any AgentRuntime, number: Int) async {
        continuation.yield(.lifecycle(.iterationStarted(number: number)))
    }

    func onIterationEnd(context _: AgentContext?, agent _: any AgentRuntime, number: Int) async {
        continuation.yield(.lifecycle(.iterationCompleted(number: number)))
    }

    func onGuardrailTriggered(context: AgentContext?, guardrailName: String, guardrailType: GuardrailType, result: GuardrailResult) async {
        continuation.yield(.observation(.guardrailTriggered(name: guardrailName, type: guardrailType, message: result.message)))
    }

    func onHandoff(context: AgentContext?, fromAgent: any AgentRuntime, toAgent: any AgentRuntime) async {
        let fromName = fromAgent.configuration.name.isEmpty ? String(describing: type(of: fromAgent)) : fromAgent.configuration.name
        let toName = toAgent.configuration.name.isEmpty ? String(describing: type(of: toAgent)) : toAgent.configuration.name

        continuation.yield(.handoff(.requested(from: fromName, to: toName, reason: nil)))
    }

    func onLLMStart(context: AgentContext?, agent: any AgentRuntime, systemPrompt: String?, inputMessages: [MemoryMessage]) async {
        continuation.yield(.observation(.llmStarted(model: nil, promptTokens: nil)))
    }

    func onLLMEnd(context: AgentContext?, agent: any AgentRuntime, response: String, usage: TokenUsage?) async {
        continuation.yield(.observation(.llmCompleted(
            model: nil,
            promptTokens: usage?.inputTokens,
            completionTokens: usage?.outputTokens,
            duration: 0 // Duration not available without explicit tracking
        )))
    }

    func onInferenceRetry(context _: AgentContext?, agent _: any AgentRuntime, attempt: Int, error: Error) async {
        continuation.yield(.observation(.inferenceRetry(
            attempt: attempt,
            message: error.localizedDescription
        )))
    }
}

// MARK: - ToolCallStore

private actor ToolCallStore {
    private var calls: [UUID: ToolCall] = [:]

    func record(_ call: ToolCall) {
        calls[call.id] = call
    }

    func take(id: UUID) -> ToolCall? {
        defer { calls.removeValue(forKey: id) }
        return calls[id]
    }
}
