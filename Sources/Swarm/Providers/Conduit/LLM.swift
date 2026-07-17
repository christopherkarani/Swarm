import Conduit
import Foundation

/// Opinionated, beginner-friendly inference presets backed by Conduit.
///
/// Use with any API that accepts an `InferenceProvider`:
/// ```swift
/// let agent = Agent("...", provider: .openAI(key: "..."))
/// ```
///
/// Advanced customization is available via `.ollama("model") { $0.port = 11435 }`.
public struct LLM: Sendable, InferenceProvider {
    // MARK: - Private Storage

    private let kind: Kind

    private static func anthropicModelID(_ model: String) -> AnthropicProvider.ModelID {
        .anthropic(model)
    }

    private static func openAIModelID(_ model: String) -> OpenAIProvider.ModelID {
        .openAI(model)
    }

    private enum Kind: Sendable {
        case openAI(OpenAIConfig)
        case anthropic(AnthropicConfig)
        case openRouter(OpenRouterConfig)
        case minimax(MiniMaxConfig)
        case ollama(OllamaConfig)
#if canImport(MLX)
        case mlx(MLXConfig)
#endif
    }

#if canImport(MLX)
    private enum MLXConfig: Sendable {
        case mlx(String)
        case mlxLocal(String)
    }
#endif

    private init(kind: Kind) {
        self.kind = kind
    }

    // MARK: - Presets

    public static func openAI(
        apiKey: String,
        model: String = "gpt-4o-mini"
    ) -> LLM {
        LLM(kind: .openAI(OpenAIConfig(apiKey: apiKey, model: model)))
    }

    public static func openAI(
        key: String,
        model: String = "gpt-4o-mini"
    ) -> LLM {
        openAI(apiKey: key, model: model)
    }

    public static func anthropic(
        apiKey: String,
        model: String = "claude-3-5-sonnet-20241022"
    ) -> LLM {
        LLM(kind: .anthropic(AnthropicConfig(apiKey: apiKey, model: model)))
    }

    public static func anthropic(
        key: String,
        model: String = "claude-3-5-sonnet-20241022"
    ) -> LLM {
        anthropic(apiKey: key, model: model)
    }

    public static func openRouter(
        apiKey: String,
        model: String = "anthropic/claude-3.5-sonnet"
    ) -> LLM {
        LLM(kind: .openRouter(OpenRouterConfig(apiKey: apiKey, model: model)))
    }

    public static func openRouter(
        key: String,
        model: String = "anthropic/claude-3.5-sonnet"
    ) -> LLM {
        openRouter(apiKey: key, model: model)
    }

    /// Creates a MiniMax-backed `LLM` provider via OpenRouter.
    ///
    /// MiniMax models are routed through OpenRouter using the `minimax/<model>` namespace.
    /// The `apiKey` should be your OpenRouter API key.
    ///
    /// - Parameters:
    ///   - apiKey: Your OpenRouter API key.
    ///   - model: The MiniMax model identifier, e.g. `"minimax-01"`.
    ///     This is automatically prefixed with `"minimax/"` when needed.
    public static func minimax(
        apiKey: String,
        model: String = "minimax-01"
    ) -> LLM {
        LLM(kind: .minimax(MiniMaxConfig(apiKey: apiKey, model: model)))
    }

    public static func minimax(
        key: String,
        model: String = "minimax-01"
    ) -> LLM {
        minimax(apiKey: key, model: model)
    }

    /// Creates an Ollama-backed `LLM` provider for local inference.
    ///
    /// - Parameters:
    ///   - model: The Ollama model name (e.g. `"llama3.2"`, `"mistral"`, `"codellama"`).
    ///   - configure: Optional closure to customize Ollama connection settings.
    ///
    /// ```swift
    /// // Simple usage
    /// let llm = LLM.ollama("mistral")
    ///
    /// // With configuration
    /// let llm = LLM.ollama("mistral") { settings in
    ///     settings.host = "127.0.0.1"
    ///     settings.port = 11435
    /// }
    /// ```
    public static func ollama(
        _ model: String,
        configure: ((inout OllamaSettings) -> Void)? = nil
    ) -> LLM {
        var settings = OllamaSettings.default
        configure?(&settings)
        return LLM(kind: .ollama(OllamaConfig(model: model, settings: settings)))
    }

    /// Creates an OpenRouter-backed `LLM` provider with routing configuration.
    ///
    /// - Parameters:
    ///   - apiKey: Your OpenRouter API key.
    ///   - model: The model identifier (e.g. `"anthropic/claude-3.5-sonnet"`).
    ///   - configure: Closure to customize OpenRouter routing preferences.
    ///
    /// ```swift
    /// let llm = LLM.openRouter(apiKey: key, model: "anthropic/claude-3.5-sonnet") { routing in
    ///     routing.providers = [.anthropic]
    /// }
    /// ```
    public static func openRouter(
        apiKey: String,
        model: String = "anthropic/claude-3.5-sonnet",
        configure: (inout OpenRouterRouting) -> Void
    ) -> LLM {
        var routing = OpenRouterRouting()
        configure(&routing)
        var config = OpenRouterConfig(apiKey: apiKey, model: model)
        config.advanced.openRouter.routing = routing
        return LLM(kind: .openRouter(config))
    }

#if canImport(MLX)
    /// Creates an MLX-backed `LLM` provider for local inference.
    ///
    /// - Parameter model: The MLX model identifier (for example, `"mlx-community/Llama-3.2-1B-Instruct-4bit"`).
    public static func mlx(_ model: String) -> LLM {
        LLM(kind: .mlx(.mlx(model)))
    }

    /// Creates an MLX-backed `LLM` provider for a local filesystem model.
    ///
    /// - Parameter path: The filesystem path to the MLX model directory.
    public static func mlxLocal(_ path: String) -> LLM {
        LLM(kind: .mlx(.mlxLocal(path)))
    }
#endif

    // MARK: - InferenceProvider

    public func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await makeProvider().generate(prompt: prompt, options: options)
    }

    public func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        makeProvider().stream(prompt: prompt, options: options)
    }

    public func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await makeProvider().generateWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    // MARK: - Internals

    private func makeProvider() -> any InferenceProvider {
        switch kind {
        case let .openAI(config):
            let provider = OpenAIProvider(apiKey: config.apiKey)
            let modelID = Self.openAIModelID(config.model)
            return ConduitInferenceProvider(
                provider: provider,
                model: modelID,
                baseConfig: config.advanced.baseConfig
            )
        case let .anthropic(config):
            let provider = AnthropicProvider(apiKey: config.apiKey)
            let modelID = Self.anthropicModelID(config.model)
            return ConduitInferenceProvider(
                provider: provider,
                model: modelID,
                baseConfig: config.advanced.baseConfig
            )
        case let .openRouter(config):
            let provider = openRouterProvider(apiKey: config.apiKey, routing: config.advanced.openRouter.routing)
            let modelID = Self.openAIModelID(config.model)
            return ConduitInferenceProvider(
                provider: provider,
                model: modelID,
                baseConfig: config.advanced.baseConfig
            )
        case let .minimax(config):
            #if CONDUIT_TRAIT_MINIMAX
                let provider = MiniMaxProvider(apiKey: config.apiKey)
                let modelID: MiniMaxProvider.ModelID = .init(config.model)
                return ConduitInferenceProvider(
                    provider: provider,
                    model: modelID,
                    baseConfig: config.advanced.baseConfig
                )
            #else
                let routedModel = config.model.hasPrefix("minimax/") ? config.model : "minimax/\(config.model)"
                let provider = OpenAIProvider(openRouterKey: config.apiKey)
                let modelID = Self.openAIModelID(routedModel)
                return ConduitInferenceProvider(
                    provider: provider,
                    model: modelID,
                    baseConfig: config.advanced.baseConfig
                )
            #endif
        case let .ollama(config):
            let provider = ollamaProvider(settings: config.settings)
            let modelID = Self.openAIModelID(config.model)
            return ConduitInferenceProvider(provider: provider, model: modelID)
#if canImport(MLX)
        case let .mlx(config):
            let model: Model = switch config {
            case let .mlx(model):
                .mlx(model)
            case let .mlxLocal(path):
                .mlxLocal(path)
            }
            return makeMLXInferenceProvider(model: model)
#endif
        }
    }

    private func openRouterProvider(
        apiKey: String,
        routing: OpenRouterRouting?
    ) -> OpenAIProvider {
        guard let routing else {
            return OpenAIProvider(openRouterKey: apiKey)
        }

        return OpenAIProvider(openRouterKey: apiKey, routing: routing.toConduit())
    }

    private func ollamaProvider(settings: OllamaSettings) -> OpenAIProvider {
        OpenAIProvider(
            ollamaHost: settings.host,
            port: settings.port,
            ollamaConfig: settings.toConduit()
        )
    }

    private var usesPrivateInference: Bool {
        switch kind {
        case .ollama:
            true
#if canImport(MLX)
        case .mlx:
            true
#endif
        default:
            false
        }
    }
}

extension LLM: InferenceProviderMetadata {
    public var providerName: String? {
        switch kind {
        case .openAI:
            "openai"
        case .anthropic:
            "anthropic"
        case .openRouter:
            "openrouter"
        case .minimax:
            "minimax"
        case .ollama:
            "ollama"
#if canImport(MLX)
        case .mlx:
            "mlx"
#endif
        }
    }

    public var modelName: String? {
        switch kind {
        case let .openAI(config):
            config.model
        case let .anthropic(config):
            config.model
        case let .openRouter(config):
            config.model
        case let .minimax(config):
            config.model
        case let .ollama(config):
            config.model
#if canImport(MLX)
        case let .mlx(config):
            switch config {
            case let .mlx(model):
                model
            case let .mlxLocal(path):
                path
            }
#endif
        }
    }

    public var endpointURL: URL? {
        switch kind {
        case .openAI:
            URL(string: "https://api.openai.com/v1")
        case .anthropic:
            URL(string: "https://api.anthropic.com")
        case .openRouter, .minimax:
            URL(string: "https://openrouter.ai/api/v1")
        case let .ollama(config):
            URL(string: "http://\(config.settings.host):\(config.settings.port)")
#if canImport(MLX)
        case .mlx:
            nil
#endif
        }
    }
}

#if DEBUG
extension LLM {
    // Test hook: keep Conduit types out of the public API, but allow the package's
    // unit tests to validate that presets are backed by Conduit providers.
    func _makeProviderForTesting() -> any InferenceProvider {
        makeProvider()
    }
}
#endif

extension LLM: ToolCallStreamingInferenceProvider {
    public func streamWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        let provider = makeProvider()
        guard let streaming = provider as? any ToolCallStreamingInferenceProvider else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: AgentError.generationFailed(reason: "Provider does not support tool-call streaming"))
            }
        }
        return streaming.streamWithToolCalls(prompt: prompt, tools: tools, options: options)
    }
}

extension LLM: CapabilityReportingInferenceProvider {
    public var capabilities: InferenceProviderCapabilities {
        var capabilities = InferenceProviderCapabilities.resolved(for: makeProvider())
        capabilities.insert(.conversationMessages)
        if usesPrivateInference {
            capabilities.insert(.privateInference)
        }
        return capabilities
    }
}

extension LLM: ConversationInferenceProvider {
    public func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        let provider = makeProvider()
        if let conversationProvider = provider as? any ConversationInferenceProvider {
            return try await conversationProvider.generate(messages: messages, options: options)
        }
        return try await provider.generate(prompt: InferenceMessage.flattenPrompt(messages), options: options)
    }

    public func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        let provider = makeProvider()
        if let conversationProvider = provider as? any ConversationInferenceProvider {
            return try await conversationProvider.generateWithToolCalls(
                messages: messages,
                tools: tools,
                options: options
            )
        }
        return try await provider.generateWithToolCalls(
            prompt: InferenceMessage.flattenPrompt(messages),
            tools: tools,
            options: options
        )
    }
}

extension LLM: StreamingConversationInferenceProvider {
    public func stream(
        messages: [InferenceMessage],
        options: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        let provider = makeProvider()
        if let conversationProvider = provider as? any StreamingConversationInferenceProvider {
            return conversationProvider.stream(messages: messages, options: options)
        }
        return provider.stream(prompt: InferenceMessage.flattenPrompt(messages), options: options)
    }
}

extension LLM: ToolCallStreamingConversationInferenceProvider {
    public func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        let provider = makeProvider()
        if let conversationProvider = provider as? any ToolCallStreamingConversationInferenceProvider {
            return conversationProvider.streamWithToolCalls(messages: messages, tools: tools, options: options)
        }
        guard let promptProvider = provider as? any ToolCallStreamingInferenceProvider else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: AgentError.generationFailed(reason: "Provider does not support tool-call streaming"))
            }
        }
        return promptProvider.streamWithToolCalls(
            prompt: InferenceMessage.flattenPrompt(messages),
            tools: tools,
            options: options
        )
    }
}

// MARK: - Dot-syntax Entry Points

/// Beginner-friendly `key:` aliases on `LLM`.
///
/// Prefer ``ConduitProviderSelection`` factories via `.anthropic(apiKey:)` /
/// `.openAI(apiKey:)` when assigning to `inferenceProvider:` — those are the
/// unambiguous, canonical spellings. The `apiKey:` overloads that previously
/// lived here were removed because they collided with
/// `InferenceProvider where Self == ConduitProviderSelection` and made
/// `Agent(..., inferenceProvider: .anthropic(apiKey:))` fail to type-check.
public extension InferenceProvider where Self == LLM {
    static func openAI(key: String, model: String = "gpt-4o-mini") -> LLM {
        LLM.openAI(key: key, model: model)
    }

    static func anthropic(key: String, model: String = "claude-3-5-sonnet-20241022") -> LLM {
        LLM.anthropic(key: key, model: model)
    }

    static func openRouter(key: String, model: String = "anthropic/claude-3.5-sonnet") -> LLM {
        LLM.openRouter(key: key, model: model)
    }

    static func minimax(key: String, model: String = "minimax-01") -> LLM {
        LLM.minimax(key: key, model: model)
    }

    /// Creates an Ollama-backed `LLM` provider for local inference.
    ///
    /// - Parameters:
    ///   - model: The Ollama model name (e.g. `"llama3.2"`, `"mistral"`, `"codellama"`).
    ///   - configure: Optional closure to customize Ollama connection settings.
    ///
    /// ```swift
    /// // Simple usage
    /// let llm: some InferenceProvider = .ollama("mistral")
    ///
    /// // With configuration
    /// let llm: some InferenceProvider = .ollama("mistral") { settings in
    ///     settings.host = "127.0.0.1"
    ///     settings.port = 11435
    /// }
    /// ```
    static func ollama(
        _ model: String,
        configure: ((inout OllamaSettings) -> Void)? = nil
    ) -> LLM {
        LLM.ollama(model, configure: configure)
    }

    /// Creates an OpenRouter-backed `LLM` provider with routing configuration.
    ///
    /// - Parameters:
    ///   - apiKey: Your OpenRouter API key.
    ///   - model: The model identifier (e.g. `"anthropic/claude-3.5-sonnet"`).
    ///   - configure: Closure to customize OpenRouter routing preferences.
    ///
    /// ```swift
    /// let llm: some InferenceProvider = .openRouter(apiKey: key, model: "anthropic/claude-3.5-sonnet") { routing in
    ///     routing.providers = [.anthropic]
    /// }
    /// ```
    static func openRouter(
        apiKey: String,
        model: String = "anthropic/claude-3.5-sonnet",
        configure: (inout OpenRouterRouting) -> Void
    ) -> LLM {
        LLM.openRouter(apiKey: apiKey, model: model, configure: configure)
    }
}

// MARK: - Configuration Types (Internal)

extension LLM {
    struct OpenAIConfig: Sendable {
        var apiKey: String
        var model: String
        var advanced: AdvancedOptions = .default

        init(apiKey: String, model: String) {
            self.apiKey = apiKey
            self.model = model
        }
    }

    struct AnthropicConfig: Sendable {
        var apiKey: String
        var model: String
        var advanced: AdvancedOptions = .default

        init(apiKey: String, model: String) {
            self.apiKey = apiKey
            self.model = model
        }
    }

    struct OpenRouterConfig: Sendable {
        var apiKey: String
        var model: String
        var advanced: AdvancedOptions = .default

        init(apiKey: String, model: String) {
            self.apiKey = apiKey
            self.model = model
        }
    }

    struct MiniMaxConfig: Sendable {
        var apiKey: String
        var model: String
        var advanced: AdvancedOptions = .default

        init(apiKey: String, model: String) {
            self.apiKey = apiKey
            self.model = model
        }
    }

    struct AdvancedOptions: Sendable {
        static let `default` = AdvancedOptions()

        /// Baseline Conduit generation configuration (internal — not part of the public API).
        var baseConfig: GenerateConfig

        var openRouter: OpenRouterOptions

        init(openRouter: OpenRouterOptions = .default) {
            self.baseConfig = .default
            self.openRouter = openRouter
        }

        init(baseConfig: GenerateConfig, openRouter: OpenRouterOptions = .default) {
            self.baseConfig = baseConfig
            self.openRouter = openRouter
        }
    }

    struct OpenRouterOptions: Sendable {
        static let `default` = OpenRouterOptions()

        var routing: OpenRouterRouting?

        init(routing: OpenRouterRouting? = nil) {
            self.routing = routing
        }
    }

    /// Ollama configuration for local inference.
    struct OllamaConfig: Sendable {
        /// The Ollama model name (e.g. `"llama3.2"`, `"mistral"`, `"codellama"`).
        var model: String
        /// Ollama connection and runtime settings.
        var settings: OllamaSettings

        init(model: String, settings: OllamaSettings = .default) {
            self.model = model
            self.settings = settings
        }
    }
}
