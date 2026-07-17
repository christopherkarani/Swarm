import Swarm
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

@Suite("README Provider Compile Tests")
struct ReadmeProviderCompileTests {
    @Test("README-style provider factories compile through public import")
    func readmeProviderFactoriesCompile() throws {
        _ = try Agent("Use Anthropic.", inferenceProvider: .anthropic(key: "test-key")) {
            PublicCompileTool()
        }

        _ = try Agent("Use OpenAI.", provider: .openAI(key: "test-key")) {
            PublicCompileTool()
        }

        let ollamaAgent = try Agent("Use local models.")
        let _: any AgentRuntime = ollamaAgent.environment(\.inferenceProvider, .ollama(model: "mistral"))

        if #available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *) {
            _ = try Agent("Use Foundation Models.", inferenceProvider: .foundationModels())
        }
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

    /// Proves major README / getting-started `Agent(...)` call sites match the
    /// canonical label order: configuration → memory → inferenceProvider → guardrails.
    @Test("Major public doc Agent snippets use legal parameter order")
    func majorPublicDocAgentSnippetsCompile() throws {
        // getting-started: on-device first agent
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            _ = try Agent(
                "Answer finance questions using tools when needed.",
                configuration: .default.name("Analyst"),
                memory: .conversation(maxMessages: 50),
                inferenceProvider: .foundationModels(),
                inputGuardrails: [InputGuard.maxLength(5000), InputGuard.notEmpty()]
            ) {
                DocSnippetPriceTool()
            }
        }

        // getting-started: cloud Anthropic first agent
        _ = try Agent(
            "Answer finance questions using real data.",
            configuration: .default.name("Analyst"),
            memory: .conversation(maxMessages: 50),
            inferenceProvider: .anthropic(apiKey: "test-key"),
            inputGuardrails: [InputGuard.maxLength(5000), InputGuard.notEmpty()]
        ) {
            DocSnippetPriceTool()
            #if canImport(Darwin)
                CalculatorTool()
            #endif
        }

        // README: Quick Start (configuration + provider only)
        _ = try Agent(
            "Answer finance questions using real data.",
            configuration: .default.name("Analyst"),
            inferenceProvider: .anthropic(apiKey: "test-key")
        ) {
            DocSnippetPriceTool()
        }

        // README: Foundation Models First
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            _ = try Agent(
                "You are a private on-device assistant.",
                inferenceProvider: .foundationModels()
            ) {
                DocSnippetPriceTool()
            }
        }

        // README: semantic memory (memory before inferenceProvider)
        let embedder = MockEmbeddingProvider()
        _ = try Agent(
            "You remember past conversations.",
            memory: .vector(embeddingProvider: embedder, similarityThreshold: 0.75),
            inferenceProvider: .anthropic(apiKey: "test-key")
        ) {
            DocSnippetPriceTool()
        }

        // README / getting-started: guardrails-only
        _ = try Agent(
            "You are a helpful assistant.",
            inputGuardrails: [InputGuard.maxLength(5000), InputGuard.notEmpty()],
            outputGuardrails: [OutputGuard.maxLength(2000)]
        )
    }
}
