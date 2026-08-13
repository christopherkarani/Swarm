// Agent+FoundationModelsNative.swift
// Swarm Framework
//
// Opt-in Foundation Models native session path. Kept off Agent.swift so the
// tool loop does not grow another 100+ lines of Apple-only branching.

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Message list for a native Foundation Models session.
///
/// Matches capture mode: when ``structuredMessages`` is `nil` (`strict4k`
/// windowing and/or `PromptEnvelope` rewrite), send the stuffed envelope
/// prompt as a single user turn. Never fall back to the raw conversation
/// history — that would drop ContextCore windowing and 4K truncation.
enum FoundationModelsNativePrompt {
    static func messages(
        structuredMessages: [InferenceMessage]?,
        envelopePrompt: String
    ) -> [InferenceMessage] {
        structuredMessages ?? [.user(envelopePrompt)]
    }
}

extension Agent {
    /// Runs Foundation Models native session mode when opted in and the provider
    /// is ``FoundationModelsInferenceProvider``. Returns `nil` so the Swarm loop
    /// continues when the flag is `.capture` or the provider is not FM.
    ///
    /// Memory has already been injected into `messages` (session start). Swarm's
    /// iteration cap, mid-loop checkpoints, and per-turn guardrail wrapping are
    /// not applied inside Apple's tool loop.
    func executeNativeFoundationModelsSessionIfAvailable(
        provider: any InferenceProvider,
        messages: [InferenceMessage],
        toolRegistry: ToolRegistry,
        toolSchemas: [ToolSchema],
        inferenceOptions: InferenceOptions,
        systemPrompt: String,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        resultBuilder: AgentResult.Builder,
        executionContext: AgentContext,
        startTime: ContinuousClock.Instant,
        session: (any Session)?,
        enableStreaming: Bool,
        structuredOutputRequest: StructuredOutputRequest?
    ) async throws -> ToolLoopOutcome? {
        guard configuration.foundationModelsExecution == .nativeSession else {
            return nil
        }

        #if canImport(FoundationModels)
        guard #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) else {
            return nil
        }
        #if os(tvOS) || os(watchOS)
        return nil
        #else
        guard let fmProvider = provider as? FoundationModelsInferenceProvider else {
            return nil
        }

        let options = optionsWithMembraneRuntimeSettings(inferenceOptions)
        await observer?.onLLMStart(
            context: nil,
            agent: self,
            systemPrompt: systemPrompt,
            inputMessages: messages.map { message in
                MemoryMessage(role: memoryRole(for: message.role), content: message.content)
            }
        )

        let executingTools: [any FoundationModels.Tool]
        if toolSchemas.isEmpty {
            executingTools = []
        } else {
            let runtime = FoundationModelsNativeToolRuntime(
                registry: toolRegistry,
                agent: self,
                context: executionContext,
                observer: observer,
                tracing: tracing,
                resultBuilder: resultBuilder,
                stopOnToolError: configuration.stopOnToolError
            )
            do {
                executingTools = try FoundationModelsToolBridge.makeExecutingTools(
                    from: toolSchemas,
                    runtime: runtime
                )
            } catch {
                throw AgentError.generationFailed(
                    reason: "Failed to bridge Swarm tools to FoundationModels.Tool: \(error)"
                )
            }
        }

        let conversationID = session?.sessionId ?? "agent:\(configuration.name)"
        let streamObserver = observer
        let streamAgent: any AgentRuntime = self
        let onOutputChunk: (@Sendable (String) async -> Void)?
        if enableStreaming {
            onOutputChunk = { chunk in
                if let streamObserver {
                    await streamObserver.onOutputToken(context: nil, agent: streamAgent, token: chunk)
                }
            }
        } else {
            onOutputChunk = nil
        }
        let native: FoundationModelsNativeTurnResult = try await executeProviderInference(
            startTime: startTime,
            observer: observer,
            tracing: tracing,
            allowsRetry: executingTools.isEmpty
        ) {
            try await fmProvider.respondUsingNativeSession(
                messages: messages,
                tools: executingTools,
                toolSchemas: toolSchemas,
                options: options,
                conversationID: conversationID,
                onOutputChunk: onOutputChunk
            )
        }

        let finalResponse = try finalizeAssistantResponse(
            content: native.content,
            request: structuredOutputRequest,
            provider: provider
        )
        await observer?.onLLMEnd(
            context: nil,
            agent: self,
            response: finalResponse.content,
            usage: nil
        )

        var transcriptMessages = native.transcriptMessages
        if let structured = finalResponse.structuredOutput {
            if let last = transcriptMessages.indices.last,
               transcriptMessages[last].role == MemoryMessage.Role.assistant
            {
                transcriptMessages[last] = SwarmTranscriptCodec.encodeMessage(
                    role: .assistant,
                    content: finalResponse.content,
                    structuredOutput: structured
                )
            }
        }

        return ToolLoopOutcome(
            output: finalResponse.content,
            structuredOutput: finalResponse.structuredOutput,
            transcriptMessages: transcriptMessages
        )
        #endif
        #else
        return nil
        #endif
    }

    private func memoryRole(for role: InferenceMessage.Role) -> MemoryMessage.Role {
        switch role {
        case .system: .system
        case .user: .user
        case .assistant: .assistant
        case .tool: .tool
        }
    }
}
