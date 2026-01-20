// ReActAgent.swift
// SwiftAgents Framework
//
// ReAct (Reasoning + Acting) agent implementation.
// Implements the ReAct paradigm for interleaved reasoning and action.

import Foundation
import Logging

// MARK: - ReActAgent

/// A ReAct (Reasoning + Acting) agent that uses interleaved reasoning and action steps.
///
/// The ReAct paradigm follows a Thought-Action-Observation loop:
/// 1. **Thought**: The agent reasons about the current state and what to do next.
/// 2. **Action**: The agent decides to call a tool or provide a final answer.
/// 3. **Observation**: The result of the tool call is observed and added to context.
///
/// This loop continues until the agent decides to provide a final answer or
/// reaches the maximum iteration limit.
///
/// Example:
/// ```swift
/// let agent = ReActAgent(
///     tools: [CalculatorTool(), DateTimeTool()],
///     instructions: "You are a helpful assistant that can perform calculations."
/// )
///
/// let result = try await agent.run("What's 15% of 200?")
/// print(result.output)  // "30"
/// ```
public actor ReActAgent: Agent {
    // MARK: Public

    // MARK: - Agent Protocol Properties

    nonisolated public let tools: [any AnyJSONTool]
    nonisolated public let instructions: String
    nonisolated public let configuration: AgentConfiguration
    nonisolated public let memory: (any Memory)?
    nonisolated public let inferenceProvider: (any InferenceProvider)?
    nonisolated public let tracer: (any Tracer)?
    nonisolated public let inputGuardrails: [any InputGuardrail]
    nonisolated public let outputGuardrails: [any OutputGuardrail]
    nonisolated public let guardrailRunnerConfiguration: GuardrailRunnerConfiguration

    /// Configured handoffs for this agent.
    nonisolated public var handoffs: [AnyHandoffConfiguration] { _handoffs }

    // MARK: - Initialization

    /// Creates a new ReActAgent.
    /// - Parameters:
    ///   - tools: Tools available to the agent. Default: []
    ///   - instructions: System instructions defining agent behavior. Default: ""
    ///   - configuration: Agent configuration settings. Default: .default
    ///   - memory: Optional memory system. Default: nil
    ///   - inferenceProvider: Optional custom inference provider. Default: nil
    ///   - tracer: Optional tracer for observability. Default: nil
    ///   - inputGuardrails: Input validation guardrails. Default: []
    ///   - outputGuardrails: Output validation guardrails. Default: []
    ///   - guardrailRunnerConfiguration: Configuration for guardrail runner. Default: .default
    ///   - handoffs: Handoff configurations for multi-agent orchestration. Default: []
    public init(
        tools: [any AnyJSONTool] = [],
        instructions: String = "",
        configuration: AgentConfiguration = .default,
        memory: (any Memory)? = nil,
        inferenceProvider: (any InferenceProvider)? = nil,
        tracer: (any Tracer)? = nil,
        inputGuardrails: [any InputGuardrail] = [],
        outputGuardrails: [any OutputGuardrail] = [],
        guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default,
        handoffs: [AnyHandoffConfiguration] = []
    ) {
        self.tools = tools
        self.instructions = instructions
        self.configuration = configuration
        self.memory = memory
        self.inferenceProvider = inferenceProvider
        self.tracer = tracer
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
        self.guardrailRunnerConfiguration = guardrailRunnerConfiguration
        _handoffs = handoffs
        toolRegistry = ToolRegistry(tools: tools)
    }

    // MARK: - Agent Protocol Methods

    /// Executes the agent with the given input and returns a result.
    /// - Parameters:
    ///   - input: The user's input/query.
    ///   - session: Optional session for conversation history management.
    ///   - hooks: Optional hooks for observing agent execution events.
    /// - Returns: The result of the agent's execution.
    /// - Throws: `AgentError` if execution fails, or `GuardrailError` if guardrails trigger.
    public func run(_ input: String, session: (any Session)? = nil, hooks: (any RunHooks)? = nil) async throws -> AgentResult {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.invalidInput(reason: "Input cannot be empty")
        }

        let tracing = TracingHelper(
            tracer: tracer,
            agentName: configuration.name.isEmpty ? "ReActAgent" : configuration.name
        )
        await tracing.traceStart(input: input)
        Log.agents.info("Agent started with input: \(input)")

        // Notify hooks of agent start
        await hooks?.onAgentStart(context: nil, agent: self, input: input)

        do {
            // Run input guardrails (with hooks for event emission)
            let runner = GuardrailRunner(configuration: guardrailRunnerConfiguration, hooks: hooks)
            _ = try await runner.runInputGuardrails(inputGuardrails, input: input, context: nil)

            isCancelled = false
            let resultBuilder = AgentResult.Builder()
            _ = resultBuilder.start()

            // Load conversation history from session (limit to recent messages)
            var sessionHistory: [MemoryMessage] = []
            if let session {
                sessionHistory = try await session.getItems(limit: configuration.sessionHistoryLimit)
            }

            // Create user message for this turn
            let userMessage = MemoryMessage.user(input)

            // Store in memory (for AI context) if available
            if let mem = memory {
                // Add session history to memory
                for msg in sessionHistory {
                    await mem.add(msg)
                }
                await mem.add(userMessage)
            }

            // Execute the ReAct loop with session context
            let output = try await executeReActLoop(
                input: input,
                sessionHistory: sessionHistory,
                resultBuilder: resultBuilder,
                hooks: hooks,
                tracing: tracing
            )

            _ = resultBuilder.setOutput(output)

            // Run output guardrails BEFORE storing in memory/session
            _ = try await runner.runOutputGuardrails(outputGuardrails, output: output, agent: self, context: nil)

            // Store turn in session (user + assistant messages)
            if let session {
                let assistantMessage = MemoryMessage.assistant(output)
                try await session.addItems([userMessage, assistantMessage])
            }

            // Only store output in memory if validation passed
            if let mem = memory {
                await mem.add(.assistant(output))
            }

            let result = resultBuilder.build()
            await tracing.traceComplete(result: result)
            Log.agents.info("Agent completed in \(result.duration)s")
            await hooks?.onAgentEnd(context: nil, agent: self, result: result)
            return result
        } catch {
            Log.agents.error("Agent execution failed: \(error.localizedDescription)")
            await hooks?.onError(context: nil, agent: self, error: error)
            await tracing.traceError(error)
            throw error
        }
    }

    /// Streams the agent's execution, yielding events as they occur.
    /// - Parameters:
    ///   - input: The user's input/query.
    ///   - session: Optional session for conversation history management.
    ///   - hooks: Optional hooks for observing agent execution events.
    /// - Returns: An async stream of agent events.
    nonisolated public func stream(_ input: String, session: (any Session)? = nil, hooks: (any RunHooks)? = nil) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream(for: self) { agent, continuation in
            // Create event bridge hooks
            let streamHooks = EventStreamHooks(continuation: continuation)

            // Combine with user-provided hooks
            let combinedHooks: any RunHooks
            if let userHooks = hooks {
                combinedHooks = CompositeRunHooks(hooks: [userHooks, streamHooks])
            } else {
                combinedHooks = streamHooks
            }

            do {
                _ = try await agent.run(input, session: session, hooks: combinedHooks)
                continuation.finish()
            } catch {
                // Error is handled by EventStreamHooks.onError
                continuation.finish(throwing: error)
            }
        }
    }

    /// Cancels any ongoing execution.
    public func cancel() async {
        Log.agents.info("Agent execution cancelled")
        isCancelled = true
    }

    // MARK: Private

    private let _handoffs: [AnyHandoffConfiguration]

    // MARK: - Internal State

    private var isCancelled: Bool = false
    private let toolRegistry: ToolRegistry

    // MARK: - ReAct Loop Implementation

    private func executeReActLoop(
        input: String,
        sessionHistory: [MemoryMessage] = [],
        resultBuilder: AgentResult.Builder,
        hooks: (any RunHooks)? = nil,
        tracing: TracingHelper? = nil
    ) async throws -> String {
        var iteration = 0
        var scratchpad = "" // Accumulates Thought-Action-Observation history
        let startTime = ContinuousClock.now
        let toolDefinitions = tools.map(\.definition)

        // Retrieve relevant context from memory once at the start
        // This enables RAG-style retrieval for VectorMemory or summarization for SummaryMemory
        var memoryContext = ""
        if let mem = memory {
            // Use a reasonable token limit for context (configurable via maxTokens or default)
            let tokenLimit = configuration.maxTokens ?? 2000
            memoryContext = await mem.context(for: input, tokenLimit: tokenLimit)
        }

        while iteration < configuration.maxIterations {
            // Check for cancellation
            try Task.checkCancellation()
            if isCancelled {
                throw AgentError.cancelled
            }

            // Check timeout
            let elapsed = ContinuousClock.now - startTime
            if elapsed > configuration.timeout {
                throw AgentError.timeout(duration: configuration.timeout)
            }

            iteration += 1
            _ = resultBuilder.incrementIteration()
            await hooks?.onIterationStart(context: nil, agent: self, number: iteration)

            // Step 1: Build prompt with current context (including memory context)
            let prompt = buildPrompt(
                input: input,
                sessionHistory: sessionHistory,
                scratchpad: scratchpad,
                iteration: iteration,
                memoryContext: memoryContext
            )

            // Step 2: Generate response from model
            await hooks?.onLLMStart(context: nil, agent: self, systemPrompt: instructions, inputMessages: [MemoryMessage.user(prompt)])
            let inference = try await generateResponse(prompt: prompt, tools: toolDefinitions)
            let modelText = inference.content ?? ""
            let llmResponseForHooks = modelText.isEmpty
                ? inference.toolCalls.map { "Calling tool: \($0.name)" }.joined(separator: ", ")
                : modelText
            await hooks?.onLLMEnd(context: nil, agent: self, response: llmResponseForHooks, usage: inference.usage)

            // Emit thinking event if a thought block is present in the response
            if let thoughtRange = modelText.range(of: "Thought:", options: .caseInsensitive) {
                var thought = String(modelText[thoughtRange.upperBound...])
                if let nextMarker = thought.range(of: "Action:", options: .caseInsensitive) {
                    thought = String(thought[..<nextMarker.lowerBound])
                } else if let nextMarker = thought.range(of: "Final Answer:", options: .caseInsensitive) {
                    thought = String(thought[..<nextMarker.lowerBound])
                }
                let cleanThought = thought.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanThought.isEmpty {
                    if let tracing { await tracing.traceThought(cleanThought) }
                    await hooks?.onThinking(context: nil, agent: self, thought: cleanThought)
                }
            }

            if !inference.toolCalls.isEmpty {
                // Native tool calls - execute them and continue.
                scratchpad = try await handleToolCalls(
                    calls: inference.toolCalls,
                    scratchpad: scratchpad,
                    resultBuilder: resultBuilder,
                    hooks: hooks,
                    tracing: tracing
                )
            } else {
                // Step 3: Parse the response (text-based ReAct fallback)
                let parsed = parseResponse(modelText)

                switch parsed {
                case let .finalAnswer(answer):
                    // Agent has decided on a final answer
                    return answer

                case let .toolCall(call):
                    // Agent wants to call a tool - delegate to helper method
                    scratchpad = try await handleToolCall(
                        call: call,
                        scratchpad: scratchpad,
                        resultBuilder: resultBuilder,
                        hooks: hooks,
                        tracing: tracing
                    )

                case let .thinking(thought):
                    // Agent is just thinking, continue
                    scratchpad += "\nThought: \(thought)"

                case let .invalid(raw):
                    // Couldn't parse response, treat as thinking
                    scratchpad += "\nThought: \(raw)"
                }
            }

            await hooks?.onIterationEnd(context: nil, agent: self, number: iteration)
        }

        // Exceeded max iterations
        throw AgentError.maxIterationsExceeded(iterations: iteration)
    }

    // MARK: - Tool Call Handling

    /// Handles a tool call during the ReAct loop.
    /// - Parameters:
    ///   - toolName: The name of the tool to execute.
    ///   - arguments: The arguments for the tool call.
    ///   - scratchpad: The current scratchpad content.
    ///   - resultBuilder: The result builder to record tool calls and results.
    ///   - hooks: Optional hooks for lifecycle callbacks.
    /// - Returns: The updated scratchpad with the tool result.
    /// - Throws: `AgentError.toolExecutionFailed` if the tool fails and `stopOnToolError` is enabled.
    private func handleToolCall(
        call: InferenceResponse.ParsedToolCall,
        scratchpad: String,
        resultBuilder: AgentResult.Builder,
        hooks: (any RunHooks)?,
        tracing: TracingHelper?
    ) async throws -> String {
        var updatedScratchpad = scratchpad
        let engine = ToolExecutionEngine()
        let outcome = try await engine.execute(
            call,
            registry: toolRegistry,
            agent: self,
            context: nil,
            resultBuilder: resultBuilder,
            hooks: hooks,
            tracing: tracing,
            stopOnToolError: false
        )

        if outcome.result.isSuccess {
            updatedScratchpad += """

            Thought: I need to use the \(call.name) tool.
            Action: \(call.name)(\(formatArguments(call.arguments)))
            Observation: \(outcome.result.output.description)
            """
        } else {
            let errorMessage = outcome.result.errorMessage ?? "Unknown error"
            updatedScratchpad += """

            Thought: I need to use the \(call.name) tool.
            Action: \(call.name)(\(formatArguments(call.arguments)))
            Observation: Error - \(errorMessage)
            """

            if configuration.stopOnToolError {
                throw AgentError.toolExecutionFailed(toolName: call.name, underlyingError: errorMessage)
            }
        }

        return updatedScratchpad
    }

    /// Executes one or more tool calls and appends observations to the scratchpad.
    private func handleToolCalls(
        calls: [InferenceResponse.ParsedToolCall],
        scratchpad: String,
        resultBuilder: AgentResult.Builder,
        hooks: (any RunHooks)?,
        tracing: TracingHelper?
    ) async throws -> String {
        guard !calls.isEmpty else { return scratchpad }

        // If we need fail-fast behavior, execute sequentially.
        if configuration.stopOnToolError || calls.count == 1 || !configuration.parallelToolCalls {
            var updatedScratchpad = scratchpad
            for call in calls {
                updatedScratchpad = try await handleToolCall(
                    call: call,
                    scratchpad: updatedScratchpad,
                    resultBuilder: resultBuilder,
                    hooks: hooks,
                    tracing: tracing
                )
            }
            return updatedScratchpad
        }

        // Parallel execution: execute tool calls concurrently, then append observations in order.
        let engine = ToolExecutionEngine()
        let outcomes = try await withThrowingTaskGroup(of: (Int, ToolExecutionEngine.Outcome).self) { group in
            for (index, call) in calls.enumerated() {
                group.addTask { [toolRegistry, resultBuilder, hooks, tracing] in
                    let outcome = try await engine.execute(
                        call,
                        registry: toolRegistry,
                        agent: self,
                        context: nil,
                        resultBuilder: resultBuilder,
                        hooks: hooks,
                        tracing: tracing,
                        stopOnToolError: false
                    )
                    return (index, outcome)
                }
            }

            var results: [(Int, ToolExecutionEngine.Outcome)] = []
            results.reserveCapacity(calls.count)
            for try await result in group {
                results.append(result)
            }

            results.sort { $0.0 < $1.0 }
            return results.map(\.1)
        }

        var updatedScratchpad = scratchpad
        for (call, outcome) in zip(calls, outcomes) {
            if outcome.result.isSuccess {
                updatedScratchpad += """

                Thought: I need to use the \(call.name) tool.
                Action: \(call.name)(\(formatArguments(call.arguments)))
                Observation: \(outcome.result.output.description)
                """
            } else {
                let errorMessage = outcome.result.errorMessage ?? "Unknown error"
                updatedScratchpad += """

                Thought: I need to use the \(call.name) tool.
                Action: \(call.name)(\(formatArguments(call.arguments)))
                Observation: Error - \(errorMessage)
                """
            }
        }

        return updatedScratchpad
    }

    // MARK: - Prompt Building

    private func buildPrompt(
        input: String,
        sessionHistory: [MemoryMessage] = [],
        scratchpad: String,
        iteration _: Int,
        memoryContext: String = ""
    ) -> String {
        let toolDescriptions = buildToolDescriptions()
        let conversationContext = buildConversationContext(from: sessionHistory)

        // Build memory context section if available
        let memorySection = memoryContext.isEmpty ? "" : """

        Relevant Context from Memory:
        \(memoryContext)
        """

        let basePrompt = """
        \(instructions.isEmpty ? "You are a helpful AI assistant." : instructions)

        You are a ReAct agent that solves problems by interleaving Thought, Action, and Observation steps.

        \(toolDescriptions.isEmpty ? "No tools are available." : "Available Tools:\n\(toolDescriptions)")

        Format your response EXACTLY as follows:
        - To reason: Start with "Thought:" followed by your reasoning about what to do next.
        - To use a tool: Write one of:
          - Action: tool_name(arg1: value1, arg2: value2)
          - Action: {"tool":"tool_name","arguments":{"arg1":value1,"arg2":value2}}
        - To give your final answer: Write "Final Answer:" followed by your complete response to the user.

        Rules:
        1. Always start with a Thought to reason about the problem.
        2. After an Observation, decide if you need another Action or can give the Final Answer.
        3. Only use tools that are available in the list above.
        4. When you have enough information, provide the Final Answer.
        5. Use parameter types shown in the tool list (quote strings; keep numbers/booleans unquoted).
        \(conversationContext.isEmpty ? "" : "\nConversation History:\n\(conversationContext)")\(memorySection)

        User Query: \(input)
        """

        if scratchpad.isEmpty {
            return basePrompt + "\n\nBegin with your first Thought:"
        } else {
            return basePrompt + "\n\nPrevious steps:" + scratchpad + "\n\nContinue with your next step:"
        }
    }

    private func buildConversationContext(from sessionHistory: [MemoryMessage]) -> String {
        guard !sessionHistory.isEmpty else { return "" }

        var lines: [String] = []
        for message in sessionHistory {
            switch message.role {
            case .user:
                lines.append("User: \(message.content)")
            case .assistant:
                lines.append("Assistant: \(message.content)")
            case .system:
                lines.append("System: \(message.content)")
            case .tool:
                lines.append("Tool: \(message.content)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func buildToolDescriptions() -> String {
        var descriptions: [String] = []
        for tool in tools {
            let toolDesc = formatToolDescription(tool)
            descriptions.append(toolDesc)
        }
        return descriptions.joined(separator: "\n\n")
    }

    private func formatToolDescription(_ tool: any AnyJSONTool) -> String {
        let params = formatParameterDescriptions(tool.parameters)
        if params.isEmpty {
            return "- \(tool.name): \(tool.description)"
        } else {
            return "- \(tool.name): \(tool.description)\n  Parameters:\n\(params)"
        }
    }

    private func formatParameterDescriptions(_ parameters: [ToolParameter]) -> String {
        var lines: [String] = []
        for param in parameters {
            let name = param.name
            let desc = param.description
            let required = param.isRequired
            let reqStr = required ? "(required)" : "(optional)"
            let typeStr = param.type.description
            let defaultStr = if let defaultValue = param.defaultValue { " default=\(defaultValue.description)" } else { "" }
            let line = "    - \(name) \(reqStr) (\(typeStr))\(defaultStr): \(desc)"
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Response Generation

    private func generateResponse(prompt: String, tools: [ToolDefinition]) async throws -> InferenceResponse {
        // Use custom inference provider if available
        if let provider = inferenceProvider {
            // Avoid tool-calling APIs when no tools are available.
            // Some providers reject requests with an empty tools array.
            if tools.isEmpty {
                let content = try await provider.generate(prompt: prompt, options: configuration.inferenceOptions)
                return InferenceResponse(content: content, toolCalls: [], finishReason: .completed, usage: nil)
            }

            return try await provider.generateWithToolCalls(
                prompt: prompt,
                tools: tools,
                options: configuration.inferenceOptions
            )
        }

        // Throw an error indicating an inference provider is required
        throw AgentError.inferenceProviderUnavailable(
            reason: "No inference provider configured. Please provide an InferenceProvider."
        )
    }

    private func formatArguments(_ arguments: [String: SendableValue]) -> String {
        arguments.map { "\($0.key): \($0.value.description)" }.joined(separator: ", ")
    }
}

// MARK: ReActAgent.Builder

public extension ReActAgent {
    /// Builder for creating ReActAgent instances with a fluent API.
    /// Uses value semantics (struct) for Swift 6 concurrency safety.
    ///
    /// Example:
    /// ```swift
    /// let agent = ReActAgent.Builder()
    ///     .tools([CalculatorTool()])
    ///     .instructions("You are a math assistant.")
    ///     .configuration(.default.maxIterations(5))
    ///     .build()
    /// ```
    struct Builder: Sendable {
        // MARK: Public

        /// Creates a new builder.
        public init() {
            tools = []
            instructions = ""
            configuration = .default
            memory = nil
            inferenceProvider = nil
            tracer = nil
            inputGuardrails = []
            outputGuardrails = []
        }

        /// Sets the tools.
        /// - Parameter tools: The tools to use.
        /// - Returns: A new builder with the updated tools.
        @discardableResult
        public func tools(_ tools: [any AnyJSONTool]) -> Builder {
            var copy = self
            copy.tools = tools
            return copy
        }

        /// Adds a tool.
        /// - Parameter tool: The tool to add.
        /// - Returns: A new builder with the tool added.
        @discardableResult
        public func addTool(_ tool: any AnyJSONTool) -> Builder {
            var copy = self
            copy.tools.append(tool)
            return copy
        }

        /// Adds built-in tools.
        /// - Returns: A new builder with built-in tools added.
        @discardableResult
        public func withBuiltInTools() -> Builder {
            var copy = self
            copy.tools.append(contentsOf: BuiltInTools.all)
            return copy
        }

        /// Sets the instructions.
        /// - Parameter instructions: The system instructions.
        /// - Returns: A new builder with the updated instructions.
        @discardableResult
        public func instructions(_ instructions: String) -> Builder {
            var copy = self
            copy.instructions = instructions
            return copy
        }

        /// Sets the configuration.
        /// - Parameter configuration: The agent configuration.
        /// - Returns: A new builder with the updated configuration.
        @discardableResult
        public func configuration(_ configuration: AgentConfiguration) -> Builder {
            var copy = self
            copy.configuration = configuration
            return copy
        }

        /// Sets the memory system.
        /// - Parameter memory: The memory to use.
        /// - Returns: A new builder with the updated memory.
        @discardableResult
        public func memory(_ memory: any Memory) -> Builder {
            var copy = self
            copy.memory = memory
            return copy
        }

        /// Sets the inference provider.
        /// - Parameter provider: The provider to use.
        /// - Returns: A new builder with the updated provider.
        @discardableResult
        public func inferenceProvider(_ provider: any InferenceProvider) -> Builder {
            var copy = self
            copy.inferenceProvider = provider
            return copy
        }

        /// Sets the tracer for observability.
        /// - Parameter tracer: The tracer to use.
        /// - Returns: A new builder with the updated tracer.
        @discardableResult
        public func tracer(_ tracer: any Tracer) -> Builder {
            var copy = self
            copy.tracer = tracer
            return copy
        }

        /// Sets the input guardrails.
        /// - Parameter guardrails: The input guardrails to use.
        /// - Returns: A new builder with the updated guardrails.
        @discardableResult
        public func inputGuardrails(_ guardrails: [any InputGuardrail]) -> Builder {
            var copy = self
            copy.inputGuardrails = guardrails
            return copy
        }

        /// Adds an input guardrail.
        /// - Parameter guardrail: The guardrail to add.
        /// - Returns: A new builder with the guardrail added.
        @discardableResult
        public func addInputGuardrail(_ guardrail: any InputGuardrail) -> Builder {
            var copy = self
            copy.inputGuardrails.append(guardrail)
            return copy
        }

        /// Sets the output guardrails.
        /// - Parameter guardrails: The output guardrails to use.
        /// - Returns: A new builder with the updated guardrails.
        @discardableResult
        public func outputGuardrails(_ guardrails: [any OutputGuardrail]) -> Builder {
            var copy = self
            copy.outputGuardrails = guardrails
            return copy
        }

        /// Adds an output guardrail.
        /// - Parameter guardrail: The guardrail to add.
        /// - Returns: A new builder with the guardrail added.
        @discardableResult
        public func addOutputGuardrail(_ guardrail: any OutputGuardrail) -> Builder {
            var copy = self
            copy.outputGuardrails.append(guardrail)
            return copy
        }

        /// Sets the guardrail runner configuration.
        /// - Parameter configuration: The guardrail runner configuration.
        /// - Returns: A new builder with the updated configuration.
        @discardableResult
        public func guardrailRunnerConfiguration(_ configuration: GuardrailRunnerConfiguration) -> Builder {
            var copy = self
            copy.guardrailRunnerConfiguration = configuration
            return copy
        }

        /// Sets the handoff configurations.
        /// - Parameter handoffs: The handoff configurations to use.
        /// - Returns: A new builder with the updated handoffs.
        @discardableResult
        public func handoffs(_ handoffs: [AnyHandoffConfiguration]) -> Builder {
            var copy = self
            copy.handoffs = handoffs
            return copy
        }

        /// Adds a handoff configuration.
        /// - Parameter handoff: The handoff configuration to add.
        /// - Returns: A new builder with the handoff added.
        @discardableResult
        public func addHandoff(_ handoff: AnyHandoffConfiguration) -> Builder {
            var copy = self
            copy.handoffs.append(handoff)
            return copy
        }

        /// Builds the agent.
        /// - Returns: A new ReActAgent instance.
        public func build() -> ReActAgent {
            ReActAgent(
                tools: tools,
                instructions: instructions,
                configuration: configuration,
                memory: memory,
                inferenceProvider: inferenceProvider,
                tracer: tracer,
                inputGuardrails: inputGuardrails,
                outputGuardrails: outputGuardrails,
                guardrailRunnerConfiguration: guardrailRunnerConfiguration,
                handoffs: handoffs
            )
        }

        // MARK: Private

        private var tools: [any AnyJSONTool]
        private var instructions: String
        private var configuration: AgentConfiguration
        private var memory: (any Memory)?
        private var inferenceProvider: (any InferenceProvider)?
        private var tracer: (any Tracer)?
        private var inputGuardrails: [any InputGuardrail]
        private var outputGuardrails: [any OutputGuardrail]
        private var guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default
        private var handoffs: [AnyHandoffConfiguration] = []
    }
}
