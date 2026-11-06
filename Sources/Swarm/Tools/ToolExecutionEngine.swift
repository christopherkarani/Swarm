// ToolExecutionEngine.swift
// Swarm Framework
//
// Shared tool execution implementation used across agents.

import Foundation

// MARK: - ToolClock

/// Nanosecond clock used by ``ToolExecutionEngine`` for duration measurement.
///
/// Matches the `SwarmClock.nowNanoseconds()` shape so tests can inject a
/// scripted source of time without sleeping. Sleep is not part of this seam;
/// tool bodies remain responsible for their own suspension.
protocol ToolClock: Sendable {
    func nowNanoseconds() -> UInt64
}

/// Live adapter over ``LiveSwarmClock`` so Engine defaults match wall-monotonic time.
struct LiveToolClock: ToolClock {
    static let live = LiveToolClock()

    func nowNanoseconds() -> UInt64 {
        LiveSwarmClock.live.nowNanoseconds()
    }
}

/// Centralized tool-call execution path.
///
/// This standardizes:
/// - ToolCall + ToolResult creation
/// - AgentResult.Builder recording
/// - AgentObserver emission
/// - ToolRegistry execution wiring
///
/// Duration is measured from an injectable ``ToolClock`` so tests can pin
/// elapsed time without `Task.sleep`. ``init()`` keeps compiling as
/// `ToolExecutionEngine()` from the Agent host loop.
struct ToolExecutionEngine: Sendable {
    private let clock: any ToolClock

    init(clock: some ToolClock = LiveToolClock()) {
        self.clock = clock
    }

    struct Outcome: Sendable {
        let call: ToolCall
        let result: ToolResult
        /// Original tool error when ``result`` is a failure; `nil` on success.
        ///
        /// ``ToolResult`` only stores a message string. The façade keeps this
        /// instance so continue-on-error and fail-fast can preserve error identity.
        let caughtError: (any Error)?
        /// `true` when a durable replay returned the call's recorded outcome
        /// instead of executing it. Callers skip side effects such as memory
        /// writes that already happened when the call executed.
        var replayed = false
    }

    func execute(
        toolName: String,
        arguments: [String: SendableValue],
        providerCallId: String? = nil,
        registry: ToolRegistry,
        agent: any AgentRuntime,
        context: AgentContext?,
        resultBuilder: AgentResult.Builder,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        stopOnToolError: Bool
    ) async throws -> Outcome {
        let call = ToolCall(providerCallId: providerCallId, toolName: toolName, arguments: arguments)
        if let recorded = await WorkflowDurableApprovalGate.replay(call: call) {
            return try replayedOutcome(
                call: call,
                recorded: recorded,
                resultBuilder: resultBuilder,
                stopOnToolError: stopOnToolError
            )
        }
        let consumedApproval = try await WorkflowDurableApprovalGate.check(
            call: call,
            registry: registry,
            agent: agent,
            context: context,
            observer: observer
        )
        _ = resultBuilder.addToolCall(call)

        await observer?.onToolStart(context: context, agent: agent, call: call)

        let spanId: UUID? = if let tracing { await tracing.traceToolCall(name: toolName, arguments: arguments) } else { nil }

        // Calls a nested agent makes inside this tool are journaled under this
        // scope, so this call's own entry replaces them once it finishes.
        let journalScope = WorkflowDurableApprovalGate.childScope(for: call)
        let startTime = clock.nowNanoseconds()
        do {
            let output = try await WorkflowDurableApprovalGate.$scope.withValue(journalScope) {
                try await registry.execute(
                    toolNamed: toolName,
                    arguments: arguments,
                    agent: agent,
                    context: context,
                    observer: observer
                )
            }

            let measured = elapsedDuration(since: startTime)
            let result = ToolResult.success(callId: call.id, output: output, duration: measured)
            _ = resultBuilder.addToolResult(result)
            await WorkflowDurableApprovalGate.record(call: call, outcome: .success(output), ownScope: journalScope)

            if let tracing, let spanId {
                await tracing.traceToolResult(spanId: spanId, name: toolName, result: output.description, duration: measured)
            }

            await observer?.onToolEnd(
                context: context,
                agent: agent,
                invocation: ToolInvocation(call: call, duration: measured, outcome: .success(output))
            )

            return Outcome(call: call, result: result, caughtError: nil)
        } catch let pause as WorkflowToolApprovalRequest {
            // A nested agent (agent-as-tool) paused for durable approval; the
            // pause belongs to the workflow, not to this tool's result. Surface
            // the nested request and close this call without a failure so start
            // and end events stay paired. This call is not journaled, so it
            // gives back its approval for the replay.
            if consumedApproval {
                await WorkflowDurableApprovalGate.restore(call: call)
            }
            await closePausedCall(
                call,
                pause: pause,
                spanId: spanId,
                startTime: startTime,
                agent: agent,
                context: context,
                observer: observer,
                tracing: tracing
            )
            throw pause
        } catch {
            let measured = elapsedDuration(since: startTime)
            let errorMessage = (error as? AgentError)?.localizedDescription ?? error.localizedDescription

            let result = ToolResult.failure(callId: call.id, error: errorMessage, duration: measured)
            _ = resultBuilder.addToolResult(result)
            if error is CancellationError || Task.isCancelled {
                // Not journaled, so the approval stays available to the replay.
                if consumedApproval {
                    await WorkflowDurableApprovalGate.restore(call: call)
                }
            } else {
                await WorkflowDurableApprovalGate.record(
                    call: call,
                    outcome: .failure(errorMessage),
                    ownScope: journalScope
                )
            }

            if let tracing, let spanId {
                await tracing.traceToolError(spanId: spanId, name: toolName, error: error)
            }

            await observer?.onToolEnd(
                context: context,
                agent: agent,
                invocation: ToolInvocation(
                    call: call,
                    duration: measured,
                    outcome: .failure(message: errorMessage)
                )
            )

            if stopOnToolError {
                throw ToolFailureCause.wrapped(toolName: toolName, error: error)
            }

            return Outcome(call: call, result: result, caughtError: error)
        }
    }

    /// Builds the outcome of a call whose result a durable replay recorded earlier.
    ///
    /// The call and result go into the step's ``AgentResult``; observers and
    /// tracing are not notified again, since they saw the original execution.
    private func replayedOutcome(
        call: ToolCall,
        recorded: WorkflowJournaledOutcome,
        resultBuilder: AgentResult.Builder,
        stopOnToolError: Bool
    ) throws -> Outcome {
        _ = resultBuilder.addToolCall(call)
        switch recorded {
        case .success(let output):
            let result = ToolResult.success(callId: call.id, output: output, duration: .zero)
            _ = resultBuilder.addToolResult(result)
            return Outcome(call: call, result: result, caughtError: nil, replayed: true)
        case .failure(let message):
            let result = ToolResult.failure(callId: call.id, error: message, duration: .zero)
            _ = resultBuilder.addToolResult(result)
            let error = AgentError.toolFailure(toolName: call.toolName, message: message, cause: nil)
            if stopOnToolError {
                throw error
            }
            return Outcome(call: call, result: result, caughtError: error, replayed: true)
        }
    }

    /// Registry execution + duration + ``ToolExecutionResult`` mapping for the public façade.
    ///
    /// Always records through ``execute`` with `stopOnToolError: false` so duration
    /// stays on ``Outcome``. Fail-fast rethrows the original tool error; continue-on-error
    /// stores that same instance on ``ToolExecutionResult``.
    func executeMapped(
        call: ToolCall,
        registry: ToolRegistry,
        agent: any AgentRuntime,
        context: AgentContext?,
        stopOnToolError: Bool
    ) async throws -> ToolExecutionResult {
        let outcome = try await execute(
            toolName: call.toolName,
            arguments: call.arguments,
            providerCallId: call.providerCallId,
            registry: registry,
            agent: agent,
            context: context,
            resultBuilder: AgentResult.Builder(),
            observer: nil,
            tracing: nil,
            stopOnToolError: false
        )
        if stopOnToolError, let error = outcome.caughtError {
            throw error
        }
        return ToolExecutionResult.from(
            call: call,
            result: outcome.result,
            underlyingError: outcome.caughtError
        )
    }

    /// Executes registry-backed calls using ``ToolBatchPlan``.
    ///
    /// Concurrent groups overlap via `withThrowingTaskGroup`. Returned outcomes
    /// stay in input order. Each call uses ``execute`` (live builder, observer,
    /// tracing). `stopOnToolError` rethrows the original tool error after
    /// recording, matching ``executeMapped``.
    ///
    /// Concurrent groups are only formed when `allowConcurrent` is true **and**
    /// the tool's ``ToolExecutionSemantics/runtimePolicy()`` allows overlap.
    /// Missing tools are treated as parallel-eligible so they fail inside
    /// ``execute`` rather than forcing a serial split. Isolated builders record
    /// each overlapping call; results are merged onto `resultBuilder` in input
    /// order. Observer and tracing callbacks for a concurrent group follow
    /// completion order.
    func executeBatch(
        _ calls: [some ToolCallGoal],
        registry: ToolRegistry,
        agent: any AgentRuntime,
        context: AgentContext?,
        resultBuilder: AgentResult.Builder,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        stopOnToolError: Bool,
        allowConcurrent: Bool
    ) async throws -> [Outcome] {
        guard !calls.isEmpty else {
            return []
        }

        var eligibility: [Bool] = []
        eligibility.reserveCapacity(calls.count)
        for call in calls {
            let tool = await registry.tool(named: call.toolName)
            let mayOverlap = tool?.executionSemantics.runtimePolicy().mayRunInParallel ?? true
            eligibility.append(allowConcurrent && mayOverlap)
        }

        var outcomes = [Outcome?](repeating: nil, count: calls.count)
        for group in ToolBatchPlan.groups(eligibility: eligibility) {
            switch group {
            case let .serial(index):
                try Task.checkCancellation()
                let outcome = try await execute(
                    calls[index],
                    registry: registry,
                    agent: agent,
                    context: context,
                    resultBuilder: resultBuilder,
                    observer: observer,
                    tracing: tracing,
                    stopOnToolError: false
                )
                outcomes[index] = outcome
                if stopOnToolError, let error = outcome.caughtError {
                    throw error
                }

            case let .concurrent(range):
                try await withThrowingTaskGroup(of: (Int, Outcome).self) { taskGroup in
                    for index in range {
                        let goal = calls[index]
                        taskGroup.addTask {
                            let isolatedBuilder = AgentResult.Builder()
                            let outcome = try await self.execute(
                                goal,
                                registry: registry,
                                agent: agent,
                                context: context,
                                resultBuilder: isolatedBuilder,
                                observer: observer,
                                tracing: tracing,
                                stopOnToolError: false
                            )
                            if stopOnToolError, let error = outcome.caughtError {
                                throw error
                            }
                            return (index, outcome)
                        }
                    }

                    var collected: [(Int, Outcome)] = []
                    collected.reserveCapacity(range.count)
                    for try await item in taskGroup {
                        try Task.checkCancellation()
                        collected.append(item)
                    }
                    collected.sort { $0.0 < $1.0 }
                    for (index, outcome) in collected {
                        _ = resultBuilder.addToolCall(outcome.call)
                        _ = resultBuilder.addToolResult(outcome.result)
                        outcomes[index] = outcome
                    }
                }
            }
        }

        return try Self.collectOutcomes(outcomes)
    }

    /// Orders batch outcomes, throwing when an outcome is missing.
    ///
    /// `ToolBatchPlan.groups(eligibility:)` partitions every input index into
    /// exactly one group, so a `nil` slot is unreachable unless batch planning
    /// regresses. It throws ``AgentError/internalError(reason:)`` instead of
    /// trapping so a planning bug surfaces as a catchable failure.
    static func collectOutcomes(_ outcomes: [Outcome?]) throws -> [Outcome] {
        var collected: [Outcome] = []
        collected.reserveCapacity(outcomes.count)
        for (index, outcome) in outcomes.enumerated() {
            guard let outcome else {
                throw AgentError.internalError(
                    reason: "ToolExecutionEngine.executeBatch missing outcome at index \(index)"
                )
            }
            collected.append(outcome)
        }
        return collected
    }

    /// Ends a started call whose tool body paused for a nested durable approval.
    ///
    /// Forwards the nested approval request (agent-as-tool runs its inner agent
    /// without an observer), then closes the span and emits a non-failure
    /// ``AgentObserver/onToolEnd(context:agent:invocation:)`` carrying a
    /// paused marker, so consumers that pair start and end events do not show
    /// the call as running forever.
    private func closePausedCall(
        _ call: ToolCall,
        pause: WorkflowToolApprovalRequest,
        spanId: UUID?,
        startTime: UInt64,
        agent: any AgentRuntime,
        context: AgentContext?,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?
    ) async {
        let measured = elapsedDuration(since: startTime)
        let marker = "paused: awaiting approval for \(pause.toolName)"
        await observer?.onToolApprovalRequested(
            context: context,
            agent: agent,
            call: ToolCall(toolName: pause.toolName, arguments: pause.arguments)
        )
        if let tracing, let spanId {
            await tracing.traceToolResult(spanId: spanId, name: call.toolName, result: marker, duration: measured)
        }
        await observer?.onToolEnd(
            context: context,
            agent: agent,
            invocation: ToolInvocation(call: call, duration: measured, outcome: .success(.string(marker)))
        )
    }

    private func elapsedDuration(since startNanoseconds: UInt64) -> Duration {
        let now = clock.nowNanoseconds()
        let elapsed = now >= startNanoseconds ? now - startNanoseconds : 0
        return Duration(swarmNanoseconds: elapsed)
    }
}
