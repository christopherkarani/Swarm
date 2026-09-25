// AgentTurnDependencies.swift
// Swarm Framework
//
// Explicit per-turn collaborator resolution for Agent.

import Foundation

/// Names which resolution channel won for one collaborator.
enum ResolutionSource: String, Sendable, Equatable {
    /// An explicit value passed to the `Agent` initializer.
    case explicit
    /// A value from the `AgentEnvironment` snapshot.
    case environment
    /// A package-global value (`Swarm.configure` / run environment).
    case global
    /// The on-device Foundation Models provider resolved by the gather step.
    case foundationModels
    /// A built-in fallback: the agent's default memory, the default tracer,
    /// or the auto-attached metrics collector standing alone.
    case fallbackDefault
    /// No collaborator resolved (stateless memory, absent tracer).
    case none
}

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

    /// Which channel won provider resolution.
    let providerSource: ResolutionSource

    /// Memory for this turn. `nil` remains legal (stateless turn).
    let memory: (any Memory)?

    /// Which channel won memory resolution (`.none` when stateless).
    let memorySource: ResolutionSource

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

    /// Which channel won tracer resolution (`.none` when no tracer resolved).
    /// Composition with the auto-attached collector keeps the base channel.
    let tracerSource: ResolutionSource

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
/// Pure data: async channel reads (`Swarm.defaultProvider`,
/// `Swarm.webConfiguration`, the agent's base tools) and the resolved
/// Foundation Models provider value are gathered by the caller before
/// resolution. Resolution itself is synchronous, so winner precedence can be
/// asserted from direct inputs without TaskLocal choreography.
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
    var foundationModelsProvider: (any InferenceProvider)?

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
        foundationModelsProvider: (any InferenceProvider)? = nil
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
///
/// Inference options, provider capabilities, and runtime environment are
/// assembled here as well. Tracker I/O stays in the ``Agent`` shell.
enum AgentTurnDependencyResolver {
    static func resolve(_ query: AgentTurnDependencyQuery) throws -> AgentTurnDependencies {
        let (provider, providerSource) = try resolveProvider(query)
        let (memory, memorySource) = resolveMemory(query)
        let shouldPersistNoSessionTurn = memory.map { memory in
            guard let defaultMemory = query.defaultMemory else { return false }
            return memoriesAreSameInstance(memory, defaultMemory)
        } ?? false
        let (tracer, tracerSource) = resolveTracer(query)

        return AgentTurnDependencies(
            provider: provider,
            providerSource: providerSource,
            memory: memory,
            memorySource: memorySource,
            memoryHooks: memory.map { MemoryHooks.resolved(from: $0) } ?? .empty,
            trackedSessionMemory: memory.flatMap {
                resolvedTrackedSessionMemory(from: $0, defaultMemory: query.defaultMemory)
            },
            shouldPersistNoSessionTurnToDefaultMemory: shouldPersistNoSessionTurn,
            tracer: tracer,
            tracerSource: tracerSource,
            toolRegistry: try resolveToolRegistry(query),
            membraneAdapter: resolveMembraneAdapter(query),
            membraneEnvironment: query.environment.membrane,
            environmentSnapshot: query.environment
        )
    }

    private static func resolveProvider(
        _ query: AgentTurnDependencyQuery
    ) throws -> (any InferenceProvider, ResolutionSource) {
        if query.configuration.inferencePolicy?.privacyRequired == true {
            if let foundationModelsProvider = query.foundationModelsProvider {
                return (transformed(foundationModelsProvider, query), .foundationModels)
            }

            let ambientProviders: [((any InferenceProvider)?, ResolutionSource)] = [
                (query.explicitProvider, .explicit),
                (query.environment.inferenceProvider, .environment),
                (query.globalProvider, .global),
            ]
            for (candidate, source) in ambientProviders {
                guard let candidate else { continue }
                if isPrivateInference(candidate) {
                    return (transformed(candidate, query), source)
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

        let candidates: [((any InferenceProvider)?, ResolutionSource)] = [
            (query.explicitProvider, .explicit),
            (query.environment.inferenceProvider, .environment),
            (query.globalProvider, .global),
        ]
        for (candidate, source) in candidates {
            if let candidate {
                return (transformed(candidate, query), source)
            }
        }

        if let foundationModelsProvider = query.foundationModelsProvider {
            return (transformed(foundationModelsProvider, query), .foundationModels)
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

    private static func resolveMemory(
        _ query: AgentTurnDependencyQuery
    ) -> ((any Memory)?, ResolutionSource) {
        if let explicit = query.explicitMemory {
            return (explicit, .explicit)
        }
        if let environment = query.environment.memory {
            return (environment, .environment)
        }
        if let fallback = query.defaultMemory {
            return (fallback, .fallbackDefault)
        }
        return (nil, .none)
    }

    private static func resolveTracer(
        _ query: AgentTurnDependencyQuery
    ) -> ((any Tracer)?, ResolutionSource) {
        let base: (any Tracer)?
        let baseSource: ResolutionSource
        if let explicit = query.explicitTracer {
            (base, baseSource) = (explicit, .explicit)
        } else if let environment = query.environment.tracer {
            (base, baseSource) = (environment, .environment)
        } else if query.configuration.defaultTracingEnabled {
            (base, baseSource) = (SwiftLogTracer(minimumLevel: .info), .fallbackDefault)
        } else {
            (base, baseSource) = (nil, .none)
        }

        guard query.configuration.autoAttachMetricsCollector, let collector = query.metricsCollector else {
            return (base, baseSource)
        }

        if let base {
            if let existing = base as? MetricsCollector, existing === collector {
                return (collector, baseSource)
            }
            return (CompositeTracer(tracers: [base, collector]), baseSource)
        }
        return (collector, .fallbackDefault)
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

    /// Effective capability set advertised by a provider.
    static func providerCapabilities(for provider: any InferenceProvider) -> InferenceProviderCapabilities {
        InferenceProviderCapabilities.resolved(for: provider)
    }

    /// Merges the provider's prompt token counter into the run environment.
    static func runtimeEnvironment(
        _ environment: AgentEnvironment,
        addingTokenCounterFrom provider: any InferenceProvider
    ) -> AgentEnvironment {
        var environment = environment
        if let tokenCounter = provider.promptTokenCounter {
            environment.promptTokenCounter = tokenCounter
        }
        return environment
    }

    /// Assembles per-run inference options from configuration and an already-read response id.
    ///
    /// Previous-response continuation applies only to providers advertising
    /// `.responseContinuation`; an explicit configured ID wins over
    /// `latestResponseID`. The shell awaits ``ResponseTracker``; this function
    /// does not.
    static func inferenceOptions(
        configuration: AgentConfiguration,
        capabilities: InferenceProviderCapabilities,
        sessionID: String?,
        latestResponseID: String?
    ) -> InferenceOptions {
        var options = configuration.inferenceOptions

        guard capabilities.contains(.responseContinuation) else {
            options.previousResponseId = nil
            return options
        }

        if let explicit = configuration.previousResponseId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            options.previousResponseId = explicit
            return options
        }

        guard configuration.autoPreviousResponseId, sessionID != nil else {
            return options
        }

        if let latestResponseID {
            options.previousResponseId = latestResponseID
        }

        return options
    }
}
