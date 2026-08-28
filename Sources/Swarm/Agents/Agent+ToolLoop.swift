// Agent+ToolLoop.swift
// Swarm Framework
//
// Extracted from Agent.swift. Effects stay on Agent behind AgentTurnKernel;
// collaborators come from the once-per-turn AgentTurnDependencies snapshot.

import Foundation

extension Agent {
    private typealias ConversationMessage = AgentTurnTranscript.Message

    // MARK: - Tool Calling Loop Implementation

    func executeToolCallingLoop(
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
    ) async throws -> ToolLoopOutcome {
        let toolRegistry = dependencies.toolRegistry
        let provider = dependencies.provider
        let startTime = ContinuousClock.now
        var inferenceOptions = await resolvedInferenceOptions(session: session, provider: provider)
        if let structuredOutputRequest {
            inferenceOptions.structuredOutput = structuredOutputRequest
        }
        inferenceOptions.conversationId = session?.sessionId ?? UUID().uuidString
        inferenceOptions = optionsWithMembraneRuntimeSettings(
            inferenceOptions,
            membrane: dependencies.membraneEnvironment
        )

        // Retrieve relevant context from memory (enables RAG for VectorMemory)
        let activeMemory = dependencies.memory
        var memoryContext = ""
        if let mem = activeMemory {
            let contextProfile = configuration.effectiveContextProfile
            let tokenLimit = contextProfile.memoryTokenLimit
            memoryContext = try await executeWithinRemainingTimeout(startTime: startTime) {
                let hooks = MemoryHooks.resolved(from: mem)
                if let contextForQuery = hooks.contextForQuery {
                    return await contextForQuery(
                        MemoryQuery(
                            text: input,
                            tokenLimit: tokenLimit,
                            maxItems: contextProfile.maxRetrievedItems,
                            maxItemTokens: contextProfile.maxRetrievedItemTokens
                        )
                    )
                }
                return await mem.context(for: input, tokenLimit: tokenLimit)
            }
        }

        var turnTranscript = AgentTurnTranscript(
            conversationMessages: try buildInitialConversationHistory(
                sessionHistory: sessionHistory,
                input: input,
                memory: activeMemory,
                memoryContext: memoryContext
            )
        )
        let systemMessage = buildSystemMessage(memory: activeMemory, memoryContext: memoryContext)
        await executionContext.recordExecution(agentName: name)

        let enableStreaming = configuration.enableStreaming && observer != nil
        let capabilities = providerCapabilities(for: provider)
        let useToolStreaming = enableStreaming && capabilities.contains(.streamingToolCalls)
        let membraneAdapter = dependencies.membraneAdapter

        var iteration = 0
        var turnState = AgentTurnKernel.TurnState(
            iteration: 0,
            maxIterations: configuration.maxIterations
        )

        while true {
            // Kernel: admit the next iteration before any per-iteration effects
            // run (mirrors the previous `while iteration < maxIterations` head).
            switch AgentTurnKernel.transition(turnState, .startNextIteration) {
            case .fail(let error):
                throw error
            case .performInference(let admitted):
                turnState = admitted
                iteration = admitted.iteration
            default:
                throw AgentError.internalError(reason: "Unexpected admission transition")
            }

            _ = resultBuilder.incrementIteration()
            await observer?.onIterationStart(context: nil, agent: self, number: iteration)

            do {
                try checkCancellationAndTimeout(startTime: startTime)

                let unplannedSchemas = await buildToolSchemasWithHandoffs(
                    toolRegistry: toolRegistry,
                    context: executionContext
                )
                var plannedSchemas = MembraneInternalTools.sortedSchemas(unplannedSchemas)
                let historyPrompt = buildPrompt(from: turnTranscript.conversationMessages)

                if let membraneAdapter {
                    do {
                        let plan = try await membraneAdapter.plan(
                            prompt: historyPrompt,
                            toolSchemas: unplannedSchemas,
                            profile: configuration.effectiveContextProfile
                        )
                        plannedSchemas = MembraneInternalTools.sortedSchemas(plan.toolSchemas)
                        _ = resultBuilder.setMetadata("membrane.mode", .string(plan.mode))
                    } catch {
                        _ = resultBuilder.setMetadata("membrane.fallback.used", .bool(true))
                        _ = resultBuilder.setMetadata("membrane.fallback.error", .string(fallbackDiagnosticMessage(for: error)))
                        plannedSchemas = MembraneInternalTools.sortedSchemas(unplannedSchemas)
                    }
                }

                let toolSchemas: [ToolSchema] = {
                    var schemas = MembraneInternalTools.sortedSchemas(plannedSchemas)
                    // For strict4k, strip tool descriptions to save ~120 tokens.
                    if configuration.effectiveContextProfile.preset == .strict4k {
                        schemas = schemas.map { ToolSchema(name: $0.name, description: $0.name, parameters: $0.parameters) }
                    }
                    return schemas
                }()
                let structuredMessages: [InferenceMessage] = await PromptEnvelope.enforce(
                    messages: turnTranscript.inferenceMessages,
                    profile: configuration.effectiveContextProfile
                )
                // REQ-003: the turn mode is derived in exactly one place.
                let mode = try AgentTurnKernel.resolveMode(
                    toolSchemasEmpty: toolSchemas.isEmpty,
                    providerOwnsToolLoop: provider.capabilities.contains(.providerOwnedToolLoop),
                    streamsToolCalls: useToolStreaming,
                    hasExecutionGate: executionGate != nil
                )
                turnState.mode = mode
                turnState.hasToolSchemas = !toolSchemas.isEmpty

                let toolExecutor: ToolCallExecutor?
                if case .ownedLoopTools = mode, let executionGate {
                    toolExecutor = makeToolCallExecutor(
                        toolRegistry: toolRegistry,
                        resultBuilder: resultBuilder,
                        observer: observer,
                        tracing: tracing,
                        executionContext: executionContext,
                        executionGate: executionGate,
                        pendingHandoff: pendingHandoff
                    )
                } else {
                    toolExecutor = nil
                }

                // If no tools defined, generate without tool calling unless the
                // adapter owns the tool loop (empty tool list).
                if mode == .textOnly {
                    let loopInferenceOptions = inferenceOptions
                    let response = try await executeProviderInference(
                        startTime: startTime,
                        observer: observer,
                        tracing: tracing
                    ) {
                        try await generateWithoutTools(
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
                    await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                    return ToolLoopOutcome(
                        output: response.content,
                        structuredOutput: response.structuredOutput,
                        transcriptMessages: turnTranscript.memoryMessages
                    )
                }

                // Generate response with tool calls
                let loopInferenceOptions = inferenceOptions
                // Owned-loop tools run inside inference; retrying would replay them.
                let ownedLoopInferenceRetryPolicy = AgentTurnKernel.ownedLoopInferenceRetryPolicy(
                    mode: mode,
                    hasToolSchemas: !toolSchemas.isEmpty
                )
                let response: InferenceResponse
                do {
                    let streamToolCalls = mode.streamsToolCalls
                    response = if streamToolCalls {
                        try await executeProviderInference(
                            startTime: startTime,
                            observer: observer,
                            tracing: tracing,
                            retryPolicy: ownedLoopInferenceRetryPolicy,
                            executionGate: executionGate
                        ) {
                            try await generateWithToolsStreaming(
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
                        try await executeProviderInference(
                            startTime: startTime,
                            observer: observer,
                            tracing: tracing,
                            retryPolicy: ownedLoopInferenceRetryPolicy,
                            executionGate: executionGate
                        ) {
                            try await generateWithTools(
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
                } catch let request as OwnedLoopHandoffRequest {
                    pendingHandoff.take()
                    let handoffOutcome = try await completeOwnedLoopHandoff(
                        request,
                        toolRegistry: toolRegistry,
                        memory: activeMemory,
                        membraneAdapter: membraneAdapter,
                        turnTranscript: &turnTranscript,
                        resultBuilder: resultBuilder,
                        observer: observer,
                        tracing: tracing,
                        context: executionContext,
                        startTime: startTime
                    )
                    await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                    return handoffOutcome
                } catch {
                    if let pending = pendingHandoff.take() {
                        let handoffOutcome = try await completeOwnedLoopHandoff(
                            OwnedLoopHandoffRequest(name: pending.name, arguments: pending.arguments),
                            toolRegistry: toolRegistry,
                            memory: activeMemory,
                            membraneAdapter: membraneAdapter,
                            turnTranscript: &turnTranscript,
                            resultBuilder: resultBuilder,
                            observer: observer,
                            tracing: tracing,
                            context: executionContext,
                            startTime: startTime
                        )
                        await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                        return handoffOutcome
                    }
                    throw error
                }
                recordUsage(response.usage, on: resultBuilder)

                switch AgentTurnKernel.transition(turnState, .inferenceCompleted(response)) {
                case .fail(let error):
                    throw error

                case .finish(let content):
                    let finalResponse = try finalizeAssistantResponse(
                        content: content,
                        request: structuredOutputRequest,
                        provider: provider
                    )
                    turnTranscript.appendOwnedLoopTranscript(
                        response.transcriptMessages,
                        finalizedResponse: AgentTurnTranscript.FinalizedResponse(
                            content: finalResponse.content,
                            structuredOutput: finalResponse.structuredOutput
                        )
                    )
                    await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                    return ToolLoopOutcome(
                        output: finalResponse.content,
                        structuredOutput: finalResponse.structuredOutput,
                        transcriptMessages: turnTranscript.memoryMessages
                    )

                case .executeTools(let toolsState):
                    turnState = toolsState
                    let handoffResult = try await processToolCallsWithHandoffs(
                        response: response,
                        toolRegistry: toolRegistry,
                        memory: activeMemory,
                        turnTranscript: &turnTranscript,
                        resultBuilder: resultBuilder,
                        observer: observer,
                        tracing: tracing,
                        membraneAdapter: membraneAdapter,
                        context: executionContext,
                        startTime: startTime
                    )
                    if let handoffOutput = handoffResult {
                        await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                        return ToolLoopOutcome(
                            output: handoffOutput.content,
                            structuredOutput: handoffOutput.structuredOutput,
                            transcriptMessages: turnTranscript.memoryMessages
                        )
                    }
                    await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                default:
                    throw AgentError.internalError(reason: "Unexpected inference transition")
                }
            } catch {
                await observer?.onIterationEnd(context: nil, agent: self, number: iteration)
                throw normalizeCancellation(error)
            }
        }
    }

    /// Builds the initial conversation history from session history and user input.
    private func buildInitialConversationHistory(
        sessionHistory: [MemoryMessage],
        input: String,
        memory: (any Memory)?,
        memoryContext: String = ""
    ) throws -> [ConversationMessage] {
        let transcript = SwarmTranscript(memoryMessages: sessionHistory)
        try transcript.validateReplayCompatibility()

        var history: [ConversationMessage] = []
        history.append(.system(buildSystemMessage(memory: memory, memoryContext: memoryContext)))

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

    /// Generates a response without tool calling.
    private func generateWithoutTools(
        provider: any InferenceProvider,
        messages: [InferenceMessage],
        systemPrompt: String,
        inferenceOptions: InferenceOptions,
        enableStreaming: Bool = false,
        observer: (any AgentObserver)?
    ) async throws -> FinalAssistantResponse {
        await observer?.notifyLLMStart(context: nil, agent: self, systemPrompt: systemPrompt, inputMessages: messages)

        let options = inferenceOptions
        let content: String
        let structuredOutput: StructuredOutputResult?
        if let request = options.structuredOutput {
            let result = try await provider.generateStructured(
                messages: messages,
                request: request,
                options: options
            )
            content = result.rawJSON
            structuredOutput = result
        } else if enableStreaming {
            var streamedContent = ""
            streamedContent.reserveCapacity(1024)
            let stream = provider.stream(messages: messages, options: options)
            for try await token in stream {
                if !token.isEmpty {
                    streamedContent += token
                }
                await observer?.onOutputToken(context: nil, agent: self, token: token)
            }
            content = streamedContent
            structuredOutput = nil
        } else {
            content = try await provider.generate(messages: messages, options: options)
            structuredOutput = nil
        }

        await observer?.onLLMEnd(context: nil, agent: self, response: content, usage: nil)
        return FinalAssistantResponse(content: content, structuredOutput: structuredOutput)
    }

    /// Executes a single tool call and updates conversation history.
    private func executeSingleToolCall(
        parsedCall: InferenceResponse.ParsedToolCall,
        toolRegistry: ToolRegistry,
        memory: (any Memory)?,
        turnTranscript: inout AgentTurnTranscript,
        resultBuilder: AgentResult.Builder,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        kind: AgentTurnKernel.HostToolCallKind,
        membraneAdapter: (any MembraneAgentAdapter)?,
        startTime: ContinuousClock.Instant
    ) async throws {
        let activeMemory = memory

        // Handoff I/O lives in `processToolCallsWithHandoffs`. A `.handoff` kind
        // here is the missing-configuration fallback and must not take the
        // Membrane internal path.
        switch (kind, membraneAdapter) {
        case (.membraneInternal, let membraneAdapter?):
            let call = ToolCall(
                providerCallId: parsedCall.id,
                toolName: parsedCall.name,
                arguments: parsedCall.arguments
            )
            _ = resultBuilder.addToolCall(call)
            await observer?.onToolStart(context: nil, agent: self, call: call)

            let spanID = await tracing?.traceToolCall(name: parsedCall.name, arguments: parsedCall.arguments)
            let toolStartTime = ContinuousClock.now

            do {
                let output = try await executeWithinRemainingTimeout(startTime: startTime) {
                    try await membraneAdapter.handleInternalToolCall(
                        name: parsedCall.name,
                        arguments: parsedCall.arguments
                    ) ?? "ok"
                }

                let duration = ContinuousClock.now - toolStartTime
                let result = ToolResult.success(callId: call.id, output: .string(output), duration: duration)
                _ = resultBuilder.addToolResult(result)
                turnTranscript.appendToolResult(
                    toolName: parsedCall.name,
                    result: output,
                    toolCallID: parsedCall.id
                )
                if let activeMemory {
                    await activeMemory.add(.tool(output, toolName: parsedCall.name))
                }
                if let spanID {
                    await tracing?.traceToolResult(
                        spanId: spanID,
                        name: parsedCall.name,
                        result: output,
                        duration: duration
                    )
                }
                await observer?.onToolEnd(context: nil, agent: self, result: result)
                return
            } catch {
                let duration = ContinuousClock.now - toolStartTime
                let message = error.localizedDescription
                let result = ToolResult.failure(callId: call.id, error: message, duration: duration)
                _ = resultBuilder.addToolResult(result)
                if let spanID {
                    await tracing?.traceToolError(spanId: spanID, name: parsedCall.name, error: error)
                }
                await observer?.onToolEnd(context: nil, agent: self, result: result)
                if configuration.stopOnToolError {
                    throw AgentError.toolExecutionFailed(toolName: parsedCall.name, underlyingError: message)
                }
                turnTranscript.appendToolResult(
                    toolName: parsedCall.name,
                    result: AgentTurnKernel.toolFailureConversationText(message: message),
                    toolCallID: parsedCall.id
                )
                if let activeMemory {
                    await activeMemory.add(.tool(
                        AgentTurnKernel.memoryToolErrorText(message: message),
                        toolName: parsedCall.name
                    ))
                }
                return
            }

        case (.handoff, _), (.regular, _), (.membraneInternal, nil):
            let engine = ToolExecutionEngine()
            let outcome = try await executeWithinRemainingTimeout(startTime: startTime) {
                try await engine.execute(
                    parsedCall,
                    registry: toolRegistry,
                    agent: self,
                    context: nil,
                    resultBuilder: resultBuilder,
                    observer: observer,
                    tracing: tracing,
                    stopOnToolError: false
                )
            }

            if outcome.result.isSuccess {
                var toolOutputText = Self.toolOutputText(for: outcome.result.output)
                if let membraneAdapter {
                    do {
                        let currentToolOutput = toolOutputText
                        let transformed = try await executeWithinRemainingTimeout(startTime: startTime) {
                            try await membraneAdapter.transformToolResult(
                                toolName: parsedCall.name,
                                output: currentToolOutput,
                                profile: configuration.effectiveContextProfile
                            )
                        }
                        toolOutputText = transformed.textForConversation
                        if let pointerID = transformed.pointerID {
                            _ = resultBuilder.setMetadata("membrane.pointerized", .bool(true))
                            _ = resultBuilder.setMetadata("membrane.pointer.last_id", .string(pointerID))
                        }
                    } catch {
                        _ = resultBuilder.setMetadata("membrane.fallback.used", .bool(true))
                        _ = resultBuilder.setMetadata("membrane.fallback.error", .string(fallbackDiagnosticMessage(for: error)))
                    }
                }

                turnTranscript.appendToolResult(
                    toolName: parsedCall.name,
                    result: toolOutputText,
                    toolCallID: parsedCall.id
                )
                if let activeMemory {
                    await activeMemory.add(.tool(toolOutputText, toolName: parsedCall.name))
                }
            } else {
                let errorMessage = outcome.result.errorMessage ?? "Unknown error"
                turnTranscript.appendToolResult(
                    toolName: parsedCall.name,
                    result: AgentTurnKernel.toolFailureConversationText(message: errorMessage),
                    toolCallID: parsedCall.id
                )
                if let activeMemory {
                    await activeMemory.add(.tool(
                        AgentTurnKernel.memoryToolErrorText(message: errorMessage),
                        toolName: parsedCall.name
                    ))
                }

                if configuration.stopOnToolError {
                    throw AgentError.toolExecutionFailed(toolName: parsedCall.name, underlyingError: errorMessage)
                }
            }
        }
    }

    /// Serializes a non-string tool result as canonical JSON so downstream
    /// consumers (Membrane pointerization, transcript replay, model context)
    /// receive a parsable contract rather than `SendableValue.description`'s
    /// JSON-ish format which does not escape quotes, backslashes, or newlines.
    ///
    /// Plain-string results pass through unchanged. Falls back to
    /// `description` if the value contains a non-finite double — `JSONSerialization`
    /// raises an Objective-C `NSException` (not a Swift error) on NaN/Infinity,
    /// so we must screen the value before serializing rather than relying on
    /// `do/catch`.
    static func toolOutputText(for output: SendableValue) -> String {
        if let string = output.stringValue {
            return string
        }

        guard !containsNonFiniteDouble(output) else {
            return output.description
        }

        do {
            let object = output.toJSONObject()
            let data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys, .fragmentsAllowed]
            )
            if let text = String(data: data, encoding: .utf8) {
                return text
            }
        } catch {
            Log.agents.warning("Tool output JSON serialization failed; falling back to description: \(error)")
        }

        return output.description
    }

    private static func containsNonFiniteDouble(_ value: SendableValue) -> Bool {
        switch value {
        case let .double(number):
            return !number.isFinite
        case let .array(values):
            return values.contains(where: containsNonFiniteDouble)
        case let .dictionary(values):
            return values.values.contains(where: containsNonFiniteDouble)
        case .null, .bool, .int, .string:
            return false
        }
    }

    // MARK: - Handoff Tool Schema Integration

    /// Builds tool schemas including handoff tool schemas.
    ///
    /// This merges regular tool schemas with handoff-generated schemas,
    /// allowing handoffs to appear as callable tools in the LLM prompt.
    private func buildToolSchemasWithHandoffs(
        toolRegistry: ToolRegistry,
        context: AgentContext
    ) async -> [ToolSchema] {
        var schemas = await toolRegistry.schemas

        for handoff in await activeHandoffs(context: context) {
            let handoffSchema = ToolSchema(
                name: handoff.effectiveToolName,
                description: handoff.effectiveToolDescription,
                parameters: [
                    ToolParameter(
                        name: "reason",
                        description: "Reason for the handoff",
                        type: .string,
                        isRequired: false
                    ),
                ]
            )
            schemas.append(handoffSchema)
        }

        return MembraneInternalTools.sortedSchemas(schemas)
    }

    private func activeHandoffs(context: AgentContext) async -> [AnyHandoffConfiguration] {
        var active: [AnyHandoffConfiguration] = []

        for handoff in _handoffs {
            if let when = handoff.when, await !when(context, handoff.targetAgent) {
                continue
            }
            active.append(handoff)
        }

        return active
    }

    /// Processes tool calls, handling both regular tools and handoff tools.
    ///
    /// When a tool call matches a handoff's `effectiveToolName`, the target agent
    /// is executed with the original user input and its result is returned.
    /// Returns the handoff output if a handoff was executed, nil otherwise.
    private func processToolCallsWithHandoffs(
        response: InferenceResponse,
        toolRegistry: ToolRegistry,
        memory: (any Memory)?,
        turnTranscript: inout AgentTurnTranscript,
        resultBuilder: AgentResult.Builder,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        membraneAdapter: (any MembraneAgentAdapter)?,
        context: AgentContext,
        startTime: ContinuousClock.Instant
    ) async throws -> FinalAssistantResponse? {
        let handoffMap = Dictionary(
            uniqueKeysWithValues: _handoffs.map { ($0.effectiveToolName, $0) }
        )

        let assistantContent = AgentTurnKernel.assistantContent(for: response)
        turnTranscript.appendAssistant(
            content: assistantContent,
            toolCalls: response.toolCalls
        )

        for parsedCall in response.toolCalls {
            let kind = AgentTurnKernel.hostToolCallKind(
                isHandoffTool: handoffMap[parsedCall.name] != nil,
                isMembraneInternal: membraneAdapter != nil
                    && MembraneInternalTools.isInternalTool(parsedCall.name)
            )

            switch kind {
            case .handoff:
                guard let handoffConfig = handoffMap[parsedCall.name] else {
                    try await executeSingleToolCall(
                        parsedCall: parsedCall,
                        toolRegistry: toolRegistry,
                        memory: memory,
                        turnTranscript: &turnTranscript,
                        resultBuilder: resultBuilder,
                        observer: observer,
                        tracing: tracing,
                        kind: .regular,
                        membraneAdapter: membraneAdapter,
                        startTime: startTime
                    )
                    continue
                }
                if let when = handoffConfig.when, await !when(context, handoffConfig.targetAgent) {
                    let message = "Handoff is not enabled"
                    let handoffCall = ToolCall(
                        providerCallId: parsedCall.id,
                        toolName: parsedCall.name,
                        arguments: parsedCall.arguments
                    )
                    _ = resultBuilder.addToolCall(handoffCall)
                    let result = ToolResult.failure(callId: handoffCall.id, error: message, duration: .zero)
                    _ = resultBuilder.addToolResult(result)

                    if configuration.stopOnToolError {
                        throw AgentError.toolExecutionFailed(toolName: parsedCall.name, underlyingError: message)
                    }

                    let toolError = AgentTurnKernel.toolFailureConversationText(message: message)
                    turnTranscript.appendToolResult(
                        toolName: parsedCall.name,
                        result: toolError,
                        toolCallID: parsedCall.id
                    )
                    continue
                }

                let reason = parsedCall.arguments["reason"]?.stringValue ?? ""
                let targetAgent = handoffConfig.targetAgent

                let handoffStart = ContinuousClock.now
                let spanId = await tracing?.traceToolCall(name: parsedCall.name, arguments: parsedCall.arguments)
                let handoffCall = ToolCall(
                    providerCallId: parsedCall.id,
                    toolName: parsedCall.name,
                    arguments: parsedCall.arguments
                )
                _ = resultBuilder.addToolCall(handoffCall)
                await observer?.onHandoff(context: context, fromAgent: self, toAgent: targetAgent)

                // Find the last user message to use as handoff input
                let lastUserMessage = turnTranscript.conversationMessages.last(where: {
                    if case .user = $0 { return true }
                    return false
                })
                let lastUserText: String? = if case let .user(content) = lastUserMessage {
                    content
                } else {
                    nil
                }
                let handoffInput = AgentTurnKernel.handoffInput(
                    lastUserText: lastUserText,
                    reason: reason
                )

                let initialHandoffData = HandoffInputData(
                    sourceAgentName: name,
                    targetAgentName: targetAgent.name,
                    input: handoffInput,
                    context: await context.snapshot,
                    metadata: reason.isEmpty ? [:] : ["reason": .string(reason)]
                )

                if let onTransfer = handoffConfig.onTransfer {
                    do {
                        try await onTransfer(context, initialHandoffData)
                    } catch {
                        Log.agents.warning("Handoff onTransfer callback failed for \(parsedCall.name): \(error)")
                    }
                }

                let handoffData = HandoffInputData(
                    sourceAgentName: initialHandoffData.sourceAgentName,
                    targetAgentName: initialHandoffData.targetAgentName,
                    input: initialHandoffData.input,
                    context: await context.snapshot,
                    metadata: initialHandoffData.metadata
                )
                let transformedData = handoffConfig.transform?(handoffData) ?? handoffData
                let requestContext = transformedData.context.merging(transformedData.metadata) { _, new in new }
                let handoffContext = await context.copy(additionalValues: requestContext)
                await applyContextValues(requestContext, to: handoffContext)
                await preserveExecutionPath(from: context, in: handoffContext)
                if handoffConfig.nestHandoffHistory {
                    await addNestedHandoffHistory(
                        turnTranscript.conversationMessages,
                        to: handoffContext,
                        skippingToolCallID: parsedCall.id
                    )
                }

                let handoffRequest = HandoffRequest(
                    sourceAgentName: transformedData.sourceAgentName,
                    targetAgentName: transformedData.targetAgentName,
                    input: transformedData.input,
                    reason: reason.isEmpty ? nil : reason,
                    context: requestContext
                )

                let result: AgentResult
                do {
                    result = try await executeWithinRemainingTimeout(startTime: startTime) {
                        if let receiver = targetAgent as? any HandoffReceiver {
                            return try await receiver.handleHandoff(handoffRequest, context: handoffContext)
                        } else {
                            let handoffSession = try await makeNestedHandoffSession(
                                from: handoffContext,
                                enabled: handoffConfig.nestHandoffHistory
                            )
                            return try await targetAgent.run(
                                transformedData.input,
                                session: handoffSession,
                                observer: observer
                            )
                        }
                    }
                } catch {
                    let handoffDuration = ContinuousClock.now - handoffStart
                    _ = resultBuilder.addToolResult(
                        ToolResult.failure(
                            callId: handoffCall.id,
                            error: error.localizedDescription,
                            duration: handoffDuration
                        )
                    )
                    if let spanId {
                        await tracing?.traceToolError(spanId: spanId, name: parsedCall.name, error: error)
                    }
                    throw error
                }
                turnTranscript.appendToolResult(
                    toolName: parsedCall.name,
                    result: result.output,
                    toolCallID: parsedCall.id
                )

                let handoffDuration = ContinuousClock.now - handoffStart
                _ = resultBuilder.addToolResult(
                    ToolResult.success(
                        callId: handoffCall.id,
                        output: .string(result.output),
                        duration: handoffDuration
                    )
                )
                if let spanId {
                    await tracing?.traceToolResult(spanId: spanId, name: parsedCall.name, result: result.output, duration: handoffDuration)
                }

                // Merge handoff tool calls, results, and combined token totals into
                // this agent's AgentResult. Nested usage is traced on the child span.
                for toolCall in result.toolCalls {
                    _ = resultBuilder.addToolCall(toolCall)
                }
                for toolResult in result.toolResults {
                    _ = resultBuilder.addToolResult(toolResult)
                }
                if let usage = result.tokenUsage {
                    _ = resultBuilder.addNestedTokenUsage(usage)
                }
                for (key, value) in result.metadata {
                    _ = resultBuilder.setMetadata(key, value)
                }

                // Return the handoff output to be used as the final result
                return FinalAssistantResponse(content: result.output, structuredOutput: nil)

            case .membraneInternal, .regular:
                try await executeSingleToolCall(
                    parsedCall: parsedCall,
                    toolRegistry: toolRegistry,
                    memory: memory,
                    turnTranscript: &turnTranscript,
                    resultBuilder: resultBuilder,
                    observer: observer,
                    tracing: tracing,
                    kind: kind,
                    membraneAdapter: membraneAdapter,
                    startTime: startTime
                )
            }
        }

        return nil
    }

    private func applyContextValues(
        _ values: [String: SendableValue],
        to context: AgentContext
    ) async {
        for (key, value) in values {
            await context.set(key, value: value)
        }
    }

    private func preserveExecutionPath(from source: AgentContext, in target: AgentContext) async {
        let executionPath = await source.getExecutionPath()
        for agentName in executionPath {
            await target.recordExecution(agentName: agentName)
        }
    }

    private func makeNestedHandoffSession(
        from context: AgentContext,
        enabled: Bool
    ) async throws -> (any Session)? {
        guard enabled else {
            return nil
        }

        let messages = await context.getMessages()
        guard !messages.isEmpty else {
            return nil
        }

        let session = InMemorySession()
        try await session.addItems(messages)
        return session
    }

    private func addNestedHandoffHistory(
        _ conversationHistory: [ConversationMessage],
        to context: AgentContext,
        skippingToolCallID skippedToolCallID: String?
    ) async {
        for message in conversationHistory {
            switch message {
            case let .system(content):
                await context.addMessage(SwarmTranscriptCodec.encodeMessage(role: .system, content: content))
            case let .user(content):
                await context.addMessage(SwarmTranscriptCodec.encodeMessage(role: .user, content: content))
            case let .assistant(content, toolCalls):
                let nestedToolCalls = toolCalls.filter { $0.id != skippedToolCallID }
                guard toolCalls.isEmpty || !nestedToolCalls.isEmpty else {
                    continue
                }
                await context.addMessage(
                    SwarmTranscriptCodec.encodeMessage(
                        role: .assistant,
                        content: content,
                        toolCalls: nestedToolCalls
                    )
                )
            case let .toolResult(toolName, result, toolCallID):
                guard toolCallID != skippedToolCallID else {
                    continue
                }
                await context.addMessage(
                    SwarmTranscriptCodec.encodeMessage(
                        role: .tool,
                        content: result,
                        toolName: toolName,
                        toolCallID: toolCallID
                    )
                )
            }
        }
    }

    // MARK: - Prompt Building

    private func buildSystemMessage(
        memory: (any Memory)?,
        memoryContext: String = ""
    ) -> String {
        let baseInstructions = instructions.isEmpty
            ? "You are a helpful AI assistant with access to tools."
            : instructions

        if memoryContext.isEmpty {
            return baseInstructions
        }

        let hooks = memory.map { MemoryHooks.resolved(from: $0) } ?? .empty
        let title = hooks.memoryPromptTitle ?? "Relevant Context from Memory"
        let priority = hooks.memoryPriority
        let guidance = hooks.memoryPromptGuidance ?? {
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

    // MARK: - Response Generation

    private func generateWithTools(
        provider: any InferenceProvider,
        messages: [InferenceMessage],
        tools: [ToolSchema],
        inferenceOptions: InferenceOptions,
        systemPrompt: String,
        observer: (any AgentObserver)? = nil,
        emitOutputTokens: Bool = false,
        toolExecutor: ToolCallExecutor? = nil
    ) async throws -> InferenceResponse {
        let options = inferenceOptions

        // Notify observer of LLM start
        await observer?.notifyLLMStart(context: nil, agent: self, systemPrompt: systemPrompt, inputMessages: messages)

        let response = try await provider.generateWithToolCalls(
            messages: messages,
            tools: tools,
            options: options,
            toolExecutor: toolExecutor
        )

        if emitOutputTokens, response.transcriptMessages.isEmpty, response.toolCalls.isEmpty,
           let content = response.content, !content.isEmpty
        {
            await observer?.onOutputToken(context: nil, agent: self, token: content)
        }

        // Notify observer of LLM end
        let responseContent = response.content ?? ""
        await observer?.onLLMEnd(context: nil, agent: self, response: responseContent, usage: response.usage)

        return response
    }

    private func generateWithToolsStreaming(
        provider: any InferenceProvider,
        messages: [InferenceMessage],
        tools: [ToolSchema],
        inferenceOptions: InferenceOptions,
        systemPrompt: String,
        observer: (any AgentObserver)? = nil,
        toolExecutor: ToolCallExecutor? = nil
    ) async throws -> InferenceResponse {
        let options = inferenceOptions

        await observer?.notifyLLMStart(context: nil, agent: self, systemPrompt: systemPrompt, inputMessages: messages)

        var content = ""
        content.reserveCapacity(1024)
        var parsedToolCalls: [InferenceResponse.ParsedToolCall] = []
        var usage: TokenUsage?
        var stopStreaming = false
        var finishedTurn: InferenceResponse?

        let stream = provider.streamWithToolCalls(
            messages: messages,
            tools: tools,
            options: options,
            toolExecutor: toolExecutor
        )

        for try await update in stream {
            switch update {
            case let .outputChunk(chunk):
                if !chunk.isEmpty { content += chunk }
                await observer?.onOutputToken(context: nil, agent: self, token: chunk)

            case let .toolCallPartial(partial):
                await observer?.onToolCallPartial(context: nil, agent: self, update: partial)

            case let .toolCallsCompleted(calls):
                parsedToolCalls = calls
                // Capture stops here so Agent can run tools. An owned-loop adapter
                // still has a finished turn to yield; keep reading when we passed
                // an executor.
                if toolExecutor == nil {
                    stopStreaming = true
                }

            case let .usage(u):
                usage = u

            case let .finishedTurn(response):
                finishedTurn = response
            }

            if stopStreaming { break }
        }

        await observer?.onLLMEnd(context: nil, agent: self, response: content, usage: usage)

        if let finishedTurn {
            return finishedTurn
        }

        return InferenceResponse(
            content: content.isEmpty ? nil : content,
            toolCalls: parsedToolCalls,
            finishReason: parsedToolCalls.isEmpty ? .completed : .toolCall,
            usage: usage
        )
    }

    private func makeToolCallExecutor(
        toolRegistry: ToolRegistry,
        resultBuilder: AgentResult.Builder,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        executionContext: AgentContext,
        executionGate: ProviderOwnedLoopGate,
        pendingHandoff: OwnedLoopPendingHandoff
    ) -> ToolCallExecutor {
        let handoffNames = Set(_handoffs.map(\.effectiveToolName))
        let stopOnToolError = configuration.stopOnToolError
        let engine = ToolExecutionEngine()
        return ToolCallExecutor { [self] name, arguments in
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
                agent: self,
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

    private func completeOwnedLoopHandoff(
        _ request: OwnedLoopHandoffRequest,
        toolRegistry: ToolRegistry,
        memory: (any Memory)?,
        membraneAdapter: (any MembraneAgentAdapter)?,
        turnTranscript: inout AgentTurnTranscript,
        resultBuilder: AgentResult.Builder,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        context: AgentContext,
        startTime: ContinuousClock.Instant
    ) async throws -> ToolLoopOutcome {
        var history = turnTranscript
        let response = InferenceResponse(
            content: nil,
            toolCalls: [
                InferenceResponse.ParsedToolCall(
                    id: nil,
                    name: request.name,
                    arguments: request.arguments
                ),
            ],
            finishReason: .toolCall
        )
        let handoffOutput = try await processToolCallsWithHandoffs(
            response: response,
            toolRegistry: toolRegistry,
            memory: memory,
            turnTranscript: &history,
            resultBuilder: resultBuilder,
            observer: observer,
            tracing: tracing,
            membraneAdapter: membraneAdapter,
            context: context,
            startTime: startTime
        )
        guard let handoffOutput else {
            throw AgentError.internalError(
                reason: "Owned-loop handoff '\(request.name)' did not transfer control"
            )
        }
        return ToolLoopOutcome(
            output: handoffOutput.content,
            structuredOutput: handoffOutput.structuredOutput,
            transcriptMessages: history.memoryMessages
        )
    }
}
