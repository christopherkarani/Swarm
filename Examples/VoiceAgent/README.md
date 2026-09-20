# VoiceAgent

Minimal CLI for Swarm's turn-based `VoiceSession`.

`--demo` injects a transcript through `respond(to:)` and prints spoken
sentences. It does not open the microphone.

## Run

```bash
swift run --package-path Examples/VoiceAgent VoiceAgent --demo "Hello there."
swift run --package-path Examples/VoiceAgent VoiceAgent --help
```

Requires macOS 26+ and a path dependency on the Swarm package (`../../`).

Live microphone capture is not wired in this CLI. App hosts can call
`VoiceSession.appleOnDevice` after declaring `NSMicrophoneUsageDescription`
and `NSSpeechRecognitionUsageDescription`.
