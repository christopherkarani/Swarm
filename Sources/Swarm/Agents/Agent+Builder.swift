// Agent+Builder.swift
// Swarm Framework
//
// Convenience initializers for Agent construction.

import Foundation

// MARK: - Convenience Initializers

public extension Agent {
    /// Creates a new Agent with a name as the first parameter.
    ///
    /// This convenience initializer mirrors the OpenAI Agent SDK pattern
    /// where the agent name is a top-level parameter rather than nested
    /// inside configuration.
    ///
    /// Example:
    /// ```swift
    /// let agent = Agent(name: "Triage", instructions: "Route requests", tools: [weatherTool])
    /// ```
    ///
    /// - Parameters:
    ///   - name: The display name of the agent.
    ///   - instructions: System instructions defining agent behavior. Default: ""
    ///   - tools: Tools available to the agent. Default: []
    ///   - inferenceProvider: Optional custom inference provider. Default: nil
    ///   - memory: Optional explicit memory override. Default: ContextCore+Wax `DefaultAgentMemory` when Integrations is enabled; otherwise `SlidingWindowMemory`
    ///   - tracer: Optional tracer for observability. Default: nil
    ///   - configuration: Additional agent configuration settings. Default: .default
    ///   - inputGuardrails: Input validation guardrails. Default: []
    ///   - outputGuardrails: Output validation guardrails. Default: []
    ///   - guardrailRunnerConfiguration: Configuration for guardrail runner. Default: .default
    ///   - handoffs: Handoff configurations for multi-agent orchestration. Default: []
    /// - Throws: `ToolRegistryError.duplicateToolName` if duplicate tool names are provided.
    init(
        name: String,
        instructions: String = "",
        tools: [any AnyJSONTool] = [],
        inferenceProvider: (any InferenceProvider)? = nil,
        memory: (any Memory)? = nil,
        tracer: (any Tracer)? = nil,
        configuration: AgentConfiguration = .default,
        inputGuardrails: [any InputGuardrail] = [],
        outputGuardrails: [any OutputGuardrail] = [],
        guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default,
        handoffs: [AnyHandoffConfiguration] = []
    ) throws {
        var config = configuration
        config.name = name
        try self.init(
            tools: tools,
            instructions: instructions,
            configuration: config,
            memory: memory,
            inferenceProvider: inferenceProvider,
            tracer: tracer,
            inputGuardrails: inputGuardrails,
            outputGuardrails: outputGuardrails,
            guardrailRunnerConfiguration: guardrailRunnerConfiguration,
            handoffs: handoffs
        )
    }
}

// MARK: - Simplified Handoff Declaration

public extension Agent {
    /// Creates an Agent with agents directly as handoff targets.
    ///
    /// This convenience initializer eliminates the need to wrap each agent
    /// in `AnyHandoffConfiguration`, inspired by the OpenAI SDK pattern
    /// where you pass agents directly: `Agent(handoffs=[billing, support])`.
    ///
    /// Example:
    /// ```swift
    /// let triage = Agent(
    ///     name: "Triage",
    ///     instructions: "Route requests",
    ///     handoffAgents: [billingAgent, supportAgent]
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - name: The display name of the agent.
    ///   - instructions: System instructions. Default: ""
    ///   - tools: Tools available to the agent. Default: []
    ///   - inferenceProvider: Optional inference provider. Default: nil
    ///   - memory: Optional explicit memory override. Default: ContextCore+Wax `DefaultAgentMemory` when Integrations is enabled; otherwise `SlidingWindowMemory`
    ///   - tracer: Optional tracer. Default: nil
    ///   - configuration: Additional configuration. Default: .default
    ///   - inputGuardrails: Input guardrails. Default: []
    ///   - outputGuardrails: Output guardrails. Default: []
    ///   - guardrailRunnerConfiguration: Guardrail runner config. Default: .default
    ///   - handoffAgents: Agents to use as handoff targets.
    /// - Throws: `ToolRegistryError.duplicateToolName` if duplicate tool names are provided.
    init(
        name: String,
        instructions: String = "",
        tools: [any AnyJSONTool] = [],
        inferenceProvider: (any InferenceProvider)? = nil,
        memory: (any Memory)? = nil,
        tracer: (any Tracer)? = nil,
        configuration: AgentConfiguration = .default,
        inputGuardrails: [any InputGuardrail] = [],
        outputGuardrails: [any OutputGuardrail] = [],
        guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default,
        handoffAgents: [any AgentRuntime]
    ) throws {
        let handoffs = handoffAgents.map { agent in
            AnyHandoffConfiguration(targetAgent: agent)
        }
        try self.init(
            name: name,
            instructions: instructions,
            tools: tools,
            inferenceProvider: inferenceProvider,
            memory: memory,
            tracer: tracer,
            configuration: configuration,
            inputGuardrails: inputGuardrails,
            outputGuardrails: outputGuardrails,
            guardrailRunnerConfiguration: guardrailRunnerConfiguration,
            handoffs: handoffs
        )
    }
}

// MARK: - V3 Canonical Init with Explicit Provider

public extension Agent {
    /// V3 convenience init with an explicit, non-optional inference provider.
    ///
    /// This overload avoids the optional wrapping when a provider is always known:
    /// ```swift
    /// let agent = try Agent("You are helpful.", provider: .foundationModels()) {
    ///     WeatherTool()
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - instructions: System instructions defining agent behavior.
    ///   - provider: The inference provider to use.
    ///   - tools: A `@ToolBuilder` closure producing the agent's tools. Default: empty.
    /// - Throws: `ToolRegistryError.duplicateToolName` if duplicate tool names are provided.
    init(
        _ instructions: String,
        provider: some InferenceProvider,
        @ToolBuilder tools: () -> ToolCollection = { .empty }
    ) throws {
        try self.init(
            tools: tools().storage,
            instructions: instructions,
            inferenceProvider: provider
        )
    }
}
