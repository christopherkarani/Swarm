// ConduitProviderSelection.swift
// Swarm Framework
//
// Minimal Conduit-backed provider selection for Swarm.

import Conduit
import Foundation

/// Convenience selection for Conduit-backed inference providers.
///
/// This hides Conduit types while keeping a lightweight call-site API.
public enum ConduitProviderSelection: Sendable, InferenceProvider {
    case provider(any InferenceProvider)

    /// Creates a Conduit-backed Anthropic provider.
    public static func anthropic(apiKey: String, model: String) -> ConduitProviderSelection {
        let provider = AnthropicProvider(apiKey: apiKey)
        let modelID = AnthropicModelID(model)
        let bridge = ConduitInferenceProvider(provider: provider, model: modelID)
        return .provider(bridge)
    }

    /// Creates a Conduit-backed OpenAI provider.
    public static func openAI(apiKey: String, model: String) -> ConduitProviderSelection {
        let configuration = OpenAIConfiguration.openAI(apiKey: apiKey)
        let provider = OpenAIProvider(configuration: configuration)
        let modelID = OpenAIModelID(model)
        let bridge = ConduitInferenceProvider(provider: provider, model: modelID)
        return .provider(bridge)
    }

    /// Creates a Conduit-backed OpenRouter provider.
    public static func openRouter(
        apiKey: String,
        model: String
    ) -> ConduitProviderSelection {
        openRouter(apiKey: apiKey, model: model, routing: nil)
    }

    /// Creates a Conduit-backed OpenRouter provider with routing configuration.
    ///
    /// - Parameters:
    ///   - apiKey: Your OpenRouter API key.
    ///   - model: The model identifier (e.g. `"anthropic/claude-3.5-sonnet"`).
    ///   - configure: Closure to customize OpenRouter routing preferences.
    ///
    /// ```swift
    /// let provider: some InferenceProvider = .openRouter(apiKey: key, model: "...") { routing in
    ///     routing.providers = [.anthropic]
    /// }
    /// ```
    public static func openRouter(
        apiKey: String,
        model: String,
        configure: (inout OpenRouterRouting) -> Void
    ) -> ConduitProviderSelection {
        var routing = OpenRouterRouting()
        configure(&routing)
        return openRouter(apiKey: apiKey, model: model, routing: routing)
    }

    /// Creates a Conduit-backed Ollama provider.
    ///
    /// - Parameters:
    ///   - model: The Ollama model name (e.g. `"llama3.2"`, `"mistral"`).
    public static func ollama(model: String) -> ConduitProviderSelection {
        ollama(model: model, settings: .default)
    }

    /// Creates a Conduit-backed Ollama provider with closure-based configuration.
    ///
    /// - Parameters:
    ///   - model: The Ollama model name (e.g. `"llama3.2"`, `"mistral"`).
    ///   - configure: Closure to customize Ollama connection settings.
    ///
    /// ```swift
    /// let provider: some InferenceProvider = .ollama(model: "mistral") { settings in
    ///     settings.host = "127.0.0.1"
    ///     settings.port = 11435
    /// }
    /// ```
    public static func ollama(
        model: String,
        configure: (inout OllamaSettings) -> Void
    ) -> ConduitProviderSelection {
        var settings = OllamaSettings.default
        configure(&settings)
        return ollama(model: model, settings: settings)
    }

    /// Creates a Conduit-backed Ollama provider using a base URL string.
    ///
    /// - Parameters:
    ///   - model: The model name to use (e.g. `"llama3.2"`).
    ///   - baseURL: The full base URL of the Ollama server (e.g. `"http://localhost:11434"`).
    ///     Host and port are parsed from this URL; path components are ignored.
    public static func ollama(
        model: String,
        baseURL: String
    ) -> ConduitProviderSelection {
        var settings = OllamaSettings.default
        if let url = URL(string: baseURL), let host = url.host {
            settings.host = host
            if let port = url.port {
                settings.port = port
            }
        }
        return ollama(model: model, settings: settings)
    }

    /// Creates a Conduit-backed Gemini provider via OpenRouter.
    ///
    /// Gemini models are accessed through OpenRouter using the `google/<model>` namespace.
    /// The `apiKey` should be your OpenRouter API key.
    ///
    /// - Parameters:
    ///   - apiKey: Your OpenRouter API key.
    ///   - model: The Gemini model identifier, e.g. `"gemini-2.0-flash"`.
    ///     This is automatically prefixed with `"google/"` when routing through OpenRouter.
    public static func gemini(
        apiKey: String,
        model: String = "gemini-2.0-flash"
    ) -> ConduitProviderSelection {
        let routedModel = model.hasPrefix("google/") ? model : "google/\(model)"
        return openRouter(apiKey: apiKey, model: routedModel)
    }

    /// Creates a Conduit-backed MiniMax provider via OpenRouter.
    ///
    /// MiniMax models are accessed through OpenRouter using the `minimax/<model>` namespace.
    /// The `apiKey` should be your OpenRouter API key.
    ///
    /// - Parameters:
    ///   - apiKey: Your OpenRouter API key.
    ///   - model: The MiniMax model identifier, e.g. `"minimax-01"`.
    ///     This is automatically prefixed with `"minimax/"` when needed.
    public static func minimax(
        apiKey: String,
        model: String = "minimax-01"
    ) -> ConduitProviderSelection {
        #if CONDUIT_TRAIT_MINIMAX
            let provider = MiniMaxProvider(apiKey: apiKey)
            let modelID = ModelIdentifier.miniMax(model)
            let bridge = ConduitInferenceProvider(provider: provider, model: modelID)
            return .provider(bridge)
        #else
            let routedModel = model.hasPrefix("minimax/") ? model : "minimax/\(model)"
            return openRouter(apiKey: apiKey, model: routedModel)
        #endif
    }

    /// Exposes the underlying inference provider.
    public func makeProvider() -> any InferenceProvider {
        switch self {
        case let .provider(provider):
            return provider
        }
    }

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

    // MARK: - Internal Helpers

    static func openRouter(
        apiKey: String,
        model: String,
        routing: OpenRouterRouting?
    ) -> ConduitProviderSelection {
        var configuration = OpenAIConfiguration.openRouter(apiKey: apiKey)
        if let routing {
            configuration = configuration.routing(routing.toConduit())
        }
        let provider = OpenAIProvider(configuration: configuration)
        let modelID = OpenAIModelID.openRouter(model)
        let bridge = ConduitInferenceProvider(provider: provider, model: modelID)
        return .provider(bridge)
    }

    static func ollama(
        model: String,
        settings: OllamaSettings
    ) -> ConduitProviderSelection {
        let configuration = OpenAIConfiguration.ollama(host: settings.host, port: settings.port)
            .ollama(settings.toConduit())
        let provider = OpenAIProvider(configuration: configuration)
        let modelID = OpenAIModelID.ollama(model)
        let bridge = ConduitInferenceProvider(provider: provider, model: modelID)
        return .provider(bridge)
    }
}

extension ConduitProviderSelection: CapabilityReportingInferenceProvider {
    public var capabilities: InferenceProviderCapabilities {
        var capabilities = InferenceProviderCapabilities.resolved(for: makeProvider())
        capabilities.insert(.conversationMessages)
        return capabilities
    }
}

extension ConduitProviderSelection: ConversationInferenceProvider {
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

extension ConduitProviderSelection: StreamingConversationInferenceProvider {
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

extension ConduitProviderSelection: ToolCallStreamingInferenceProvider {
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

extension ConduitProviderSelection: ToolCallStreamingConversationInferenceProvider {
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

/// Enables dot-syntax on `any InferenceProvider` parameters, e.g.:
/// ```swift
/// let agent = try Agent("...", provider: .anthropic(apiKey: "key"))
/// ```
public extension InferenceProvider where Self == ConduitProviderSelection {
    static func anthropic(apiKey: String, model: String = "claude-sonnet-4-5") -> ConduitProviderSelection {
        ConduitProviderSelection.anthropic(apiKey: apiKey, model: model)
    }

    static func openAI(apiKey: String, model: String = "gpt-4o") -> ConduitProviderSelection {
        ConduitProviderSelection.openAI(apiKey: apiKey, model: model)
    }

    static func openRouter(
        apiKey: String,
        model: String
    ) -> ConduitProviderSelection {
        ConduitProviderSelection.openRouter(apiKey: apiKey, model: model)
    }

    static func openRouter(
        apiKey: String,
        model: String,
        configure: (inout OpenRouterRouting) -> Void
    ) -> ConduitProviderSelection {
        ConduitProviderSelection.openRouter(apiKey: apiKey, model: model, configure: configure)
    }

    static func ollama(model: String) -> ConduitProviderSelection {
        ConduitProviderSelection.ollama(model: model)
    }

    static func ollama(
        model: String,
        configure: (inout OllamaSettings) -> Void
    ) -> ConduitProviderSelection {
        ConduitProviderSelection.ollama(model: model, configure: configure)
    }

    static func ollama(
        model: String,
        baseURL: String
    ) -> ConduitProviderSelection {
        ConduitProviderSelection.ollama(model: model, baseURL: baseURL)
    }

    static func gemini(
        apiKey: String,
        model: String = "gemini-2.0-flash"
    ) -> ConduitProviderSelection {
        ConduitProviderSelection.gemini(apiKey: apiKey, model: model)
    }

    static func minimax(
        apiKey: String,
        model: String = "minimax-01"
    ) -> ConduitProviderSelection {
        ConduitProviderSelection.minimax(apiKey: apiKey, model: model)
    }
}
