// VoiceAgent — turn-based VoiceSession demo.
//
// --demo injects a transcript via VoiceSession.respond(to:). It does not
// open the microphone.
//
// Usage:
//   swift run VoiceAgent --demo "Hello there."
//   swift run VoiceAgent --help

import Foundation
import Swarm

@main
struct VoiceAgentMain {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("VoiceAgent error: \(error)\n", stderr)
            exit(1)
        }
    }
}

private func run(arguments: [String]) async throws {
    if arguments.contains("-h") || arguments.contains("--help") {
        print(
            """
            VoiceAgent — Swarm turn-based voice coordinator

            Usage:
              swift run VoiceAgent --demo [prompt]

            Options:
              --demo   Inject the prompt via VoiceSession.respond(to:) (no microphone)
              --help   Show this help

            Live microphone capture is not wired in this CLI. Use --demo, or call
            VoiceSession.appleOnDevice from an app that declares
            NSMicrophoneUsageDescription and NSSpeechRecognitionUsageDescription.
            """
        )
        return
    }

    let demoMode = arguments.contains("--demo")
    let promptParts = arguments.filter { $0 != "--demo" }
    let userPrompt = promptParts.isEmpty
        ? "What is 2 plus 2? Answer in one short sentence."
        : promptParts.joined(separator: " ")

    guard demoMode else {
        fputs("live mic not wired in this CLI, use --demo\n", stderr)
        exit(2)
    }

    let provider = DemoScriptedProvider()
    let agent = try Agent(
        "You are a concise on-device assistant.",
        configuration: .default.name("VoiceAgent"),
        memory: .conversation(maxMessages: 16),
        inferenceProvider: provider
    )
    let textToSpeech = DemoTextToSpeech()
    let voice = VoiceSession(
        agent: agent,
        speechToText: IdleSpeechToText(),
        textToSpeech: textToSpeech
    )

    print("Swarm \(Swarm.version) · mode=demo (scripted)")
    print("--- respond ---")
    print("transcript=\(userPrompt)")

    let turn = try await voice.respond(to: userPrompt)
    let spoken = await textToSpeech.spoken

    for utterance in spoken {
        print("spoken=\(utterance)")
    }
    print("agent_output=\(turn.agentResult.output)")
    print("spoken_count=\(spoken.count)")
}

// MARK: - Demo doubles (no capture)

private actor IdleSpeechToText: SpeechToText {
    nonisolated func start() -> AsyncThrowingStream<SpeechTranscript, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func stop() async {}
}

private actor DemoTextToSpeech: TextToSpeech {
    private(set) var spoken: [String] = []

    func speak(_ text: String) async throws {
        spoken.append(text)
        print(text)
    }

    func stop() async {}
}

private actor DemoScriptedProvider: InferenceProvider {
    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        "Hello there. Two plus two is four."
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
        return InferenceResponse(content: "Hello there. Two plus two is four.", finishReason: .completed)
    }

    nonisolated func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("Hello there. ")
            continuation.yield("Two plus two is four.")
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        InferenceResponse(content: "Hello there. Two plus two is four.", finishReason: .completed)
    }
}
