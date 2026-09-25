import SwiftUI
import Swarm

@MainActor
@Observable
final class VoiceAssistantModel {
    var bargeInEnabled = false
    var phase = "idle"
    var transcript = ""
    var spoken: [String] = []
    var status = "Ready"
    var isBusy = false

    func listen() {
        guard !isBusy else { return }
        isBusy = true
        status = "Listening…"
        Task {
            do {
                let turn = try await Self.runListen(bargeInEnabled: bargeInEnabled)
                transcript = turn.transcript
                spoken = turn.spokenUtterances
                phase = "idle"
                status = "Spoken \(turn.spokenUtterances.count) sentence(s)."
            } catch {
                status = String(describing: error)
            }
            isBusy = false
        }
    }

    func demo(_ prompt: String) {
        guard !isBusy else { return }
        isBusy = true
        status = "Demo…"
        Task {
            do {
                let turn = try await Self.runDemo(prompt: prompt)
                transcript = turn.transcript
                spoken = turn.spokenUtterances
                phase = "idle"
                status = "Demo spoken \(turn.spokenUtterances.count) sentence(s)."
            } catch {
                status = String(describing: error)
            }
            isBusy = false
        }
    }

    private static func runListen(bargeInEnabled: Bool) async throws -> VoiceTurnResult {
        var configuration = VoiceSessionConfiguration.default
        configuration.bargeInEnabled = bargeInEnabled
        let agent = try await makeAgent()
        #if canImport(Speech)
        if #available(macOS 26.0, *) {
            let voice = try await VoiceSession.appleOnDevice(
                agent: agent,
                configuration: configuration,
                installAssetsIfNeeded: false
            )
            return try await voice.listenAndRespond()
        }
        #endif
        throw VoiceError.assetUnavailable(reason: "Apple on-device speech is not available.")
    }

    private static func runDemo(prompt: String) async throws -> VoiceTurnResult {
        let agent = try await makeAgent()
        let voice = VoiceSession(
            agent: agent,
            speechToText: IdleSpeechToText(),
            textToSpeech: RecordingTextToSpeech()
        )
        return try await voice.respond(to: prompt)
    }

    private static func makeAgent() async throws -> Agent {
        let provider = DemoScriptedProvider()
        return try Agent(
            "You are a concise on-device assistant.",
            configuration: .default.name("VoiceAssistant"),
            inferenceProvider: provider
        )
    }
}

struct VoiceAssistantView: View {
    @State private var model = VoiceAssistantModel()
    @State private var demoPrompt = "Hello there."

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Voice Assistant")
                .font(.title)
            Text("Turn-based VoiceSession. Not a realtime duplex socket.")
                .foregroundStyle(.secondary)
            Toggle("Barge-in", isOn: $model.bargeInEnabled)
                .disabled(model.isBusy)
            HStack {
                Button("Listen") {
                    model.listen()
                }
                .disabled(model.isBusy)
                Button("Demo") {
                    model.demo(demoPrompt)
                }
                .disabled(model.isBusy)
            }
            TextField("Demo prompt", text: $demoPrompt)
            LabeledContent("Phase", value: model.phase)
            LabeledContent("Status", value: model.status)
            Text("Transcript")
                .font(.headline)
            Text(model.transcript.isEmpty ? "—" : model.transcript)
            Text("Spoken")
                .font(.headline)
            if model.spoken.isEmpty {
                Text("—")
            } else {
                ForEach(model.spoken, id: \.self) { line in
                    Text(line)
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 360)
    }
}

private actor IdleSpeechToText: SpeechToText {
    nonisolated func start() -> AsyncThrowingStream<SpeechTranscript, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func stop() async {}
}
