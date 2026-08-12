import Foundation
@testable import Swarm
import Testing

@Suite("Integrations trait gates")
struct IntegrationsTraitGateTests {
    @Test("requirement message names the trait and the rebuild remedy")
    func requirementMessageNamesTraitAndRemedy() {
        let message = IntegrationsTrait.requirementMessage(for: "Web search")
        #expect(message.contains("Web search"))
        #expect(message.contains("Integrations trait"))
        #expect(message.contains("--traits Integrations"))
        #expect(message.contains("traits: [\"Integrations\"]"))
    }

    @Test("WebSearchTool reports availability and fails at construction-time warning plus execute")
    func webSearchToolFailsEarly() async throws {
        IntegrationsTraitTesting.reset()
        #expect(WebSearchTool.isAvailable == IntegrationsTrait.isEnabled)

        let tool = WebSearchTool(apiKey: "test-key")

        #if SWARM_INTEGRATIONS
        #expect(IntegrationsTraitTesting.warnings.isEmpty)
        #else
        #expect(
            IntegrationsTraitTesting.warnings.contains { warning in
                warning.contains("Web search")
                    && warning.contains("--traits Integrations")
                    && warning.contains("traits: [\"Integrations\"]")
            }
        )

        do {
            _ = try await tool.execute()
            Issue.record("WebSearchTool.execute should throw on lean builds")
        } catch let error as AgentError {
            let description = String(describing: error)
            #expect(description.contains("Web search"))
            #expect(description.contains("Integrations trait"))
            #expect(description.contains("--traits Integrations"))
            #expect(description.contains("traits: [\"Integrations\"]"))
        }

        do {
            _ = try await tool.execute(arguments: ["query": .string("swift")])
            Issue.record("WebSearchTool.execute(arguments:) should throw on lean builds")
        } catch let error as AgentError {
            let description = String(describing: error)
            #expect(description.contains("--traits Integrations"))
        }
        #endif
    }

    @Test("durable checkpoint factories warn immediately and execute throws the remedy on lean")
    func durableCheckpointingFailsEarly() async throws {
        IntegrationsTraitTesting.reset()
        #expect(WorkflowCheckpointing.isAvailable == IntegrationsTrait.isEnabled)
        #expect(Workflow.Durable.isAvailable == IntegrationsTrait.isEnabled)

        _ = WorkflowCheckpointing.inMemory()
        let workflow = Workflow()
            .step(MockAgentRuntime(response: "ok"))
            .durable.checkpoint(id: "lean-trap")
            .durable.checkpointing(.fileSystem(directory: FileManager.default.temporaryDirectory))

        #if SWARM_INTEGRATIONS
        #expect(IntegrationsTraitTesting.warnings.isEmpty)
        #else
        #expect(
            IntegrationsTraitTesting.warnings.contains { warning in
                warning.contains("Durable workflow checkpointing")
                    && warning.contains("--traits Integrations")
                    && warning.contains("traits: [\"Integrations\"]")
            }
        )

        do {
            _ = try await workflow.durable.execute("hello")
            Issue.record("durable execute should throw on lean builds when checkpointing is configured")
        } catch let error as WorkflowError {
            let description = error.localizedDescription
            #expect(description.contains("Durable workflow execution"))
            #expect(description.contains("Integrations trait"))
            #expect(description.contains("--traits Integrations"))
            #expect(description.contains("traits: [\"Integrations\"]"))
        }
        #endif
    }

    @Test("ambient web configuration warns at the Swarm.configure touchpoint on lean")
    func configureWebWarnsOnLean() async {
        await withSwarmConfigurationIsolation {
            IntegrationsTraitTesting.reset()
            await Swarm.configure(web: WebSearchTool.Configuration(apiKey: "test-key", enabled: true))

            #if SWARM_INTEGRATIONS
            #expect(IntegrationsTraitTesting.warnings.isEmpty)
            #else
            #expect(
                IntegrationsTraitTesting.warnings.contains { warning in
                    warning.contains("Web search") && warning.contains("--traits Integrations")
                }
            )
            #endif
        }
    }

    @Test("Memory.vector is not trait-gated")
    func vectorMemoryIsAvailableWithoutIntegrations() async {
        let memory: VectorMemory = .vector(
            embeddingProvider: MockEmbeddingProvider(),
            similarityThreshold: 0.75
        )
        #expect(await memory.isEmpty)
    }
}
