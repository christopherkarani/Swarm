// FoundationModelsInferenceProvider.swift
// Swarm Framework
//
// First-class Apple Foundation Models inference provider.
//
// This is Swarm's only built-in inference backend. Tool calling uses Apple's
// native `FoundationModels.Tool` protocol and guided generation.

import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Configuration for on-device Apple Foundation Models inference.
public struct FoundationModelsProviderConfiguration: Sendable, Equatable {
    /// Optional system instructions applied to each session.
    public var instructions: String?

    /// When true, prewarms the model after session creation.
    public var prewarmOnInit: Bool

    /// Creates a configuration.
    public init(instructions: String? = nil, prewarmOnInit: Bool = false) {
        self.instructions = instructions
        self.prewarmOnInit = prewarmOnInit
    }

    /// Default configuration with no instructions and no prewarm.
    public static let `default` = FoundationModelsProviderConfiguration()
}

/// On-device inference provider backed by Apple Foundation Models.
///
/// ## Conversation history
///
/// `LanguageModelSession.respond(to:)` accepts a `Prompt`, not a role-tagged
/// message array. **Capture mode** (default) creates a fresh session per request —
/// it does not keep Apple's accumulating `transcript` across Swarm turns — so
/// structured ``InferenceMessage`` history is serialized into that prompt with
/// role labels (`System:`, `User:`, `Assistant:`, `Tool result`).
///
/// **Provider-owned tool loop** (``foundationModelsOwningToolLoop()``) keeps
/// a `LanguageModelSession` for the agent run so Apple's transcript and KV cache
/// can be reused. Memory is injected when that session is created, not on every
/// inner tool iteration. The session is discarded when tools or instructions
/// change, the conversation id changes, generation fails, or the provider is
/// deallocated.
///
/// ## Token usage
///
/// On OS 27, ``InferenceResponse/usage`` comes from
/// `LanguageModelSession.Response.usage` (`input.totalTokenCount` /
/// `output.totalTokenCount`). On OS 26 that field does not exist, so usage
/// stays `nil`. Swarm does not estimate or fabricate token counts.
///
/// ## First-class Apple platform path
///
/// ```swift
/// let agent = try Agent(
///     "Be helpful.",
///     inferenceProvider: .foundationModels()
/// )
/// ```
///
/// ## Tool calling
///
/// Swarm tools are bridged to `FoundationModels.Tool` at request time. The model
/// produces structured arguments via guided generation.
///
/// **Capture mode (default):** capture tools record their arguments into a
/// per-turn store and return a sentinel so Apple can invoke every tool in a
/// parallel group. Swarm recovers **all** calls from the first `ToolCalls`
/// group and executes them in the agent loop with guardrails, observers, and
/// retries intact. Assistant text that accompanied those calls is preserved;
/// sentinel-mediated final text is discarded.
///
/// **Structured outputs:** ``generateStructured`` uses native guided
/// generation (`respond(to:schema:)`) when the JSON Schema maps onto
/// `GenerationSchema`. ``StructuredOutputFormat/jsonObject`` and schemas
/// outside that subset stay prompt-instruction + parse, labeled
/// ``StructuredOutputResult/Source/promptFallback``.
///
/// **Provider-owned tool loop:** construct
/// ``InferenceProvider/foundationModelsOwningToolLoop()``. Agent calls
/// ``generateWithToolCalls(messages:tools:options:toolExecutor:)``; this
/// adapter executes tools inside Apple's session and returns a finished turn.
/// Capture remains ``foundationModels()``.
///
/// ## Dynamic profiles
///
/// Pass a Swarm ``DynamicProfile`` to re-resolve instructions, tool filters,
/// generation overrides, and history policy on every capture turn. That type
/// is **not** Apple's `LanguageModelSession.DynamicProfile` (OS 27). The
/// names overlap; the modules do not. Capture still uses the Swarm model.
/// A later revision can bridge to `LanguageModelSession(profile:)` on OS 27
/// owned-loop without changing `.foundationModels(profile:)` call sites.
///
/// ```swift
/// let mode = ProfileMode(Phase.brainstorm)
/// let profile = ModeSwitchingDynamicProfile(mode: mode) { phase in
///     switch phase {
///     case .brainstorm:
///         Profile(id: "brainstorm", instructions: "Ideate freely.",
///                 generation: .init(temperature: 1.0))
///     case .review:
///         Profile(id: "review", instructions: "Be precise.",
///                 history: .dropToolTranscriptAndKeepLast(count: 12))
///     }
/// }
/// let provider: any InferenceProvider = .foundationModels(profile: profile)
/// ```
///
/// ## Naming note
///
/// Apple's framework and Swarm both define a public type named `Tool`. Prefer
/// module-qualified names (`Swarm.Tool` / `FoundationModels.Tool`) when both
/// modules are imported, or use Swarm's `@Tool` macro / `AnyJSONTool` surface
/// without importing FoundationModels in app code.
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public struct FoundationModelsInferenceProvider: InferenceProvider,
    InferenceProviderMetadata
{
    private let configuration: FoundationModelsProviderConfiguration
    private let dynamicProfile: (any DynamicProfile)?
    private let model: SystemLanguageModel
    private let ownsToolLoop: Bool
    let nativeSessionStore = FoundationModelsNativeSessionStore()

    /// Whether the system language model is currently available on this device.
    public static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Creates a provider when Foundation Models are available; otherwise `nil`.
    public static func ifAvailable(
        configuration: FoundationModelsProviderConfiguration = .default,
        profile: (any DynamicProfile)? = nil,
        ownsToolLoop: Bool = false
    ) -> FoundationModelsInferenceProvider? {
        guard isAvailable else { return nil }
        return FoundationModelsInferenceProvider(
            configuration: configuration,
            profile: profile,
            ownsToolLoop: ownsToolLoop
        )
    }

    /// Creates a Foundation Models provider.
    ///
    /// - Parameters:
    ///   - configuration: Session configuration.
    ///   - profile: Optional dynamic profile resolved every generation turn.
    ///   - ownsToolLoop: When true, this adapter advertises a provider-owned
    ///     tool loop and executes tools via the call's ``ToolCallExecutor``.
    public init(
        configuration: FoundationModelsProviderConfiguration = .default,
        profile: (any DynamicProfile)? = nil,
        ownsToolLoop: Bool = false
    ) {
        self.configuration = configuration
        self.dynamicProfile = profile
        self.model = .default
        self.ownsToolLoop = ownsToolLoop
    }

    // MARK: - Metadata

    public var providerName: String? { "foundationmodels" }
    public var modelName: String? {
        if let profileID = dynamicProfile?.resolve().id, !profileID.isEmpty {
            return "systemLanguageModel/\(profileID)"
        }
        return "systemLanguageModel"
    }
    public var endpointURL: URL? { nil }

    public var capabilities: InferenceProviderCapabilities {
        var capabilities: InferenceProviderCapabilities = [
            .conversationMessages,
            .nativeToolCalling,
            .structuredOutputs,
            .privateInference,
        ]
        if ownsToolLoop {
            capabilities.insert(.providerOwnedToolLoop)
        }
        return capabilities
    }

    // MARK: - InferenceProvider

    public func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await generate(messages: [.user(prompt)], options: options)
    }

    public func stream(
        messages: [InferenceMessage],
        options: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        let resolved = resolveTurn(messages: messages, tools: [], options: options)
        let session = makeSession(tools: [], instructions: resolved.instructions)
        let generationOptions = makeGenerationOptions(from: resolved.options)
        return StreamHelper.makeTrackedStream { continuation in
            let fitted = await PromptEnvelope.enforce(
                messages: resolved.messages,
                profile: envelopeProfile
            )
            let promptText = flattenPrompt(
                messages: fitted,
                tools: [],
                options: resolved.options
            )
            do {
                var previous = ""
                for try await snapshot in session.streamResponse(to: promptText, options: generationOptions) {
                    let current = snapshot.content
                    let delta: String
                    if current.hasPrefix(previous) {
                        delta = String(current.dropFirst(previous.count))
                    } else {
                        delta = current
                    }
                    previous = current
                    if !delta.isEmpty {
                        continuation.yield(delta)
                    }
                }
                continuation.finish()
            } catch is CancellationError {
                throw AgentError.cancelled
            } catch {
                throw mapError(error)
            }
        }
    }

    public func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await generateWithToolCalls(
            messages: [.user(prompt)],
            tools: tools,
            options: options,
            toolExecutor: nil
        )
    }

    // MARK: - Structured message inference

    public func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        let resolved = resolveTurn(messages: messages, tools: [], options: options)
        let generationOptions = makeGenerationOptions(from: resolved.options)
        let turn = try await respondWithContextRecovery(
            messages: resolved.messages,
            tools: [],
            flattenTools: [],
            instructions: resolved.instructions,
            options: resolved.options,
            generationOptions: generationOptions
        )
        return turn.content
    }

    public func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        if ownsToolLoop {
            guard let toolExecutor else {
                throw AgentError.providerOwnedToolLoopRequiresExecutor
            }
            return try await completeProviderOwnedToolLoop(
                messages: messages,
                tools: tools,
                options: options,
                toolExecutor: toolExecutor
            )
        }
        return try await generateWithToolCalls(messages: messages, tools: tools, options: options)
    }

    // No `streamWithToolCalls` override: Foundation Models has no native
    // tool-call stream, so the protocol default's shared finished-turn emitter
    // is used verbatim. Its closure dispatches into
    // `generateWithToolCalls(messages:tools:options:toolExecutor:)` below.

    public func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        if ownsToolLoop {
            throw AgentError.providerOwnedToolLoopRequiresExecutor
        }

        let resolved = resolveTurn(messages: messages, tools: tools, options: options)

        let effectiveTools: [ToolSchema]
        if resolved.options.toolChoice == ToolChoice.none {
            effectiveTools = []
        } else {
            effectiveTools = resolved.tools
        }

        if effectiveTools.isEmpty {
            let generationOptions = makeGenerationOptions(from: resolved.options)
            let turn = try await respondWithContextRecovery(
                messages: resolved.messages,
                tools: [],
                flattenTools: [],
                instructions: resolved.instructions,
                options: resolved.options,
                generationOptions: generationOptions
            )
            return InferenceResponse(
                content: turn.content,
                toolCalls: [],
                finishReason: .completed,
                usage: turn.usage
            )
        }

        let store = FoundationModelsToolCaptureStore()
        let fmTools: [any FoundationModels.Tool]
        do {
            fmTools = try FoundationModelsToolBridge.makeCaptureTools(from: effectiveTools, store: store)
        } catch {
            throw AgentError.generationFailed(
                reason: "Failed to bridge Swarm tools to FoundationModels.Tool: \(error)"
            )
        }

        let fitted = await PromptEnvelope.enforce(
            messages: resolved.messages,
            profile: envelopeProfile
        )
        let session = makeSession(tools: fmTools, instructions: resolved.instructions)
        let prompt = flattenPrompt(
            messages: fitted,
            tools: effectiveTools,
            options: resolved.options
        )
        let generationOptions = makeGenerationOptions(from: resolved.options)
        let startCount = session.transcript.count

        do {
            let response = try await session.respond(to: prompt, options: generationOptions)
            let turnEntries = Array(session.transcript.dropFirst(startCount))
            if let captured = await FoundationModelsToolBridge.inferenceResponse(
                store: store,
                turnEntries: turnEntries
            ) {
                return captured.withUsage(FoundationModelsUsageMapping.tokenUsage(from: response))
            }
            let content = applyStopSequences(response.content, options: resolved.options)
            return InferenceResponse(
                content: content,
                toolCalls: [],
                finishReason: .completed,
                usage: FoundationModelsUsageMapping.tokenUsage(from: response)
            )
        } catch {
            let turnEntries = Array(session.transcript.dropFirst(startCount))
            if let captured = await FoundationModelsToolBridge.inferenceResponse(
                store: store,
                turnEntries: turnEntries,
                error: error
            ) {
                return captured
            }
            if FoundationModelsContextOverflow.matches(error) {
                let retryMessages = await PromptEnvelope.enforce(
                    messages: PromptEnvelope.compactForRetry(fitted),
                    profile: envelopeProfile
                )
                let retrySession = makeSession(tools: fmTools, instructions: resolved.instructions)
                let retryPrompt = flattenPrompt(
                    messages: retryMessages,
                    tools: effectiveTools,
                    options: resolved.options
                )
                do {
                    let response = try await retrySession.respond(to: retryPrompt, options: generationOptions)
                    let retryEntries = Array(retrySession.transcript.dropFirst(0))
                    if let captured = await FoundationModelsToolBridge.inferenceResponse(
                        store: store,
                        turnEntries: retryEntries
                    ) {
                        return captured.withUsage(FoundationModelsUsageMapping.tokenUsage(from: response))
                    }
                    let content = applyStopSequences(response.content, options: resolved.options)
                    return InferenceResponse(
                        content: content,
                        toolCalls: [],
                        finishReason: .completed,
                        usage: FoundationModelsUsageMapping.tokenUsage(from: response)
                    )
                } catch {
                    throw mapError(error)
                }
            }
            throw mapError(error)
        }
    }

    // MARK: - Structured output

    public func generateStructured(
        prompt: String,
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await generateStructured(messages: [.user(prompt)], request: request, options: options)
    }

    public func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        let resolved = resolveTurn(messages: messages, tools: [], options: options)
        switch FoundationModelsStructuredSchemaMapping.evaluate(request) {
        case let .mapped(mapped):
            do {
                let schema = try FoundationModelsSchemaConversion.generationSchema(from: mapped)
                var promptOptions = resolved.options
                promptOptions.structuredOutput = nil
                let prompt = flattenPrompt(
                    messages: resolved.messages,
                    tools: [],
                    options: promptOptions
                )
                let session = makeSession(tools: [], instructions: resolved.instructions)
                let generationOptions = makeGenerationOptions(from: resolved.options)
                let response = try await session.respond(
                    to: prompt,
                    schema: schema,
                    includeSchemaInPrompt: true,
                    options: generationOptions
                )
                return StructuredOutputResult(
                    format: request.format,
                    rawJSON: response.content.jsonString,
                    value: FoundationModelsSchemaConversion.sendableValue(from: response.content),
                    source: .providerNative
                )
            } catch is GenerationSchema.SchemaError {
                return try await generateStructuredPromptFallback(
                    messages: messages,
                    request: request,
                    options: options
                )
            } catch {
                throw mapError(error)
            }
        case .unsupported:
            return try await generateStructuredPromptFallback(
                messages: messages,
                request: request,
                options: options
            )
        }
    }

    private func generateStructuredPromptFallback(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        var structuredOptions = options
        structuredOptions.structuredOutput = request
        let text = try await generate(messages: messages, options: structuredOptions)
        return try StructuredOutputParser.parse(text, request: request, source: .promptFallback)
    }

    // MARK: - Session helpers

    func resolveTurn(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> (
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        instructions: String?
    ) {
        let active = dynamicProfile?.resolve()
        let applied = DynamicProfileResolution.apply(
            active,
            messages: messages,
            tools: tools,
            options: options,
            baseInstructions: configuration.instructions
        )
        let withSystem = DynamicProfileResolution.messagesByInjectingInstructions(
            applied.instructions,
            into: applied.messages
        )
        return (withSystem, applied.tools, applied.options, applied.instructions)
    }

    var envelopeProfile: ContextProfile {
        FoundationModelsContextBudget.profile(contextSize: model.contextSize)
    }

    func respondWithContextRecovery(
        messages: [InferenceMessage],
        tools: [any FoundationModels.Tool],
        flattenTools: [ToolSchema],
        instructions: String?,
        options: InferenceOptions,
        generationOptions: GenerationOptions
    ) async throws -> (content: String, usage: TokenUsage?) {
        let fitted = await PromptEnvelope.enforce(messages: messages, profile: envelopeProfile)
        do {
            return try await respondOnce(
                messages: fitted,
                tools: tools,
                flattenTools: flattenTools,
                instructions: instructions,
                options: options,
                generationOptions: generationOptions
            )
        } catch {
            guard FoundationModelsContextOverflow.matches(error) else {
                throw mapError(error)
            }
            let retry = await PromptEnvelope.enforce(
                messages: PromptEnvelope.compactForRetry(fitted),
                profile: envelopeProfile
            )
            do {
                return try await respondOnce(
                    messages: retry,
                    tools: tools,
                    flattenTools: flattenTools,
                    instructions: instructions,
                    options: options,
                    generationOptions: generationOptions
                )
            } catch {
                throw mapError(error)
            }
        }
    }

    func respondOnce(
        messages: [InferenceMessage],
        tools: [any FoundationModels.Tool],
        flattenTools: [ToolSchema],
        instructions: String?,
        options: InferenceOptions,
        generationOptions: GenerationOptions
    ) async throws -> (content: String, usage: TokenUsage?) {
        let session = makeSession(tools: tools, instructions: instructions)
        let prompt = flattenPrompt(
            messages: messages,
            tools: flattenTools,
            options: options
        )
        let response = try await session.respond(to: prompt, options: generationOptions)
        return (
            applyStopSequences(response.content, options: options),
            FoundationModelsUsageMapping.tokenUsage(from: response)
        )
    }

    func makeSession(
        tools: [any FoundationModels.Tool],
        instructions: String?
    ) -> LanguageModelSession {
        let session: LanguageModelSession
        if let instructions, !instructions.isEmpty {
            session = LanguageModelSession(
                model: model,
                tools: tools,
                instructions: instructions
            )
        } else {
            session = LanguageModelSession(model: model, tools: tools)
        }

        if configuration.prewarmOnInit {
            session.prewarm(promptPrefix: nil)
        }
        return session
    }

    func makeSession(
        tools: [any FoundationModels.Tool],
        transcript: Transcript
    ) -> LanguageModelSession {
        let session = LanguageModelSession(model: model, tools: tools, transcript: transcript)
        if configuration.prewarmOnInit {
            session.prewarm(promptPrefix: nil)
        }
        return session
    }

    func makeGenerationOptions(from options: InferenceOptions) -> GenerationOptions {
        FoundationModelsGenerationOptions.make(from: options)
    }

    /// Serializes structured history into a single `Prompt` string.
    ///
    /// Required because `LanguageModelSession.respond(to:)` / `streamResponse(to:)`
    /// take a `Prompt`, and capture mode is session-less (a new
    /// `LanguageModelSession` per call cannot reuse Apple's transcript).
    func flattenPrompt(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> String {
        FoundationModelsPromptFlattening.flatten(
            messages: messages,
            tools: tools,
            options: options
        )
    }

    func applyStopSequences(_ content: String, options: InferenceOptions) -> String {
        var result = content
        var earliestStop: String.Index?
        for stopSequence in options.stopSequences {
            if let range = result.range(of: stopSequence) {
                if earliestStop == nil || range.lowerBound < earliestStop! {
                    earliestStop = range.lowerBound
                }
            }
        }
        if let stop = earliestStop {
            result = String(result[..<stop])
        }
        return result
    }

    func mapError(_ error: Error) -> AgentError {
        FoundationModelsErrorMapping.map(error)
    }
}

extension InferenceResponse {
    fileprivate func withUsage(_ usage: TokenUsage?) -> InferenceResponse {
        guard let usage else { return self }
        return InferenceResponse(
            content: content,
            toolCalls: toolCalls,
            finishReason: finishReason,
            usage: self.usage ?? usage,
            transcriptMessages: transcriptMessages
        )
    }
}

// MARK: - Dot-syntax entry points

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public extension InferenceProvider where Self == FoundationModelsInferenceProvider {
    /// Creates an on-device Apple Foundation Models provider.
    ///
    /// Prefer this for macOS/iOS apps that want first-class Apple Intelligence
    /// integration. For custom backends, inject any ``InferenceProvider``.
    static func foundationModels(
        configuration: FoundationModelsProviderConfiguration = .default
    ) -> FoundationModelsInferenceProvider {
        FoundationModelsInferenceProvider(configuration: configuration)
    }

    /// Creates an on-device adapter that owns the tool loop.
    ///
    /// Agent supplies a ``ToolCallExecutor`` on each tool-calling call and
    /// does not iterate. Capture remains ``foundationModels()``.
    static func foundationModelsOwningToolLoop(
        configuration: FoundationModelsProviderConfiguration = .default
    ) -> FoundationModelsInferenceProvider {
        FoundationModelsInferenceProvider(configuration: configuration, ownsToolLoop: true)
    }

    /// Creates an on-device Apple Foundation Models provider with instructions.
    static func foundationModels(
        instructions: String,
        prewarmOnInit: Bool = false
    ) -> FoundationModelsInferenceProvider {
        FoundationModelsInferenceProvider(
            configuration: FoundationModelsProviderConfiguration(
                instructions: instructions,
                prewarmOnInit: prewarmOnInit
            )
        )
    }

    /// Creates an on-device adapter that owns the tool loop, with instructions.
    static func foundationModelsOwningToolLoop(
        instructions: String,
        prewarmOnInit: Bool = false
    ) -> FoundationModelsInferenceProvider {
        FoundationModelsInferenceProvider(
            configuration: FoundationModelsProviderConfiguration(
                instructions: instructions,
                prewarmOnInit: prewarmOnInit
            ),
            ownsToolLoop: true
        )
    }

    /// Creates an on-device provider driven by a Swarm ``DynamicProfile``.
    ///
    /// The profile is re-resolved every generation turn (instructions, tools,
    /// generation overrides, history policy).
    static func foundationModels(
        profile: some DynamicProfile,
        configuration: FoundationModelsProviderConfiguration = .default
    ) -> FoundationModelsInferenceProvider {
        FoundationModelsInferenceProvider(
            configuration: configuration,
            profile: profile
        )
    }

    /// Creates an on-device owned-loop adapter driven by a Swarm ``DynamicProfile``.
    static func foundationModelsOwningToolLoop(
        profile: some DynamicProfile,
        configuration: FoundationModelsProviderConfiguration = .default
    ) -> FoundationModelsInferenceProvider {
        FoundationModelsInferenceProvider(
            configuration: configuration,
            profile: profile,
            ownsToolLoop: true
        )
    }
}

#else

/// Stub configuration when FoundationModels is unavailable (e.g. Linux CI).
public struct FoundationModelsProviderConfiguration: Sendable, Equatable {
    public var instructions: String?
    public var prewarmOnInit: Bool

    public init(instructions: String? = nil, prewarmOnInit: Bool = false) {
        self.instructions = instructions
        self.prewarmOnInit = prewarmOnInit
    }

    public static let `default` = FoundationModelsProviderConfiguration()
}

#endif
