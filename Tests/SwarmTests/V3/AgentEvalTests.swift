// AgentEvalTests.swift
// SwarmTests
//
// V3 AI Agent Eval — validates the API from an AI coding agent's perspective.
// These tests simulate what an AI agent would generate when asked to "create an agent".

import Testing
@testable import Swarm

// MARK: - Minimal Tool conformer for eval tests

/// Lightweight Tool conformer used by eval tests.
private struct EvalTool: Tool {
    struct Input: Codable, Sendable { let query: String }
    typealias Output = String

    let name = "eval_tool"
    let description = "Eval helper tool"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "query", description: "Query string", type: .string)
    ]

    func execute(_ input: Input) async throws -> String { input.query }
}

// MARK: - V3 AI Agent Eval Tests

@Suite("V3 Agent Eval — AI Agent Perspective")
struct AgentEvalTests {

    // MARK: - Eval 1: Minimal agent creation
    // Prompt: "Create a simple agent with instructions"

    @Test("AI can create minimal agent with just instructions")
    func eval01_minimal() throws {
        let agent = try Agent("You are helpful")
        #expect(agent.instructions == "You are helpful")
    }

    // MARK: - Eval 2: Agent with tools using @ToolBuilder
    // Prompt: "Create an agent with a tool"

    @Test("AI can create agent with provider and tools")
    func eval02_withTools() throws {
        let provider = MockInferenceProvider()
        let agent = try Agent("Be helpful", inferenceProvider: provider) {
            EvalTool()
        }
        #expect(agent.instructions == "Be helpful")
        #expect(agent.tools.count >= 1)
        #expect(agent.inferenceProvider != nil)
    }

    // MARK: - Eval 3: Full modifier chain
    // Prompt: "Create an agent with memory, guardrails, and tools"

    @Test("AI can create agent with full modifier chain")
    func eval03_fullChain() throws {
        let provider = MockInferenceProvider()
        let agent = try Agent("Be helpful", inferenceProvider: provider) {
            EvalTool()
        }
        .withMemory(.conversation())
        .withGuardrails(input: [InputGuard.notEmpty()])

        #expect(agent.memory != nil)
        #expect(agent.inputGuardrails.count == 1)
    }

    // MARK: - Eval 4: callAsFunction
    // Prompt: "Run an agent with a simple input"

    @Test("callAsFunction works as sugar for run()")
    func eval04_callAsFunction() async throws {
        let provider = MockInferenceProvider(responses: ["OK"])
        let agent = try Agent("Say OK", inferenceProvider: provider)
        let result = try await agent("Hi")
        #expect(result.output.contains("OK"))
    }

    // MARK: - Eval 5: Memory factory dot-syntax
    // Prompt: "Create a conversation memory"

    @Test("Memory dot-syntax factory works")
    func eval05_memoryFactory() async {
        let memory: any Memory = .conversation(maxMessages: 50)
        let count = await memory.count
        #expect(count == 0)
    }

    // MARK: - Eval 6: Guardrail factory dot-syntax
    // Prompt: "Add input validation that rejects empty input"

    @Test("Guardrail factories work via InputGuard")
    func eval06_guardrailFactory() throws {
        let agent = try Agent("test")
            .withGuardrails(input: [InputGuard.notEmpty(), InputGuard.maxLength(500)])
        #expect(agent.inputGuardrails.count == 2)
    }

    // MARK: - Eval 7: ToolCollection from @ToolBuilder
    // Prompt: "Build a collection of tools"

    @Test("@ToolBuilder produces ToolCollection with correct count")
    func eval07_toolCollection() {
        @ToolBuilder var tools: ToolCollection {
            EvalTool()
        }
        #expect(!tools.storage.isEmpty)
        #expect(tools.storage.count == 1)
        #expect(tools.storage[0].name == "eval_tool")
    }

    // MARK: - Eval 8: Modifier chaining preserves all state
    // Prompt: "Create a fully configured agent"

    @Test("Chaining modifiers preserves all configuration")
    func eval08_chainingPreservesState() throws {
        let provider = MockInferenceProvider()
        let agent = try Agent("test", inferenceProvider: provider) {
            EvalTool()
        }
        .withMemory(.conversation())
        .withGuardrails(input: [InputGuard.notEmpty()], output: [OutputGuard.maxLength(2000)])

        #expect(agent.instructions == "test")
        #expect(agent.tools.count >= 1)
        #expect(agent.memory != nil)
        #expect(agent.inputGuardrails.count == 1)
        #expect(agent.outputGuardrails.count == 1)
    }

    // MARK: - Eval 9: Instructions-first is the obvious path
    // Verifies that the V3 canonical init is the single natural entry point.

    @Test("Instructions-first init is non-throwing for empty tools")
    func eval09_instructionsFirstIsSimple() throws {
        // An AI agent should reach for this as the obvious first line.
        let agent = try Agent("You are a helpful assistant.")
        #expect(!agent.instructions.isEmpty)
    }

    // MARK: - Eval 10: Copy-on-write semantics are safe
    // Prompt: "Modify an agent without affecting the original"

    @Test("Modifiers are copy-on-write — original is unaffected")
    func eval10_copyOnWriteSafety() throws {
        let original = try Agent("original")
        let modified = original.withMemory(.conversation())

        #expect(original.memory == nil)
        #expect(modified.memory != nil)
        #expect(original.instructions == "original")
        #expect(modified.instructions == "original")
    }
}
