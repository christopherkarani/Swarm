// OpenRouterRouting.swift
// Swarm Framework
//
// Lightweight OpenRouter routing configuration without exposing Conduit types.

import Conduit
typealias ConduitOpenRouterProvider = ConduitTypes.OpenRouterProvider
typealias ConduitOpenRouterDataCollection = ConduitTypes.OpenRouterDataCollection
import Foundation

/// OpenRouter routing preferences.
///
/// Use via the closure-based configuration on provider factories:
/// ```swift
/// let llm: some InferenceProvider = .openRouter(apiKey: key, model: "...") { routing in
///     routing.providers = [.anthropic]
/// }
/// ```
public struct OpenRouterRouting: Sendable, Hashable {
    public var providers: [OpenRouterProvider]?
    public var fallbacks: Bool
    public var routeByLatency: Bool
    public var siteURL: URL?
    public var appName: String?
    public var dataCollection: OpenRouterDataCollectionPolicy?

    public init(
        providers: [OpenRouterProvider]? = nil,
        fallbacks: Bool = true,
        routeByLatency: Bool = false,
        siteURL: URL? = nil,
        appName: String? = nil,
        dataCollection: OpenRouterDataCollectionPolicy? = nil
    ) {
        self.providers = providers
        self.fallbacks = fallbacks
        self.routeByLatency = routeByLatency
        self.siteURL = siteURL
        self.appName = appName
        self.dataCollection = dataCollection
    }

    func toConduit() -> OpenRouterRoutingConfig {
        let mappedProviders = providers?.map(\.toConduit)
        return OpenRouterRoutingConfig(
            providers: mappedProviders,
            fallbacks: fallbacks,
            routeByLatency: routeByLatency,
            siteURL: siteURL,
            appName: appName,
            dataCollection: dataCollection.flatMap { ConduitOpenRouterDataCollection(rawValue: $0.rawValue) }
        )
    }
}

// MARK: - Public Enums

/// OpenRouter inference provider options.
public enum OpenRouterProvider: String, Sendable, Hashable, CaseIterable {
    case openai
    case anthropic
    case google
    case googleAIStudio
    case together
    case fireworks
    case perplexity
    case mistral
    case groq
    case deepseek
    case cohere
    case ai21
    case bedrock
    case azure
}

/// OpenRouter data collection policy.
public enum OpenRouterDataCollectionPolicy: String, Sendable, Hashable, CaseIterable {
    case allow
    case deny
}

extension OpenRouterProvider {
    var toConduit: ConduitOpenRouterProvider {
        switch self {
        case .openai:
            .openai
        case .anthropic:
            .anthropic
        case .google:
            .google
        case .googleAIStudio:
            .googleAIStudio
        case .together:
            .together
        case .fireworks:
            .fireworks
        case .perplexity:
            .perplexity
        case .mistral:
            .mistral
        case .groq:
            .groq
        case .deepseek:
            .deepseek
        case .cohere:
            .cohere
        case .ai21:
            .ai21
        case .bedrock:
            .bedrock
        case .azure:
            .azure
        }
    }
}
