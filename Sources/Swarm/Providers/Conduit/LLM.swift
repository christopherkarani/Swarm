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

    private enum Kind: Sendable {
        case openAI(OpenAIConfig)
        case anthropic(AnthropicConfig)
        case openRouter(OpenRouterConfig)
        case minimax(MiniMaxConfig)
        case ollama(OllamaConfig)
    }

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
            let provider = OpenAIProvider(configuration: .openAI(apiKey: config.apiKey))
            let modelID = OpenAIModelID(config.model)
            return ConduitInferenceProvider(
                provider: provider,
                model: modelID,
                baseConfig: config.advanced.baseConfig
            )
        case let .anthropic(config):
            let provider = AnthropicProvider(apiKey: config.apiKey)
            let modelID = AnthropicModelID(config.model)
            return ConduitInferenceProvider(
                provider: provider,
                model: modelID,
                baseConfig: config.advanced.baseConfig
            )
        case let .openRouter(config):
            var configuration = OpenAIConfiguration.openRouter(apiKey: config.apiKey)
            if let routing = config.advanced.openRouter.routing {
                configuration = configuration.routing(routing.toConduit())
            }
            let provider = OpenAIProvider(configuration: configuration)
            let modelID = OpenAIModelID.openRouter(config.model)
            return ConduitInferenceProvider(
                provider: provider,
                model: modelID,
                baseConfig: config.advanced.baseConfig
            )
        case let .minimax(config):
            #if CONDUIT_TRAIT_MINIMAX
                let provider = MiniMaxProvider(apiKey: config.apiKey)
                let modelID = ModelIdentifier.miniMax(config.model)
                return ConduitInferenceProvider(
                    provider: provider,
                    model: modelID,
                    baseConfig: config.advanced.baseConfig
                )
            #else
                let routedModel = config.model.hasPrefix("minimax/") ? config.model : "minimax/\(config.model)"
                let configuration = OpenAIConfiguration.openRouter(apiKey: config.apiKey)
                let provider = OpenAIProvider(configuration: configuration)
                let modelID = OpenAIModelID.openRouter(routedModel)
                return ConduitInferenceProvider(
                    provider: provider,
                    model: modelID,
                    baseConfig: config.advanced.baseConfig
                )
            #endif
        case let .ollama(config):
            let configuration = OpenAIConfiguration.ollama(
                host: config.settings.host,
                port: config.settings.port
            )
            .ollama(config.settings.toConduit())
            let provider = OpenAIProvider(configuration: configuration)
            let modelID = OpenAIModelID.ollama(config.model)
            return ConduitInferenceProvider(provider: provider, model: modelID)
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

public extension InferenceProvider where Self == LLM {
    static func openAI(apiKey: String, model: String = "gpt-4o-mini") -> LLM {
        LLM.openAI(apiKey: apiKey, model: model)
    }

    static func openAI(key: String, model: String = "gpt-4o-mini") -> LLM {
        LLM.openAI(key: key, model: model)
    }

    static func anthropic(apiKey: String, model: String = "claude-3-5-sonnet-20241022") -> LLM {
        LLM.anthropic(apiKey: apiKey, model: model)
    }

    static func anthropic(key: String, model: String = "claude-3-5-sonnet-20241022") -> LLM {
        LLM.anthropic(key: key, model: model)
    }

    static func openRouter(apiKey: String, model: String = "anthropic/claude-3.5-sonnet") -> LLM {
        LLM.openRouter(apiKey: apiKey, model: model)
    }

    static func openRouter(key: String, model: String = "anthropic/claude-3.5-sonnet") -> LLM {
        LLM.openRouter(key: key, model: model)
    }

    static func minimax(apiKey: String, model: String = "minimax-01") -> LLM {
        LLM.minimax(apiKey: apiKey, model: model)
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
        var baseConfig: Conduit.GenerateConfig

        var openRouter: OpenRouterOptions

        init(openRouter: OpenRouterOptions = .default) {
            self.baseConfig = .default
            self.openRouter = openRouter
        }

        init(baseConfig: Conduit.GenerateConfig, openRouter: OpenRouterOptions = .default) {
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
