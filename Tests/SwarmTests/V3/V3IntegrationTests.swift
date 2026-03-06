// V3IntegrationTests.swift
// End-to-end tests for the complete V3 API surface.

@testable import Swarm
import Testing

@Suite("V3 API Integration")
struct V3IntegrationTests {
    // MARK: - Tool fixtures

    struct SearchTool: ToolV3 {
        let name = "search"
        let description = "Search the web"
        @ParameterV3("Query") var query: String
        func call() async throws -> String { "Results for: \(query)" }
    }

    struct CalculatorTool: ToolV3 {
        let name = "calculator"
        let description = "Performs calculations"
        @ParameterV3("Expression") var expression: String
        func call() async throws -> String { "42" }
    }

    // MARK: - Agent creation patterns

    @Test("Minimal agent — instructions only")
    func minimalAgent() {
        let agent = AgentV3("You are a helpful assistant.")
        #expect(agent.instructions == "You are a helpful assistant.")
        #expect(agent.name == "Agent")
        #expect(agent.tools.isEmpty)
        #expect(agent.guardrails.isEmpty)
    }

    @Test("Agent with tools — THE primary creation path")
    func agentWithTools() {
        let agent = AgentV3("Research assistant") {
            SearchTool()
            CalculatorTool()
        }
        #expect(agent.tools.count == 2)
        #expect(agent.tools[0].name == "search")
        #expect(agent.tools[1].name == "calculator")
    }

    @Test("Fully configured agent via modifier chain")
    func fullyConfigured() {
        let agent = AgentV3("Analyst", guardrails: [.maxInput(1000), .inputNotEmpty]) {
            SearchTool()
        }
        .named("DataAnalyst")
        .memory(.conversation(limit: 50))

        #expect(agent.name == "DataAnalyst")
        #expect(agent.instructions == "Analyst")
        #expect(agent.tools.count == 1)
        #expect(agent.guardrails.count == 2)
        if case .conversation(let limit) = agent.memoryOption {
            #expect(limit == 50)
        } else {
            Issue.record("Expected .conversation memory")
        }
    }

    // MARK: - Multi-agent handoff via tools

    @Test("Handoff as tool in agent creation")
    func multiAgentHandoff() {
        let expert = AgentV3("Domain expert")
            .named("expert")

        let summarizer = AgentV3("Summarizer")
            .named("summarizer")

        let router = AgentV3("Route to the right agent") {
            SearchTool()
            HandoffV3(expert)
            HandoffV3(summarizer, history: .summarized(maxTokens: 500))
        }

        #expect(router.tools.count == 3)
        #expect(router.tools[0].name == "search")
        #expect(router.tools[1].name == "handoff_to_expert")
        #expect(router.tools[2].name == "handoff_to_summarizer")
    }

    // MARK: - Guardrails

    @Test("Guardrail validation")
    func guardrailValidation() async throws {
        let guardrails: [GuardrailV3] = [
            .maxInput(10),
            .inputNotEmpty,
            .inputCustom("No profanity") { input in
                input.contains("bad") ? .tripwire(message: "Profanity") : .passed()
            }
        ]

        // Test maxInput
        let longResult = try await guardrails[0].validate("this is way too long input")
        #expect(longResult.tripwireTriggered)

        let shortResult = try await guardrails[0].validate("hi")
        #expect(!shortResult.tripwireTriggered)

        // Test inputNotEmpty
        let emptyResult = try await guardrails[1].validate("  ")
        #expect(emptyResult.tripwireTriggered)

        // Test custom
        let badResult = try await guardrails[2].validate("bad word")
        #expect(badResult.tripwireTriggered)
    }

    // MARK: - RunOptions presets

    @Test("RunOptions presets")
    func runOptionsPresets() {
        let defaults = RunOptions.default
        #expect(defaults.maxIterations == 10)
        #expect(defaults.temperature == 1.0)

        let creative = RunOptions.creative
        #expect(creative.temperature == 1.5)

        let precise = RunOptions.precise
        #expect(precise.temperature == 0.2)

        let fast = RunOptions.fast
        #expect(fast.maxIterations == 3)
        #expect(fast.timeout == .seconds(15))
    }

    // MARK: - Memory dot-syntax

    @Test("Memory options resolve correctly")
    func memoryResolution() {
        #expect(MemoryOption.none.resolve() == nil)
        #expect(MemoryOption.conversation(limit: 25).resolve() != nil)
        #expect(MemoryOption.slidingWindow(count: 10).resolve() != nil)
    }

    // MARK: - Workflow composition

    @Test("Workflow with steps")
    func workflowComposition() {
        let researcher = AgentV3("Research").named("researcher")
        let writer = AgentV3("Write").named("writer")
        let reviewer = AgentV3("Review").named("reviewer")

        let workflow = WorkflowV3 {
            StepV3(researcher)
            StepV3(writer, transform: { "Write about: \($0)" })
            StepV3(reviewer)
        }

        #expect(workflow.steps.count == 3)
        #expect(workflow.steps[0].id == "researcher")
        #expect(workflow.steps[1].id == "writer")
        #expect(workflow.steps[2].id == "reviewer")
    }

    // MARK: - Inline tools

    @Test("Inline tools in agent")
    func inlineTools() {
        let agent = AgentV3("Helper") {
            InlineToolV3("timestamp", "Returns current time", { () async throws -> String in
                "2026-03-06T12:00:00Z"
            })
            SearchTool()
        }

        #expect(agent.tools.count == 2)
        #expect(agent.tools[0].name == "timestamp")
        #expect(agent.tools[1].name == "search")
    }

    // MARK: - Agent is value type

    @Test("Agent struct is a value type — modifications return new copies")
    func agentValueSemantics() {
        let original = AgentV3("Original")
        let renamed = original.named("Renamed")
        let withMemory = renamed.memory(.conversation())

        // Each step produces a new independent agent
        #expect(original.name == "Agent")
        #expect(renamed.name == "Renamed")
        #expect(withMemory.name == "Renamed")

        if case .none = original.memoryOption { /* pass */ }
        else { Issue.record("Original should have .none memory") }

        if case .conversation = withMemory.memoryOption { /* pass */ }
        else { Issue.record("withMemory should have .conversation") }
    }

    // MARK: - Tool bridge

    @Test("V3 tools bridge to legacy AnyJSONTool")
    func toolBridging() {
        let tool = SearchTool()
        let bridged = tool.asAnyJSONTool()

        #expect(bridged.name == "search")
        #expect(bridged.description == "Search the web")
        #expect(bridged.parameters.count == 1)
        #expect(bridged.parameters[0].name == "query")
        #expect(bridged.parameters[0].description == "Query")
    }
}
