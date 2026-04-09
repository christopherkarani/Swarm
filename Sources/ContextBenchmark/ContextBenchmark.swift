import ContextBenchmarkSupport
import Foundation
import Swarm

@main
struct ContextBenchmarkExecutable {
    static func main() async {
        Log.bootstrap()

        let arguments = Array(CommandLine.arguments.dropFirst())
        let scenarios = parseScenarios(from: arguments)
        let modes = parseModes(from: arguments)
        let harness = ContextBenchmarkHarness()

        do {
            if arguments.contains("--live-real") {
                let prompt = parseStringFlag("--prompt", arguments: arguments) ?? defaultLivePrompt
                let maxIterations = parseIntegerFlag("--max-iterations", arguments: arguments, defaultValue: 12)
                try await runLiveReal(prompt: prompt, maxIterations: maxIterations)
            } else if arguments.contains("--quality") {
                let toolCalls = parseIntegerFlag("--tool-calls", defaultValue: 32)
                let results = try await harness.runQuality(
                    scenarios: [.deepResearch(toolCalls: toolCalls)],
                    modes: modes
                )
                print(BenchmarkMarkdownWriter.renderQuality(results: results))
            } else if arguments.contains("--depth-sweep") {
                let maxToolCalls = parseIntegerFlag("--max-tool-calls", defaultValue: 256)
                let startToolCalls = parseIntegerFlag("--start-tool-calls", defaultValue: 12)
                let results = try await harness.runDepthSweep(
                    scenarios: scenarios,
                    modes: modes,
                    startToolCalls: startToolCalls,
                    maxToolCalls: maxToolCalls
                )
                print(BenchmarkMarkdownWriter.renderDepthSweep(results: results, maxExploredToolCalls: maxToolCalls))
            } else {
                let results = try await harness.run(scenarios: scenarios, modes: modes)
                print(BenchmarkMarkdownWriter.render(results: results))
            }
        } catch {
            fputs("ContextBenchmark failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func runLiveReal(prompt: String, maxIterations: Int) async throws {
        let searchTool = WebSearchTool.fromEnvironment()
        let agent = try Agent(
            tools: [searchTool],
            instructions: """
            You are a research assistant running on the real Swarm runtime.
            Use websearch when needed, keep the answer factual and concise, and clearly separate findings from uncertainty.
            """,
            configuration: AgentConfiguration.default
                .contextProfile(.strict4k)
                .maxIterations(maxIterations)
                .defaultTracingEnabled(false)
        )

        let result = try await agent.run(prompt)

        print("# Live Real Run")
        print("")
        print("## Prompt")
        print(prompt)
        print("")
        print("## Summary")
        print("- iterations: \(result.iterationCount)")
        print("- tool calls: \(result.toolCalls.count)")
        print("- tool results: \(result.toolResults.count)")
        print("")

        if !result.toolCalls.isEmpty {
            print("## Tool Calls")
            for (index, call) in result.toolCalls.enumerated() {
                print("\(index + 1). \(call.toolName) \(call.arguments)")
            }
            print("")
        }

        if !result.toolResults.isEmpty {
            print("## Tool Result Excerpts")
            for (index, toolResult) in result.toolResults.enumerated() {
                let output = toolResult.output.stringValue ?? toolResult.output.description
                let excerpt = output
                    .replacingOccurrences(of: "\n", with: " ")
                    .prefix(400)
                print("\(index + 1). \(excerpt)")
            }
            print("")
        }

        print("## Final Output")
        print(result.output)
    }

    private static func parseScenarios<S: Sequence>(from arguments: S) -> [BenchmarkScenario] where S.Element == String {
        let selected = Set(arguments)
        if selected.contains("--grounded-only") {
            return [.groundedWebSearch()]
        }
        if selected.contains("--compact-only") {
            return [.compactWebSearch()]
        }
        return [
            .compactWebSearch(),
            .groundedWebSearch(),
        ]
    }

    private static func parseModes<S: Sequence>(from arguments: S) -> [BenchmarkMode] where S.Element == String {
        let arguments = Array(arguments)
        guard let index = arguments.firstIndex(of: "--mode"),
              arguments.indices.contains(arguments.index(after: index))
        else {
            return BenchmarkMode.all
        }

        let raw = arguments[arguments.index(after: index)].lowercased()
        return switch raw {
        case "baseline":
            [.baseline]
        case "contextcore":
            [.contextCoreOnly]
        case "membrane":
            [.membraneOnly]
        case "combined":
            [.combined]
        default:
            BenchmarkMode.all
        }
    }

    private static func parseIntegerFlag(_ flag: String, defaultValue: Int) -> Int {
        let arguments = Array(CommandLine.arguments.dropFirst())
        return parseIntegerFlag(flag, arguments: arguments, defaultValue: defaultValue)
    }

    private static func parseIntegerFlag(_ flag: String, arguments: [String], defaultValue: Int) -> Int {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(arguments.index(after: index)),
              let value = Int(arguments[arguments.index(after: index)])
        else {
            return defaultValue
        }
        return value
    }

    private static func parseStringFlag(_ flag: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(arguments.index(after: index))
        else {
            return nil
        }
        return arguments[arguments.index(after: index)]
    }

    private static let defaultLivePrompt = """
    Research whether Membrane-style pointerization and retrieval-aware context packing help a strict-4k on-device research agent using repeated websearch calls. Use a few websearch calls, summarize your findings, and state any limitations.
    """
}
