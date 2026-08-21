// OnDeviceChat — end-to-end Swarm demo for Apple Foundation Models.
//
// Zero external API keys. Demonstrates:
// - Agent + @Tool / FunctionTool
// - Streaming tokens
// - Multi-turn Conversation
// - On-device `.foundationModels()` when available
// - Deterministic `--demo` mode for CI / environments without Apple Intelligence
//
// Usage:
//   swift run OnDeviceChat              # live Foundation Models when available
//   swift run OnDeviceChat --demo       # scripted provider (always deterministic)
//   swift run OnDeviceChat --help

import Foundation
import Swarm

@main
struct OnDeviceChatMain {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("OnDeviceChat error: \(error)\n", stderr)
            exit(1)
        }
    }
}

@Tool("Adds two integers.")
struct AddTool {
    @Parameter("Left-hand value") var lhs: Int = 0
    @Parameter("Right-hand value") var rhs: Int = 0

    func execute() async throws -> String {
        String(lhs + rhs)
    }
}

private func run(arguments: [String]) async throws {
    if arguments.contains("-h") || arguments.contains("--help") {
        print(
            """
            OnDeviceChat — Swarm on-device chat demo

            Usage:
              swift run OnDeviceChat [--demo] [prompt]

            Options:
              --demo   Use a scripted inference provider (no Foundation Models required)
              --help   Show this help

            Without --demo, uses Apple Foundation Models when the system model is available.
            """
        )
        return
    }

    let demoMode = arguments.contains("--demo")
    let promptParts = arguments.filter { $0 != "--demo" }
    let userPrompt = promptParts.isEmpty
        ? "What is 20 + 22? Use the add tool, then answer in one short sentence."
        : promptParts.joined(separator: " ")

    let provider: any InferenceProvider
    let modeLabel: String

    if demoMode {
        provider = DemoScriptedProvider()
        modeLabel = "demo (scripted)"
    } else {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
                if let fm = FoundationModelsInferenceProvider.ifAvailable(
                    configuration: .init(instructions: "You are a concise on-device assistant.")
                ) {
                    provider = fm
                    modeLabel = "foundation-models (live)"
                } else {
                    fputs(
                        """
                        Foundation Models system model is not available on this device.
                        Re-run with --demo for a deterministic walkthrough, or enable Apple Intelligence.

                        """,
                        stderr
                    )
                    exit(2)
                }
            } else {
                fputs("This OS is below Foundation Models availability. Use --demo.\n", stderr)
                exit(2)
            }
        #else
            fputs("FoundationModels is not importable on this platform. Use --demo.\n", stderr)
            exit(2)
        #endif
    }

    let agent = try Agent(
        "You are a helpful on-device assistant. Prefer tools for arithmetic.",
        configuration: .default.name("OnDeviceChat"),
        memory: .conversation(maxMessages: 32),
        inferenceProvider: provider
    ) {
        AddTool()
        FunctionTool(
            name: "uppercase",
            description: "Uppercases text",
            parameters: [
                ToolParameter(name: "text", description: "Text to uppercase", type: .string),
            ]
        ) { args in
            let text = try args.require("text", as: String.self)
            return .string(text.uppercased())
        }
    }

    print("Swarm \(Swarm.version) · mode=\(modeLabel)")
    print("--- stream ---")

    var streamed = ""
    var toolNames: [String] = []
    for try await event in agent.stream(userPrompt) {
        switch event {
        case let .output(.token(token)):
            print(token, terminator: "")
            fflush(stdout)
            streamed += token
        case let .tool(.completed(call, _)):
            toolNames.append(call.toolName)
            print("\n[tool: \(call.toolName)]", terminator: "")
            fflush(stdout)
        case let .lifecycle(.completed(result)):
            if streamed.isEmpty {
                streamed = result.output
                print(result.output, terminator: "")
            }
            print("\n--- done (\(result.duration)) ---")
        case let .lifecycle(.failed(error)):
            throw error
        default:
            break
        }
    }

    print("--- conversation ---")
    // Use a benign multi-turn prompt: some on-device safety policies refuse "secret/codeword" framing.
    let conversation = Conversation(with: agent)
    let first = try await conversation.send("My favorite color is teal.")
    let second = try await conversation.send("What is my favorite color?")
    print("turn1: \(first.output)")
    print("turn2: \(second.output)")

    // Primary success criteria for --demo: arithmetic tool path and multi-turn reply.
    if demoMode {
        let okArithmetic = streamed.contains("42") || toolNames.contains(where: { $0.lowercased().contains("add") })
        let okMemory = second.output.lowercased().contains("teal")
        guard okArithmetic, okMemory else {
            throw DemoError.unexpectedOutput(
                "demo expected arithmetic result and teal in follow-up; got stream=\(streamed) turn2=\(second.output)"
            )
        }
        print("demo checks: arithmetic=ok memory=ok")
    }

    print("primary_output=\(streamed)")
}

// MARK: - Deterministic demo provider

/// Scripted provider for CI / machines without Apple Intelligence.
private actor DemoScriptedProvider: InferenceProvider {
    private var toolTurn = 0
    private var chatTurn = 0

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        "ok"
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await generate(
            prompt: TextOnlyConversationInferenceProviderAdapter.prompt(from: messages),
            options: options
        )
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        _ = toolExecutor
        return try await generateWithToolCalls(
            prompt: TextOnlyConversationInferenceProviderAdapter.prompt(from: messages),
            tools: tools,
            options: options
        )
    }

    nonisolated func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("The ")
            continuation.yield("sum ")
            continuation.yield("is ")
            continuation.yield("42.")
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        // First agent.stream / run turn: request the add tool, then finalize.
        if toolTurn == 0, tools.contains(where: { $0.name.lowercased().contains("add") }) {
            toolTurn += 1
            let name = tools.first(where: { $0.name.lowercased().contains("add") })!.name
            return InferenceResponse(
                toolCalls: [
                    .init(id: "demo-add", name: name, arguments: ["lhs": .int(20), "rhs": .int(22)]),
                ],
                finishReason: .toolCall
            )
        }
        if toolTurn == 1 {
            toolTurn += 1
            return InferenceResponse(content: "The sum is 42.", finishReason: .completed)
        }

        // Conversation turns
        chatTurn += 1
        if chatTurn == 1 {
            return InferenceResponse(content: "Got it — favorite color teal saved.", finishReason: .completed)
        }
        return InferenceResponse(content: "Your favorite color is teal.", finishReason: .completed)
    }
}

private enum DemoError: Error, CustomStringConvertible {
    case unexpectedOutput(String)
    var description: String {
        switch self {
        case let .unexpectedOutput(message): message
        }
    }
}
