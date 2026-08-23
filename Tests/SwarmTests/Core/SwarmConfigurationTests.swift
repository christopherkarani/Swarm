import Foundation
@testable import Swarm
import Testing

// MARK: - SwarmConfigurationTests

@Suite("SwarmConfiguration", .serialized)
struct SwarmConfigurationTests {
    private let _ephemeralDefaultStores = SwarmEphemeralStoreBootstrap.installOnce

    // MARK: Internal

    @Test("configure sets global provider")
    func configureProvider() async throws {
        await withIsolatedConfiguration {
            let mock = MockInferenceProvider()
            await Swarm.configure(provider: mock)
            let resolved = await Swarm.defaultProvider
            #expect(resolved != nil)
        }
    }

    @Test("reset clears all configuration")
    func resetConfiguration() async throws {
        await withIsolatedConfiguration {
            let mock = MockInferenceProvider()
            await Swarm.configure(provider: mock)
            await Swarm.configure(web: testWebConfiguration())
            await Swarm.reset()
            let p = await Swarm.defaultProvider
            let w = await Swarm.webConfiguration
            #expect(p == nil)
            #expect(w == nil)
        }
    }

    @Test("Agent resolves Swarm.defaultProvider when no explicit provider")
    func agentResolvesGlobalProvider() async throws {
        try await withIsolatedConfiguration {
            let mock = MockInferenceProvider(responses: ["from global"])
            await Swarm.configure(provider: mock)
            let agent = try Agent(instructions: "test")
            let result = try await agent.run("hello")
            #expect(result.output == "from global")
        }
    }

    @Test("Explicit provider on Agent takes priority over global")
    func explicitProviderPriority() async throws {
        try await withIsolatedConfiguration {
            let globalMock = MockInferenceProvider(responses: ["from global"])
            let explicitMock = MockInferenceProvider(responses: ["from explicit"])
            await Swarm.configure(provider: globalMock)
            let agent = try Agent(instructions: "test", inferenceProvider: explicitMock)
            let result = try await agent.run("hello")
            #expect(result.output == "from explicit")
        }
    }

    @Test("Agent with tools resolves Swarm.defaultProvider")
    func defaultProviderForToolAgents() async throws {
        try await withIsolatedConfiguration {
            let defaultMock = MockInferenceProvider(responses: ["from default"])
            await Swarm.configure(provider: defaultMock)
            let tool = MockTool(name: "test_tool")
            let agent = try Agent(tools: [tool], instructions: "test")
            let result = try await agent.run("use tool")
            #expect(result.output == "from default")
        }
    }

    @Test("Agent with handoff only resolves Swarm.defaultProvider")
    func defaultProviderForHandoffOnlyAgents() async throws {
        try await withIsolatedConfiguration {
            let defaultMock = MockInferenceProvider(responses: ["from handoff-default"])
            let handoffProvider = MockInferenceProvider(responses: ["unused"])
            await Swarm.configure(provider: defaultMock)

            let handoffTarget = try Agent(instructions: "handoff target", inferenceProvider: handoffProvider)
            let agent = try Agent(instructions: "route", handoffAgents: [handoffTarget])

            let result = try await agent.run("transfer me")
            #expect(result.output == "from handoff-default")
        }
    }

    @Test("unavailable path message does not mention Conduit or cloud packages")
    func unavailableMessageDoesNotMentionConduit() async {
        await withIsolatedConfiguration {
            if DefaultInferenceProviderFactory.makeFoundationModelsProviderIfAvailable() != nil {
                return
            }

            do {
                _ = try await Agent().run("hi")
                Issue.record("Expected inference provider unavailable error")
            } catch let error as AgentError {
                switch error {
                case let .inferenceProviderUnavailable(reason):
                    #expect(reason.contains("Foundation Models"))
                    #expect(reason.contains("Swarm.configure(provider:"))
                    #expect(!reason.localizedCaseInsensitiveContains("Conduit"))
                    #expect(!reason.localizedCaseInsensitiveContains("cloudProvider"))
                    #expect(!reason.localizedCaseInsensitiveContains("OpenAI"))
                    #expect(!reason.localizedCaseInsensitiveContains("Anthropic"))
                default:
                    Issue.record("Unexpected AgentError: \(error)")
                }
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test("configure stores global web configuration")
    func configureWebConfiguration() async throws {
        await withIsolatedConfiguration {
            let configuration = testWebConfiguration(enabled: false)
            await Swarm.configure(web: configuration)

            let resolved = await Swarm.webConfiguration
            #expect(resolved == configuration)
        }
    }

    #if SWARM_INTEGRATIONS
    @Test("Ambient web configuration injects websearch without mutating agent tools")
    func ambientWebConfigurationInjectsWebsearch() async throws {
        try await withIsolatedConfiguration {
            let provider = MockInferenceProvider()
            await provider.configureToolCallingSequence(
                toolCalls: [(
                    name: "websearch",
                    args: [
                        "mode": .string("recall"),
                        "query": .string("current docs"),
                    ]
                )],
                finalAnswer: "done"
            )

            await Swarm.configure(provider: provider)
            await Swarm.configure(web: testWebConfiguration())

            let agent = try Agent(instructions: "Use tools when available.")
            #expect(agent.tools.isEmpty)

            let result = try await agent.run("Find current docs")
            #expect(result.output == "done")
            #expect(result.toolResults.count == 1)
            #expect(result.toolResults.first?.isSuccess == true)
            let toolSummary = result.toolResults.first?.output.stringValue
            #expect(toolSummary?.contains("Recalled 0 cached sections") == true)

            let schemas = await capturedToolSchemas(from: provider)
            #expect(schemas?.contains(where: { $0.name == "websearch" }) == true)
        }
    }

    @Test("Ambient web configuration uses defaultProvider for tool-calling agents")
    func ambientWebConfigurationUsesDefaultProviderWhenNeeded() async throws {
        try await withIsolatedConfiguration {
            let defaultProvider = MockInferenceProvider(responses: ["from default web"])
            await defaultProvider.setToolCallResponses([
                InferenceResponse(content: "from default web", finishReason: .completed),
            ])

            await Swarm.configure(provider: defaultProvider)
            await Swarm.configure(web: testWebConfiguration())

            let agent = try Agent(instructions: "Use web tools.")
            let result = try await agent.run("Research this")

            #expect(result.output == "from default web")
            #expect((await capturedToolSchemas(from: defaultProvider))?.contains(where: { $0.name == "websearch" }) == true)
        }
    }

    @Test("Task-local web configuration overrides global web configuration")
    func taskLocalWebConfigurationOverridesGlobal() async throws {
        try await withIsolatedConfiguration {
            let provider = MockInferenceProvider()
            await provider.setToolCallResponses([
                InferenceResponse(content: "done", finishReason: .completed),
            ])

            await Swarm.configure(provider: provider)
            await Swarm.configure(web: testWebConfiguration(enabled: false))

            let agent = try Agent(instructions: "Use tools when available.")
                .webSearch(testWebConfiguration(enabled: true))

            _ = try await agent.run("Find docs")
            let schemas = await capturedToolSchemas(from: provider)
            #expect(schemas?.contains(where: { $0.name == "websearch" }) == true)
        }
    }

    @Test("Explicit websearch tool takes priority over ambient injection")
    func explicitWebsearchToolTakesPriority() async throws {
        try await withIsolatedConfiguration {
            let provider = MockInferenceProvider()
            await provider.setToolCallResponses([
                InferenceResponse(content: "done", finishReason: .completed),
            ])

            await Swarm.configure(provider: provider)
            await Swarm.configure(web: testWebConfiguration())

            let explicitTool = MockTool(name: "websearch", description: "Explicit override")
            let agent = try Agent(tools: [explicitTool], instructions: "Use the explicit tool.")

            _ = try await agent.run("Search")

            let schemas = await capturedToolSchemas(from: provider) ?? []
            #expect(schemas.filter { $0.name == "websearch" }.count == 1)
            #expect(schemas.first(where: { $0.name == "websearch" })?.description == "Explicit override")
        }
    }
    #endif

    // MARK: Private

    private func withIsolatedConfiguration<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        try await withSwarmConfigurationIsolation(operation)
    }

    private func testWebConfiguration(enabled: Bool = true) -> WebSearchTool.Configuration {
        WebSearchTool.Configuration(
            apiKey: nil,
            persistFetchedArtifacts: false,
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("swarm-web-tests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            enabled: enabled,
            persistEvidenceBundles: false
        )
    }

    private func capturedToolSchemas(from provider: MockInferenceProvider) async -> [ToolSchema]? {
        if let lastCall = await provider.toolCallCalls.last {
            return lastCall.tools
        }
        if let lastCall = await provider.toolCallMessageCalls.last {
            return lastCall.tools
        }
        return nil
    }
}
