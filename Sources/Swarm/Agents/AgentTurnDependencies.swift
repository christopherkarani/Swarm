// AgentTurnDependencies.swift
// Swarm Framework
//
// Explicit per-turn collaborator resolution for Agent.

import Foundation

/// The collaborators chosen for one agent turn.
///
/// ``Agent`` resolves this value exactly once at the start of every run, and
/// the turn loop plus its helpers read only from it. Identity-sensitive
/// decisions — whether the resolved memory is the package default, which
/// memory layer owns session tracking — are computed here against the resolved
/// instances instead of being re-derived mid-loop.
struct AgentTurnDependencies: Sendable {
    /// Inference provider that won resolution for this turn.
    let provider: any InferenceProvider

    /// Memory for this turn. `nil` remains legal (stateless turn).
    let memory: (any Memory)?

    /// Optional memory behavior derived from ``memory``.
    let memoryHooks: MemoryHooks

    /// Memory layer that owns session isolation for this turn: the agent's
    /// default memory when the resolved memory is that instance, otherwise the
    /// resolved memory's tracked session layer.
    let trackedSessionMemory: (any Memory)?

    /// Whether a session-less turn persists into the resolved memory. True
    /// exactly when the resolved memory is the agent's default memory instance.
    let shouldPersistNoSessionTurnToDefaultMemory: Bool

    /// Tracer chain for this turn: explicit tracer or environment tracer,
    /// falling back to the configured default, composed with the auto-attached
    /// metrics collector when enabled.
    let tracer: (any Tracer)?

    /// Tool registry for this turn, including any ambient web-search tool.
    let toolRegistry: ToolRegistry

    /// Membrane planning/transform adapter for this turn, `nil` when membrane
    /// is disabled in the environment.
    let membraneAdapter: (any MembraneAgentAdapter)?

    /// Raw membrane environment used to derive inference runtime settings.
    let membraneEnvironment: MembraneEnvironment?

    /// Environment snapshot captured when this turn's dependencies resolved.
    /// Nested execution re-binds it (with provider-derived token counters) via
    /// the existing TaskLocal propagation.
    let environmentSnapshot: AgentEnvironment
}

/// Direct inputs to collaborator resolution for one agent turn.
///
/// Async channel reads (`Swarm.defaultProvider`, `Swarm.webConfiguration`,
/// the agent's base tools) are gathered by the caller before resolution.
/// Resolution itself is synchronous, so winner precedence can be asserted from
/// direct inputs without TaskLocal choreography.
struct AgentTurnDependencyQuery {
    var configuration: AgentConfiguration
    var explicitProvider: (any InferenceProvider)?
    var explicitMemory: (any Memory)?
    var defaultMemory: (any Memory)?
    var explicitTracer: (any Tracer)?
    var metricsCollector: MetricsCollector?
    var baseTools: [any AnyJSONTool]
    var environment: AgentEnvironment
    var globalProvider: (any InferenceProvider)?
    var globalWebSearch: WebSearchTool.Configuration?
    var foundationModelsProvider: @Sendable () -> (any InferenceProvider)?

    init(
        configuration: AgentConfiguration,
        explicitProvider: (any InferenceProvider)? = nil,
        explicitMemory: (any Memory)? = nil,
        defaultMemory: (any Memory)? = nil,
        explicitTracer: (any Tracer)? = nil,
        metricsCollector: MetricsCollector? = nil,
        baseTools: [any AnyJSONTool] = [],
        environment: AgentEnvironment = AgentEnvironment(),
        globalProvider: (any InferenceProvider)? = nil,
        globalWebSearch: WebSearchTool.Configuration? = nil,
        foundationModelsProvider: @escaping @Sendable () -> (any InferenceProvider)? = { DefaultInferenceProviderFactory.makeFoundationModelsProviderIfAvailable() }
    ) {
        self.configuration = configuration
        self.explicitProvider = explicitProvider
        self.explicitMemory = explicitMemory
        self.defaultMemory = defaultMemory
        self.explicitTracer = explicitTracer
        self.metricsCollector = metricsCollector
        self.baseTools = baseTools
        self.environment = environment
        self.globalProvider = globalProvider
        self.globalWebSearch = globalWebSearch
        self.foundationModelsProvider = foundationModelsProvider
    }
}

/// Single resolution point turning an ``AgentTurnDependencyQuery`` into
/// ``AgentTurnDependencies``.
///
/// Normal-policy provider precedence:
/// explicit → environment → `Swarm.defaultProvider` → Foundation Models → throw.
///
/// Privacy-required policy reranks to:
/// Foundation Models → private explicit → private environment → private global
/// → throw. Non-private providers are filtered out; Foundation Models is
/// accepted as on-device private inference.
enum AgentTurnDependencyResolver {
    static func resolve(_ query: AgentTurnDependencyQuery) throws -> AgentTurnDependencies {
        let memory = resolveMemory(query)
        let shouldPersistNoSessionTurn = memory.map { memory in
            guard let defaultMemory = query.defaultMemory else { return false }
            return memoriesAreSameInstance(memory, defaultMemory)
        } ?? false

        return AgentTurnDependencies(
            provider: try resolveProvider(query),
            memory: memory,
            memoryHooks: memory.map { MemoryHooks.resolved(from: $0) } ?? .empty,
            trackedSessionMemory: memory.flatMap {
                resolvedTrackedSessionMemory(from: $0, defaultMemory: query.defaultMemory)
            },
            shouldPersistNoSessionTurnToDefaultMemory: shouldPersistNoSessionTurn,
            tracer: resolveTracer(query),
            toolRegistry: try resolveToolRegistry(query),
            membraneAdapter: resolveMembraneAdapter(query),
            membraneEnvironment: query.environment.membrane,
            environmentSnapshot: query.environment
        )
    }

    private static func resolveProvider(_ query: AgentTurnDependencyQuery) throws -> any InferenceProvider {
        if query.configuration.inferencePolicy?.privacyRequired == true {
            if let foundationModelsProvider = query.foundationModelsProvider() {
                return transformed(foundationModelsProvider, query)
            }

            let ambientProviders = [
                query.explicitProvider,
                query.environment.inferenceProvider,
                query.globalProvider,
            ]
            for candidate in ambientProviders {
                guard let candidate else { continue }
                if isPrivateInference(candidate) {
                    return transformed(candidate, query)
                }
            }

            throw AgentError.inferenceProviderUnavailable(
                reason: """
                AgentConfiguration.inferencePolicy.privacyRequired is true, but no private inference provider is available.

                Use Apple Foundation Models on a supported device, or configure a provider that reports \
                InferenceProviderCapabilities.privateInference via `await Swarm.configure(provider: ...)`.
                """
            )
        }

        let candidates = [
            query.explicitProvider,
            query.environment.inferenceProvider,
            query.globalProvider,
        ]
        for candidate in candidates {
            if let candidate {
                return transformed(candidate, query)
            }
        }

        if let foundationModelsProvider = query.foundationModelsProvider() {
            return transformed(foundationModelsProvider, query)
        }

        throw AgentError.inferenceProviderUnavailable(
            reason: """
            No inference provider configured and Apple Foundation Models are unavailable.

            Configure a provider globally via `await Swarm.configure(provider: ...)` \
            or pass one explicitly to Agent(...).
            """
        )
    }

    private static func isPrivateInference(_ provider: any InferenceProvider) -> Bool {
        InferenceProviderCapabilities.resolved(for: provider).contains(.privateInference)
    }

    private static func transformed(
        _ provider: any InferenceProvider,
        _ query: AgentTurnDependencyQuery
    ) -> any InferenceProvider {
        guard let transform = query.environment.inferenceProviderTransform else {
            return provider
        }
        return transform(provider)
    }

    private static func resolveMemory(_ query: AgentTurnDependencyQuery) -> (any Memory)? {
        query.explicitMemory ?? query.environment.memory ?? query.defaultMemory
    }

    private static func resolveTracer(_ query: AgentTurnDependencyQuery) -> (any Tracer)? {
        let configured = query.explicitTracer ?? query.environment.tracer
        let fallback = query.configuration.defaultTracingEnabled
            ? SwiftLogTracer(minimumLevel: .debug)
            : nil
        let base = configured ?? fallback

        guard query.configuration.autoAttachMetricsCollector, let collector = query.metricsCollector else {
            return base
        }

        if let base {
            if let existing = base as? MetricsCollector, existing === collector {
                return collector
            }
            return CompositeTracer(tracers: [base, collector])
        }
        return collector
    }

    private static func resolveToolRegistry(_ query: AgentTurnDependencyQuery) throws -> ToolRegistry {
        var tools = query.baseTools
        #if SWARM_INTEGRATIONS
        if !tools.contains(where: { $0.name == "websearch" }) {
            let ambientWeb = query.environment.webSearch ?? query.globalWebSearch
            if let ambientWeb, ambientWeb.enabled {
                tools.append(WebSearchTool(configuration: ambientWeb))
            }
        }
        #endif
        return try ToolRegistry(tools: tools)
    }

    private static func resolveMembraneAdapter(_ query: AgentTurnDependencyQuery) -> (any MembraneAgentAdapter)? {
        let membrane = query.environment.membrane ?? .enabled
        guard membrane.isEnabled else {
            return nil
        }
        return membrane.adapter ?? DefaultMembraneAgentAdapter(configuration: membrane.configuration)
    }
}
