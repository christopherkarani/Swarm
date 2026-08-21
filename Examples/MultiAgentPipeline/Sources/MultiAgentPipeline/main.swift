// MultiAgentPipeline — Swarm multi-agent + durable workflow demo.
//
// Demonstrates:
// - Sequential Workflow steps (research → write)
// - Parallel fan-out with structured merge
// - Durable checkpoint + resume
// - Foundation Models for live on-device runs (optional)
// - Deterministic `--demo` mode for CI (scripted providers, no keys)
//
// Usage:
//   swift run MultiAgentPipeline --demo
//   swift run MultiAgentPipeline              # live FM when available
//   swift run MultiAgentPipeline --help

import Foundation
import Swarm

@main
struct MultiAgentPipelineMain {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("MultiAgentPipeline error: \(error)\n", stderr)
            exit(1)
        }
    }
}

private func run(arguments: [String]) async throws {
    if arguments.contains("-h") || arguments.contains("--help") {
        print(
            """
            MultiAgentPipeline — Swarm workflow demo

            Usage:
              swift run MultiAgentPipeline [--demo]

            Options:
              --demo   Scripted providers (deterministic, no API keys / no FM required)
              --help   Show this help

            Without --demo, uses Apple Foundation Models when available for both agents.
            """
        )
        return
    }

    let demoMode = arguments.contains("--demo")
    let topic = "on-device Swift agents with Foundation Models"

    let researchProvider: any InferenceProvider
    let writerProvider: any InferenceProvider
    let parallelA: any InferenceProvider
    let parallelB: any InferenceProvider
    let durableProvider: any InferenceProvider
    let modeLabel: String

    if demoMode {
        researchProvider = ScriptedTextProvider(responses: [
            "Facts: 1) Swarm agents are Sendable. 2) Foundation Models run on-device. 3) Workflows support checkpoints.",
        ])
        writerProvider = ScriptedTextProvider(responses: [
            "Summary: Swarm lets you build private on-device Swift agents with tools, workflows, and crash-safe checkpoints.",
        ])
        parallelA = ScriptedTextProvider(responses: ["bullish: strong local privacy story"])
        parallelB = ScriptedTextProvider(responses: ["bearish: model capability still smaller than cloud"])
        durableProvider = ScriptedTextProvider(responses: ["working", "done"])
        modeLabel = "demo (scripted)"
    } else {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
                guard let fm = FoundationModelsInferenceProvider.ifAvailable() else {
                    fputs(
                        "Foundation Models unavailable. Re-run with --demo.\n",
                        stderr
                    )
                    exit(2)
                }
                // Separate provider instances keep session state isolated per agent.
                researchProvider = FoundationModelsInferenceProvider(
                    configuration: .init(instructions: "Extract 3 short factual bullets.")
                )
                writerProvider = FoundationModelsInferenceProvider(
                    configuration: .init(instructions: "Write one concise paragraph from research notes.")
                )
                parallelA = fm
                parallelB = FoundationModelsInferenceProvider(
                    configuration: .init(instructions: "Be skeptical and concise.")
                )
                durableProvider = FoundationModelsInferenceProvider(
                    configuration: .init(instructions: "Reply with a single status word.")
                )
                modeLabel = "foundation-models (live)"
            } else {
                fputs("OS below Foundation Models availability. Use --demo.\n", stderr)
                exit(2)
            }
        #else
            fputs("FoundationModels not importable. Use --demo.\n", stderr)
            exit(2)
        #endif
    }

    let researcher = try Agent(
        "Research the topic and list key facts only.",
        configuration: .default.name("Researcher"),
        memory: .conversation(maxMessages: 16),
        inferenceProvider: researchProvider
    )
    let writer = try Agent(
        "Write a concise summary from the research notes you receive.",
        configuration: .default.name("Writer"),
        memory: .conversation(maxMessages: 16),
        inferenceProvider: writerProvider
    )

    print("Swarm \(Swarm.version) · mode=\(modeLabel)")
    print("--- sequential research → write ---")
    let sequential = try await Workflow()
        .step(researcher)
        .step(writer)
        .run(topic)
    print(sequential.output)

    print("--- parallel fan-out ---")
    let bull = try Agent(
        "Give a short bullish take.",
        memory: .conversation(maxMessages: 8),
        inferenceProvider: parallelA
    )
    let bear = try Agent(
        "Give a short bearish take.",
        memory: .conversation(maxMessages: 8),
        inferenceProvider: parallelB
    )
    let parallel = try await Workflow()
        .parallel([bull, bear], merge: .structured)
        .run(topic)
    print(parallel.output)

    print("--- durable checkpoint + resume ---")
    let monitor = try Agent(
        "Emit a short status; eventually say done.",
        memory: .conversation(maxMessages: 8),
        inferenceProvider: durableProvider
    )
    let checkpointing = WorkflowCheckpointing.inMemory()
    let durableWorkflow = Workflow()
        .step(monitor)
        .repeatUntil(maxIterations: 4) { $0.output.lowercased().contains("done") }
        .durable
        .checkpoint(id: "pipeline-monitor", policy: .everyStep)
        .durable
        .checkpointing(checkpointing)

    _ = try await durableWorkflow.durable.execute("start")
    let resumed = try await durableWorkflow.durable.execute("ignored", resumeFrom: "pipeline-monitor")
    print("resumed=\(resumed.output)")

    if demoMode {
        let okSeq = sequential.output.lowercased().contains("swarm")
            || sequential.output.lowercased().contains("on-device")
            || sequential.output.lowercased().contains("summary")
        let okPar = parallel.output.lowercased().contains("bullish")
            && parallel.output.lowercased().contains("bearish")
        let okDur = resumed.output.lowercased().contains("done")
        guard okSeq, okPar, okDur else {
            throw PipelineError.unexpected(
                "demo checks failed seq=\(sequential.output) par=\(parallel.output) dur=\(resumed.output)"
            )
        }
        print("demo checks: sequential=ok parallel=ok durable=ok")
    }

    print("primary_output=\(sequential.output)")
}

// MARK: - Scripted provider

private actor ScriptedTextProvider: InferenceProvider {
    private var responses: [String]
    private var index = 0

    init(responses: [String]) {
        self.responses = responses
    }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        next()
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await generate(
            prompt: TextOnlyConversationInferenceProviderAdapter.prompt(from: messages),
            options: options
        )
    }

    nonisolated func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let text = try await self.generate(prompt: prompt, options: options)
                    continuation.yield(text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        InferenceResponse(content: next(), finishReason: .completed)
    }

    private func next() -> String {
        defer { index += 1 }
        guard index < responses.count else {
            return responses.last ?? "done"
        }
        return responses[index]
    }
}

private enum PipelineError: Error, CustomStringConvertible {
    case unexpected(String)
    var description: String {
        switch self {
        case let .unexpected(message): message
        }
    }
}
