// Agent+RunLoop.swift
// Swarm Framework
//
// Extracted from Agent.swift. Effects stay on Agent behind AgentTurnKernel;
// collaborators come from the once-per-turn AgentTurnDependencies snapshot.

import Foundation

extension Agent {
    /// Executes the agent with the given input and returns a result.
    /// - Parameters:
    ///   - input: The user's input/query.
    ///   - session: Optional session for conversation history management.
    ///   - observer: Optional run observer for observing agent execution events.
    /// - Returns: The result of the agent's execution.
    /// - Throws: `AgentError` if execution fails, or `GuardrailError` if guardrails trigger.
    public func run(_ input: String, session: (any Session)? = nil, observer: (any AgentObserver)? = nil) async throws -> AgentResult {
        let runID = UUID()
        await activeRuns.reserve(runID)
        let task = Task { [self] in
            try await runInternal(input, session: session, observer: observer, structuredOutputRequest: nil)
        }
        await activeRuns.attach(runID) { [task] in
            task.cancel()
        }

        do {
            let result = try await withTaskCancellationHandler(
                operation: {
                    try await task.value.agentResult
                },
                onCancel: {
                    task.cancel()
                }
            )
            await activeRuns.finish(runID)
            return result
        } catch {
            task.cancel()
            await activeRuns.finish(runID)
            throw normalizeCancellation(error)
        }
    }

    /// Executes the agent and enforces a structured output contract for the final assistant response.
    public func runStructured(
        _ input: String,
        request: StructuredOutputRequest,
        session: (any Session)? = nil,
        observer: (any AgentObserver)? = nil
    ) async throws -> StructuredAgentResult {
        let runID = UUID()
        await activeRuns.reserve(runID)
        let task = Task { [self] in
            try await runInternal(input, session: session, observer: observer, structuredOutputRequest: request)
        }
        await activeRuns.attach(runID) { [task] in
            task.cancel()
        }

        do {
            let result = try await withTaskCancellationHandler(
                operation: {
                    try await task.value
                },
                onCancel: {
                    task.cancel()
                }
            )
            await activeRuns.finish(runID)

            guard let structuredOutput = result.structuredOutput else {
                throw AgentError.generationFailed(reason: "Structured output request completed without a structured result")
            }

            return StructuredAgentResult(agentResult: result.agentResult, structuredOutput: structuredOutput)
        } catch {
            task.cancel()
            await activeRuns.finish(runID)
            throw normalizeCancellation(error)
        }
    }

    public func stream(_ input: String, session: (any Session)? = nil, observer: (any AgentObserver)? = nil) -> AsyncThrowingStream<AgentEvent, Error> {
        let agent = self
        return StreamHelper.makeTrackedStream(bufferingPolicy: .unbounded) { continuation in
            // Create event bridge observer
            let streamObserver = EventStreamObserver(continuation: continuation)

            // Combine with user-provided observer
            let combinedObserver: any AgentObserver = if let userObserver = observer {
                CompositeObserver(observers: [userObserver, streamObserver])
            } else {
                streamObserver
            }

            do {
                _ = try await agent.run(input, session: session, observer: combinedObserver)
                continuation.finish()
            } catch {
                // Error is handled by EventStreamObserver.onError
                continuation.finish(throwing: error)
            }
        }
    }

    public func runWithResponse(
        _ input: String,
        session: (any Session)? = nil,
        observer: (any AgentObserver)? = nil
    ) async throws -> AgentResponse {
        let result = try await run(input, session: session, observer: observer)
        let responseID = responseID(from: result)
        return makeResponse(from: result, responseID: responseID)
    }

    func runInternal(
        _ input: String,
        session: (any Session)? = nil,
        observer: (any AgentObserver)? = nil,
        structuredOutputRequest: StructuredOutputRequest?
    ) async throws -> InternalRunResult {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.invalidInput(reason: "Input cannot be empty")
        }

        let dependencies = try await resolveTurnDependencies()
        let activeTracer = dependencies.tracer
        let activeMemory = dependencies.memory
        let memoryHooks = dependencies.memoryHooks
        var defaultMemoryRunKey: ObjectIdentifier?

        if let session,
           let trackedSessionMemory = dependencies.trackedSessionMemory
        {
            let memoryKey = memoryObjectIdentifier(trackedSessionMemory)
            defaultMemoryRunKey = memoryKey
            if try await runEnvironment.defaultMemorySessionTracker.beginRun(for: memoryKey, sessionID: session.sessionId) {
                await trackedSessionMemory.clear()
            }
        }

        let tracing = TracingHelper(
            tracer: activeTracer,
            agentName: configuration.name.isEmpty ? "Agent" : configuration.name
        )
        await tracing.traceStart(input: input)

        // Notify observer of agent start
        await observer?.onAgentStart(context: nil, agent: self, input: input)

        if let beginMemorySession = memoryHooks.beginMemorySession {
            await beginMemorySession()
        }

        do {
            // Run input guardrails (with observer for event emission)
            let runner = GuardrailRunner(configuration: guardrailRunnerConfiguration, observer: observer)
            _ = try await runner.runInputGuardrails(inputGuardrails, input: input, context: nil)

            // Reset cancellation state and create result builder
            let resultBuilder = AgentResult.Builder()
            _ = resultBuilder.start()
            let responseID = UUID().uuidString
            _ = resultBuilder.setMetadata(Self.responseIDMetadataKey, .string(responseID))
            if let structuredOutputRequest {
                _ = resultBuilder.setMetadata(
                    Self.structuredOutputFormatMetadataKey,
                    .string(Self.structuredOutputFormatDescription(structuredOutputRequest.format))
                )
            }

            // Load conversation history from session (limit to recent messages)
            var sessionHistory: [MemoryMessage] = []
            if let session {
                sessionHistory = try await session.getItems(limit: configuration.sessionHistoryLimit)
            }

            let replayTranscript = SwarmTranscript(memoryMessages: sessionHistory)
            try replayTranscript.validateReplayCompatibility()

            // Seed memory with session history once when the memory is eligible.
            if let activeMemory, session != nil {
                await activeMemory.seedSessionHistoryIfNeeded(sessionHistory)
            }

            // Create user message for this turn
            let userMessage = SwarmTranscriptCodec.encodeMessage(role: .user, content: input)

            // Execute the tool calling loop with session context
            let provider = dependencies.provider
            let executionContext = AgentContext(input: input)
            let runtimeEnvironment = runtimeEnvironment(for: provider, snapshot: dependencies.environmentSnapshot)
            let ownsToolLoop = provider.capabilities.contains(.providerOwnedToolLoop)
            let executionGate = ownsToolLoop ? ProviderOwnedLoopGate() : nil
            let pendingHandoff = OwnedLoopPendingHandoff()
            let toolLoopOutcome = try await AgentEnvironmentValues.$current.withValue(runtimeEnvironment) {
                try await executeToolCallingLoop(
                    input: input,
                    dependencies: dependencies,
                    sessionHistory: sessionHistory,
                    session: session,
                    resultBuilder: resultBuilder,
                    observer: observer,
                    tracing: tracing,
                    structuredOutputRequest: structuredOutputRequest,
                    executionContext: executionContext,
                    executionGate: executionGate,
                    pendingHandoff: pendingHandoff
                )
            }

            _ = resultBuilder.setOutput(toolLoopOutcome.output)
            applyStructuredOutputMetadata(toolLoopOutcome.structuredOutput, to: resultBuilder)

            // Run output guardrails BEFORE storing in session/memory
            _ = try await runner.runOutputGuardrails(
                outputGuardrails,
                output: toolLoopOutcome.output,
                agent: self,
                context: nil
            )

            // Store turn in session for conversation persistence
            // Session is the source of truth for conversation history
            if let session {
                try await session.addItems([userMessage] + toolLoopOutcome.transcriptMessages)

                let persistedTranscript = SwarmTranscript(memoryMessages: try await session.getAllItems())
                try persistedTranscript.validateReplayCompatibility()
                _ = resultBuilder.setMetadata(
                    Self.transcriptSchemaVersionMetadataKey,
                    .string(persistedTranscript.schemaVersion.rawValue)
                )
                if let transcriptHash = try? persistedTranscript.transcriptHash() {
                    _ = resultBuilder.setMetadata(Self.transcriptHashMetadataKey, .string(transcriptHash))
                }
            } else if let activeMemory, dependencies.shouldPersistNoSessionTurnToDefaultMemory {
                await persistNoSessionTurn(
                    userMessage: userMessage,
                    transcriptMessages: toolLoopOutcome.transcriptMessages,
                    to: activeMemory
                )
            }

            // Session remains the transcript source of truth. When no session is supplied,
            // the default memory keeps user/assistant turns available for subsequent runs.

            _ = resultBuilder.setMetadata(RuntimeMetadata.runtimeEngineKey, .string(RuntimeMetadata.nativeRuntimeEngineName))
            let result = resultBuilder.build()
            if configuration.autoPreviousResponseId, let session {
                let response = makeResponse(from: result, responseID: responseID)
                await runEnvironment.responseTracker.recordResponse(response, sessionId: session.sessionId)
            }
            await tracing.traceComplete(result: result, tokenUsage: resultBuilder.ownTokenUsage())

            // Notify observer of agent completion
            await observer?.onAgentEnd(context: nil, agent: self, result: result)

            if let endMemorySession = memoryHooks.endMemorySession {
                await endMemorySession()
            }
            if let defaultMemoryRunKey {
                await runEnvironment.defaultMemorySessionTracker.endRun(for: defaultMemoryRunKey)
            }
            return InternalRunResult(agentResult: result, structuredOutput: toolLoopOutcome.structuredOutput)
        } catch {
            let normalizedError = normalizeCancellation(error)
            // Notify observer of error
            await observer?.onError(context: nil, agent: self, error: normalizedError)
            await tracing.traceError(normalizedError)
            if let endMemorySession = memoryHooks.endMemorySession {
                await endMemorySession()
            }
            if let defaultMemoryRunKey {
                await runEnvironment.defaultMemorySessionTracker.endRun(for: defaultMemoryRunKey)
            }
            throw normalizedError
        }
    }

    func runtimeEnvironment(
        for provider: any InferenceProvider,
        snapshot: AgentEnvironment
    ) -> AgentEnvironment {
        AgentDependencyResolver.runtimeEnvironment(snapshot, addingTokenCounterFrom: provider)
    }

    func applyStructuredOutputMetadata(
        _ structuredOutput: StructuredOutputResult?,
        to resultBuilder: AgentResult.Builder
    ) {
        guard let structuredOutput else { return }

        _ = resultBuilder.setMetadata(Self.structuredOutputJSONMetadataKey, .string(structuredOutput.rawJSON))
        _ = resultBuilder.setMetadata(Self.structuredOutputSourceMetadataKey, .string(structuredOutput.source.rawValue))
        _ = resultBuilder.setMetadata(
            Self.structuredOutputFormatMetadataKey,
            .string(Self.structuredOutputFormatDescription(structuredOutput.format))
        )
    }
}
