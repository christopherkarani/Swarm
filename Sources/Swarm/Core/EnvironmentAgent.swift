// EnvironmentAgent.swift
// Swarm Framework
//
// LegacyAgent wrapper that applies task-local AgentEnvironment values.

import Foundation

/// Wraps an `AgentRuntime` and runs it with modified `AgentEnvironment` values.
public struct EnvironmentAgent: AgentRuntime, Sendable {
    private let base: any AgentRuntime
    private let modify: @Sendable (inout AgentEnvironment) -> Void

    public init(
        base: any AgentRuntime,
        modify: @escaping @Sendable (inout AgentEnvironment) -> Void
    ) {
        self.base = base
        self.modify = modify
    }

    // MARK: - AgentRuntime (forwarded)

    public var tools: [any AnyJSONTool] { base.tools }
    public var instructions: String { base.instructions }
    public var configuration: AgentConfiguration { base.configuration }
    public var memory: (any Memory)? { base.memory }
    public var inferenceProvider: (any InferenceProvider)? { base.inferenceProvider }
    public var tracer: (any Tracer)? { base.tracer }
    public var inputGuardrails: [any InputGuardrail] { base.inputGuardrails }
    public var outputGuardrails: [any OutputGuardrail] { base.outputGuardrails }
    public var handoffs: [AnyHandoffConfiguration] { base.handoffs }

    public func run(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) async throws -> AgentResult {
        var env = AgentEnvironmentValues.current
        modify(&env)

        return try await AgentEnvironmentValues.$current.withValue(env) {
            try await base.run(input, session: session, observer: observer)
        }
    }

    public nonisolated func stream(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            try await AgentEnvironmentValues.$current.withValue(envForStream()) {
                for try await event in base.stream(input, session: session, observer: observer) {
                    continuation.yield(event)
                }
            }
            continuation.finish()
        }
    }

    public func cancel() async {
        await base.cancel()
    }

    public func handleHandoff(
        _ request: HandoffRequest,
        context: AgentContext,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) async throws -> AgentResult {
        var env = AgentEnvironmentValues.current
        modify(&env)

        return try await AgentEnvironmentValues.$current.withValue(env) {
            try await base.handleHandoff(request, context: context, session: session, observer: observer)
        }
    }

    // MARK: - Private

    private func envForStream() -> AgentEnvironment {
        var env = AgentEnvironmentValues.current
        modify(&env)
        return env
    }
}

private struct SendableWritableKeyPath<Root, Value>: @unchecked Sendable {
    let keyPath: WritableKeyPath<Root, Value>

    init(_ keyPath: WritableKeyPath<Root, Value>) {
        self.keyPath = keyPath
    }
}

// MARK: - Modifiers

public extension AgentRuntime {
    /// Applies an environment value for the duration of this agent's execution.
    func environment<V: Sendable>(
        _ keyPath: WritableKeyPath<AgentEnvironment, V>,
        _ value: V
    ) -> EnvironmentAgent {
        let sendableKeyPath = SendableWritableKeyPath(keyPath)
        return EnvironmentAgent(base: self) { env in
            env[keyPath: sendableKeyPath.keyPath] = value
        }
    }

    /// Applies a memory implementation via the environment for the duration of execution.
    func memory(_ memory: any Memory) -> EnvironmentAgent {
        environment(\.memory, memory)
    }

    /// Applies a prompt token counter via the environment for the duration of execution.
    func promptTokenCounter(_ counter: any PromptTokenCounter) -> EnvironmentAgent {
        environment(\.promptTokenCounter, counter)
    }

    /// Applies a web-search configuration via the environment for the duration of execution.
    func webSearch(_ configuration: WebSearchTool.Configuration) -> EnvironmentAgent {
        environment(\.webSearch, configuration)
    }
}
