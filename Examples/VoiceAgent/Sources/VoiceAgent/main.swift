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
              swift run VoiceAgent --http-stt <url> --audio <wav> [--api-key <key>]
              swift run VoiceAgent --http-tts <url> --demo [prompt] [--api-key <key>]
              swift run VoiceAgent --eleven-stt --audio <file> [--api-key <key>]
              swift run VoiceAgent --eleven-tts <voice-id> --demo [prompt] [--api-key <key>] [--out speech.mp3]

            Options:
              --demo       Inject the prompt via VoiceSession.respond(to:) (no microphone)
              --http-stt   OpenAI-compatible /audio/transcriptions URL (requires --audio)
              --http-tts   OpenAI-compatible /audio/speech URL
              --eleven-stt ElevenLabs Scribe transcription (requires --audio)
              --eleven-tts ElevenLabs synthesis with a voice id
              --audio      Audio file for speech-to-text
              --api-key    Bearer token for HTTP adapters (or OPENAI_API_KEY);
                           xi-api-key for ElevenLabs (or ELEVENLABS_API_KEY)
              --out        Write the last ElevenLabs TTS payload to this file
              --help       Show this help

            Live microphone capture is not wired in this CLI. Use --demo, or call
            VoiceSession.appleOnDevice from an app that declares
            NSMicrophoneUsageDescription and NSSpeechRecognitionUsageDescription.
            """
        )
        return
    }

    let flags = FlagParser(arguments: arguments)
    let demoMode = flags.contains("demo")
    let httpSTT = flags.value("http-stt")
    let httpTTS = flags.value("http-tts")
    let elevenSTT = flags.contains("eleven-stt")
    let elevenTTS = flags.value("eleven-tts")
    let outPath = flags.value("out")
    let audioPath = flags.value("audio")
    let apiKey = flags.value("api-key")
        ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
    let elevenKey = flags.value("api-key")
        ?? ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"]
    let userPrompt = flags.positional.isEmpty
        ? "What is 2 plus 2? Answer in one short sentence."
        : flags.positional.joined(separator: " ")

    if !demoMode, httpSTT == nil, !elevenSTT {
        fputs("live mic not wired in this CLI, use --demo or --http-stt/--eleven-stt with --audio\n", stderr)
        exit(2)
    }

    let provider = DemoScriptedProvider()
    let agent = try Agent(
        "You are a concise on-device assistant.",
        configuration: .default.name("VoiceAgent"),
        memory: .conversation(maxMessages: 16),
        inferenceProvider: provider
    )

    let speechToText: any SpeechToText
    if elevenSTT {
        guard let audioPath else {
            fputs("--eleven-stt requires --audio <file>\n", stderr)
            exit(2)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: audioPath))
        let eleven = ElevenLabsSpeechToText(
            configuration: ElevenLabsSpeechConfiguration(apiKey: elevenKey)
        )
        await eleven.submitAudio(data)
        speechToText = eleven
    } else if let httpSTT {
        guard let audioPath else {
            fputs("--http-stt requires --audio <file>\n", stderr)
            exit(2)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: audioPath))
        let http = HTTPSpeechToText(
            configuration: HTTPSpeechConfiguration(
                endpoint: try url(httpSTT),
                apiKey: apiKey
            )
        )
        await http.submitAudio(data)
        speechToText = http
    } else {
        speechToText = IdleSpeechToText()
    }

    let textToSpeech: any TextToSpeech
    let recordingTTS = DemoTextToSpeech()
    let elevenTTSAdapter: ElevenLabsTextToSpeech?
    if let elevenTTS {
        let eleven = ElevenLabsTextToSpeech(
            configuration: ElevenLabsSpeechSynthesisConfiguration(
                voiceId: elevenTTS,
                apiKey: elevenKey
            )
        )
        elevenTTSAdapter = eleven
        textToSpeech = eleven
    } else if let httpTTS {
        elevenTTSAdapter = nil
        textToSpeech = HTTPTextToSpeech(
            configuration: HTTPSpeechSynthesisConfiguration(
                endpoint: try url(httpTTS),
                apiKey: apiKey
            )
        )
    } else {
        elevenTTSAdapter = nil
        textToSpeech = recordingTTS
    }

    let voice = VoiceSession(
        agent: agent,
        speechToText: speechToText,
        textToSpeech: textToSpeech
    )

    let mode: String
    let turn: VoiceTurnResult
    if demoMode || (httpSTT == nil && !elevenSTT) {
        if elevenTTS != nil {
            mode = "demo + eleven-tts"
        } else if httpTTS != nil {
            mode = "demo + http-tts"
        } else {
            mode = "demo (scripted)"
        }
        print("Swarm \(Swarm.version) · mode=\(mode)")
        print("--- respond ---")
        print("transcript=\(userPrompt)")
        turn = try await voice.respond(to: userPrompt)
    } else {
        mode = elevenSTT ? "eleven-stt" : "http-stt"
        print("Swarm \(Swarm.version) · mode=\(mode)")
        print("--- listen ---")
        turn = try await voice.listenAndRespond()
        print("transcript=\(turn.transcript)")
    }

    if elevenTTSAdapter != nil || httpTTS != nil {
        print("spoken_count=\(turn.spokenUtterances.count)")
    } else {
        let spoken = await recordingTTS.spoken
        for utterance in spoken {
            print("spoken=\(utterance)")
        }
        print("spoken_count=\(spoken.count)")
    }
    if let elevenTTSAdapter, let outPath {
        let audio = await elevenTTSAdapter.lastAudio
        try audio.write(to: URL(fileURLWithPath: outPath))
        print("audio_out=\(outPath) bytes=\(audio.count)")
    }
    print("agent_output=\(turn.agentResult.output)")
}

private func url(_ string: String) throws -> URL {
    guard let url = URL(string: string), url.scheme != nil else {
        throw VoiceError.speechFailed(reason: "Invalid HTTP voice URL.")
    }
    return url
}

private struct FlagParser {
    let positional: [String]
    private let values: [String: String]
    private let switches: Set<String>

    init(arguments: [String]) {
        var positional: [String] = []
        var values: [String: String] = [:]
        var switches: Set<String> = []
        var index = 0
        let valued: Set<String> = ["http-stt", "http-tts", "eleven-tts", "audio", "api-key", "out"]
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--demo" {
                switches.insert("demo")
                index += 1
                continue
            }
            if argument.hasPrefix("--") {
                let name = String(argument.dropFirst(2))
                if valued.contains(name), index + 1 < arguments.count {
                    values[name] = arguments[index + 1]
                    index += 2
                    continue
                }
                switches.insert(name)
                index += 1
                continue
            }
            positional.append(argument)
            index += 1
        }
        self.positional = positional
        self.values = values
        self.switches = switches
    }

    func contains(_ name: String) -> Bool {
        switches.contains(name)
    }

    func value(_ name: String) -> String? {
        values[name]
    }
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
