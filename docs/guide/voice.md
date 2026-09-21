# Voice

`VoiceSession` is a turn-based coordinator around an existing `Agent`. It listens
for one utterance (or accepts an injected transcript), calls `agent.stream` with
that **text**, and speaks output tokens as sentences.

Swarm does not accept audio. `VoiceSession` is not an Agent. The microphone and
speaker stay in host-injected `SpeechToText` and `TextToSpeech` adapters.

Barge-in is not in v1. Call `stop()` to cancel the in-flight turn.

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

## What is spoken

Only `.output(.token)` and `.output(.chunk)` are buffered into sentences. Thinking
and tool events are never spoken. If the stream finishes with no tokens, Swarm
speaks `agentResult.output` so tool-loop-only turns still talk.

Default sentence split: terminators `.`, `!`, `?`, and newline; minimum 8
characters before a terminator emits.

## Linux and tests

Protocols, `VoiceSession`, and test doubles compile on Linux. Inject scripted
`SpeechToText` / `TextToSpeech` adapters — the same path the capability showcase
`voice` scenario uses.

## Live Apple capture

On Apple platforms, `AppleSpeechToText` uses `SpeechAnalyzer` +
`SpeechTranscriber` (not `SFSpeechRecognizer`) and `AppleTextToSpeech` uses
`AVSpeechSynthesizer`. Construct both through `VoiceSession.appleOnDevice`.

A host app that opens the mic must declare `NSMicrophoneUsageDescription` and
`NSSpeechRecognitionUsageDescription`. Language assets may be missing on the
first offline run. `installAssetsIfNeeded` defaults to `false` so the first
listen cannot surprise-download.

Barge-in is not in v1.

```swift
#if canImport(Speech)
if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
    let voice = try await VoiceSession.appleOnDevice(
        agent: agent,
        session: InMemorySession(),
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
