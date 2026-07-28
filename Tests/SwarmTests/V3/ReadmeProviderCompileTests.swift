@testable import Swarm
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
            #endif
        }

        // README: Foundation Models First
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            #if canImport(FoundationModels)
            _ = try Agent(
                "You are a private on-device assistant.",
                inferenceProvider: .foundationModels()
            ) {
                DocSnippetPriceTool()
            }
            #endif
        }

        // README: custom InferenceProvider (mock stands in for any custom backend)
        let embedder = MockEmbeddingProvider()
        let mock = MockInferenceProvider(responses: ["ok"])
        _ = try Agent(
            "You remember past conversations.",
            memory: .vector(embeddingProvider: embedder, similarityThreshold: 0.75),
            inferenceProvider: mock
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
