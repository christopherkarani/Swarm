// Agent+Builder.swift
// Swarm Framework
//
// Convenience initializers for Agent construction.

import Foundation

// MARK: Agent.Builder Compatibility

public extension Agent {
    /// Deprecated fluent compatibility builder for creating ``Agent`` values.
    ///
    /// Use an ``Agent`` initializer or ``Agent/withTools(_:)`` for new code.
    /// This compatibility surface remains available through the 0.7 boundary.
    @available(*, deprecated, message: "Use an Agent initializer or withTools(_:). Agent.Builder compatibility will be removed in 0.7.0.")
    struct Builder: Sendable {
        /// Creates an empty compatibility builder.
        public init() {}

        /// Sets the tools used by the agent.
        @discardableResult
        @available(*, deprecated, message: "Use typed Tool values or an Agent initializer.")
        public func tools(_ tools: [any AnyJSONTool]) -> Builder {
            var copy = self
            copy._tools = tools
            return copy
        }

        /// Sets the typed tools used by the agent.
        @discardableResult
        public func tools(_ tools: [some Tool]) -> Builder {
            var copy = self
            copy._tools = tools.map { AnyJSONToolAdapter($0) }
            return copy
        }

        /// Adds a JSON tool to the agent.
        @discardableResult
        @available(*, deprecated, message: "Use a typed Tool value or an Agent initializer.")
        public func addTool(_ tool: some AnyJSONTool) -> Builder {
            var copy = self
            copy._tools.append(tool)
            return copy
        }

        /// Adds an existential JSON tool to the agent.
        @discardableResult
        @available(*, deprecated, message: "Use a typed Tool value or an Agent initializer.")
        public func addTool(_ tool: any AnyJSONTool) -> Builder {
            var copy = self
            copy._tools.append(tool)
            return copy
        }

        /// Adds a typed tool to the agent.
        @discardableResult
        public func addTool(_ tool: some Tool) -> Builder {
            var copy = self
            copy._tools.append(AnyJSONToolAdapter(tool))
            return copy
        }

        /// Adds all built-in tools to the agent.
        @discardableResult
        public func withBuiltInTools() -> Builder {
            var copy = self
            copy._tools.append(contentsOf: BuiltInTools.all)
            return copy
        }

        /// Sets the agent instructions.
        @discardableResult
        public func instructions(_ instructions: String) -> Builder {
            var copy = self
            copy._instructions = instructions
            return copy
        }

        /// Sets the agent configuration.
        @discardableResult
        public func configuration(_ configuration: AgentConfiguration) -> Builder {
            var copy = self
            copy._configuration = configuration
            return copy
        }

        /// Sets the agent memory system.
        @discardableResult
        public func memory(_ memory: any Memory) -> Builder {
            var copy = self
            copy._memory = memory
            return copy
        }

        /// Sets the inference provider.
        @discardableResult
        public func inferenceProvider(_ provider: any InferenceProvider) -> Builder {
            var copy = self
            copy._inferenceProvider = provider
            return copy
        }

        /// Sets the tracer.
        @discardableResult
        public func tracer(_ tracer: any Tracer) -> Builder {
            var copy = self
            copy._tracer = tracer
            return copy
        }

        /// Sets the input guardrails.
        @discardableResult
        public func inputGuardrails(_ guardrails: [any InputGuardrail]) -> Builder {
            var copy = self
            copy._inputGuardrails = guardrails
            return copy
        }

        /// Adds an input guardrail.
        @discardableResult
        public func addInputGuardrail(_ guardrail: any InputGuardrail) -> Builder {
            var copy = self
            copy._inputGuardrails.append(guardrail)
            return copy
        }

        /// Sets the output guardrails.
        @discardableResult
        public func outputGuardrails(_ guardrails: [any OutputGuardrail]) -> Builder {
            var copy = self
            copy._outputGuardrails = guardrails
            return copy
        }

        /// Adds an output guardrail.
        @discardableResult
        public func addOutputGuardrail(_ guardrail: any OutputGuardrail) -> Builder {
            var copy = self
            copy._outputGuardrails.append(guardrail)
            return copy
        }

        /// Sets the guardrail runner configuration.
        @discardableResult
        public func guardrailRunnerConfiguration(_ configuration: GuardrailRunnerConfiguration) -> Builder {
            var copy = self
            copy._guardrailRunnerConfiguration = configuration
            return copy
        }

        /// Sets the handoff configurations.
        @discardableResult
        public func handoffs(_ handoffs: [AnyHandoffConfiguration]) -> Builder {
            var copy = self
            copy._handoffs = handoffs
            return copy
        }

        /// Adds a handoff configuration.
        @discardableResult
        public func addHandoff(_ handoff: AnyHandoffConfiguration) -> Builder {
            var copy = self
            copy._handoffs.append(handoff)
            return copy
        }

        /// Adds a handoff target with typed options.
        @discardableResult
        public func handoff<Target: AgentRuntime>(
            to target: Target,
            configure: (HandoffOptions<Target>) -> HandoffOptions<Target> = { $0 }
        ) -> Builder {
            var copy = self
            copy._handoffs.append(configure(HandoffOptions()).erasedConfiguration(for: target))
            return copy
        }

        /// Adds multiple handoff targets.
        @discardableResult
        public func handoffs<each Target: AgentRuntime>(_ targets: repeat each Target) -> Builder {
            var copy = self
            repeat copy._handoffs.append(AnyHandoffConfiguration(targetAgent: each targets))
            return copy
        }

        /// Builds an agent from the configured compatibility values.
        ///
        /// - Throws: `ToolRegistryError.duplicateToolName` if duplicate tool names are provided.
        public func build() throws -> Agent {
            try Agent(
                tools: _tools,
                instructions: _instructions,
                configuration: _configuration,
                memory: _memory,
                inferenceProvider: _inferenceProvider,
                tracer: _tracer,
                inputGuardrails: _inputGuardrails,
                outputGuardrails: _outputGuardrails,
                guardrailRunnerConfiguration: _guardrailRunnerConfiguration,
                handoffs: _handoffs
            )
        }

        private var _tools: [any AnyJSONTool] = []
        private var _instructions = ""
        private var _configuration: AgentConfiguration = .default
        private var _memory: (any Memory)?
        private var _inferenceProvider: (any InferenceProvider)?
        private var _tracer: (any Tracer)?
        private var _inputGuardrails: [any InputGuardrail] = []
        private var _outputGuardrails: [any OutputGuardrail] = []
        private var _guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default
        private var _handoffs: [AnyHandoffConfiguration] = []
    }
}

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
