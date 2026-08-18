// FoundationModelsNativeSession.swift
// Swarm Framework
//
// Persistent LanguageModelSession store, native respond/stream, transcript mapping.

import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Identity for a reused native Foundation Models session.
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
struct FoundationModelsNativeSessionIdentity: Hashable, Sendable {
    var conversationID: String
    var instructions: String
    var toolNames: [String]
}

/// Result of one native-session turn after Apple's tool loop completes.
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
struct FoundationModelsNativeTurnResult: Sendable {
    let content: String
    let transcriptMessages: [MemoryMessage]
}

/// Holds a `LanguageModelSession` so native mode can reuse Apple's transcript
/// across Swarm turns of the same conversation.
///
/// ## Lifecycle
///
/// Within one `Agent.run`, Apple's `respond`/`streamResponse` owns the inner
/// tool loop on a single session (parallel tool calls + KV for that turn).
/// Across `Agent.run` calls with the same tools, instructions, and conversation
/// id, a **new** session is created that copies the previous ``Transcript`` so
/// history is preserved while tool wrappers bind to the current run's observers.
/// The previous session object's on-device KV cache is not kept — Apple does
/// not expose a way to retarget tools on a live session.
///
/// The session is discarded when:
/// - tools or instructions change (identity mismatch)
/// - the conversation id changes
/// - `discard()` is called after an unrecoverable generation error
/// - this store is deallocated with the provider instance
///
/// Memory is injected only when a **new** transcript is started (the first
/// prompt carries Swarm history). Subsequent turns send only the latest user
/// message.
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
actor FoundationModelsNativeSessionStore {
    private var session: LanguageModelSession?
    private var identity: FoundationModelsNativeSessionIdentity?

    func session(
        matching identity: FoundationModelsNativeSessionIdentity,
        create: @Sendable () -> LanguageModelSession,
        recreate: @Sendable (Transcript) -> LanguageModelSession
    ) -> (session: LanguageModelSession, reusedTranscript: Bool) {
        if self.identity == identity, let current = self.session, !current.isResponding {
            let created = recreate(current.transcript)
            self.session = created
            return (created, true)
        }
        let created = create()
        self.session = created
        self.identity = identity
        return (created, false)
    }

    func discard() {
        session = nil
        identity = nil
    }
}

/// Maps Apple `Transcript` entries produced during a native turn into Swarm
/// ``MemoryMessage`` values for conversation persistence.
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
enum FoundationModelsNativeTranscriptMapper {
    /// Converts new transcript entries (after a turn) into Swarm memory messages.
    ///
    /// User prompts are omitted — ``Agent`` already stores the user turn.
    /// Instructions are omitted — they are session configuration, not history.
    static func turnTranscriptMessages<S: Sequence>(
        from entries: S
    ) -> [MemoryMessage] where S.Element == Transcript.Entry {
        var messages: [MemoryMessage] = []
        for entry in entries {
            switch entry {
            case .instructions, .prompt:
                continue
            case let .toolCalls(calls):
                let parsed = calls.map { call in
                    InferenceResponse.ParsedToolCall(
                        id: call.id,
                        name: call.toolName,
                        arguments: FoundationModelsSchemaConversion.argumentDictionary(from: call.arguments)
                    )
                }
                messages.append(
                    SwarmTranscriptCodec.encodeMessage(
                        role: .assistant,
                        content: "",
                        toolCalls: parsed
                    )
                )
            case let .toolOutput(output):
                messages.append(
                    SwarmTranscriptCodec.encodeMessage(
                        role: .tool,
                        content: concatenatedText(output.segments),
                        toolName: output.toolName,
                        toolCallID: output.id
                    )
                )
            case let .response(response):
                let text = concatenatedText(response.segments)
                guard !text.isEmpty else { continue }
                messages.append(
                    SwarmTranscriptCodec.encodeMessage(role: .assistant, content: text)
                )
            @unknown default:
                continue
            }
        }
        return messages
    }

    static func concatenatedText(_ segments: [Transcript.Segment]) -> String {
        segments.map { segment in
            switch segment {
            case let .text(text):
                return text.content
            case let .structure(structure):
                return structure.content.jsonString
            @unknown default:
                return ""
            }
        }.joined()
    }
}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension FoundationModelsInferenceProvider {
    /// Runs a provider-owned tool loop when Agent copied ``ProviderOwnedToolLoop``
    /// with ``FoundationModelsExecutionMode/nativeSession``. Returns `nil` so
    /// capture mode continues when the hook is absent, the mode is `.capture`,
    /// or Apple Intelligence is unavailable.
    func completeProviderOwnedToolLoopIfRequested(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse? {
        let hook = AgentEnvironmentValues.current.providerOwnedToolLoop
        guard let hook,
              ProviderOwnedToolLoop.shouldRun(
                mode: hook.executionMode,
                appleAvailable: Self.isAvailable
              )
        else {
            return nil
        }

        let requestedTools = options.toolChoice == ToolChoice.none ? [] : tools
        let executingTools: [any FoundationModels.Tool]
        if requestedTools.isEmpty {
            executingTools = []
        } else {
            let runtime = FoundationModelsNativeToolRuntime(
                registry: hook.toolRegistry,
                agent: hook.agent,
                context: hook.context,
                observer: hook.observer,
                tracing: hook.tracing,
                resultBuilder: hook.resultBuilder,
                stopOnToolError: hook.stopOnToolError
            )
            do {
                executingTools = try FoundationModelsToolBridge.makeExecutingTools(
                    from: requestedTools,
                    runtime: runtime
                )
            } catch {
                throw AgentError.generationFailed(
                    reason: "Failed to bridge Swarm tools to FoundationModels.Tool: \(error)"
                )
            }
        }

        let streamObserver = hook.observer
        let streamAgent = hook.agent
        let onOutputChunk: (@Sendable (String) async -> Void)?
        if hook.enableStreaming {
            onOutputChunk = { chunk in
                if let streamObserver {
                    await streamObserver.onOutputToken(context: nil, agent: streamAgent, token: chunk)
                }
            }
        } else {
            onOutputChunk = nil
        }

        let native = try await respondUsingNativeSession(
            messages: messages,
            tools: executingTools,
            toolSchemas: requestedTools,
            options: options,
            conversationID: hook.conversationID,
            onOutputChunk: onOutputChunk
        )
        await hook.transcript.store(native.transcriptMessages)
        return InferenceResponse(
            content: native.content,
            toolCalls: [],
            finishReason: .completed
        )
    }

    /// Runs one native-session turn: Apple owns the tool loop; Swarm consumes the
    /// final response and maps new transcript entries into memory messages.
    ///
    /// - Parameters:
    ///   - messages: Swarm conversation history. On a **new** session this is
    ///     flattened into the first prompt (memory injection at session start).
    ///     On a **reused** session only the latest user message is sent.
    ///   - tools: Executing `FoundationModels.Tool` values (Task 2 wrappers).
    ///   - options: Generation options. `toolChoice` is honored via prompt
    ///     guidance on new sessions; Apple's SDK has no `toolCallingMode` yet.
    ///   - conversationID: Session key. Changing it discards the native session.
    ///   - onOutputChunk: When non-nil, uses `streamResponse` and reports text
    ///     deltas. Tool-call partials are not streamed — Apple executes tools
    ///     inside the session before yielding the final answer tokens.
    ///
    /// Cancellation is cooperative via `Task.checkCancellation` around the FM
    /// call. Timeout is enforced by the caller (``Agent`` wraps this in its
    /// remaining-timeout helper). Foundation Models has no native timeout API.
    /// ``AgentConfiguration/maxIterations`` is **not** applied inside Apple's loop.
    func respondUsingNativeSession(
        messages: [InferenceMessage],
        tools: [any FoundationModels.Tool],
        toolSchemas: [ToolSchema] = [],
        options: InferenceOptions,
        conversationID: String,
        onOutputChunk: (@Sendable (String) async -> Void)? = nil
    ) async throws -> FoundationModelsNativeTurnResult {
        let resolved = resolveTurn(messages: messages, tools: toolSchemas, options: options)
        let identity = FoundationModelsNativeSessionIdentity(
            conversationID: conversationID,
            instructions: resolved.instructions ?? "",
            toolNames: tools.map(\.name).sorted()
        )
        let instructions = resolved.instructions
        let store = nativeSessionStore
        let (session, reused) = await store.session(matching: identity) {
            self.makeSession(tools: tools, instructions: instructions)
        } recreate: { transcript in
            self.makeSession(tools: tools, transcript: transcript)
        }

        let prompt: String
        if reused {
            prompt = resolved.messages.last(where: { $0.role == .user })?.content
                ?? resolved.messages.last?.content
                ?? ""
        } else {
            prompt = flattenPrompt(
                messages: resolved.messages,
                tools: toolSchemas,
                options: resolved.options
            )
        }

        let generationOptions = makeGenerationOptions(from: resolved.options)
        let startCount = session.transcript.count

        do {
            try Task.checkCancellation()
            let content: String
            if let onOutputChunk {
                let streamed = try await streamNativeResponse(
                    session: session,
                    prompt: prompt,
                    options: generationOptions,
                    onOutputChunk: onOutputChunk
                )
                content = applyStopSequences(streamed, options: resolved.options)
            } else {
                let response = try await session.respond(to: prompt, options: generationOptions)
                content = applyStopSequences(response.content, options: resolved.options)
            }
            try Task.checkCancellation()
            let newEntries = session.transcript.dropFirst(startCount)
            let transcriptMessages = FoundationModelsNativeTranscriptMapper.turnTranscriptMessages(
                from: newEntries
            )
            return FoundationModelsNativeTurnResult(
                content: content,
                transcriptMessages: transcriptMessages.isEmpty
                    ? [SwarmTranscriptCodec.encodeMessage(role: .assistant, content: content)]
                    : transcriptMessages
            )
        } catch is CancellationError {
            await store.discard()
            throw AgentError.cancelled
        } catch let error as LanguageModelSession.ToolCallError {
            await store.discard()
            if let native = error.underlyingError as? FoundationModelsNativeToolError {
                throw AgentError.toolExecutionFailed(
                    toolName: native.toolName,
                    underlyingError: native.message
                )
            }
            if error.underlyingError is CancellationError {
                throw AgentError.cancelled
            }
            throw mapError(error)
        } catch let error as FoundationModelsNativeToolError {
            await store.discard()
            throw AgentError.toolExecutionFailed(toolName: error.toolName, underlyingError: error.message)
        } catch {
            await store.discard()
            throw mapError(error)
        }
    }

    private func streamNativeResponse(
        session: LanguageModelSession,
        prompt: String,
        options: GenerationOptions,
        onOutputChunk: @Sendable (String) async -> Void
    ) async throws -> String {
        var previous = ""
        for try await snapshot in session.streamResponse(to: prompt, options: options) {
            try Task.checkCancellation()
            let current = snapshot.content
            let delta: String
            if current.hasPrefix(previous) {
                delta = String(current.dropFirst(previous.count))
            } else {
                delta = current
            }
            previous = current
            if !delta.isEmpty {
                await onOutputChunk(delta)
            }
        }
        return previous
    }
}
#endif
