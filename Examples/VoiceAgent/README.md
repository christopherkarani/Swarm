# VoiceAgent

Minimal CLI for Swarm's turn-based `VoiceSession`.

`--demo` injects a transcript through `respond(to:)` and prints spoken
sentences. It does not open the microphone.

## Run

```bash
swift run --package-path Examples/VoiceAgent VoiceAgent --demo "Hello there."
swift run --package-path Examples/VoiceAgent VoiceAgent --help
```

`--http-stt <url> --audio <file>` uses `HTTPSpeechToText` against an
OpenAI-compatible `/audio/transcriptions` endpoint (no microphone).
`--http-tts <url>` uses `HTTPTextToSpeech`. Pass `--api-key` or set
`OPENAI_API_KEY`. `--demo` stays scripted and does not require a mic.

`--eleven-stt --audio <file>` transcribes with ElevenLabs Scribe
(`ElevenLabsSpeechToText`). `--eleven-tts <voice-id> --demo [prompt]`
speaks with ElevenLabs (`ElevenLabsTextToSpeech`); add `--out speech.mp3`
to save the last synthesized payload. Pass `--api-key` or set
`ELEVENLABS_API_KEY`.

```bash
export ELEVENLABS_API_KEY=...
swift run --package-path Examples/VoiceAgent VoiceAgent --eleven-tts <voice-id> --demo "Hello there." --out speech.mp3
swift run --package-path Examples/VoiceAgent VoiceAgent --eleven-stt --audio hello.wav
```

Requires macOS 26+ and a path dependency on the Swarm package (`../../`).

Live microphone capture is not wired in this CLI. App hosts can call
`VoiceSession.appleOnDevice` after declaring `NSMicrophoneUsageDescription`
and `NSSpeechRecognitionUsageDescription`.
