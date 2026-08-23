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
    let transcriptMessages: [InferenceMessage]
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
/// - tools or instructions change (identity mismatch) on a **free** slot
/// - the conversation id changes on a **free** slot
/// - `discard(_:)` is called for the lease that currently owns the slot
/// - this store is deallocated with the provider instance
///
/// Re-entry while an owned loop is active, or while the stored session is
/// still `isResponding`, returns a **detached** session from `create()` and
/// leaves the stored slot untouched. Nested `.nativeSession` AgentTool runs
/// and a second `Agent.run` on a shared provider therefore cannot clobber
/// the parent. `discard` of a detached or already-ended lease is a no-op.
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
    private var nextGeneration: UInt64 = 0
    private var activeOwnedLoop: UInt64?

    /// Token for one `tryBeginOwnedLoop` acquisition.
    ///
    /// A zero generation is detached (nested / in-flight): `endOwnedLoop` and
    /// `discard` ignore it. Owned generations only mutate the slot while they
    /// are still the active lease.
    struct Lease: Sendable, Equatable {
        fileprivate let generation: UInt64

        var isOwned: Bool { generation != 0 }

        static let detached = Lease(generation: 0)
    }

    /// Acquires a session for one provider-owned tool loop.
    ///
    /// - Returns: An owned session (stored, `lease.isOwned == true`) when the
    ///   slot is free; otherwise a throwaway session that does not replace
    ///   whatever is already stored.
    func tryBeginOwnedLoop(
        matching identity: FoundationModelsNativeSessionIdentity,
        create: @Sendable () -> LanguageModelSession,
        recreate: @Sendable (Transcript) -> LanguageModelSession
    ) -> (session: LanguageModelSession, reusedTranscript: Bool, lease: Lease) {
        if isSlotBusy {
            return (create(), false, .detached)
        }

        let created: LanguageModelSession
        let reused: Bool
        if self.identity == identity, let current = session {
            created = recreate(current.transcript)
            reused = true
        } else {
            created = create()
            reused = false
        }
        session = created
        self.identity = identity
        nextGeneration += 1
        let generation = nextGeneration
        activeOwnedLoop = generation
        return (created, reused, Lease(generation: generation))
    }

    /// Releases the owned-loop flag after a successful turn. The session stays
    /// stored for the next same-identity `Agent.run`.
    func endOwnedLoop(_ lease: Lease) {
        guard lease.generation != 0, activeOwnedLoop == lease.generation else { return }
        activeOwnedLoop = nil
    }

    /// Nils the stored session only when `lease` still owns the slot.
    func discard(_ lease: Lease) {
        guard lease.generation != 0, activeOwnedLoop == lease.generation else { return }
        session = nil
        identity = nil
        activeOwnedLoop = nil
    }

    func isStored(_ candidate: LanguageModelSession) -> Bool {
        session === candidate
    }

    func hasStoredSession() -> Bool {
        session != nil
    }

    func isOwnedLoopActive() -> Bool {
        activeOwnedLoop != nil
    }

    private var isSlotBusy: Bool {
        activeOwnedLoop != nil || session?.isResponding == true
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
    ) -> [InferenceMessage] where S.Element == Transcript.Entry {
        var messages: [InferenceMessage] = []
        for entry in entries {
            switch entry {
            case .instructions, .prompt:
                continue
            case let .toolCalls(calls):
                let parsed = calls.map { call in
                    InferenceMessage.ToolCall(
                        id: call.id,
                        name: call.toolName,
                        arguments: FoundationModelsSchemaConversion.argumentDictionary(from: call.arguments)
                    )
                }
                messages.append(.assistant("", toolCalls: parsed))
            case let .toolOutput(output):
                messages.append(
                    .tool(
                        name: output.toolName,
                        content: concatenatedText(output.segments),
                        toolCallID: output.id
                    )
                )
            case let .response(response):
                let text = concatenatedText(response.segments)
                guard !text.isEmpty else { continue }
                messages.append(.assistant(text))
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
    /// Tool schemas bound onto a native `LanguageModelSession` after profile resolution.
    ///
    /// Matches capture-mode ``generateWithToolCalls``: `resolveTurn` first, then
    /// drop every tool when the resolved `toolChoice` is ``ToolChoice/none``.
    func nativeExecutingToolSchemas(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> [ToolSchema] {
        let resolved = resolveTurn(messages: messages, tools: tools, options: options)
        return Self.executingToolSchemas(
            resolvedTools: resolved.tools,
            toolChoice: resolved.options.toolChoice
        )
    }

    /// Selects executing schemas from an already-resolved turn.
    static func executingToolSchemas(
        resolvedTools: [ToolSchema],
        toolChoice: ToolChoice?
    ) -> [ToolSchema] {
        toolChoice == ToolChoice.none ? [] : resolvedTools
    }

    /// Runs a provider-owned tool loop using the call's ``ToolCallExecutor``.
    ///
    /// - Throws: ``AgentError/modelNotAvailable(model:)`` when Apple Intelligence
    ///   is unavailable. Owned-loop adapters do not fall back to capture.
    func completeProviderOwnedToolLoop(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        toolExecutor: ToolCallExecutor
    ) async throws -> InferenceResponse {
        guard Self.isAvailable else {
            throw AgentError.modelNotAvailable(model: "Apple Foundation Models")
        }

        // Resolve before bridging so DynamicProfile toolFilter / toolChoice.none
        // bind onto LanguageModelSession (same order as capture-mode generateWithToolCalls).
        let requestedTools = nativeExecutingToolSchemas(
            messages: messages,
            tools: tools,
            options: options
        )
        let executingTools: [any FoundationModels.Tool]
        if requestedTools.isEmpty {
            executingTools = []
        } else {
            do {
                executingTools = try FoundationModelsToolBridge.makeExecutingTools(
                    from: requestedTools,
                    executor: toolExecutor
                )
            } catch {
                throw AgentError.generationFailed(
                    reason: "Failed to bridge Swarm tools to FoundationModels.Tool: \(error)"
                )
            }
        }

        let native = try await respondUsingNativeSession(
            messages: messages,
            tools: executingTools,
            toolSchemas: requestedTools,
            options: options,
            conversationID: options.conversationId ?? "foundation-models-owned-loop",
            onOutputChunk: nil
        )
        return InferenceResponse(
            content: native.content,
            toolCalls: [],
            finishReason: .completed,
            transcriptMessages: native.transcriptMessages
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
        let boundSchemas = Self.executingToolSchemas(
            resolvedTools: resolved.tools,
            toolChoice: resolved.options.toolChoice
        )
        // Never bind a wider set than the resolved schemas. If the caller omitted
        // schemas, keep the executing tools unless resolved toolChoice is `.none`.
        let boundTools: [any FoundationModels.Tool]
        if resolved.options.toolChoice == ToolChoice.none {
            boundTools = []
        } else if toolSchemas.isEmpty {
            boundTools = tools
        } else {
            let boundNames = Set(boundSchemas.map(\.name))
            boundTools = tools.filter { boundNames.contains($0.name) }
        }
        let identity = FoundationModelsNativeSessionIdentity(
            conversationID: conversationID,
            instructions: resolved.instructions ?? "",
            toolNames: boundTools.map(\.name).sorted()
        )
        let instructions = resolved.instructions
        let store = nativeSessionStore
        let (session, reused, lease) = await store.tryBeginOwnedLoop(matching: identity) {
            self.makeSession(tools: boundTools, instructions: instructions)
        } recreate: { transcript in
            self.makeSession(tools: boundTools, transcript: transcript)
        }

        let prompt: String
        if reused {
            prompt = resolved.messages.last(where: { $0.role == .user })?.content
                ?? resolved.messages.last?.content
                ?? ""
        } else {
            prompt = flattenPrompt(
                messages: resolved.messages,
                tools: boundSchemas,
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
            await store.endOwnedLoop(lease)
            return FoundationModelsNativeTurnResult(
                content: content,
                transcriptMessages: transcriptMessages.isEmpty
                    ? [.assistant(content)]
                    : transcriptMessages
            )
        } catch let request as OwnedLoopHandoffRequest {
            await store.discard(lease)
            throw request
        } catch is CancellationError {
            await store.discard(lease)
            throw AgentError.cancelled
        } catch let error as LanguageModelSession.ToolCallError {
            await store.discard(lease)
            if let native = error.underlyingError as? FoundationModelsNativeToolError {
                throw AgentError.toolFailure(
                    toolName: native.toolName,
                    message: native.message,
                    cause: native.cause ?? native
                )
            }
            if let request = error.underlyingError as? OwnedLoopHandoffRequest {
                throw request
            }
            if error.underlyingError is CancellationError {
                throw AgentError.cancelled
            }
            throw mapError(error)
        } catch let error as FoundationModelsNativeToolError {
            await store.discard(lease)
            throw AgentError.toolFailure(toolName: error.toolName, message: error.message, cause: error.cause ?? error)
        } catch {
            await store.discard(lease)
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
