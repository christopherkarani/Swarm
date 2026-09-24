# Voice

`VoiceSession` is a turn-based coordinator around an existing `Agent`. It listens
for one utterance (or accepts an injected transcript), calls `agent.stream` with
that **text**, and speaks output tokens as sentences.

VoiceSession sends text to Agent.stream; audio attachments are opt-in and
capability-gated. `VoiceSession` is not an Agent. The microphone and speaker
stay in host-injected `SpeechToText` and `TextToSpeech` adapters.

Barge-in is opt-in via `bargeInEnabled`. Call `stop()` to cancel the in-flight
turn without starting a replacement listen.

## Listen and respond

```swift
let voice = VoiceSession(
    agent: agent,
    speechToText: mySpeechToText,
    textToSpeech: myTextToSpeech,
    session: InMemorySession()
)

let turn = try await voice.listenAndRespond()
// turn.transcript is the final utterance
// turn.spokenUtterances are the sentences that were spoken
```

Tests and CLIs can skip the microphone:

```swift
let turn = try await voice.respond(to: "What's the weather in Tokyo?")
```

`respond(to:)` does not open speech-to-text. Whitespace-only input throws
`VoiceError.emptyTranscript` and never starts the agent.

## Barge-in

Set `VoiceSessionConfiguration.bargeInEnabled` to `true` and inject a
`VoiceActivityDetector`. While the session is speaking, `speechStarted`
stops TTS, cancels the agent, emits `.interrupted(transcriptSoFar:)`, and
listens for a replacement utterance in the same turn (`busy` is not thrown).

```swift
var configuration = VoiceSessionConfiguration.default
configuration.bargeInEnabled = true
let voice = VoiceSession(
    agent: agent,
    speechToText: mySpeechToText,
    textToSpeech: myTextToSpeech,
    voiceActivityDetector: myDetector,
    configuration: configuration
)
```

This is still turn-based. It is not a full-duplex conversational socket.

## Workflow and Job

Wrap a session as `VoiceTurnRuntime` so `Workflow().step` and `JobChild` can
speak a turn. The input is still a `String`. Durable checkpoints store text
only — not microphone or TTS state.

```swift
let runtime = VoiceTurnRuntime(voice: voice, presenting: agent)
let result = try await Workflow().step(runtime).run("Hello there.")
```

## HTTP Whisper-compatible adapters

`HTTPSpeechToText` and `HTTPTextToSpeech` POST to OpenAI-compatible
`/audio/transcriptions` and `/audio/speech` through an injected `URLSession`.
There is no whisper.cpp pin and no Voice SwiftPM trait.

```swift
let stt = HTTPSpeechToText(configuration: .init(endpoint: transcriptionsURL, apiKey: key))
await stt.submitAudio(wavData)
let tts = HTTPTextToSpeech(configuration: .init(endpoint: speechURL, apiKey: key))
```

## ElevenLabs adapters

`ElevenLabsSpeechToText` (Scribe) and `ElevenLabsTextToSpeech` POST to
`https://api.elevenlabs.io` with the key in an `xi-api-key` header. They
follow the same shape as the HTTP adapters: queue audio with `submitAudio`
before `start()`, and read synthesized bytes from `lastAudio` — the host
plays them.

```swift
let stt = ElevenLabsSpeechToText(configuration: .init(apiKey: key))
await stt.submitAudio(wavData)
let tts = ElevenLabsTextToSpeech(configuration: .init(voiceId: voiceId, apiKey: key))
```

Optional tuning: `ElevenLabsSpeechConfiguration(modelId:languageCode:)` for
Scribe (`scribe_v2` by default) and
`ElevenLabsSpeechSynthesisConfiguration(voiceId:modelId:outputFormat:voiceSettings:)`
for synthesis (`eleven_multilingual_v2` by default).

```bash
export ELEVENLABS_API_KEY=...
swift run --package-path Examples/VoiceAgent VoiceAgent --eleven-tts <voice-id> --demo "Hello there." --out speech.mp3
swift run --package-path Examples/VoiceAgent VoiceAgent --eleven-stt --audio hello.wav
```

## Audio attachments

`InferenceMessage.attachments` is an additive sidecar (`audio` | `image`).
`content` stays a `String`. `Agent.run` / `stream` stay `String`.

Providers without `InferenceProviderCapabilities.multimodalAudio` drop or
reject audio. Prompt token counts stay text-only. Persist identifier and MIME
type, never PCM.

Optional host API:

```swift
try await voice.respond(to: transcript, attachments: [audio])
```

## What is spoken

Only `.output(.token)` and `.output(.chunk)` are buffered into sentences. Thinking
and tool events are never spoken. If the stream finishes with no tokens, Swarm
speaks `agentResult.output` so tool-loop-only turns still talk.

Default sentence split: terminators `.`, `!`, `?`, and newline; minimum 8
characters before a terminator emits.

## Linux and tests

Protocols, `VoiceSession`, HTTP adapters, and test doubles compile on Linux.
Inject scripted `SpeechToText` / `TextToSpeech` adapters — the same path the
capability showcase `voice`, `voice-bargein`, and `voice-workflow` scenarios
use.

## Live Apple capture

On Apple platforms, `AppleSpeechToText` uses `SpeechAnalyzer` +
`SpeechTranscriber` (not `SFSpeechRecognizer`) and `AppleTextToSpeech` uses
`AVSpeechSynthesizer`. Construct both through `VoiceSession.appleOnDevice`.
When `bargeInEnabled` is true, that factory also attaches
`AppleVoiceActivityDetector` (`SpeechDetector`).

A host app that opens the mic must declare `NSMicrophoneUsageDescription` and
`NSSpeechRecognitionUsageDescription`. Language assets may be missing on the
first offline run. `installAssetsIfNeeded` defaults to `false` so the first
listen cannot surprise-download.

```swift
#if canImport(Speech)
if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
    var configuration = VoiceSessionConfiguration.default
    configuration.bargeInEnabled = true
    let voice = try await VoiceSession.appleOnDevice(
        agent: agent,
        session: InMemorySession(),
        configuration: configuration,
        installAssetsIfNeeded: false
    )
    let turn = try await voice.listenAndRespond()
}
#endif
```

Deterministic CLI (no microphone):

```bash
swift run --package-path Examples/VoiceAgent VoiceAgent --demo "Hello there."
```

macOS SwiftUI sample:

```bash
swift build --package-path Examples/VoiceAssistant
swift run --package-path Examples/VoiceAssistant VoiceAssistant --demo "Hello there."
```
