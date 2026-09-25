// VoiceAssistant — macOS SwiftUI host for VoiceSession.
//
// --demo injects a transcript via VoiceSession.respond(to:). It does not
// open the microphone.

import Foundation
import SwiftUI
import Swarm

@main
struct VoiceAssistantEntry {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("-h") || arguments.contains("--help") {
            print(
                """
                VoiceAssistant — Swarm turn-based voice sample

                Usage:
                  swift run VoiceAssistant
                  swift run VoiceAssistant --demo [prompt]

                Options:
                  --demo   Inject the prompt via VoiceSession.respond(to:) (no microphone)
                  --help   Show this help

                Live capture needs NSMicrophoneUsageDescription and
                NSSpeechRecognitionUsageDescription. Barge-in is a toggle in the UI.
                """
            )
            return
        }

        if arguments.contains("--demo") {
            let promptParts = arguments.filter { $0 != "--demo" }
            let prompt = promptParts.isEmpty ? "Hello there." : promptParts.joined(separator: " ")
            do {
                let output = try await performDemo(prompt: prompt)
                print(output)
            } catch {
                fputs("VoiceAssistant error: \(error)\n", stderr)
                exit(1)
            }
            return
        }

        await MainActor.run {
            VoiceAssistantApp.main()
        }
    }
}

private func performDemo(prompt: String) async throws -> String {
    let provider = DemoScriptedProvider()
    let agent = try Agent(
        "You are a concise on-device assistant.",
        configuration: .default.name("VoiceAssistant"),
        inferenceProvider: provider
    )
    let textToSpeech = RecordingTextToSpeech()
    let voice = VoiceSession(
        agent: agent,
        speechToText: IdleSpeechToText(),
        textToSpeech: textToSpeech
    )
    print("Swarm \(Swarm.version) · mode=demo (scripted)")
    print("transcript=\(prompt)")
    let turn = try await voice.respond(to: prompt)
    let spoken = await textToSpeech.spoken
    for utterance in spoken {
        print("spoken=\(utterance)")
    }
    return "agent_output=\(turn.agentResult.output)\nspoken_count=\(spoken.count)"
}

private actor IdleSpeechToText: SpeechToText {
    nonisolated func start() -> AsyncThrowingStream<SpeechTranscript, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func stop() async {}
}

actor RecordingTextToSpeech: TextToSpeech {
    private(set) var spoken: [String] = []

    func speak(_ text: String) async throws {
        spoken.append(text)
        print(text)
    }

    func stop() async {}
}

actor DemoScriptedProvider: InferenceProvider {
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

struct VoiceAssistantApp: App {
    var body: some Scene {
        WindowGroup {
            VoiceAssistantView()
        }
    }
}
