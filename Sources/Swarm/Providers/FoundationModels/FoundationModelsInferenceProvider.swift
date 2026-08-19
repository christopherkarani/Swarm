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
/// **Native session mode** (``FoundationModelsExecutionMode/nativeSession``) keeps
/// a `LanguageModelSession` for the agent run so Apple's transcript and KV cache
/// can be reused. Memory is injected when that session is created, not on every
/// inner tool iteration. See ``FoundationModelsExecutionMode`` for the trade-off
/// table. The session is discarded when tools or instructions change, the
/// conversation id changes, generation fails, or the provider is deallocated.
///
/// ## Token usage
///
/// Apple's Foundation Models SDK does not expose token-count APIs on
/// `LanguageModelSession.Response` in the macOS 26.x SDK this package targets.
/// ``InferenceResponse/usage`` and ``AgentResult/tokenUsage`` remain `nil`.
/// Swarm does not estimate or fabricate token counts for this provider.
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
/// **Native session mode (experimental):** a provider-owned tool loop.
/// Agent calls ``generateWithToolCalls(messages:tools:options:)``; this adapter
/// executes tools inside Apple's session and returns a finished turn. Opt in
/// with ``InferenceProvider/foundationModelsOwningToolLoop()``.
///
/// ## Dynamic profiles
///
/// Pass a ``DynamicProfile`` to re-resolve instructions, tool filters, generation
/// overrides, and history policy on every turn (Apple WWDC 2026 semantics).
/// Native `LanguageModelSession.DynamicProfile` is not in the macOS 26.2 SDK yet;
/// Swarm's profile model works today and is designed to bridge when Apple ships it.
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
    InferenceProviderMetadata,
    StructuredOutputInferenceProvider
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

    public func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        let resolved = resolveTurn(messages: [.user(prompt)], tools: [], options: options)
        let session = makeSession(tools: [], instructions: resolved.instructions)
        let generationOptions = makeGenerationOptions(from: resolved.options)
        let promptText = flattenPrompt(
            messages: resolved.messages,
            tools: [],
            options: resolved.options
        )
        return StreamHelper.makeTrackedStream { continuation in
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

    // MARK: - ConversationInferenceProvider

    public func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        let resolved = resolveTurn(messages: messages, tools: [], options: options)
        let session = makeSession(tools: [], instructions: resolved.instructions)
        let generationOptions = makeGenerationOptions(from: resolved.options)
        let prompt = flattenPrompt(
            messages: resolved.messages,
            tools: [],
            options: resolved.options
        )
        do {
            let response = try await session.respond(to: prompt, options: generationOptions)
            return applyStopSequences(response.content, options: resolved.options)
        } catch {
            throw mapError(error)
        }
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
            if let finished = try await completeProviderOwnedToolLoopIfRequested(
                messages: messages,
                tools: tools,
                options: options,
                toolExecutor: toolExecutor
            ) {
                return finished
            }
        }
        return try await generateWithToolCalls(messages: messages, tools: tools, options: options)
    }

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
            let session = makeSession(tools: [], instructions: resolved.instructions)
            let generationOptions = makeGenerationOptions(from: resolved.options)
            let prompt = flattenPrompt(
                messages: resolved.messages,
                tools: [],
                options: resolved.options
            )
            do {
                let response = try await session.respond(to: prompt, options: generationOptions)
                let content = applyStopSequences(response.content, options: resolved.options)
                return InferenceResponse(content: content, toolCalls: [], finishReason: .completed)
            } catch {
                throw mapError(error)
            }
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

        let session = makeSession(tools: fmTools, instructions: resolved.instructions)
        let prompt = flattenPrompt(
            messages: resolved.messages,
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
                return captured
            }
            let content = applyStopSequences(response.content, options: resolved.options)
            return InferenceResponse(
                content: content,
                toolCalls: [],
                finishReason: .completed
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
        var generationOptions = GenerationOptions()
        generationOptions.temperature = options.temperature
        if let maxTokens = options.maxTokens {
            generationOptions.maximumResponseTokens = maxTokens
        }
        if options.temperature == 0 {
            generationOptions.sampling = .greedy
        } else if let topP = options.topP, topP > 0, topP <= 1 {
            generationOptions.sampling = .random(probabilityThreshold: topP)
        }
        return generationOptions
    }

    /// Serializes structured history into a single `Prompt` string.
    ///
    /// Required because `LanguageModelSession.respond(to:)` / `streamResponse(to:)`
    /// take a `Prompt`, and this provider is session-less (a new
    /// `LanguageModelSession` per call cannot reuse Apple's transcript).
    func flattenPrompt(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> String {
        var lines: [String] = []
        lines.reserveCapacity(messages.count)

        for message in messages {
            switch message.role {
            case .system:
                guard !message.content.isEmpty else { continue }
                lines.append("System: \(message.content)")
            case .user:
                guard !message.content.isEmpty else { continue }
                lines.append("User: \(message.content)")
            case .assistant:
                if !message.toolCalls.isEmpty {
                    lines.append("Assistant requested tool calls:")
                    for call in message.toolCalls {
                        lines.append("- \(call.name)(\(encodeArguments(call.arguments)))")
                    }
                }
                if !message.content.isEmpty {
                    lines.append("Assistant: \(message.content)")
                }
            case .tool:
                let prefix = message.name.map { "Tool result (\($0))" } ?? "Tool result"
                if let callID = message.toolCallID, !callID.isEmpty {
                    lines.append("\(prefix) [id=\(callID)]: \(message.content)")
                } else {
                    lines.append("\(prefix): \(message.content)")
                }
            }
        }

        var prompt = lines.joined(separator: "\n")

        // Light guidance so the model prefers tools when required.
        // WWDC 2026 adds GenerationOptions.toolCallingMode; the shipped macOS 26.x
        // SDK used here does not yet expose that knob, so we guide via prompt text.
        if !tools.isEmpty {
            switch options.toolChoice {
            case .required:
                prompt += "\n\nYou must call one of the available tools before answering."
            case let .specific(toolName):
                prompt += "\n\nIf you need a tool, call \"\(toolName)\"."
            case .auto, ToolChoice.none?, nil:
                break
            }
        }

        if let structuredOutput = options.structuredOutput {
            prompt = StructuredOutputPromptBuilder.appendInstruction(to: prompt, request: structuredOutput)
        }

        return prompt
    }

    private func encodeArguments(_ arguments: [String: SendableValue]) -> String {
        var object: [String: Any] = [:]
        for (key, value) in arguments {
            object[key] = value.toJSONObject()
        }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
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
        if error is CancellationError {
            return .cancelled
        }
        if let generationError = error as? LanguageModelSession.GenerationError {
            switch generationError {
            case .rateLimited:
                return .generationFailed(reason: "Foundation Models rate limited the request.")
            case .refusal:
                return .generationFailed(reason: "Foundation Models refused the request.")
            case .unsupportedLanguageOrLocale:
                return .generationFailed(reason: "Foundation Models does not support this language or locale.")
            case .concurrentRequests:
                return .generationFailed(reason: "Foundation Models does not allow concurrent requests on one session.")
            default:
                return .generationFailed(reason: generationError.localizedDescription)
            }
        }
        return .generationFailed(reason: String(describing: error))
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
