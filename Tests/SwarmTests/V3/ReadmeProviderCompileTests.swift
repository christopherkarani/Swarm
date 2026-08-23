@testable import Swarm
import Foundation
import Testing

private struct PublicCompileTool: Tool {
    struct Input: Codable, Sendable {}

    let name = "public_compile_tool"
    let description = "Compile-only public API tool"
    let parameters: [ToolParameter] = []

    func execute(_: Input) async throws -> String {
        "ok"
    }
}

@Tool("Looks up a canned stock price")
private struct DocSnippetPriceTool {
    @Parameter("Ticker symbol") var ticker: String = "AAPL"

    func execute() async throws -> String { "182.50" }
}

/// Type-checks the README `agent.stream` switch without running inference.
private func readmeStreamingSwitchSurface(_ event: AgentEvent) {
    switch event {
    case .output(.token(let t)):
        _ = t
    case .tool(.completed(let call, _)):
        _ = call.toolName
    case .lifecycle(.completed(let r)):
        _ = r.duration
    case .lifecycle(.failed(let error)):
        _ = error
    default:
        break
    }
}

@Suite("README Provider Compile Tests")
struct ReadmeProviderCompileTests {
    private let _ephemeralDefaultStores = SwarmEphemeralStoreBootstrap.installOnce

    @Test("README-style provider factories compile through public import")
    func readmeProviderFactoriesCompile() throws {
        if #available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *) {
            #if canImport(FoundationModels)
            _ = try Agent("Use Foundation Models.", inferenceProvider: .foundationModels())
            #endif
        }

        // Custom InferenceProvider injection remains the extension path.
        let mock = MockInferenceProvider(responses: ["ok"])
        _ = try Agent("Use a custom backend.", inferenceProvider: mock) {
            PublicCompileTool()
        }

        _ = try Agent(
            "Use a remote OpenAI-compatible backend.",
            inferenceProvider: .openAICompatible(.ollama(model: "llama3.2"))
        )
        _ = try Agent(
            "Use OpenAI.",
            inferenceProvider: .openAICompatible(.openAI(apiKey: "sk-test", model: "gpt-4o"))
        )
    }

    @Test("README dynamic tool examples compile through public import")
    func readmeDynamicToolExamplesCompile() throws {
        _ = try Agent("Use closure tools.") {
            FunctionTool(name: "reverse", description: "Reverses text") { args in
                let text = try args.require("text", as: String.self)
                return .string(String(text.reversed()))
            }

            #if canImport(Darwin)
                CalculatorTool()
            #endif
        }
    }

    /// Parameter-order proof for getting-started + README Foundation Models First.
    /// Named README sample tests below own semantic memory / guardrails / quick start.
    @Test("Major public doc Agent snippets use legal parameter order")
    func majorPublicDocAgentSnippetsCompile() throws {
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            #if canImport(FoundationModels)
            _ = try Agent(
                "Answer finance questions using tools when needed.",
                configuration: .default.name("Analyst"),
                memory: .conversation(maxMessages: 50),
                inferenceProvider: .foundationModels(),
                inputGuardrails: [InputGuard.maxLength(5000), InputGuard.notEmpty()]
            ) {
                DocSnippetPriceTool()
            }

            _ = try Agent(
                "You are a private on-device assistant.",
                inferenceProvider: .foundationModels()
            ) {
                DocSnippetPriceTool()
            }
            #endif
        }
    }

    @Test("README Quick Start sample compiles")
    func readmeQuickStartCompiles() throws {
        let mock = MockInferenceProvider(responses: ["Apple (AAPL) is currently trading at $182.50."])
        _ = try Agent(
            "Answer finance questions using real data.",
            configuration: .default.name("Analyst"),
            inferenceProvider: mock
        ) {
            DocSnippetPriceTool()
            #if canImport(Darwin)
                CalculatorTool()
            #endif
        }
    }

    @Test("README Multi-agent pipeline sample compiles")
    func readmeMultiAgentPipelineCompiles() throws {
        let mock = MockInferenceProvider(responses: ["facts", "summary"])
        // WebSearchTool(apiKey:) exists on lean; construction warns and execute requires Integrations.
        let researcher = try Agent(
            "Research the topic and extract key facts.",
            inferenceProvider: mock
        ) {
            WebSearchTool(apiKey: "YOUR_API_KEY")
        }

        let writer = try Agent(
            "Write a concise summary from the research.",
            inferenceProvider: mock
        )

        _ = Workflow()
            .step(researcher)
            .step(writer)
    }

    @Test("README Parallel fan-out sample compiles")
    func readmeParallelFanOutCompiles() throws {
        let mock = MockInferenceProvider(responses: ["ok"])
        let bullAgent = try Agent("Bullish take.", inferenceProvider: mock)
        let bearAgent = try Agent("Bearish take.", inferenceProvider: mock)
        let analystAgent = try Agent("Neutral analysis.", inferenceProvider: mock)

        _ = Workflow()
            .parallel([bullAgent, bearAgent, analystAgent], merge: .structured)
    }

    @Test("README Dynamic routing sample compiles")
    func readmeDynamicRoutingCompiles() throws {
        let mock = MockInferenceProvider(responses: ["ok"])
        let mathAgent = try Agent("Math.", inferenceProvider: mock)
        let weatherAgent = try Agent("Weather.", inferenceProvider: mock)
        let generalAgent = try Agent("General.", inferenceProvider: mock)

        _ = Workflow()
            .route { input in
                if input.contains("$") { return mathAgent }
                if input.contains("weather") { return weatherAgent }
                return generalAgent
            }
    }

    @Test("README Streaming sample compiles")
    func readmeStreamingCompiles() throws {
        let mock = MockInferenceProvider(responses: ["token"])
        let agent = try Agent("Summarizer.", inferenceProvider: mock)
        // Lock the README switch surface + stream return type without executing inference.
        _ = agent.stream("Summarize the changelog.")
        readmeStreamingSwitchSurface(.output(.token("x")))
    }

    @Test("README Semantic memory sample compiles")
    func readmeSemanticMemoryCompiles() throws {
        let embedder = MockEmbeddingProvider()
        let mock = MockInferenceProvider(responses: ["ok"])
        _ = try Agent(
            "You remember past conversations.",
            memory: .vector(embeddingProvider: embedder, similarityThreshold: 0.75),
            inferenceProvider: mock
        ) {
            DocSnippetPriceTool()
        }
    }

    @Test("README Guardrails sample compiles")
    func readmeGuardrailsCompiles() throws {
        _ = try Agent(
            "You are a helpful assistant.",
            inputGuardrails: [InputGuard.maxLength(5000), InputGuard.notEmpty()],
            outputGuardrails: [OutputGuard.maxLength(2000)]
        )
    }

    @Test("README Closure tools sample compiles")
    func readmeClosureToolsCompiles() throws {
        let reverse = FunctionTool(
            name: "reverse",
            description: "Reverses a string",
            parameters: [
                ToolParameter(
                    name: "text",
                    description: "Text to reverse",
                    type: .string,
                    isRequired: true
                ),
            ]
        ) { args in
            let text = try args.require("text", as: String.self)
            return .string(String(text.reversed()))
        }

        // Canonical unlabeled-instructions + @ToolBuilder form (ToolBuilder accepts FunctionTool).
        _ = try Agent("Text utilities.") {
            reverse
        }
    }

    @Test("README Crash-resumable workflows sample compiles")
    func readmeCrashResumableCompiles() throws {
        // Construction is lean-safe (warns); durable.execute requires Integrations at runtime.
        let mock = MockInferenceProvider(responses: ["done"])
        let monitor = try Agent("Emit a short status.", inferenceProvider: mock)
        let checkpointsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-readme-compile-checkpoints", isDirectory: true)

        _ = Workflow()
            .step(monitor)
            .durable.checkpoint(id: "monitor-v1", policy: .everyStep)
            .durable.checkpointing(.fileSystem(directory: checkpointsURL))
    }

    @Test("README Provider selection sample compiles")
    func readmeProviderSelectionCompiles() throws {
        let myCustomProvider = MockInferenceProvider(responses: ["ok"])

        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            #if canImport(FoundationModels)
            _ = try Agent("Be helpful.", inferenceProvider: .foundationModels())
            #endif
        }

        let agent = try Agent("Be helpful.", inferenceProvider: myCustomProvider)
        _ = agent.environment(\.inferenceProvider, myCustomProvider)

        _ = try Agent(
            "Be helpful.",
            inferenceProvider: .openAICompatible(.ollama(model: "llama3.2"))
        )
    }

    @Test("README Conversation sample compiles")
    func readmeConversationCompiles() throws {
        let mock = MockInferenceProvider(responses: ["ok"])
        let agent = try Agent("Chatty.", inferenceProvider: mock)
        _ = Conversation(with: agent)
    }
}
