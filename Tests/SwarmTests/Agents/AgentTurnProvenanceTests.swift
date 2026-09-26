// AgentTurnProvenanceTests.swift
// SwarmTests
//
// Resolution-provenance tests: every precedence winner names its channel.

import Foundation
@testable import Swarm
import Testing

@Suite("Agent Turn Provenance")
struct AgentTurnProvenanceTests {
    // MARK: - Query purity

    @Test("Query defaults the Foundation Models channel to nil instead of calling the factory")
    func queryDefaultsFoundationModelsToNil() {
        let query = AgentTurnDependencyQuery(configuration: .default)

        #expect(query.foundationModelsProvider == nil)
    }

    // MARK: - Provider provenance (normal policy)

    @Test("Normal policy reports the explicit source when explicit wins")
    func normalPolicyExplicitSource() throws {
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
        #expect(dependencies.providerSource == .explicit)
    }

    @Test("Normal policy provenance follows the environment, global, Foundation Models fallback order")
    func normalPolicyFallbackSources() throws {
        let environment = MockInferenceProvider(responses: ["environment"])
        let global = MockInferenceProvider(responses: ["global"])
        let foundationModels = MockInferenceProvider(responses: ["foundation-models"])

        let fromEnvironment = try AgentTurnDependencyResolver.resolve(
            query(environmentProvider: environment, globalProvider: global, foundationModels: foundationModels)
        )
        #expect(sameInstance(fromEnvironment.provider, environment))
        #expect(fromEnvironment.providerSource == .environment)

        let fromGlobal = try AgentTurnDependencyResolver.resolve(
            query(globalProvider: global, foundationModels: foundationModels)
        )
        #expect(sameInstance(fromGlobal.provider, global))
        #expect(fromGlobal.providerSource == .global)

        let fromFoundationModels = try AgentTurnDependencyResolver.resolve(
            query(foundationModels: foundationModels)
        )
        #expect(sameInstance(fromFoundationModels.provider, foundationModels))
        #expect(fromFoundationModels.providerSource == .foundationModels)
    }

    // MARK: - Provider provenance (privacy-required policy)

    @Test("Privacy-required reports the Foundation Models source ahead of private ambient providers")
    func privacyRequiredFoundationModelsSource() throws {
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
        #expect(dependencies.providerSource == .foundationModels)
    }

    @Test("Privacy-required provenance follows the private explicit, environment, global order")
    func privacyRequiredPrivateAmbientSources() throws {
        let configuration = AgentConfiguration.default.inferencePolicy(InferencePolicy(privacyRequired: true))
        let explicitPrivate = MockInferenceProvider(
            responses: ["explicit"],
            capabilities: [.privateInference]
        )
        let environmentPrivate = MockInferenceProvider(
            responses: ["environment"],
            capabilities: [.privateInference]
        )
        let globalPrivate = MockInferenceProvider(
            responses: ["global"],
            capabilities: [.privateInference]
        )

        let fromExplicit = try AgentTurnDependencyResolver.resolve(query(
            configuration: configuration,
            explicitProvider: explicitPrivate,
            environmentProvider: environmentPrivate,
            globalProvider: globalPrivate
        ))
        #expect(sameInstance(fromExplicit.provider, explicitPrivate))
        #expect(fromExplicit.providerSource == .explicit)

        let fromEnvironment = try AgentTurnDependencyResolver.resolve(query(
            configuration: configuration,
            environmentProvider: environmentPrivate,
            globalProvider: globalPrivate
        ))
        #expect(sameInstance(fromEnvironment.provider, environmentPrivate))
        #expect(fromEnvironment.providerSource == .environment)

        let fromGlobal = try AgentTurnDependencyResolver.resolve(query(
            configuration: configuration,
            globalProvider: globalPrivate
        ))
        #expect(sameInstance(fromGlobal.provider, globalPrivate))
        #expect(fromGlobal.providerSource == .global)
    }

    @Test("Privacy-required skips non-private providers and names the private winner")
    func privacyRequiredSkipsNonPrivateSource() throws {
        let configuration = AgentConfiguration.default.inferencePolicy(InferencePolicy(privacyRequired: true))
        let privateGlobal = MockInferenceProvider(
            responses: ["private-global"],
            capabilities: [.privateInference]
        )

        let dependencies = try AgentTurnDependencyResolver.resolve(query(
            configuration: configuration,
            explicitProvider: MockInferenceProvider(responses: ["non-private-explicit"]),
            environmentProvider: MockInferenceProvider(responses: ["non-private-environment"]),
            globalProvider: privateGlobal
        ))

        #expect(sameInstance(dependencies.provider, privateGlobal))
        #expect(dependencies.providerSource == .global)
    }

    // MARK: - Memory provenance

    @Test("Memory provenance names explicit, environment, fallbackDefault, and none")
    func memorySources() throws {
        let explicit = SlidingWindowMemory()
        let environmentMemory = SlidingWindowMemory()
        let defaultMemory = SlidingWindowMemory()
        let provider = MockInferenceProvider(responses: ["provider"])

        let fromExplicit = try AgentTurnDependencyResolver.resolve(query(
            explicitProvider: provider,
            explicitMemory: explicit,
            defaultMemory: defaultMemory
        ))
        #expect(identical(fromExplicit.memory, explicit as (any Memory)?))
        #expect(fromExplicit.memorySource == .explicit)

        let fromEnvironment = try AgentTurnDependencyResolver.resolve(query(
            explicitProvider: provider,
            environmentMemory: environmentMemory,
            defaultMemory: defaultMemory
        ))
        #expect(identical(fromEnvironment.memory, environmentMemory as (any Memory)?))
        #expect(fromEnvironment.memorySource == .environment)

        let fromDefault = try AgentTurnDependencyResolver.resolve(query(
            explicitProvider: provider,
            defaultMemory: defaultMemory
        ))
        #expect(identical(fromDefault.memory, defaultMemory as (any Memory)?))
        #expect(fromDefault.memorySource == .fallbackDefault)

        let stateless = try AgentTurnDependencyResolver.resolve(query(
            explicitProvider: provider
        ))
        #expect(stateless.memory == nil)
        #expect(stateless.memorySource == .none)
    }

    // MARK: - Tracer provenance

    @Test("Tracer provenance names the explicit and environment channels")
    func tracerConfiguredSources() throws {
        let provider = MockInferenceProvider(responses: ["provider"])
        let explicit = SwiftLogTracer(minimumLevel: .debug)
        let environmentTracer = SwiftLogTracer(minimumLevel: .info)

        let fromExplicit = try AgentTurnDependencyResolver.resolve(query(
            explicitProvider: provider,
            explicitTracer: explicit,
            environmentTracer: environmentTracer
        ))
        #expect(identical(fromExplicit.tracer, explicit as (any Tracer)?))
        #expect(fromExplicit.tracerSource == .explicit)

        let fromEnvironment = try AgentTurnDependencyResolver.resolve(query(
            explicitProvider: provider,
            environmentTracer: environmentTracer
        ))
        #expect(identical(fromEnvironment.tracer, environmentTracer as (any Tracer)?))
        #expect(fromEnvironment.tracerSource == .environment)
    }

    @Test("Tracer provenance names the default-tracing fallback and the absent case")
    func tracerFallbackAndAbsentSources() throws {
        let provider = MockInferenceProvider(responses: ["provider"])

        let fallback = try AgentTurnDependencyResolver.resolve(query(
            configuration: .default.defaultTracingEnabled(true),
            explicitProvider: provider
        ))
        #expect(fallback.tracer != nil)
        #expect(fallback.tracerSource == .fallbackDefault)

        let absent = try AgentTurnDependencyResolver.resolve(query(
            configuration: .default.defaultTracingEnabled(false),
            explicitProvider: provider
        ))
        #expect(absent.tracer == nil)
        #expect(absent.tracerSource == .none)
    }

    @Test("Tracer composition keeps the base channel as provenance")
    func tracerCompositionSources() throws {
        let provider = MockInferenceProvider(responses: ["provider"])
        let tracer = SwiftLogTracer(minimumLevel: .debug)
        let collector = MetricsCollector()

        let composed = try AgentTurnDependencyResolver.resolve(query(
            configuration: .default.autoAttachMetricsCollector(true),
            explicitProvider: provider,
            explicitTracer: tracer,
            metricsCollector: collector
        ))
        #expect(composed.tracer is CompositeTracer)
        #expect(composed.tracerSource == .explicit)

        let collectorOnly = try AgentTurnDependencyResolver.resolve(query(
            configuration: .default.autoAttachMetricsCollector(true).defaultTracingEnabled(false),
            explicitProvider: provider,
            metricsCollector: collector
        ))
        #expect(identical(collectorOnly.tracer, collector as (any Tracer)?))
        #expect(collectorOnly.tracerSource == .fallbackDefault)
    }

    // MARK: - Helpers

    private func query(
        configuration: AgentConfiguration = .default,
        explicitProvider: (any InferenceProvider)? = nil,
        environmentProvider: (any InferenceProvider)? = nil,
        globalProvider: (any InferenceProvider)? = nil,
        foundationModels: (any InferenceProvider)? = nil,
        explicitMemory: (any Memory)? = nil,
        environmentMemory: (any Memory)? = nil,
        defaultMemory: (any Memory)? = nil,
        explicitTracer: (any Tracer)? = nil,
        environmentTracer: (any Tracer)? = nil,
        metricsCollector: MetricsCollector? = nil
    ) -> AgentTurnDependencyQuery {
        var environment = AgentEnvironment()
        environment.inferenceProvider = environmentProvider
        environment.memory = environmentMemory
        environment.tracer = environmentTracer
        return AgentTurnDependencyQuery(
            configuration: configuration,
            explicitProvider: explicitProvider,
            explicitMemory: explicitMemory,
            defaultMemory: defaultMemory,
            explicitTracer: explicitTracer,
            metricsCollector: metricsCollector,
            environment: environment,
            globalProvider: globalProvider,
            foundationModelsProvider: foundationModels
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
