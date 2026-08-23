// AgentModifiersTests.swift
// SwarmTests
//
// Tests for V3 Agent modifier chain and callAsFunction.

import Testing
@testable import Swarm

// MARK: - Minimal Tool Conformers

/// Lightweight Tool conformer for modifier tests.
private struct PingTool: Tool {
    struct Input: Codable, Sendable { let message: String }
    typealias Output = String

    let name = "ping"
    let description = "Ping tool"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "message", description: "Message", type: .string)
    ]
    func execute(_ input: Input) async throws -> String { "pong: \(input.message)" }
}

/// A second minimal Tool conformer.
private struct PongTool: Tool {
    struct Input: Codable, Sendable { let value: Int }
    typealias Output = String

    let name = "pong"
    let description = "Pong tool"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "value", description: "Integer value", type: .int)
    ]
    func execute(_ input: Input) async throws -> String { "\(input.value)" }
}

// MARK: - Agent V3 Modifiers Tests

@Suite("Agent V3 Modifiers", .ephemeralDefaultStores)
struct AgentModifiersTests {


    // MARK: - Canonical Init

    @Test("canonical init with instructions only")
    func minimalInit() throws {
        let agent = try Agent("You are helpful")
        #expect(agent.instructions == "You are helpful")
        #expect(agent.tools.isEmpty)
    }

    @Test("canonical init with explicit provider overload")
    func initWithProvider() throws {
        let provider = MockInferenceProvider()
        let agent = try Agent("You are helpful", provider: provider)
        #expect(agent.instructions == "You are helpful")
        #expect(agent.inferenceProvider != nil)
    }

    @Test("canonical init with provider and tool builder")
    func initWithProviderAndTools() throws {
        let provider = MockInferenceProvider()
        let agent = try Agent("You are helpful", provider: provider) {
            PingTool()
        }
        #expect(agent.tools.count == 1)
        #expect(agent.inferenceProvider != nil)
    }

    // MARK: - Memory Modifier

    @Test("memory modifier sets memory")
    func memoryModifier() throws {
        let agent = try Agent("test")
            .withMemory(ConversationMemory(maxMessages: 50))
        #expect(agent.memory != nil)
    }

    @Test("memory modifier is copy-on-write — original unchanged")
    func memoryCopyOnWrite() throws {
        let original = try Agent("test")
        let modified = original.withMemory(ConversationMemory())
        #expect(original.memory == nil)
        #expect(modified.memory != nil)
    }

    // MARK: - Tracer Modifier

    @Test("tracer modifier sets tracer")
    func tracerModifier() throws {
        let agent = try Agent("test")
            .withTracer(SwiftLogTracer(minimumLevel: .debug))
        #expect(agent.tracer != nil)
    }

    @Test("tracer modifier is copy-on-write — original unchanged")
    func tracerCopyOnWrite() throws {
        let original = try Agent("test")
        let modified = original.withTracer(SwiftLogTracer(minimumLevel: .debug))
        #expect(original.tracer == nil)
        #expect(modified.tracer != nil)
    }

    // MARK: - Guardrails Modifier

    @Test("guardrails modifier with empty arrays is a no-op on existing values")
    func guardrailsModifierEmpty() throws {
        let agent = try Agent("test")
            .withGuardrails()
        #expect(agent.inputGuardrails.isEmpty)
        #expect(agent.outputGuardrails.isEmpty)
    }

    @Test("guardrails modifier preserves other properties")
    func guardrailsModifierPreservesInstructions() throws {
        let agent = try Agent("preserve me")
            .withGuardrails(input: [], output: [])
        #expect(agent.instructions == "preserve me")
    }

    // MARK: - Tools Modifier (array overload)

    @Test("tools modifier with array replaces tools")
    func toolsArrayModifier() throws {
        let tools: [any Tool] = [PingTool(), PongTool()]
        let agent = try Agent("test")
            .withTools(tools)
        #expect(agent.tools.count == 2)
    }

    @Test("tools modifier with array replaces existing tools")
    func toolsArrayReplacesExistingTools() throws {
        let agent = try Agent("test") {
            PingTool()
            PongTool()
        }
        let replacementTools: [any Tool] = [PingTool()]
        let modified = try agent.withTools(replacementTools)
        #expect(modified.tools.count == 1)
    }

    @Test("tools modifier with array throws duplicate tool names")
    func toolsArrayModifierThrowsDuplicateNames() throws {
        let tools: [any Tool] = [PingTool(), PingTool()]
        #expect(throws: ToolRegistryError.self) {
            _ = try Agent("test").withTools(tools)
        }
    }

    @Test("tools modifier with empty array clears tools")
    func toolsArrayModifierEmpty() throws {
        let emptyTools: [any Tool] = []
        let agent = try Agent("test") {
            PingTool()
        }
        .withTools(emptyTools)
        #expect(agent.tools.isEmpty)
    }

    // MARK: - Tools Modifier (builder overload)

    @Test("tools builder modifier sets tools")
    func toolsBuilderModifier() throws {
        let agent = try Agent("test")
            .withTools {
                PingTool()
                PongTool()
            }
        #expect(agent.tools.count == 2)
    }

    @Test("tools builder modifier replaces previously set tools")
    func toolsBuilderModifierReplaces() throws {
        let agent = try Agent("test") {
            PingTool()
            PongTool()
        }
        .withTools {
            PingTool()
        }
        #expect(agent.tools.count == 1)
        #expect(agent.tools[0].name == "ping")
    }

    @Test("tools builder modifier with empty closure clears tools")
    func toolsBuilderModifierEmptyClosure() throws {
        let agent = try Agent("test") {
            PingTool()
        }
        .withTools { }
        #expect(agent.tools.isEmpty)
    }

    @Test("tools builder modifier throws duplicate tool names")
    func toolsBuilderModifierThrowsDuplicateNames() throws {
        #expect(throws: ToolRegistryError.self) {
            _ = try Agent("test").withTools {
                PingTool()
                PingTool()
            }
        }
    }

    // MARK: - Configuration Modifier

    @Test("configuration modifier sets config")
    func configModifier() throws {
        let config = AgentConfiguration.default.name("TestAgent").maxIterations(5)
        let agent = try Agent("test")
            .withConfiguration(config)
        #expect(agent.configuration.name == "TestAgent")
        #expect(agent.configuration.maxIterations == 5)
    }

    @Test("configuration modifier is copy-on-write")
    func configCopyOnWrite() throws {
        let original = try Agent("test")
        let modified = original.withConfiguration(.default.name("Modified"))
        #expect(original.configuration.name == "Agent")
        #expect(modified.configuration.name == "Modified")
    }

    // MARK: - Handoffs Modifier

    @Test("handoffs modifier sets agents")
    func handoffsModifier() throws {
        let helper = try Agent("I help")
        let agent = try Agent("I triage")
            .withHandoffs([helper])
        #expect(agent.handoffs.count == 1)
    }

    @Test("handoffs modifier with multiple agents")
    func handoffsModifierMultiple() throws {
        let helper1 = try Agent("helper one")
        let helper2 = try Agent("helper two")
        let agent = try Agent("triage")
            .withHandoffs([helper1, helper2])
        #expect(agent.handoffs.count == 2)
    }

    @Test("handoffs modifier is copy-on-write")
    func handoffsCopyOnWrite() throws {
        let original = try Agent("test")
        let helper = try Agent("helper")
        let modified = original.withHandoffs([helper])
        #expect(original.handoffs.isEmpty)
        #expect(modified.handoffs.count == 1)
    }

    // MARK: - Modifier Chaining

    @Test("modifier chaining preserves all config")
    func chainingPreservesConfig() throws {
        let agent = try Agent("test instructions") {
            PingTool()
        }
        .withMemory(ConversationMemory())
        .withTracer(SwiftLogTracer(minimumLevel: .debug))

        #expect(agent.instructions == "test instructions")
        #expect(agent.tools.count == 1)
        #expect(agent.memory != nil)
        #expect(agent.tracer != nil)
    }

    @Test("full modifier chain end to end")
    func fullModifierChain() throws {
        let helper = try Agent("I help with billing")
        let config = AgentConfiguration.default.name("Triage").maxIterations(10)

        let agent = try Agent("Route requests") {
            PingTool()
        }
        .withMemory(ConversationMemory(maxMessages: 20))
        .withTracer(SwiftLogTracer(minimumLevel: .info))
        .withGuardrails()
        .withConfiguration(config)
        .withHandoffs([helper])

        #expect(agent.instructions == "Route requests")
        #expect(agent.tools.count == 1)
        #expect(agent.memory != nil)
        #expect(agent.tracer != nil)
        #expect(agent.configuration.name == "Triage")
        #expect(agent.handoffs.count == 1)
    }

    @Test("each modifier creates independent copy")
    func modifierIndependence() throws {
        let base = try Agent("base")
        let withMemory = base.withMemory(ConversationMemory())
        let withTracer = base.withTracer(SwiftLogTracer(minimumLevel: .debug))

        // base is unmodified
        #expect(base.memory == nil)
        #expect(base.tracer == nil)

        // each derived copy has only its own modification
        #expect(withMemory.memory != nil)
        #expect(withMemory.tracer == nil)

        #expect(withTracer.tracer != nil)
        #expect(withTracer.memory == nil)
    }

    // MARK: - callAsFunction

    @Test("callAsFunction dispatches to run — equivalent results")
    func callAsFunctionEquivalentToRun() async throws {
        // Use two separate providers so both calls get a fresh response index.
        let provider1 = MockInferenceProvider(responses: ["hello from run"])
        let provider2 = MockInferenceProvider(responses: ["hello from run"])

        let agentRun = try Agent("test", provider: provider1)
        let agentCaF = try Agent("test", provider: provider2)

        let viaRun = try await agentRun.run("say hello")
        let viaCaF = try await agentCaF("say hello")

        #expect(viaRun.output == viaCaF.output)
    }
}
