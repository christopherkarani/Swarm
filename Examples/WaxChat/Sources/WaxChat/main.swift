// WaxChat — on-device chat AI using Swarm + Foundation Models + websearch + Wax memory.
//
// Usage:
//   swift run WaxChat              # live Foundation Models when available
//   swift run WaxChat --demo       # scripted provider (always deterministic)
//   swift run WaxChat --help

import Foundation
import Swarm
import WaxChatCore

@main
struct WaxChatMain {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("WaxChat error: \(error)\n", stderr)
            exit(1)
        }
    }
}

private func run(arguments: [String]) async throws {
    if arguments.contains("-h") || arguments.contains("--help") {
        print(
            """
            WaxChat — on-device Swarm chat with Foundation Models, websearch, and Wax memory

            Usage:
              swift run WaxChat [--demo] [prompt]

            Options:
              --demo   Use a scripted inference provider (no Foundation Models required)
              --help   Show this help

            Environment:
              TAVILY_API_KEY   Optional. Enables live websearch via Tavily when set.

            Without --demo, uses Apple Foundation Models when the system model is available.
            Memory is Wax-backed (durable). Websearch is always registered on the agent.
            """
        )
        return
    }

    let demoMode = arguments.contains("--demo")
    let promptParts = arguments.filter { $0 != "--demo" }
    let userPrompt = promptParts.isEmpty
        ? DemoMarkers.defaultPrimaryPrompt
        : promptParts.joined(separator: " ")

    // Demo uses isolated temp stores so runs don't clobber interactive memory.
    // Live mode uses Application Support for durable personal context.
    let configuration = demoMode
        ? ChatAgentConfiguration.temporary(demoMode: true)
        : ChatAgentConfiguration.appSupport(demoMode: false)

    _ = try await ChatSession.run(
        prompt: userPrompt,
        configuration: configuration,
        printStream: true
    )
}
