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

    /// Live executors Agent copies for the run so an InferenceProvider can
    /// execute a provider-owned tool loop and return a finished turn.
    var providerOwnedToolLoop: ProviderOwnedToolLoop?

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
        self.providerOwnedToolLoop = nil
    }
}

/// Executors and mode for a provider-owned tool loop.
///
/// Agent copies this onto ``AgentEnvironment`` for the duration of a run.
/// ``FoundationModelsInferenceProvider`` reads it from the task-local
/// environment. Non-FM providers ignore it.
struct ProviderOwnedToolLoop: Sendable {
    var executionMode: FoundationModelsExecutionMode
    var toolRegistry: ToolRegistry
    var agent: any AgentRuntime
    var context: AgentContext?
    var observer: (any AgentObserver)?
    var tracing: TracingHelper?
    var resultBuilder: AgentResult.Builder
    var stopOnToolError: Bool
    var conversationID: String
    var enableStreaming: Bool
    let transcript = ProviderOwnedTurnTranscript()

    /// Whether the adapter should execute tools and return a finished turn.
    static func shouldRun(mode: FoundationModelsExecutionMode, appleAvailable: Bool) -> Bool {
        mode == .nativeSession && appleAvailable
    }
}

/// Transcript produced by a provider-owned tool loop for Agent to persist.
actor ProviderOwnedTurnTranscript {
    private var messages: [MemoryMessage] = []

    func store(_ messages: [MemoryMessage]) {
        self.messages = messages
    }

    func snapshot() -> [MemoryMessage] {
        messages
    }
}

/// Task-local access to the current `AgentEnvironment`.
///
/// Callers should generally prefer using the `.environment(...)` modifier on `AgentRuntime`
/// (see `EnvironmentAgent`) instead of interacting with `TaskLocal` directly.
public enum AgentEnvironmentValues {
    @TaskLocal public static var current = AgentEnvironment()
}
