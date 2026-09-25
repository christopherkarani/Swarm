# VoiceAssistant

macOS 26 SwiftUI sample for Swarm's turn-based `VoiceSession`.

`--demo` injects a transcript through `respond(to:)` and prints spoken
sentences without opening a window. Live capture uses
`VoiceSession.appleOnDevice` and the Listen button.

## Run

```bash
swift build --package-path Examples/VoiceAssistant
swift run --package-path Examples/VoiceAssistant VoiceAssistant --demo "Hello there."
swift run --package-path Examples/VoiceAssistant VoiceAssistant
```

Requires a path dependency on the Swarm package (`../../`).

Live microphone capture needs `NSMicrophoneUsageDescription` and
`NSSpeechRecognitionUsageDescription` (see `Sources/VoiceAssistant/Info.plist`).
Barge-in is a UI toggle (`bargeInEnabled`). This sample is not a full-duplex
conversational socket.

When wrapping the executable in an `.app` bundle, copy that Info.plist into
the bundle so TCC can show the microphone and speech prompts.
