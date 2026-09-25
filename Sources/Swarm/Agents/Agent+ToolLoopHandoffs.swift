// Agent+ToolLoopHandoffs.swift
// Swarm Framework
//
// Handoff tool-schema integration for the owned tool loop.

import Foundation

extension Agent {
    // MARK: - Handoff Tool Schema Integration

    /// Builds tool schemas including handoff tool schemas.
    ///
    /// This merges regular tool schemas with handoff-generated schemas,
    /// allowing handoffs to appear as callable tools in the LLM prompt.
    func buildToolSchemasWithHandoffs(
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
    func processToolCallsWithHandoffs(
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
            _handoffs.map { ($0.effectiveToolName, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let assistantContent = AgentTurnKernel.assistantContent(for: response)
        turnTranscript.appendAssistant(
            content: assistantContent,
            toolCalls: response.toolCalls
        )

        let hostKind: (InferenceResponse.ParsedToolCall) -> AgentTurnKernel.HostToolCallKind = { parsedCall in
            AgentTurnKernel.hostToolCallKind(
                isHandoffTool: handoffMap[parsedCall.name] != nil,
                isMembraneInternal: membraneAdapter != nil
                    && MembraneInternalTools.isInternalTool(parsedCall.name)
            )
        }

        var callIndex = 0
        while callIndex < response.toolCalls.count {
            let parsedCall = response.toolCalls[callIndex]
            let kind = hostKind(parsedCall)

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
                    callIndex += 1
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
                        throw AgentError.toolFailure(toolName: parsedCall.name, message: message, cause: nil)
                    }

                    let toolError = AgentTurnKernel.toolFailureConversationText(message: message)
                    turnTranscript.appendToolResult(
                        toolName: parsedCall.name,
                        result: toolError,
                        toolCallID: parsedCall.id
                    )
                    callIndex += 1
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

                let lastUserText = HandoffPreparation.lastUserText(
                    from: turnTranscript.conversationMessages
                )
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
                let prepared = HandoffPreparation.prepare(
                    sourceAgentName: handoffData.sourceAgentName,
                    targetAgentName: handoffData.targetAgentName,
                    lastUserText: lastUserText,
                    reason: reason,
                    transformed: handoffConfig.transform?(handoffData) ?? handoffData,
                    history: handoffConfig.history,
                    conversation: turnTranscript.conversationMessages,
                    skippingToolCallID: parsedCall.id
                )
                let allowedContext = prepared.allowedContext
                let handoffContext = await context.copy(additionalValues: allowedContext)
                await applyContextValues(allowedContext, to: handoffContext)
                await preserveExecutionPath(from: context, in: handoffContext)
                if prepared.nestsSession {
                    await addNestedHandoffHistory(
                        prepared.historyProjection.messages,
                        to: handoffContext
                    )
                }

                let handoffRequest = prepared.request

                let result: AgentResult
                do {
                    result = try await executeWithinRemainingTimeout(startTime: startTime) {
                        let handoffSession = try await makeNestedHandoffSession(
                            from: handoffContext,
                            enabled: prepared.nestsSession
                        )
                        return try await targetAgent.handleHandoff(
                            handoffRequest,
                            context: handoffContext,
                            session: handoffSession,
                            observer: observer
                        )
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

            case .membraneInternal:
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
                callIndex += 1

            case .regular:
                var end = callIndex + 1
                while end < response.toolCalls.count,
                      hostKind(response.toolCalls[end]) == .regular {
                    end += 1
                }
                try await executeRegularToolBatch(
                    calls: Array(response.toolCalls[callIndex..<end]),
                    toolRegistry: toolRegistry,
                    memory: memory,
                    turnTranscript: &turnTranscript,
                    resultBuilder: resultBuilder,
                    observer: observer,
                    tracing: tracing,
                    membraneAdapter: membraneAdapter,
                    startTime: startTime
                )
                callIndex = end
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
        _ conversationHistory: [AgentTurnTranscript.Message],
        to context: AgentContext
    ) async {
        for message in conversationHistory {
            switch message {
            case let .system(content):
                await context.addMessage(SwarmTranscriptCodec.encodeMessage(role: .system, content: content))
            case let .user(content):
                await context.addMessage(SwarmTranscriptCodec.encodeMessage(role: .user, content: content))
            case let .assistant(content, toolCalls):
                await context.addMessage(
                    SwarmTranscriptCodec.encodeMessage(
                        role: .assistant,
                        content: content,
                        toolCalls: toolCalls
                    )
                )
            case let .toolResult(toolName, result, toolCallID):
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
}
