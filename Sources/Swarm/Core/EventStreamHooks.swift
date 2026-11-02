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
/// With `holdsOutputTokens`, `.output(.token)` events (and every event queued
/// behind one, to keep order) are held until the outermost run ends. They are
/// released just before `.lifecycle(.completed)`, or dropped before
/// `.lifecycle(.failed)` so a tripped output guardrail never leaks the text.
internal struct EventStreamObserver: AgentObserver {
    /// The continuation to yield events to.
    private let continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    private let toolCallStore = ToolCallStore()
    private let tokenGate: OutputTokenGate?

    /// Creates a new event stream hook.
    /// - Parameters:
    ///   - continuation: The continuation to yield events to.
    ///   - holdsOutputTokens: Whether to hold token events until the run succeeds.
    init(
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation,
        holdsOutputTokens: Bool = false
    ) {
        self.continuation = continuation
        tokenGate = holdsOutputTokens ? OutputTokenGate() : nil
    }

    // MARK: - AgentObserver Implementation

    func onAgentStart(context _: AgentContext?, agent _: any AgentRuntime, input: String) async {
        await tokenGate?.runStarted()
        await emit(.lifecycle(.started(input: input)))
    }

    func onAgentEnd(context _: AgentContext?, agent _: any AgentRuntime, result: AgentResult) async {
        await endRun(with: .lifecycle(.completed(result: result)), succeeded: true)
    }

    func onError(context _: AgentContext?, agent _: any AgentRuntime, error: Error) async {
        let agentError = error as? AgentError ?? .internalError(reason: error.localizedDescription)
        let event = AgentEvent.lifecycle(.failed(error: agentError))
        // `ToolRegistry` reports tool failures here while the call is still
        // open, and the run may recover from them. Only an error with no open
        // tool call ends a run.
        guard await !toolCallStore.hasPending() else {
            await emit(event)
            return
        }
        await endRun(with: event, succeeded: false)
    }

    func onToolStart(context _: AgentContext?, agent _: any AgentRuntime, call: ToolCall) async {
        await toolCallStore.record(call)
        await emit(.tool(.started(call: call)))
    }

    func onToolCallPartial(context _: AgentContext?, agent _: any AgentRuntime, update: PartialToolCallUpdate) async {
        await emit(.tool(.partial(update: update)))
    }

    func onToolEnd(context _: AgentContext?, agent _: any AgentRuntime, result: ToolResult) async {
        let call = await toolCallStore.take(id: result.callId)
            ?? ToolCall(id: result.callId, toolName: "unknown", arguments: [:])
        await emitToolCompletion(call: call, result: result)
    }

    func onToolEnd(context _: AgentContext?, agent _: any AgentRuntime, invocation: ToolInvocation) async {
        _ = await toolCallStore.take(id: invocation.result.callId)
        await emit(.tool(.completed(invocation)))
        await emitFailedIfNeeded(call: invocation.call, result: invocation.result)
    }

    func onThinking(context _: AgentContext?, agent _: any AgentRuntime, thought: String) async {
        await emit(.output(.thinking(thought: thought)))
    }

    func onThinkingPartial(context _: AgentContext?, agent _: any AgentRuntime, partialThought: String) async {
        await emit(.output(.thinkingPartial(partialThought)))
    }

    func onOutputToken(context _: AgentContext?, agent _: any AgentRuntime, token: String) async {
        await emit(.output(.token(token)))
    }

    func onIterationStart(context _: AgentContext?, agent _: any AgentRuntime, number: Int) async {
        await emit(.lifecycle(.iterationStarted(number: number)))
    }

    func onIterationEnd(context _: AgentContext?, agent _: any AgentRuntime, number: Int) async {
        await emit(.lifecycle(.iterationCompleted(number: number)))
    }

    func onGuardrailTriggered(context: AgentContext?, guardrailName: String, guardrailType: GuardrailType, result: GuardrailResult) async {
        await emit(.observation(.guardrailTriggered(name: guardrailName, type: guardrailType, message: result.message)))
    }

    func onHandoff(context: AgentContext?, fromAgent: any AgentRuntime, toAgent: any AgentRuntime) async {
        let fromName = fromAgent.configuration.name.isEmpty ? String(describing: type(of: fromAgent)) : fromAgent.configuration.name
        let toName = toAgent.configuration.name.isEmpty ? String(describing: type(of: toAgent)) : toAgent.configuration.name

        await emit(.handoff(.requested(from: fromName, to: toName, reason: nil)))
    }

    func onLLMStart(context: AgentContext?, agent: any AgentRuntime, systemPrompt: String?, inputMessages: [InferenceMessage]) async {
        await emit(.observation(.llmStarted(model: nil, promptTokens: nil)))
    }

    func onLLMEnd(context: AgentContext?, agent: any AgentRuntime, response: String, usage: TokenUsage?) async {
        await emit(.observation(.llmCompleted(
            model: nil,
            promptTokens: usage?.inputTokens,
            completionTokens: usage?.outputTokens,
            duration: 0 // Duration not available without explicit tracking
        )))
    }

    func onInferenceRetry(context _: AgentContext?, agent _: any AgentRuntime, attempt: Int, error: Error) async {
        await emit(.observation(.inferenceRetry(
            attempt: attempt,
            message: error.localizedDescription
        )))
    }

    private func emitToolCompletion(call: ToolCall, result: ToolResult) async {
        await emit(.tool(.completed(call: call, result: result)))
        await emitFailedIfNeeded(call: call, result: result)
    }

    private func emitFailedIfNeeded(call: ToolCall, result: ToolResult) async {
        guard !result.isSuccess else {
            return
        }
        let errorMessage = result.errorMessage ?? "Unknown error"
        await emit(.tool(.failed(
            call: call,
            error: ToolFailureCause.messageOnly(toolName: call.toolName, message: errorMessage)
        )))
    }

    private func emit(_ event: AgentEvent) async {
        guard let tokenGate else {
            continuation.yield(event)
            return
        }
        for released in await tokenGate.submit(event) {
            continuation.yield(released)
        }
    }

    private func endRun(with terminal: AgentEvent, succeeded: Bool) async {
        guard let tokenGate else {
            continuation.yield(terminal)
            return
        }
        for released in await tokenGate.runEnded(with: terminal, succeeded: succeeded) {
            continuation.yield(released)
        }
    }
}

// MARK: - ToolCallStore

private actor ToolCallStore {
    private var calls: [UUID: ToolCall] = [:]

    func record(_ call: ToolCall) {
        calls[call.id] = call
    }

    func hasPending() -> Bool {
        !calls.isEmpty
    }

    func take(id: UUID) -> ToolCall? {
        defer { calls.removeValue(forKey: id) }
        return calls[id]
    }
}

// MARK: - OutputTokenGate

/// Holds token events until the outermost run's output guardrails have passed.
///
/// Handoff targets report through the same observer, so nested `onAgentStart`
/// / `onAgentEnd` pairs are counted and only the outermost end releases.
private actor OutputTokenGate {
    private var depth = 0
    private var held: [AgentEvent] = []

    func runStarted() {
        depth += 1
    }

    /// Returns the events to yield now; the rest stay queued in order.
    func submit(_ event: AgentEvent) -> [AgentEvent] {
        if case .output(.token) = event {
            held.append(event)
            return []
        }
        guard held.isEmpty else {
            held.append(event)
            return []
        }
        return [event]
    }

    /// Ends one run. The outermost end releases the queue followed by
    /// `terminal`; held tokens are released only when the run succeeded.
    func runEnded(with terminal: AgentEvent, succeeded: Bool) -> [AgentEvent] {
        depth -= 1
        guard depth <= 0 else {
            return submit(terminal)
        }
        // Defensive: a handoff target outside `Agent` may end without a start.
        depth = 0
        let queued = held
        held = []
        let released = succeeded ? queued : queued.filter { event in
            if case .output(.token) = event { false } else { true }
        }
        return released + [terminal]
    }
}
