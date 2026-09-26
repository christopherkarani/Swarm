// Agent+ToolLoop.swift
// Swarm Framework
//
// The tool-calling turn: one deep module behind a narrow seam. Agent builds a
// single AgentTurnRequest per run; the runner owns iteration admission,
// inference, tool execution, transcript, and observer ordering for the turn.

import Foundation

/// Everything one tool-calling turn needs, resolved before the turn starts.
///
/// `Agent` builds this once per run from the run's inputs plus the
/// once-per-turn ``AgentTurnDependencies`` snapshot. The loop reads only from
/// it; loop-carried state lives on ``AgentTurnRunner`` instead.
struct AgentTurnRequest: Sendable {
    let input: String
    let dependencies: AgentTurnDependencies
    let sessionHistory: [MemoryMessage]
    let session: (any Session)?
    let resultBuilder: AgentResult.Builder
    let observer: (any AgentObserver)?
    let tracing: TracingHelper?
    let structuredOutputRequest: StructuredOutputRequest?
    let executionContext: AgentContext
    let executionGate: ProviderOwnedLoopGate?
    let pendingHandoff: OwnedLoopPendingHandoff

    init(
        input: String,
        dependencies: AgentTurnDependencies,
        sessionHistory: [MemoryMessage] = [],
        session: (any Session)?,
        resultBuilder: AgentResult.Builder,
        observer: (any AgentObserver)? = nil,
        tracing: TracingHelper? = nil,
        structuredOutputRequest: StructuredOutputRequest?,
        executionContext: AgentContext,
        executionGate: ProviderOwnedLoopGate?,
        pendingHandoff: OwnedLoopPendingHandoff
    ) {
        self.input = input
        self.dependencies = dependencies
        self.sessionHistory = sessionHistory
        self.session = session
        self.resultBuilder = resultBuilder
        self.observer = observer
        self.tracing = tracing
        self.structuredOutputRequest = structuredOutputRequest
        self.executionContext = executionContext
        self.executionGate = executionGate
        self.pendingHandoff = pendingHandoff
    }
}

/// Owns one tool-calling turn's decide-plus-execute ordering.
///
/// The kernel (``AgentTurnKernel``) makes the pure decisions; the runner
/// executes the effect each decision names and feeds the next action back.
/// Iteration admission, inference dispatch, host-tool execution, handoff
/// transfer, transcript appends, and observer pairing all live here, behind
/// the single ``run()`` seam. Host callbacks (options, resilience, timeout,
/// guardrail-adjacent helpers) stay on the stored `agent` value.
struct AgentTurnRunner: Sendable {
    private typealias ConversationMessage = AgentTurnTranscript.Message

    /// Per-iteration outcome: admit another iteration or finish the turn.
    private enum IterationDecision {
        case continueTurn
        case done(Agent.ToolLoopOutcome)
    }

    // The seam is `init(agent:request:)` plus `run()`. The remaining members
    // are the module's internal seams: they cross the runner's files, so
    // Swift cannot scope them `private`, but no caller outside the turn uses
    // them.
    let agent: Agent
    let request: AgentTurnRequest

    var startTime = ContinuousClock.now
    private var turnState: AgentTurnKernel.TurnState
    private var loopDetector: ToolCallLoopDetector
    private var pendingTurnAction = AgentTurnKernel.TurnAction.startNextIteration
    var turnTranscript = AgentTurnTranscript()
    private var inferenceOptions: InferenceOptions!
    private var systemMessage = ""
    private var enableStreaming = false
    private var useToolStreaming = false

    init(agent: Agent, request: AgentTurnRequest) {
        self.agent = agent
        self.request = request
        self.turnState = AgentTurnKernel.TurnState(
            iteration: 0,
            maxIterations: agent.configuration.maxIterations
        )
        self.loopDetector = ToolCallLoopDetector(
            maxConsecutiveRepeats: agent.configuration.maxConsecutiveToolRepeats
        )
    }

    /// Runs the turn to an outcome: assistant text, handoff transfer, or throw.
    mutating func run() async throws -> Agent.ToolLoopOutcome {
        try await prepare()
        while true {
            switch try await runIteration() {
            case .continueTurn:
                continue
            case .done(let outcome):
                return outcome
            }
        }
    }

    /// Admits one iteration through the kernel, then performs it.
    private mutating func runIteration() async throws -> IterationDecision {
        // Kernel: admit before per-iteration effects. After host tools the
        // runner feeds `.toolsCompleted` instead of `.startNextIteration`.
        switch AgentTurnKernel.transition(turnState, pendingTurnAction) {
        case .fail(let error):
            throw error
        case .performInference(let admitted):
            turnState = admitted
        case .executeTools, .retryOwnedLoopInference, .finish:
            throw AgentError.internalError(reason: "Unexpected admission transition")
        }

        _ = request.resultBuilder.incrementIteration()
        await request.observer?.onIterationStart(context: nil, agent: agent, number: turnState.iteration)

        do {
            return try await performIteration()
        } catch {
            await request.observer?.onIterationEnd(context: nil, agent: agent, number: turnState.iteration)
            throw agent.normalizeCancellation(error)
        }
    }

    /// Performs one admitted iteration: schemas, inference, then tools or finish.
    private mutating func performIteration() async throws -> IterationDecision {
        try agent.checkCancellationAndTimeout(startTime: startTime)

        let unplannedSchemas = await buildToolSchemasWithHandoffs()
        var plannedSchemas = MembraneInternalTools.sortedSchemas(unplannedSchemas)
        let historyPrompt = buildPrompt(from: turnTranscript.conversationMessages)

        if let membraneAdapter = request.dependencies.membraneAdapter {
            do {
                let plan = try await membraneAdapter.plan(
                    prompt: historyPrompt,
                    toolSchemas: unplannedSchemas,
                    profile: agent.configuration.effectiveContextProfile
                )
                plannedSchemas = MembraneInternalTools.sortedSchemas(plan.toolSchemas)
                _ = request.resultBuilder.setMetadata("membrane.mode", .string(plan.mode))
            } catch {
                _ = request.resultBuilder.setMetadata("membrane.fallback.used", .bool(true))
                _ = request.resultBuilder.setMetadata("membrane.fallback.error", .string(agent.fallbackDiagnosticMessage(for: error)))
                plannedSchemas = MembraneInternalTools.sortedSchemas(unplannedSchemas)
            }
        }

        let toolSchemas: [ToolSchema] = {
            var schemas = MembraneInternalTools.sortedSchemas(plannedSchemas)
            // For strict4k, strip tool descriptions to save ~120 tokens.
            if agent.configuration.effectiveContextProfile.preset == .strict4k {
                schemas = schemas.map { ToolSchema(name: $0.name, description: $0.name, parameters: $0.parameters) }
            }
            return schemas
        }()
        let structuredMessages: [InferenceMessage] = await PromptEnvelope.enforce(
            messages: turnTranscript.inferenceMessages,
            profile: agent.configuration.effectiveContextProfile
        )
        // REQ-003: the turn mode is derived in exactly one place.
        let mode = try AgentTurnKernel.resolveMode(
            toolSchemasEmpty: toolSchemas.isEmpty,
            providerOwnsToolLoop: request.dependencies.provider.capabilities.contains(.providerOwnedToolLoop),
            streamsToolCalls: useToolStreaming,
            hasExecutionGate: request.executionGate != nil
        )
        turnState.mode = mode
        turnState.hasToolSchemas = !toolSchemas.isEmpty

        let toolExecutor: ToolCallExecutor?
        if case .ownedLoopTools = mode, let executionGate = request.executionGate {
            toolExecutor = makeToolCallExecutor(executionGate: executionGate)
        } else {
            toolExecutor = nil
        }

        // If no tools defined, generate without tool calling unless the
        // adapter owns the tool loop (empty tool list).
        if mode == .textOnly {
            let hostAgent = agent
            let provider = request.dependencies.provider
            let systemMessage = systemMessage
            let loopInferenceOptions: InferenceOptions = inferenceOptions
            let enableStreaming = enableStreaming
            let observer = request.observer
            let response = try await agent.executeProviderInference(
                startTime: startTime,
                observer: observer,
                tracing: request.tracing
            ) {
                try await Self.generateWithoutTools(
                    agent: hostAgent,
                    provider: provider,
                    messages: structuredMessages,
                    systemPrompt: systemMessage,
                    inferenceOptions: loopInferenceOptions,
                    enableStreaming: enableStreaming,
                    observer: observer
                )
            }
            turnTranscript.appendAssistant(
                content: response.content,
                structuredOutput: response.structuredOutput
            )
            await request.observer?.onIterationEnd(context: nil, agent: agent, number: turnState.iteration)
            return .done(Agent.ToolLoopOutcome(
                output: response.content,
                structuredOutput: response.structuredOutput,
                transcriptMessages: turnTranscript.memoryMessages
            ))
        }

        // Generate response with tool calls
        let loopInferenceOptions: InferenceOptions = inferenceOptions
        // Owned-loop tools run inside inference; retrying would replay them.
        let ownedLoopInferenceRetryPolicy = AgentTurnKernel.ownedLoopInferenceRetryPolicy(
            mode: mode,
            hasToolSchemas: !toolSchemas.isEmpty
        )
        let response: InferenceResponse
        do {
            let hostAgent = agent
            let provider = request.dependencies.provider
            let systemMessage = systemMessage
            let observer = request.observer
            let enableStreaming = enableStreaming
            let streamToolCalls = mode.streamsToolCalls
            response = if streamToolCalls {
                try await agent.executeProviderInference(
                    startTime: startTime,
                    observer: observer,
                    tracing: request.tracing,
                    retryPolicy: ownedLoopInferenceRetryPolicy,
                    executionGate: request.executionGate
                ) {
                    try await Self.generateWithToolsStreaming(
                        agent: hostAgent,
                        provider: provider,
                        messages: structuredMessages,
                        tools: toolSchemas,
                        inferenceOptions: loopInferenceOptions,
                        systemPrompt: systemMessage,
                        observer: observer,
                        toolExecutor: toolExecutor
                    )
                }
            } else {
                try await agent.executeProviderInference(
                    startTime: startTime,
                    observer: observer,
                    tracing: request.tracing,
                    retryPolicy: ownedLoopInferenceRetryPolicy,
                    executionGate: request.executionGate
                ) {
                    try await Self.generateWithTools(
                        agent: hostAgent,
                        provider: provider,
                        messages: structuredMessages,
                        tools: toolSchemas,
                        inferenceOptions: loopInferenceOptions,
                        systemPrompt: systemMessage,
                        observer: observer,
                        emitOutputTokens: enableStreaming,
                        toolExecutor: toolExecutor
                    )
                }
            }
        } catch let handoffRequest as OwnedLoopHandoffRequest {
            _ = request.pendingHandoff.take()
            return .done(try await finishHandoffTransfer(handoffRequest))
        } catch {
            if let pending = request.pendingHandoff.take() {
                return .done(try await finishHandoffTransfer(
                    OwnedLoopHandoffRequest(name: pending.name, arguments: pending.arguments)
                ))
            }
            if case .ownedLoopTools = turnState.mode {
                switch AgentTurnKernel.transition(
                    turnState,
                    .ownedLoopInferenceFailed(Self.ownedLoopInferenceFailure(from: error))
                ) {
                case .fail(let kernelError):
                    if error is CancellationError || error is AgentError {
                        throw kernelError
                    }
                    throw error
                case .retryOwnedLoopInference:
                    // Empty schemas: executeProviderInference already
                    // applied ownedLoopInferenceRetryPolicy. Honor the
                    // kernel without admitting or replaying tools.
                    throw error
                case .performInference, .executeTools, .finish:
                    throw AgentError.internalError(
                        reason: "Unexpected owned-loop failure transition"
                    )
                }
            }
            throw error
        }
        agent.recordUsage(response.usage, on: request.resultBuilder)

        return try await handleInferenceResponse(response)
    }

    /// Interprets one provider response: finish, fail, or execute host tools.
    private mutating func handleInferenceResponse(
        _ response: InferenceResponse
    ) async throws -> IterationDecision {
        switch AgentTurnKernel.transition(turnState, .inferenceCompleted(response)) {
        case .fail(let error):
            throw error

        case .finish(let content):
            let finalResponse = try agent.finalizeAssistantResponse(
                content: content,
                request: request.structuredOutputRequest,
                provider: request.dependencies.provider
            )
            turnTranscript.appendOwnedLoopTranscript(
                response.transcriptMessages,
                finalizedResponse: AgentTurnTranscript.FinalizedResponse(
                    content: finalResponse.content,
                    structuredOutput: finalResponse.structuredOutput
                )
            )
            await request.observer?.onIterationEnd(context: nil, agent: agent, number: turnState.iteration)
            return .done(Agent.ToolLoopOutcome(
                output: finalResponse.content,
                structuredOutput: finalResponse.structuredOutput,
                transcriptMessages: turnTranscript.memoryMessages
            ))

        case .executeTools(let toolsState):
            turnState = toolsState
            if let loop = loopDetector.observe(response.toolCalls) {
                throw AgentError.toolCallLoopDetected(
                    toolNames: loop.toolNames,
                    repetitions: loop.repetitions
                )
            }
            let handoffResult = try await processToolCallsWithHandoffs(response)
            if let handoffOutput = handoffResult {
                await request.observer?.onIterationEnd(context: nil, agent: agent, number: turnState.iteration)
                return .done(Agent.ToolLoopOutcome(
                    output: handoffOutput.content,
                    structuredOutput: handoffOutput.structuredOutput,
                    transcriptMessages: turnTranscript.memoryMessages
                ))
            }
            await request.observer?.onIterationEnd(context: nil, agent: agent, number: turnState.iteration)
            pendingTurnAction = .toolsCompleted
            return .continueTurn

        case .performInference, .retryOwnedLoopInference:
            throw AgentError.internalError(reason: "Unexpected inference transition")
        }
    }

    /// Resolves options, memory context, transcript, and streaming flags once.
    private mutating func prepare() async throws {
        var resolvedOptions = await agent.resolvedInferenceOptions(
            session: request.session,
            provider: request.dependencies.provider
        )
        if let structuredOutputRequest = request.structuredOutputRequest {
            resolvedOptions.structuredOutput = structuredOutputRequest
        }
        resolvedOptions.conversationId = request.session?.sessionId ?? UUID().uuidString
        inferenceOptions = agent.optionsWithMembraneRuntimeSettings(
            resolvedOptions,
            membrane: request.dependencies.membraneEnvironment
        )

        // Retrieve relevant context from memory (enables RAG for VectorMemory)
        let memoryHooks = request.dependencies.memoryHooks
        var memoryContext = ""
        if let memory = request.dependencies.memory {
            let contextProfile = agent.configuration.effectiveContextProfile
            let tokenLimit = contextProfile.memoryTokenLimit
            let input = request.input
            let startTime = startTime
            memoryContext = try await agent.executeWithinRemainingTimeout(startTime: startTime) {
                if let contextForQuery = memoryHooks.contextForQuery {
                    return await contextForQuery(
                        MemoryQuery(
                            text: input,
                            tokenLimit: tokenLimit,
                            maxItems: contextProfile.maxRetrievedItems,
                            maxItemTokens: contextProfile.maxRetrievedItemTokens
                        )
                    )
                }
                return await memory.context(for: input, tokenLimit: tokenLimit)
            }
        }

        turnTranscript = AgentTurnTranscript(
            conversationMessages: try buildInitialConversationHistory(
                sessionHistory: request.sessionHistory,
                input: request.input,
                memoryHooks: memoryHooks,
                memoryContext: memoryContext
            )
        )
        systemMessage = buildSystemMessage(memoryHooks: memoryHooks, memoryContext: memoryContext)
        await request.executionContext.recordExecution(agentName: agent.name)

        enableStreaming = agent.configuration.enableStreaming && request.observer != nil
        let capabilities = agent.providerCapabilities(for: request.dependencies.provider)
        useToolStreaming = enableStreaming && capabilities.contains(.streamingToolCalls)
    }

    // MARK: - Prompt Building

    /// Builds the initial conversation history from session history and user input.
    private func buildInitialConversationHistory(
        sessionHistory: [MemoryMessage],
        input: String,
        memoryHooks: MemoryHooks,
        memoryContext: String = ""
    ) throws -> [ConversationMessage] {
        let transcript = SwarmTranscript(memoryMessages: sessionHistory)
        try transcript.validateReplayCompatibility()

        var history: [ConversationMessage] = []
        history.append(.system(buildSystemMessage(memoryHooks: memoryHooks, memoryContext: memoryContext)))

        for entry in transcript.entries {
            switch entry.role {
            case .user:
                history.append(.user(entry.content))
            case .assistant:
                history.append(.assistant(
                    entry.content,
                    toolCalls: entry.toolCalls.map {
                        InferenceResponse.ParsedToolCall(id: $0.id, name: $0.name, arguments: $0.arguments)
                    }
                ))
            case .system:
                history.append(.system(entry.content))
            case .tool:
                history.append(.toolResult(
                    toolName: entry.toolName ?? "previous",
                    result: entry.content,
                    toolCallID: entry.toolCallID
                ))
            }
        }

        history.append(.user(input))
        return history
    }

    private func buildSystemMessage(
        memoryHooks: MemoryHooks,
        memoryContext: String = ""
    ) -> String {
        let baseInstructions = agent.instructions.isEmpty
            ? "You are a helpful AI assistant with access to tools."
            : agent.instructions

        if memoryContext.isEmpty {
            return baseInstructions
        }

        let title = memoryHooks.memoryPromptTitle ?? "Relevant Context from Memory"
        let priority = memoryHooks.memoryPriority
        let guidance = memoryHooks.memoryPromptGuidance ?? {
            guard priority == .primary else { return nil }
            return "Use the memory context as primary source of truth before calling tools."
        }()

        let guidanceBlock = guidance.flatMap { $0.isEmpty ? nil : $0 }

        if let guidanceBlock {
            return """
            \(baseInstructions)

            \(guidanceBlock)

            \(title):
            \(memoryContext)
            """
        }

        return """
        \(baseInstructions)

        \(title):
        \(memoryContext)
        """
    }

    private func buildPrompt(from history: [ConversationMessage]) -> String {
        history.map(\.formatted).joined(separator: "\n\n")
    }

    // MARK: - Owned-Loop Handoffs

    private func makeToolCallExecutor(executionGate: ProviderOwnedLoopGate) -> ToolCallExecutor {
        let agent = agent
        let toolRegistry = request.dependencies.toolRegistry
        let resultBuilder = request.resultBuilder
        let observer = request.observer
        let tracing = request.tracing
        let executionContext = request.executionContext
        let pendingHandoff = request.pendingHandoff
        let handoffNames = Set(agent._handoffs.map(\.effectiveToolName))
        let stopOnToolError = agent.configuration.stopOnToolError
        let engine = ToolExecutionEngine()
        return ToolCallExecutor { name, arguments in
            guard executionGate.isActive else {
                throw CancellationError()
            }
            if handoffNames.contains(name) {
                pendingHandoff.store(name: name, arguments: arguments)
                executionGate.deactivate()
                throw OwnedLoopHandoffRequest(name: name, arguments: arguments)
            }
            let outcome = try await engine.execute(
                toolName: name,
                arguments: arguments,
                registry: toolRegistry,
                agent: agent,
                context: executionContext,
                resultBuilder: resultBuilder,
                observer: observer,
                tracing: tracing,
                stopOnToolError: stopOnToolError
            )
            if outcome.result.isSuccess {
                return outcome.result.output
            }
            return .string(outcome.result.errorMessage ?? "Tool '\(name)' failed")
        }
    }

    /// Completes an owned-loop handoff transfer and ends the iteration.
    private mutating func finishHandoffTransfer(
        _ handoffRequest: OwnedLoopHandoffRequest
    ) async throws -> Agent.ToolLoopOutcome {
        let handoffOutcome = try await completeOwnedLoopHandoff(handoffRequest)
        await request.observer?.onIterationEnd(context: nil, agent: agent, number: turnState.iteration)
        return handoffOutcome
    }

    private mutating func completeOwnedLoopHandoff(
        _ handoffRequest: OwnedLoopHandoffRequest
    ) async throws -> Agent.ToolLoopOutcome {
        // The turn ends with the handoff outcome, so the transfer appends to
        // the runner's transcript directly; no caller observes it afterwards.
        let response = InferenceResponse(
            content: nil,
            toolCalls: [
                InferenceResponse.ParsedToolCall(
                    id: nil,
                    name: handoffRequest.name,
                    arguments: handoffRequest.arguments
                ),
            ],
            finishReason: .toolCall
        )
        let handoffOutput = try await processToolCallsWithHandoffs(response)
        guard let handoffOutput else {
            throw AgentError.internalError(
                reason: "Owned-loop handoff '\(handoffRequest.name)' did not transfer control"
            )
        }
        return Agent.ToolLoopOutcome(
            output: handoffOutput.content,
            structuredOutput: handoffOutput.structuredOutput,
            transcriptMessages: turnTranscript.memoryMessages
        )
    }

    /// Maps an owned-loop inference error to ``AgentError`` for the kernel.
    ///
    /// `CancellationError` must stay ``AgentError/cancelled`` (not retryable
    /// ``AgentError/generationFailed(reason:)``). Other non-`AgentError` values
    /// keep a generationFailed stand-in so the kernel can classify retry vs
    /// fail; the runner still rethrows the original error in that case.
    private static func ownedLoopInferenceFailure(from error: Error) -> AgentError {
        if error is CancellationError {
            return .cancelled
        }
        if let agentError = error as? AgentError {
            return agentError
        }
        return .generationFailed(reason: error.localizedDescription)
    }

    // MARK: - Tool Execution

    /// Executes a single tool call and updates conversation history.
    mutating func executeSingleToolCall(
        parsedCall: InferenceResponse.ParsedToolCall,
        kind: AgentTurnKernel.HostToolCallKind
    ) async throws {
        // Handoff I/O lives in `processToolCallsWithHandoffs`. A `.handoff` kind
        // here is the missing-configuration fallback and must not take the
        // Membrane internal path.
        switch (kind, request.dependencies.membraneAdapter) {
        case (.membraneInternal, let membraneAdapter?):
            let call = ToolCall(
                providerCallId: parsedCall.id,
                toolName: parsedCall.name,
                arguments: parsedCall.arguments
            )
            _ = request.resultBuilder.addToolCall(call)
            await request.observer?.onToolStart(context: nil, agent: agent, call: call)

            let spanID = await request.tracing?.traceToolCall(name: parsedCall.name, arguments: parsedCall.arguments)
            let toolStartTime = ContinuousClock.now

            do {
                let output = try await agent.executeWithinRemainingTimeout(startTime: startTime) {
                    try await membraneAdapter.handleInternalToolCall(
                        name: parsedCall.name,
                        arguments: parsedCall.arguments
                    ) ?? "ok"
                }

                let duration = ContinuousClock.now - toolStartTime
                let result = ToolResult.success(callId: call.id, output: .string(output), duration: duration)
                _ = request.resultBuilder.addToolResult(result)
                turnTranscript.appendToolResult(
                    toolName: parsedCall.name,
                    result: output,
                    toolCallID: parsedCall.id
                )
                if let memory = request.dependencies.memory {
                    await memory.add(.tool(output, toolName: parsedCall.name))
                }
                if let spanID {
                    await request.tracing?.traceToolResult(
                        spanId: spanID,
                        name: parsedCall.name,
                        result: output,
                        duration: duration
                    )
                }
                await request.observer?.onToolEnd(
                    context: nil,
                    agent: agent,
                    invocation: ToolInvocation(
                        call: call,
                        duration: duration,
                        outcome: .success(.string(output))
                    )
                )
                return
            } catch {
                let duration = ContinuousClock.now - toolStartTime
                let message = error.localizedDescription
                let result = ToolResult.failure(callId: call.id, error: message, duration: duration)
                _ = request.resultBuilder.addToolResult(result)
                if let spanID {
                    await request.tracing?.traceToolError(spanId: spanID, name: parsedCall.name, error: error)
                }
                await request.observer?.onToolEnd(
                    context: nil,
                    agent: agent,
                    invocation: ToolInvocation(
                        call: call,
                        duration: duration,
                        outcome: .failure(message: message)
                    )
                )
                if agent.configuration.stopOnToolError {
                    throw AgentError.toolFailure(toolName: parsedCall.name, message: message, cause: error)
                }
                turnTranscript.appendToolResult(
                    toolName: parsedCall.name,
                    result: AgentTurnKernel.toolFailureConversationText(message: message),
                    toolCallID: parsedCall.id
                )
                if let memory = request.dependencies.memory {
                    await memory.add(.tool(
                        AgentTurnKernel.memoryToolErrorText(message: message),
                        toolName: parsedCall.name
                    ))
                }
                return
            }

        case (.handoff, _), (.regular, _), (.membraneInternal, nil):
            try await executeRegularToolBatch(calls: [parsedCall])
        }
    }

    /// Registry-backed regular tools through ``ToolExecutionEngine/executeBatch``.
    ///
    /// Engine is invoked with `stopOnToolError: false` and
    /// `allowConcurrent: configuration.parallelToolCalls`. After transcript and
    /// memory updates, this throws ``AgentError/toolFailure`` when configured.
    mutating func executeRegularToolBatch(
        calls: [InferenceResponse.ParsedToolCall]
    ) async throws {
        guard !calls.isEmpty else {
            return
        }

        let agent = agent
        let toolRegistry = request.dependencies.toolRegistry
        let resultBuilder = request.resultBuilder
        let observer = request.observer
        let tracing = request.tracing
        let startTime = startTime
        let engine = ToolExecutionEngine()
        let outcomes = try await agent.executeWithinRemainingTimeout(startTime: startTime) {
            try await engine.executeBatch(
                calls,
                registry: toolRegistry,
                agent: agent,
                context: nil,
                resultBuilder: resultBuilder,
                observer: observer,
                tracing: tracing,
                stopOnToolError: false,
                allowConcurrent: agent.configuration.parallelToolCalls
            )
        }

        var firstFailure: (toolName: String, message: String)?
        for (parsedCall, outcome) in zip(calls, outcomes) {
            if outcome.result.isSuccess {
                var toolOutputText = Agent.toolOutputText(for: outcome.result.output)
                if let membraneAdapter = request.dependencies.membraneAdapter {
                    do {
                        let currentToolOutput = toolOutputText
                        let startTime = startTime
                        let transformed = try await agent.executeWithinRemainingTimeout(startTime: startTime) {
                            try await membraneAdapter.transformToolResult(
                                toolName: parsedCall.name,
                                output: currentToolOutput,
                                profile: agent.configuration.effectiveContextProfile
                            )
                        }
                        toolOutputText = transformed.textForConversation
                        if let pointerID = transformed.pointerID {
                            _ = resultBuilder.setMetadata("membrane.pointerized", .bool(true))
                            _ = resultBuilder.setMetadata("membrane.pointer.last_id", .string(pointerID))
                        }
                    } catch {
                        _ = resultBuilder.setMetadata("membrane.fallback.used", .bool(true))
                        _ = resultBuilder.setMetadata("membrane.fallback.error", .string(agent.fallbackDiagnosticMessage(for: error)))
                    }
                }

                turnTranscript.appendToolResult(
                    toolName: parsedCall.name,
                    result: toolOutputText,
                    toolCallID: parsedCall.id
                )
                if let memory = request.dependencies.memory {
                    await memory.add(.tool(toolOutputText, toolName: parsedCall.name))
                }
            } else {
                let errorMessage = outcome.result.errorMessage ?? "Unknown error"
                turnTranscript.appendToolResult(
                    toolName: parsedCall.name,
                    result: AgentTurnKernel.toolFailureConversationText(message: errorMessage),
                    toolCallID: parsedCall.id
                )
                if let memory = request.dependencies.memory {
                    await memory.add(.tool(
                        AgentTurnKernel.memoryToolErrorText(message: errorMessage),
                        toolName: parsedCall.name
                    ))
                }
                if firstFailure == nil {
                    firstFailure = (parsedCall.name, errorMessage)
                }
            }
        }

        if agent.configuration.stopOnToolError, let firstFailure {
            throw AgentError.toolFailure(
                toolName: firstFailure.toolName,
                message: firstFailure.message,
                cause: nil
            )
        }
    }
}
