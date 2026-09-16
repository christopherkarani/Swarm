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
        _ = resultBuilder.addToolCall(call)

        await observer?.onToolStart(context: context, agent: agent, call: call)

        let spanId: UUID? = if let tracing { await tracing.traceToolCall(name: toolName, arguments: arguments) } else { nil }

        let startTime = clock.nowNanoseconds()
        do {
            let output = try await registry.execute(
                toolNamed: toolName,
                arguments: arguments,
                agent: agent,
                context: context,
                observer: observer
            )

            let measured = elapsedDuration(since: startTime)
            let result = ToolResult.success(callId: call.id, output: output, duration: measured)
            _ = resultBuilder.addToolResult(result)

            if let tracing, let spanId {
                await tracing.traceToolResult(spanId: spanId, name: toolName, result: output.description, duration: measured)
            }

            await observer?.onToolEnd(context: context, agent: agent, result: result)

            return Outcome(call: call, result: result, caughtError: nil)
        } catch {
            let measured = elapsedDuration(since: startTime)
            let errorMessage = (error as? AgentError)?.localizedDescription ?? error.localizedDescription

            let result = ToolResult.failure(callId: call.id, error: errorMessage, duration: measured)
            _ = resultBuilder.addToolResult(result)

            if let tracing, let spanId {
                await tracing.traceToolError(spanId: spanId, name: toolName, error: error)
            }

            await observer?.onToolEnd(context: context, agent: agent, result: result)

            if stopOnToolError {
                throw AgentError.toolFailure(toolName: toolName, message: errorMessage, cause: error)
            }

            return Outcome(call: call, result: result, caughtError: error)
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

        return outcomes.map { outcome in
            guard let outcome else {
                preconditionFailure("ToolExecutionEngine.executeBatch missing outcome")
            }
            return outcome
        }
    }

    private func elapsedDuration(since startNanoseconds: UInt64) -> Duration {
        let now = clock.nowNanoseconds()
        let elapsed = now >= startNanoseconds ? now - startNanoseconds : 0
        return Duration(swarmNanoseconds: elapsed)
    }
}
