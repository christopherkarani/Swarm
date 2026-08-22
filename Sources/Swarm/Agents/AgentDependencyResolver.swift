// AgentDependencyResolver.swift
// Swarm Framework
//
// Pure resolution functions for per-run agent dependencies.

import Foundation

/// Pure resolution of per-run ``Agent`` dependencies.
///
/// Extracted from ``Agent`` so provider, tracer, memory, tool-registry, and
/// inference-options decisions are unit-testable without running an agent.
/// Each function receives value snapshots (configuration fields, task-local
/// ``AgentEnvironment``, ``AgentRunEnvironment``) and returns the resolved
/// dependency; ``Agent`` call sites remain thin delegations that gather the
/// ambient inputs at the same points they did before extraction.
enum AgentDependencyResolver {
    // MARK: - Tracing

    /// Composes the active tracer chain.
    ///
    /// Order: explicit agent tracer, then task-local tracer, then a
    /// `SwiftLogTracer` fallback when default tracing is enabled. When metric
    /// auto-attach is on, the collector is composed into (or returned as) the
    /// resulting chain.
    static func activeTracer(
        explicitTracer: (any Tracer)?,
        environmentTracer: (any Tracer)?,
        defaultTracingEnabled: Bool,
        autoAttachMetricsCollector: Bool,
        metricsCollector: MetricsCollector?
    ) -> (any Tracer)? {
        let configured = explicitTracer ?? environmentTracer
        let fallback = defaultTracingEnabled
            ? SwiftLogTracer(minimumLevel: .debug)
            : nil
        let base = configured ?? fallback

        guard autoAttachMetricsCollector, let collector = metricsCollector else {
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

    // MARK: - Inference Provider

    /// Resolves the provider for a run.
    ///
    /// Privacy-required runs accept only on-device or `.privateInference`
    /// providers; otherwise resolution follows explicit → task-local →
    /// globally configured → Foundation Models.
    static func inferenceProvider(
        privacyRequired: Bool,
        explicitProvider: (any InferenceProvider)?,
        environment: AgentEnvironment,
        runEnvironment: AgentRunEnvironment,
        foundationModelsProvider: @escaping @Sendable () -> (any InferenceProvider)? = {
            DefaultInferenceProviderFactory.makeFoundationModelsProviderIfAvailable()
        }
    ) async throws -> any InferenceProvider {
        if privacyRequired {
            return try await resolvedPrivateInferenceProvider(
                explicitProvider: explicitProvider,
                environment: environment,
                runEnvironment: runEnvironment,
                foundationModelsProvider: foundationModelsProvider
            )
        }

        // 1. Explicit provider on Agent
        if let explicitProvider {
            return transformedInferenceProvider(explicitProvider, transform: environment.inferenceProviderTransform)
        }

        // 2. TaskLocal via .environment()
        if let environmentProvider = environment.inferenceProvider {
            return transformedInferenceProvider(environmentProvider, transform: environment.inferenceProviderTransform)
        }

        // 3. Swarm.defaultProvider (global)
        if let globalProvider = await runEnvironment.defaultProvider() {
            return transformedInferenceProvider(globalProvider, transform: environment.inferenceProviderTransform)
        }

        // 4. Foundation Models (if available, on Apple platform)
        if let foundationModelsProvider = foundationModelsProvider() {
            return transformedInferenceProvider(foundationModelsProvider, transform: environment.inferenceProviderTransform)
        }

        // 5. No provider available
        throw AgentError.inferenceProviderUnavailable(
            reason: """
            No inference provider configured and Apple Foundation Models are unavailable.

            Configure a provider globally via `await Swarm.configure(provider: ...)` \
            or pass one explicitly to Agent(...).
            """
        )
    }

    private static func resolvedPrivateInferenceProvider(
        explicitProvider: (any InferenceProvider)?,
        environment: AgentEnvironment,
        runEnvironment: AgentRunEnvironment,
        foundationModelsProvider: @escaping @Sendable () -> (any InferenceProvider)?
    ) async throws -> any InferenceProvider {
        if let foundationModelsProvider = foundationModelsProvider() {
            return transformedInferenceProvider(foundationModelsProvider, transform: environment.inferenceProviderTransform)
        }

        if let provider = privateInferenceProvider(explicitProvider) {
            return transformedInferenceProvider(provider, transform: environment.inferenceProviderTransform)
        }

        if let provider = privateInferenceProvider(environment.inferenceProvider) {
            return transformedInferenceProvider(provider, transform: environment.inferenceProviderTransform)
        }

        if let globalProvider = await runEnvironment.defaultProvider(),
           let provider = privateInferenceProvider(globalProvider)
        {
            return transformedInferenceProvider(provider, transform: environment.inferenceProviderTransform)
        }

        throw AgentError.inferenceProviderUnavailable(
            reason: """
            AgentConfiguration.inferencePolicy.privacyRequired is true, but no private inference provider is available.

            Use Apple Foundation Models on a supported device, or configure a provider that reports \
            InferenceProviderCapabilities.privateInference via `await Swarm.configure(provider: ...)`.
            """
        )
    }

    /// Filters out providers that do not report `.privateInference`.
    static func privateInferenceProvider(_ provider: (any InferenceProvider)?) -> (any InferenceProvider)? {
        guard let provider else {
            return nil
        }

        let capabilities = InferenceProviderCapabilities.resolved(for: provider)
        guard capabilities.contains(.privateInference) else {
            return nil
        }
        return provider
    }

    /// Applies the task-local provider transform, when present.
    static func transformedInferenceProvider(
        _ provider: any InferenceProvider,
        transform: (@Sendable (any InferenceProvider) -> any InferenceProvider)?
    ) -> any InferenceProvider {
        guard let transform else {
            return provider
        }
        return transform(provider)
    }

    /// Effective capability set advertised by a provider.
    static func providerCapabilities(for provider: any InferenceProvider) -> InferenceProviderCapabilities {
        InferenceProviderCapabilities.resolved(for: provider)
    }

    // MARK: - Membrane

    /// Resolves the Membrane planning adapter for a run, when enabled.
    static func membraneAdapter(in environment: AgentEnvironment) -> (any MembraneAgentAdapter)? {
        let membrane = environment.membrane ?? .enabled
        guard membrane.isEnabled else {
            return nil
        }
        if let adapter = membrane.adapter {
            return adapter
        }
        return DefaultMembraneAgentAdapter(configuration: membrane.configuration)
    }

    // MARK: - Runtime Environment

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

    // MARK: - Memory

    /// Resolves the effective memory for a run.
    ///
    /// Precedence: explicit agent memory, then task-local memory, then the
    /// package default memory created at init.
    static func memory(
        explicitMemory: (any Memory)?,
        environmentMemory: (any Memory)?,
        defaultMemory: (any Memory)?
    ) -> (any Memory)? {
        explicitMemory ?? environmentMemory ?? defaultMemory
    }

    // MARK: - Tool Registry

    /// Resolves the tool registry for a run.
    ///
    /// With the Integrations trait an ambient web-search configuration
    /// (task-local first, then the shared configuration source) appends a
    /// `websearch` tool unless the agent already carries one.
    static func toolRegistry(
        baseTools: [any AnyJSONTool],
        taskLocalWebSearch: WebSearchTool.Configuration?,
        runEnvironment: AgentRunEnvironment
    ) async throws -> ToolRegistry {
        #if SWARM_INTEGRATIONS
        guard !baseTools.contains(where: { $0.name == "websearch" }) else {
            return try ToolRegistry(tools: baseTools)
        }

        let ambientWeb = if let taskLocalWebSearch { taskLocalWebSearch } else { await runEnvironment.webConfiguration() }
        guard let ambientWeb,
              ambientWeb.enabled
        else {
            return try ToolRegistry(tools: baseTools)
        }

        var tools = baseTools
        tools.append(WebSearchTool(configuration: ambientWeb))
        return try ToolRegistry(tools: tools)
        #else
        return try ToolRegistry(tools: baseTools)
        #endif
    }

    // MARK: - Inference Options

    /// Assembles per-run inference options from configuration and tracker state.
    ///
    /// Previous-response continuation applies only to providers advertising
    /// `.responseContinuation`; an explicit configured ID wins over the
    /// auto-tracked latest response ID.
    static func inferenceOptions(
        configuration: AgentConfiguration,
        capabilities: InferenceProviderCapabilities,
        sessionID: String?,
        responseTracker: ResponseTracker
    ) async -> InferenceOptions {
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

        guard configuration.autoPreviousResponseId, let sessionID else {
            return options
        }

        if let latestResponseID = await responseTracker.getLatestResponseId(for: sessionID) {
            options.previousResponseId = latestResponseID
        }

        return options
    }
}
