// AgentTurnDependenciesTests.swift
// SwarmTests
//
// Direct-input tests for per-turn Agent collaborator resolution.

import Foundation
@testable import Swarm
import Testing

@Suite("Agent Turn Dependencies")
struct AgentTurnDependenciesTests {
    // MARK: - Provider Winner Order (normal policy)

    @Test("Normal policy prefers explicit provider over environment, global, and Foundation Models")
    func explicitProviderWins() throws {
        let explicit = MockInferenceProvider(responses: ["explicit"])
        let environment = MockInferenceProvider(responses: ["environment"])
        let global = MockInferenceProvider(responses: ["global"])
        let foundationModels = MockInferenceProvider(responses: ["foundation-models"])

        let dependencies = try AgentTurnDependencyResolver.resolve(
            query(
                explicitProvider: explicit,
                environmentProvider: environment,
                globalProvider: global,
                foundationModels: foundationModels
            )
        )

        #expect(sameInstance(dependencies.provider, explicit))
    }

    @Test("Normal policy falls back through environment, global, then Foundation Models")
    func normalPolicyFallbackOrder() throws {
        let environment = MockInferenceProvider(responses: ["environment"])
        let global = MockInferenceProvider(responses: ["global"])
        let foundationModels = MockInferenceProvider(responses: ["foundation-models"])

        let fromEnvironment = try AgentTurnDependencyResolver.resolve(
            query(environmentProvider: environment, globalProvider: global, foundationModels: foundationModels)
        )
        #expect(sameInstance(fromEnvironment.provider, environment))

        let fromGlobal = try AgentTurnDependencyResolver.resolve(
            query(globalProvider: global, foundationModels: foundationModels)
        )
        #expect(sameInstance(fromGlobal.provider, global))

        let fromFoundationModels = try AgentTurnDependencyResolver.resolve(
            query(foundationModels: foundationModels)
        )
        #expect(sameInstance(fromFoundationModels.provider, foundationModels))
    }

    @Test("Normal policy throws when no channel offers a provider")
    func normalPolicyThrowsWithoutAnyProvider() {
        #expect(throws: AgentError.self) {
            _ = try AgentTurnDependencyResolver.resolve(query(foundationModels: nil))
        }
    }

    // MARK: - Provider Winner Order (privacy-required policy)

    @Test("Privacy-required reranks Foundation Models ahead of private ambient providers")
    func privacyRequiredPrefersFoundationModels() throws {
        let foundationModels = MockInferenceProvider(
            responses: ["foundation-models"],
            capabilities: [.privateInference]
        )
        let explicitPrivate = MockInferenceProvider(
            responses: ["explicit"],
            capabilities: [.privateInference]
        )

        let dependencies = try AgentTurnDependencyResolver.resolve(
            query(
                configuration: AgentConfiguration.default.inferencePolicy(InferencePolicy(privacyRequired: true)),
                explicitProvider: explicitPrivate,
                foundationModels: foundationModels
            )
        )

        #expect(sameInstance(dependencies.provider, foundationModels))
    }

    @Test("Privacy-required skips non-private providers and keeps private order")
    func privacyRequiredFiltersNonPrivateProviders() throws {
        let configuration = AgentConfiguration.default.inferencePolicy(InferencePolicy(privacyRequired: true))
        let nonPrivateExplicit = MockInferenceProvider(responses: ["non-private-explicit"])
        let nonPrivateEnvironment = MockInferenceProvider(responses: ["non-private-environment"])
        let privateGlobal = MockInferenceProvider(
            responses: ["private-global"],
            capabilities: [.privateInference]
        )

        let dependencies = try AgentTurnDependencyResolver.resolve(query(
            configuration: configuration,
            explicitProvider: nonPrivateExplicit,
            environmentProvider: nonPrivateEnvironment,
            globalProvider: privateGlobal,
            foundationModels: nil
        ))

        #expect(sameInstance(dependencies.provider, privateGlobal))
    }

    @Test("Privacy-required throws when no private provider exists")
    func privacyRequiredThrowsWithoutPrivateProvider() {
        let configuration = AgentConfiguration.default.inferencePolicy(InferencePolicy(privacyRequired: true))

        #expect(throws: AgentError.self) {
            _ = try AgentTurnDependencyResolver.resolve(
                query(configuration: configuration, explicitProvider: MockInferenceProvider(), foundationModels: nil)
            )
        }
    }

    // MARK: - Provider transform

    @Test("Environment transform applies to the winning provider")
    func transformAppliesToWinner() throws {
        let explicit = MockInferenceProvider(responses: ["explicit"])
        let transformed = MockInferenceProvider(responses: ["transformed"])
        var environment = AgentEnvironment()
        environment.inferenceProviderTransform = { _ in transformed }

        let dependencies = try AgentTurnDependencyResolver.resolve(
            query(explicitProvider: explicit, environment: environment, foundationModels: nil)
        )

        #expect(sameInstance(dependencies.provider, transformed))
    }

    // MARK: - Memory winner order and identity decisions

    @Test("Memory precedence is explicit, then environment, then default")
    func memoryPrecedence() throws {
        let explicit = SlidingWindowMemory()
        let environmentMemory = SlidingWindowMemory()
        let defaultMemory = SlidingWindowMemory()
        var environment = AgentEnvironment()
        environment.memory = environmentMemory

        let fromExplicit = try resolve(explicitMemory: explicit, defaultMemory: defaultMemory)
        #expect(sameInstance(fromExplicit.memory!, explicit))

        let fromEnvironment = try resolve(defaultMemory: defaultMemory, environment: environment)
        #expect(sameInstance(fromEnvironment.memory!, environmentMemory))

        let fromDefault = try resolve(defaultMemory: defaultMemory)
        #expect(sameInstance(fromDefault.memory!, defaultMemory))

        let stateless = try resolve(defaultMemory: nil, environment: AgentEnvironment())
        #expect(stateless.memory == nil)
    }

    @Test("Session-less persistence records identity against the resolved memory")
    func sessionlessPersistenceIdentityDecision() throws {
        let defaultMemory = SlidingWindowMemory()

        let sameInstance = try resolve(explicitMemory: defaultMemory, defaultMemory: defaultMemory)
        #expect(sameInstance.shouldPersistNoSessionTurnToDefaultMemory)
        #expect(identical(sameInstance.trackedSessionMemory, defaultMemory as (any Memory)?))

        let differentInstance = try resolve(
            explicitMemory: SlidingWindowMemory(),
            defaultMemory: defaultMemory
        )
        #expect(!differentInstance.shouldPersistNoSessionTurnToDefaultMemory)
        #expect(differentInstance.trackedSessionMemory == nil)
    }

    // MARK: - Tracer resolution

    @Test("Tracer prefers explicit tracer and composes the auto-attached collector")
    func tracerComposition() throws {
        let tracer = SwiftLogTracer(minimumLevel: .debug)
        let collector = MetricsCollector()

        let composed = try resolve(
            configuration: .default.autoAttachMetricsCollector(true),
            explicitTracer: tracer,
            metricsCollector: collector
        )
        #expect(composed.tracer is CompositeTracer)

        let collectorAsTracer = try resolve(
            configuration: .default.autoAttachMetricsCollector(true),
            explicitTracer: collector,
            metricsCollector: collector
        )
        #expect(identical(collectorAsTracer.tracer, collector as (any Tracer)?))

        let withoutCollector = try resolve(
            configuration: .default.autoAttachMetricsCollector(false),
            explicitTracer: tracer,
            metricsCollector: nil
        )
        #expect(identical(withoutCollector.tracer, tracer as (any Tracer)?))
    }

    @Test("Default tracing fallback produces a tracer only when configured")
    func defaultTracingFallback() throws {
        let enabled = try resolve(configuration: .default.defaultTracingEnabled(true), explicitTracer: nil)
        #expect(enabled.tracer != nil)

        let disabled = try resolve(configuration: .default.defaultTracingEnabled(false), explicitTracer: nil)
        #expect(disabled.tracer == nil)
    }

    // MARK: - Determinism

    @Test("Repeated resolution with identical inputs yields identical winners")
    func resolutionIsDeterministic() async throws {
        let memory = SlidingWindowMemory()
        let provider = MockInferenceProvider(responses: ["winner"])
        let tracer = SwiftLogTracer(minimumLevel: .debug)
        let tool = StubTurnDependencyTool(name: "echo")

        let first = try resolve(explicitProvider: provider, explicitMemory: memory, explicitTracer: tracer, baseTools: [tool])
        let second = try resolve(explicitProvider: provider, explicitMemory: memory, explicitTracer: tracer, baseTools: [tool])

        #expect(sameInstance(first.provider, second.provider))
        #expect(identical(first.memory, second.memory))
        #expect(identical(first.tracer, second.tracer))

        let firstNames = Set(await first.toolRegistry.toolNames)
        let secondNames = Set(await second.toolRegistry.toolNames)
        #expect(firstNames == secondNames)
    }

    // MARK: - Tool registry

    @Test("Resolved tool registry keeps the agent's base tools")
    func toolRegistryPreservesBaseTools() async throws {
        let toolA = StubTurnDependencyTool(name: "alpha")
        let toolB = StubTurnDependencyTool(name: "beta")

        let dependencies = try resolve(baseTools: [toolA, toolB])
        let names = Set(await dependencies.toolRegistry.toolNames)

        #expect(names == ["alpha", "beta"])
    }

    #if SWARM_INTEGRATIONS
    @Test("Ambient web search injects once with environment precedence over global")
    func webSearchInjectionPrecedence() async throws {
        let environmentWeb = WebSearchTool.Configuration(enabled: true)
        let globalWeb = WebSearchTool.Configuration(enabled: false)
        var environment = AgentEnvironment()
        environment.webSearch = environmentWeb

        let fromEnvironment = try resolve(baseTools: [], environment: environment, globalWebSearch: globalWeb)
        var names = await Set(fromEnvironment.toolRegistry.toolNames)
        #expect(names == ["websearch"])

        let fromGlobal = try resolve(baseTools: [], globalWebSearch: globalWeb)
        names = await Set(fromGlobal.toolRegistry.toolNames)
        #expect(names.isEmpty)

        let alreadyAttached = try resolve(
            baseTools: [StubTurnDependencyTool(name: "websearch")],
            environment: environment
        )
        names = await Set(alreadyAttached.toolRegistry.toolNames)
        #expect(names == ["websearch"])
    }
    #endif

    // MARK: - Membrane resolution

    @Test("Membrane adapter defaults to enabled and honors disabled environments")
    func membraneResolution() throws {
        let defaultsEnabled = try resolve(environment: AgentEnvironment())
        #expect(defaultsEnabled.membraneAdapter != nil)
        #expect(defaultsEnabled.membraneEnvironment?.isEnabled == true)

        var absentMembrane = AgentEnvironment()
        absentMembrane.membrane = nil
        let defaulted = try resolve(environment: absentMembrane)
        #expect(defaulted.membraneAdapter != nil)
        #expect(defaulted.membraneEnvironment == nil)

        let disabled = try resolve(environment: AgentEnvironment(membrane: .disabled))
        #expect(disabled.membraneAdapter == nil)
        #expect(disabled.membraneEnvironment?.isEnabled == false)
    }

    // MARK: - Helpers

    private func query(
        configuration: AgentConfiguration = .default,
        explicitProvider: (any InferenceProvider)? = nil,
        explicitMemory: (any Memory)? = nil,
        defaultMemory: (any Memory)? = nil,
        explicitTracer: (any Tracer)? = nil,
        metricsCollector: MetricsCollector? = nil,
        baseTools: [any AnyJSONTool] = [],
        environment: AgentEnvironment = AgentEnvironment(),
        environmentProvider: (any InferenceProvider)? = nil,
        environmentMemory: (any Memory)? = nil,
        globalProvider: (any InferenceProvider)? = nil,
        globalWebSearch: WebSearchTool.Configuration? = nil,
        foundationModels: (any InferenceProvider)?
    ) -> AgentTurnDependencyQuery {
        var resolvedEnvironment = environment
        if let environmentProvider {
            resolvedEnvironment.inferenceProvider = environmentProvider
        }
        if let environmentMemory {
            resolvedEnvironment.memory = environmentMemory
        }
        return AgentTurnDependencyQuery(
            configuration: configuration,
            explicitProvider: explicitProvider,
            explicitMemory: explicitMemory,
            defaultMemory: defaultMemory,
            explicitTracer: explicitTracer,
            metricsCollector: metricsCollector,
            baseTools: baseTools,
            environment: resolvedEnvironment,
            globalProvider: globalProvider,
            globalWebSearch: globalWebSearch,
            foundationModelsProvider: { foundationModels }
        )
    }

    private func resolve(
        configuration: AgentConfiguration = .default,
        explicitProvider providedProvider: (any InferenceProvider)? = nil,
        explicitMemory: (any Memory)? = nil,
        defaultMemory: (any Memory)? = nil,
        explicitTracer: (any Tracer)? = nil,
        metricsCollector: MetricsCollector? = nil,
        baseTools: [any AnyJSONTool] = [],
        environment: AgentEnvironment = AgentEnvironment(),
        environmentProvider: (any InferenceProvider)? = nil,
        globalProvider: (any InferenceProvider)? = nil,
        globalWebSearch: WebSearchTool.Configuration? = nil
    ) throws -> AgentTurnDependencies {
        try AgentTurnDependencyResolver.resolve(
            query(
                configuration: configuration,
                explicitProvider: providedProvider ?? MockInferenceProvider(responses: ["resolve-helper"]),
                explicitMemory: explicitMemory,
                defaultMemory: defaultMemory,
                explicitTracer: explicitTracer,
                metricsCollector: metricsCollector,
                baseTools: baseTools,
                environment: environment,
                environmentProvider: environmentProvider,
                globalProvider: globalProvider,
                globalWebSearch: globalWebSearch,
                foundationModels: nil
            )
        )
    }

    private func sameInstance(_ lhs: some Any, _ rhs: some Any) -> Bool {
        ObjectIdentifier(lhs as AnyObject) == ObjectIdentifier(rhs as AnyObject)
    }

    private func identical(_ lhs: (any Memory)?, _ rhs: (any Memory)?) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return sameInstance(lhs, rhs)
        case (nil, nil):
            return true
        default:
            return false
        }
    }

    private func identical(_ lhs: (any Tracer)?, _ rhs: (any Tracer)?) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return sameInstance(lhs, rhs)
        case (nil, nil):
            return true
        default:
            return false
        }
    }
}

/// Minimal JSON tool used to populate resolved registries.
private struct StubTurnDependencyTool: AnyJSONTool {
    let name: String
    let description = "stub"
    let parameters: [ToolParameter] = []

    init(name: String) {
        self.name = name
    }

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        .string("ok")
    }
}
