// AgentRunEnvironmentTests.swift
// SwarmTests
//
// Proves AgentRunEnvironment isolation semantics (AC-005) and the extracted
// AgentDependencyResolver decisions.

import Foundation
import Testing
@testable import Swarm

// MARK: - Test Doubles

private actor StubTracer: Tracer {
    func trace(_ event: TraceEvent) {}
}

private struct BareInferenceProvider: InferenceProvider {
    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        "bare"
    }
}

private final class LookupCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private func sameInstance(_ lhs: any InferenceProvider, _ rhs: any InferenceProvider) -> Bool {
    ObjectIdentifier(lhs as AnyObject) == ObjectIdentifier(rhs as AnyObject)
}

private func makeAgent(
    configuration: AgentConfiguration,
    provider: MockInferenceProvider,
    environment: AgentRunEnvironment
) throws -> Agent {
    try Agent(
        configuration: configuration,
        inferenceProvider: provider,
        runEnvironment: environment
    )
}

// MARK: - Environment Isolation & Default Sharing

@Suite("AgentRunEnvironment", .ephemeralDefaultStores)
struct AgentRunEnvironmentTests {

    private let config = AgentConfiguration.default.autoPreviousResponseId(true)

    @Test("two constructed environments carry fully isolated tracker state")
    func constructedEnvironmentsAreIsolated() async throws {
        let first = AgentRunEnvironment()
        let second = AgentRunEnvironment()

        #expect(first.responseTracker !== second.responseTracker)
        #expect(first.defaultMemorySessionTracker !== second.defaultMemorySessionTracker)

        let response = AgentResponse(responseId: "first-env-response", output: "hi", agentName: "A")
        await first.responseTracker.recordResponse(response, sessionId: "isolation-session")

        let leaked = await second.responseTracker.getLatestResponseId(for: "isolation-session")
        #expect(leaked == nil)

        let own = await first.responseTracker.getLatestResponseId(for: "isolation-session")
        #expect(own == "first-env-response")
    }

    @Test("default-configured agents share one environment exactly as the former globals")
    func defaultAgentsShareLiveEnvironment() throws {
        let first = try Agent(configuration: .default)
        let second = try Agent(configuration: .default)

        #expect(first.runEnvironment.responseTracker === second.runEnvironment.responseTracker)
        #expect(
            first.runEnvironment.defaultMemorySessionTracker
                === second.runEnvironment.defaultMemorySessionTracker
        )
        #expect(first.runEnvironment.responseTracker === AgentRunEnvironment.live.responseTracker)
        #expect(
            first.runEnvironment.defaultMemorySessionTracker
                === AgentRunEnvironment.live.defaultMemorySessionTracker
        )

        // Former process-global statics delegate to the shared default instance.
        #expect(Agent.autoResponseTracker === first.runEnvironment.responseTracker)
        #expect(Agent.defaultMemorySessionTracker === first.runEnvironment.defaultMemorySessionTracker)
    }

    @Test("explicit default memory store URL threads through to default memory creation")
    func explicitDefaultMemoryStoreURLThreadsThrough() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentRunEnvironmentTests", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).mv2s")

        let agent = try makeAgent(
            configuration: config,
            provider: MockInferenceProvider(responses: ["ok"]),
            environment: AgentRunEnvironment(defaultMemoryStoreURL: storeURL)
        )

        #expect(agent.runEnvironment.defaultMemoryStoreURL == storeURL)
        #expect(AgentRunEnvironment.live.defaultMemoryStoreURL == nil)

        #if SWARM_INTEGRATIONS && canImport(ContextCore)
        let memory = try Agent.makeDefaultMemory(waxStoreURL: storeURL)
        #expect(memory is DefaultAgentMemory)
        #endif
    }

    @Test("agents using defaults share response tracking across copies")
    func defaultAgentsShareTrackerStateAcrossRuns() async throws {
        let sessionID = "shared-default-\(UUID().uuidString)"
        let session = InMemorySession(sessionId: sessionID)
        let provider = MockInferenceProvider(
            responses: ["first reply", "second reply"],
            capabilities: [.responseContinuation]
        )

        let first = try Agent(configuration: config, inferenceProvider: provider)
        let second = try Agent(configuration: config, inferenceProvider: provider)

        let firstResult = try await first.run("first prompt", session: session)
        _ = try await second.run("second prompt", session: session)

        guard case let .string(firstResponseID)? = firstResult.metadata["response.id"] else {
            Issue.record("Expected first result metadata to include response.id")
            return
        }

        let calls = await provider.generateMessageCalls
        #expect(calls.count == 2)
        if calls.count == 2 {
            #expect(calls[0].options.previousResponseId == nil)
            #expect(calls[1].options.previousResponseId == firstResponseID)
        }
    }

    @Test("agents with distinct environments isolate response tracking across copies")
    func distinctEnvironmentsIsolateTrackingAcrossRuns() async throws {
        let sessionID = "isolated-envs-\(UUID().uuidString)"
        let session = InMemorySession(sessionId: sessionID)
        let provider = MockInferenceProvider(
            responses: ["first reply", "second reply"],
            capabilities: [.responseContinuation]
        )

        let first = try makeAgent(
            configuration: config,
            provider: provider,
            environment: AgentRunEnvironment()
        )
        let second = try makeAgent(
            configuration: config,
            provider: provider,
            environment: AgentRunEnvironment()
        )

        let firstResult = try await first.run("first prompt", session: session)
        _ = try await second.run("second prompt", session: session)

        guard case let .string(firstResponseID)? = firstResult.metadata["response.id"] else {
            Issue.record("Expected first result metadata to include response.id")
            return
        }
        #expect(!firstResponseID.isEmpty)

        let calls = await provider.generateMessageCalls
        #expect(calls.count == 2)
        if calls.count == 2 {
            #expect(calls[0].options.previousResponseId == nil)
            #expect(calls[1].options.previousResponseId == nil)
        }
    }

    @Test("session tracker clears memory only when the session changes")
    func sessionTrackerClearsOnlyOnSessionChange() async throws {
        let tracker = DefaultMemorySessionTracker()
        let key = ObjectIdentifier(NSObject())

        let firstClaim = try await tracker.beginRun(for: key, sessionID: "s1")
        #expect(firstClaim == true)

        // Same session re-claiming while active must not trigger a memory clear.
        let reentrantClaim = try await tracker.beginRun(for: key, sessionID: "s1")
        #expect(reentrantClaim == false)

        await tracker.endRun(for: key)
        await tracker.endRun(for: key)

        let changedClaim = try await tracker.beginRun(for: key, sessionID: "s2")
        #expect(changedClaim == true)

        await tracker.endRun(for: key)
    }

    @Test("session tracker state is isolated between instances")
    func sessionTrackerStateIsPerInstance() async throws {
        let first = DefaultMemorySessionTracker()
        let second = DefaultMemorySessionTracker()
        let key = ObjectIdentifier(NSObject())

        let firstResult = try await first.beginRun(for: key, sessionID: "shared-session")
        let secondResult = try await second.beginRun(for: key, sessionID: "shared-session")

        #expect(firstResult == true)
        #expect(secondResult == true)
    }
}

// MARK: - Resolver Decisions

@Suite("AgentDependencyResolver")
struct AgentDependencyResolverTests {
    // MARK: Tracer composition

    @Test("active tracer prefers explicit over environment over fallback")
    func activeTracerPrecedence() {
        let explicit = StubTracer()
        let environment = StubTracer()

        let explicitWins = AgentDependencyResolver.activeTracer(
            explicitTracer: explicit,
            environmentTracer: environment,
            defaultTracingEnabled: true,
            autoAttachMetricsCollector: false,
            metricsCollector: nil
        )
        #expect(explicitWins === explicit)

        let environmentUsed = AgentDependencyResolver.activeTracer(
            explicitTracer: nil,
            environmentTracer: environment,
            defaultTracingEnabled: true,
            autoAttachMetricsCollector: false,
            metricsCollector: nil
        )
        #expect(environmentUsed === environment)
    }

    @Test("active tracer falls back to SwiftLog tracer only when default tracing is enabled")
    func activeTracerFallback() {
        let fallback = AgentDependencyResolver.activeTracer(
            explicitTracer: nil,
            environmentTracer: nil,
            defaultTracingEnabled: true,
            autoAttachMetricsCollector: false,
            metricsCollector: nil
        )
        #expect(fallback is SwiftLogTracer)

        let silent = AgentDependencyResolver.activeTracer(
            explicitTracer: nil,
            environmentTracer: nil,
            defaultTracingEnabled: false,
            autoAttachMetricsCollector: false,
            metricsCollector: nil
        )
        #expect(silent == nil)
    }

    @Test("metrics collector composes into the tracer chain per auto-attach flag")
    func activeTracerComposesMetricsCollector() {
        let base = StubTracer()
        let collector = MetricsCollector()

        let composed = AgentDependencyResolver.activeTracer(
            explicitTracer: base,
            environmentTracer: nil,
            defaultTracingEnabled: false,
            autoAttachMetricsCollector: true,
            metricsCollector: collector
        )
        #expect(composed is CompositeTracer)

        let passthrough = AgentDependencyResolver.activeTracer(
            explicitTracer: collector,
            environmentTracer: nil,
            defaultTracingEnabled: false,
            autoAttachMetricsCollector: true,
            metricsCollector: collector
        )
        #expect(passthrough === collector)

        let collectorOnly = AgentDependencyResolver.activeTracer(
            explicitTracer: nil,
            environmentTracer: nil,
            defaultTracingEnabled: false,
            autoAttachMetricsCollector: true,
            metricsCollector: collector
        )
        #expect(collectorOnly === collector)

        let detached = AgentDependencyResolver.activeTracer(
            explicitTracer: base,
            environmentTracer: nil,
            defaultTracingEnabled: false,
            autoAttachMetricsCollector: false,
            metricsCollector: collector
        )
        #expect(detached === base)
    }

    // MARK: Inference provider resolution

    @Test("non-private resolution prefers explicit, then environment, then global lookup")
    func providerResolutionOrder() async throws {
        let explicit = MockInferenceProvider(responses: ["explicit"])
        let environment = MockInferenceProvider(responses: ["environment"])
        let global = MockInferenceProvider(responses: ["global"])
        let emptyEnvironment = AgentEnvironment()

        let fromExplicit = try await AgentDependencyResolver.inferenceProvider(
            privacyRequired: false,
            explicitProvider: explicit,
            environment: emptyEnvironment,
            runEnvironment: AgentRunEnvironment(defaultProvider: { global })
        )
        #expect(sameInstance(fromExplicit, explicit))

        let fromEnvironment = try await AgentDependencyResolver.inferenceProvider(
            privacyRequired: false,
            explicitProvider: nil,
            environment: AgentEnvironment(inferenceProvider: environment),
            runEnvironment: AgentRunEnvironment(defaultProvider: { global })
        )
        #expect(sameInstance(fromEnvironment, environment))

        let fromGlobal = try await AgentDependencyResolver.inferenceProvider(
            privacyRequired: false,
            explicitProvider: nil,
            environment: emptyEnvironment,
            runEnvironment: AgentRunEnvironment(defaultProvider: { global })
        )
        #expect(sameInstance(fromGlobal, global))
    }

    @Test("global lookup is skipped while an explicit or environment provider exists")
    func providerGlobalLookupLaziness() async throws {
        let counter = LookupCounter()
        let explicit = MockInferenceProvider(responses: ["explicit"])
        let global = MockInferenceProvider(responses: ["global"])

        _ = try await AgentDependencyResolver.inferenceProvider(
            privacyRequired: false,
            explicitProvider: explicit,
            environment: AgentEnvironment(),
            runEnvironment: AgentRunEnvironment(defaultProvider: {
                counter.increment()
                return global
            })
        )
        #expect(counter.value == 0)

        _ = try await AgentDependencyResolver.inferenceProvider(
            privacyRequired: false,
            explicitProvider: nil,
            environment: AgentEnvironment(),
            runEnvironment: AgentRunEnvironment(defaultProvider: {
                counter.increment()
                return global
            })
        )
        #expect(counter.value == 1)
    }

    @Test("environment transform wraps whichever provider resolution selects")
    func providerTransformApplied() async throws {
        let base = MockInferenceProvider(responses: ["base"])
        let wrapped = MockInferenceProvider(responses: ["wrapped"])
        var environment = AgentEnvironment()
        environment.inferenceProviderTransform = { _ in wrapped }

        let resolved = try await AgentDependencyResolver.inferenceProvider(
            privacyRequired: false,
            explicitProvider: base,
            environment: environment,
            runEnvironment: AgentRunEnvironment()
        )
        #expect(sameInstance(resolved, wrapped))
    }

    @Test("foundation models fill in only when no configured source resolves")
    func providerFoundationModelsFallback() async throws {
        let foundationModels = MockInferenceProvider(responses: ["on-device"])

        let fromFoundationModels = try await AgentDependencyResolver.inferenceProvider(
            privacyRequired: false,
            explicitProvider: nil,
            environment: AgentEnvironment(),
            runEnvironment: AgentRunEnvironment(defaultProvider: { nil }),
            foundationModelsProvider: { foundationModels }
        )
        #expect(sameInstance(fromFoundationModels, foundationModels))
    }

    @Test("globally configured provider wins over the foundation models fallback")
    func providerGlobalBeatsFoundationModels() async throws {
        let foundationModels = MockInferenceProvider(responses: ["on-device"])
        let global = MockInferenceProvider(responses: ["global"])

        let resolved = try await AgentDependencyResolver.inferenceProvider(
            privacyRequired: false,
            explicitProvider: nil,
            environment: AgentEnvironment(),
            runEnvironment: AgentRunEnvironment(defaultProvider: { global }),
            foundationModelsProvider: { foundationModels }
        )
        #expect(sameInstance(resolved, global))
    }

    @Test("resolution throws when no source can supply a provider")
    func providerUnavailableThrows() async throws {
        do {
            _ = try await AgentDependencyResolver.inferenceProvider(
                privacyRequired: false,
                explicitProvider: nil,
                environment: AgentEnvironment(),
                runEnvironment: AgentRunEnvironment(defaultProvider: { nil }),
                foundationModelsProvider: { nil }
            )
            Issue.record("Expected inferenceProviderUnavailable")
        } catch let error as AgentError {
            guard case .inferenceProviderUnavailable = error else {
                Issue.record("Unexpected AgentError case: \(error)")
                return
            }
        }
    }

    // MARK: Privacy filtering

    @Test("privacy filter keeps only providers reporting privateInference")
    func privacyFilterBranches() {
        let publicProvider = MockInferenceProvider(responses: ["public"])
        let privateProvider = MockInferenceProvider(responses: ["private"], capabilities: [.privateInference])

        #expect(AgentDependencyResolver.privateInferenceProvider(nil) == nil)
        #expect(AgentDependencyResolver.privateInferenceProvider(publicProvider) == nil)

        let kept = AgentDependencyResolver.privateInferenceProvider(privateProvider)
        #expect(kept != nil)
        if let kept {
            #expect(sameInstance(kept, privateProvider))
        }
    }

    @Test("privacy-required resolution prefers on-device and filters non-private sources")
    func privacyRequiredResolutionOrder() async throws {
        let nonPrivate = MockInferenceProvider(responses: ["non-private"])
        let privateProvider = MockInferenceProvider(responses: ["private"], capabilities: [.privateInference])
        let foundationModels = MockInferenceProvider(responses: ["on-device"])
        let filteredEnvironment = AgentEnvironment(inferenceProvider: nonPrivate)

        let onDeviceWins = try await AgentDependencyResolver.inferenceProvider(
            privacyRequired: true,
            explicitProvider: nonPrivate,
            environment: filteredEnvironment,
            runEnvironment: AgentRunEnvironment(defaultProvider: { nonPrivate }),
            foundationModelsProvider: { foundationModels }
        )
        #expect(sameInstance(onDeviceWins, foundationModels))

        let explicitPrivateWins = try await AgentDependencyResolver.inferenceProvider(
            privacyRequired: true,
            explicitProvider: privateProvider,
            environment: filteredEnvironment,
            runEnvironment: AgentRunEnvironment(defaultProvider: { nonPrivate }),
            foundationModelsProvider: { nil }
        )
        #expect(sameInstance(explicitPrivateWins, privateProvider))

        let environmentPrivateWins = try await AgentDependencyResolver.inferenceProvider(
            privacyRequired: true,
            explicitProvider: nil,
            environment: AgentEnvironment(inferenceProvider: privateProvider),
            runEnvironment: AgentRunEnvironment(defaultProvider: { nonPrivate }),
            foundationModelsProvider: { nil }
        )
        #expect(sameInstance(environmentPrivateWins, privateProvider))

        let globalPrivateWins = try await AgentDependencyResolver.inferenceProvider(
            privacyRequired: true,
            explicitProvider: nonPrivate,
            environment: filteredEnvironment,
            runEnvironment: AgentRunEnvironment(defaultProvider: { privateProvider }),
            foundationModelsProvider: { nil }
        )
        #expect(sameInstance(globalPrivateWins, privateProvider))

        do {
            _ = try await AgentDependencyResolver.inferenceProvider(
                privacyRequired: true,
                explicitProvider: nonPrivate,
                environment: filteredEnvironment,
                runEnvironment: AgentRunEnvironment(defaultProvider: { nonPrivate }),
                foundationModelsProvider: { nil }
            )
            Issue.record("Expected inferenceProviderUnavailable for all-non-private sources")
        } catch let error as AgentError {
            guard case .inferenceProviderUnavailable = error else {
                Issue.record("Unexpected AgentError case: \(error)")
                return
            }
        }
    }

    // MARK: Memory & runtime environment

    @Test("memory resolution follows explicit, environment, then default precedence")
    func memoryPrecedence() {
        let explicit = SlidingWindowMemory()
        let ambient = SlidingWindowMemory()
        let fallback = SlidingWindowMemory()

        let usesExplicit = AgentDependencyResolver.memory(
            explicitMemory: explicit,
            environmentMemory: ambient,
            defaultMemory: fallback
        )
        #expect(usesExplicit === explicit)

        let usesEnvironment = AgentDependencyResolver.memory(
            explicitMemory: nil,
            environmentMemory: ambient,
            defaultMemory: fallback
        )
        #expect(usesEnvironment === ambient)

        let usesDefault = AgentDependencyResolver.memory(
            explicitMemory: nil,
            environmentMemory: nil,
            defaultMemory: fallback
        )
        #expect(usesDefault === fallback)

        #expect(AgentDependencyResolver.memory(explicitMemory: nil, environmentMemory: nil, defaultMemory: nil) == nil)
    }

    @Test("runtime environment merges the provider token counter when present")
    func runtimeEnvironmentTokenCounterMerge() {
        func identity(_ counter: any PromptTokenCounter) -> ObjectIdentifier {
            ObjectIdentifier(counter as AnyObject)
        }

        let countingProvider = MockInferenceProvider(responses: ["counted"])
        let bare = BareInferenceProvider()
        let originalCounter = EstimatedPromptTokenCounter.shared
        let environment = AgentEnvironment(promptTokenCounter: originalCounter)

        let merged = AgentDependencyResolver.runtimeEnvironment(environment, addingTokenCounterFrom: countingProvider)
        #expect(identity(merged.promptTokenCounter) == identity(countingProvider))

        let preserved = AgentDependencyResolver.runtimeEnvironment(environment, addingTokenCounterFrom: bare)
        #expect(identity(preserved.promptTokenCounter) == identity(originalCounter))
    }

    // MARK: Tool registry

    @Test("tool registry preserves the agent's registered tools")
    func toolRegistryRoundTripsBaseTools() async throws {
        let registry = try ToolRegistry(tools: [MockTool(name: "marker")])
        let resolved = try await AgentDependencyResolver.toolRegistry(
            baseTools: await registry.allTools,
            taskLocalWebSearch: nil,
            runEnvironment: AgentRunEnvironment(webConfiguration: { nil })
        )

        let names = await resolved.toolNames
        #expect(names == ["marker"])
    }

    // MARK: Inference options assembly

    @Test("previous response id is stripped without continuation capability")
    func optionsStripWithoutContinuationSupport() async {
        var configuration = AgentConfiguration.default
        configuration.autoPreviousResponseId = true

        let options = await AgentDependencyResolver.inferenceOptions(
            configuration: configuration,
            capabilities: [],
            sessionID: "any",
            responseTracker: ResponseTracker()
        )
        #expect(options.previousResponseId == nil)
    }

    @Test("configured previous response id trims whitespace and beats auto tracking")
    func optionsExplicitIDWins() async throws {
        var configuration = AgentConfiguration.default
        configuration.autoPreviousResponseId = true
        configuration.previousResponseId = "  explicit-id  "

        let options = await AgentDependencyResolver.inferenceOptions(
            configuration: configuration,
            capabilities: [.responseContinuation],
            sessionID: "session-a",
            responseTracker: ResponseTracker()
        )
        #expect(options.previousResponseId == "explicit-id")
    }

    @Test("auto tracking reads the latest response id from the shared tracker")
    func optionsAutoTracksLatestResponse() async throws {
        var configuration = AgentConfiguration.default
        configuration.autoPreviousResponseId = true

        let tracker = ResponseTracker()
        let response = AgentResponse(responseId: "tracked-1", output: "out", agentName: "A")
        await tracker.recordResponse(response, sessionId: "session-b")

        let options = await AgentDependencyResolver.inferenceOptions(
            configuration: configuration,
            capabilities: [.responseContinuation],
            sessionID: "session-b",
            responseTracker: tracker
        )
        #expect(options.previousResponseId == "tracked-1")

        let unknownSession = await AgentDependencyResolver.inferenceOptions(
            configuration: configuration,
            capabilities: [.responseContinuation],
            sessionID: "unknown-session",
            responseTracker: tracker
        )
        #expect(unknownSession.previousResponseId == nil)
    }

    @Test("auto tracking requires a session and stays inert when disabled")
    func optionsAutoRequiresSessionAndFlag() async throws {
        var disabled = AgentConfiguration.default
        disabled.previousResponseId = nil

        let tracker = ResponseTracker()
        let response = AgentResponse(responseId: "tracked-2", output: "out", agentName: "A")
        await tracker.recordResponse(response, sessionId: "session-c")

        let noSession = await AgentDependencyResolver.inferenceOptions(
            configuration: disabled,
            capabilities: [.responseContinuation],
            sessionID: nil,
            responseTracker: tracker
        )
        #expect(noSession.previousResponseId == nil)

        var flagOff = disabled
        flagOff.autoPreviousResponseId = false
        let flagOffResult = await AgentDependencyResolver.inferenceOptions(
            configuration: flagOff,
            capabilities: [.responseContinuation],
            sessionID: "session-c",
            responseTracker: tracker
        )
        #expect(flagOffResult.previousResponseId == nil)
    }
}
