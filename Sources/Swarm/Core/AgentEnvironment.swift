// AgentEnvironment.swift
// Swarm Framework
//
// Task-local environment values for declarative agent configuration.

import Foundation

/// Environment values that can be provided implicitly to agents during execution.
///
/// `AgentEnvironment` is modeled after SwiftUI's `EnvironmentValues` pattern: a caller can
/// set environment values once (e.g. an inference provider) and agents that do not have an
/// explicit configuration can fall back to these values.
///
/// Environment values are propagated using `TaskLocal` via `AgentEnvironmentValues.current`.
public struct AgentEnvironment: Sendable {
    public var inferenceProvider: (any InferenceProvider)?
    public var inferenceProviderTransform: (@Sendable (any InferenceProvider) -> any InferenceProvider)?
    public var tracer: (any Tracer)?
    public var memory: (any Memory)?
    public var promptTokenCounter: any PromptTokenCounter
    public var membrane: MembraneEnvironment?
    public var webSearch: WebSearchTool.Configuration?

    public init(
        inferenceProvider: (any InferenceProvider)? = nil,
        inferenceProviderTransform: (@Sendable (any InferenceProvider) -> any InferenceProvider)? = nil,
        tracer: (any Tracer)? = nil,
        memory: (any Memory)? = nil,
        promptTokenCounter: any PromptTokenCounter = EstimatedPromptTokenCounter.shared,
        membrane: MembraneEnvironment? = .enabled,
        webSearch: WebSearchTool.Configuration? = nil
    ) {
        self.inferenceProvider = inferenceProvider
        self.inferenceProviderTransform = inferenceProviderTransform
        self.tracer = tracer
        self.memory = memory
        self.promptTokenCounter = promptTokenCounter
        self.membrane = membrane
        self.webSearch = webSearch
    }
}

/// Synchronous cancel flag shared by the timeout coordinator and tool executor.
final class ProviderOwnedLoopGate: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true

    func deactivate() {
        lock.lock()
        active = false
        lock.unlock()
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }
}

/// Task-local access to the current `AgentEnvironment`.
///
/// Callers should generally prefer using the `.environment(...)` modifier on `AgentRuntime`
/// (see `EnvironmentAgent`) instead of interacting with `TaskLocal` directly.
public enum AgentEnvironmentValues {
    @TaskLocal public static var current = AgentEnvironment()
}
